import '../data/tradelab_data.dart';
import 'pine_runtime_core.dart';
import 'pine_subset_program.dart';
import 'pine_v6_frontend.dart';
import 'pine_function_registry.dart';
import 'pine_ta_library.dart';
import 'pine_scalar_primitives.dart';
import 'pine_scalar_dispatch.dart';
import 'pine_series_primitives.dart';
import 'pine_series_dispatch.dart';
import 'pine_indicator_dispatch.dart';
import 'pine_execution_context.dart';
import 'pine_runtime_map.dart';
import 'pine_security_dispatch.dart';

/// Stage 3a, closed-bar Pine language execution. The old PineSubsetProgram
/// remains the sole runtime for source it already supports. This interpreter
/// accepts only a verified AST subset and rejects unknown calls before any
/// candle is read; it never fabricates quotes or sees hidden Replay candles.
///
/// Official Pine execution model: var is committed once per closed bar;
/// varip differs only on intrabar ticks. Replay here processes only confirmed
/// historical candles: there is no speculative tick/rollback.
class PineV6LanguageProgram {
  PineV6LanguageProgram._(this.source, this.ast, this.legacy,
      this._functions, this._plotCalls, this._types, this.context,this._inputs,this._securitySpecs);

  final String source;
  final PineScriptAst ast;
  final PineSubsetProgram? legacy;
  final Map<String, PineFunctionStatement> _functions;
  final List<PineCallExpression> _plotCalls;
  final Map<PineExpression,PineTypeInfo> _types;
  final PineExecutionContext context;
  final Map<PineCallExpression,Object> _inputs;
  final Map<PineCallExpression,PineSecuritySpec> _securitySpecs;

  bool get overlay {
    for(final statement in ast.statements){
      if(statement is! PineExpressionStatement)continue;
      final value=statement.expression;
      if(value is! PineCallExpression || value.name!='indicator')continue;
      for(final argument in value.arguments){
        if(argument.name=='overlay'&&
            argument.value is PineLiteralExpression){
          return (argument.value as PineLiteralExpression).value=='true';
        }
      }
    }
    return false;
  }

  static PineV6LanguageProgram compile(String source,{bool preferGeneral=false,PineExecutionContext? context}) {
    final prepared=const PineV6Frontend().prepare(source);
    if(prepared.hasErrors) {
      throw PineRuntimeException('compile_invalid',
          prepared.message??'Invalid Pine syntax or semantics');
    }
    final legacy=preferGeneral||context!=null?null:prepared.legacyProgram;
    final executionContext=context??PineExecutionContext();
    if(prepared.diagnostics.any((d)=>d.code=='tuple_shape_unknown')){
      throw const PineRuntimeException('tuple_shape_unknown','Tuple result shape must be resolved before execution');
    }
    final functions=<String,PineFunctionStatement>{};
    final plots=<PineCallExpression>[];
    final constants=<String,Object?>{},inputs=<PineCallExpression,Object>{};
    final securitySpecs=<PineCallExpression,PineSecuritySpec>{};
    for(final stmt in prepared.ast.statements) {
      if(stmt is PineFunctionStatement)functions[stmt.name]=stmt;
    }

    var usesNewTa=false;
    void validateExpr(PineExpression expr, {bool global=false}) {
      if(expr is PineLiteralExpression || expr is PineIdentifierExpression) {
        if(expr is PineIdentifierExpression&&const {'time','volume'}.contains(expr.name))usesNewTa=true;
        return;
      }
      if(expr is PineMemberExpression) {
        if(PineExecutionContext.members.contains(expr.qualifiedName)){
          executionContext.member(expr.qualifiedName!);
          usesNewTa=true;
          return;
        }
        if(!PineScalarDispatch.isColorMember(expr.qualifiedName)) {
          throw PineRuntimeException('unsupported_member',
            'Unimplemented Pine member: '+(expr.qualifiedName??'unknown'));
        }
        return;
      }
      if(expr is PineHistoryExpression) {
        if(prepared.semantic.inferred[expr.target]?.type==PineBaseType.mapType){
          throw const PineRuntimeException('unsupported_map_history','Map history is not enabled');
        }
        if(expr.target is PineCallExpression){
          validateExpr(expr.target);
          usesNewTa=true;
        }else if(expr.target is! PineIdentifierExpression){
          throw const PineRuntimeException('unsupported_history',
              'History currently supports named series and written call results');
        }
        validateExpr(expr.offset);
        return;
      }
      if(expr is PineTupleExpression){
        for(final item in expr.values)validateExpr(item);
        return;
      }
      if(expr is PineUnaryExpression) {
        validateExpr(expr.value);return;
      }
      if(expr is PineBinaryExpression) {
        validateExpr(expr.left);validateExpr(expr.right);return;
      }
      if(expr is PineTernaryExpression) {
        validateExpr(expr.condition);
        validateExpr(expr.thenValue);validateExpr(expr.elseValue);return;
      }
      if(expr is PineCallExpression) {
        final name=expr.name;
        if(name=='request.security'){
          if(executionContext.tickerId==null||executionContext.timeframePeriod==null){
            throw const PineRuntimeException('unsupported_security_context','Verified chart symbol and timeframe required');
          }
          final spec=PineSecuritySpec.parse(expr);
          securitySpecs[expr]=spec;
          validateExpr(spec.symbol);validateExpr(spec.timeframe);
          usesNewTa=true;return;
        }
        if(name=='ticker.standard'||name=='ticker.heikinashi'){
          if(executionContext.tickerId==null)throw const PineRuntimeException('unsupported_ticker_context','Verified chart ticker required');
          if(expr.arguments.length!=1)throw const PineRuntimeException('unsupported_ticker_arguments','Explicit ticker argument required');
          validateExpr(expr.arguments.single.value);usesNewTa=true;return;
        }
        if(name=='time'){
          executionContext.validateTimeCall(expr);
          usesNewTa=true;
        }
        if(name=='int')usesNewTa=true;
        if(PineRuntimeMap.names.contains(name)){
          PineRuntimeMap.validate(expr);
          usesNewTa=true;
        }
        if(PineExecutionContext.inputs.contains(name)){
          inputs[expr]=executionContext.input(expr,constants:constants);
          usesNewTa=true;
          return;
        }
        if(PineScalarDispatch.supports(name)){
          PineScalarDispatch.validate(expr);
          usesNewTa=true;
        }
        if(PineSeriesDispatch.supports(name)){
          PineSeriesDispatch.validate(expr);
          usesNewTa=true;
        }
        if(PineIndicatorDispatch.supports(name)){
          PineIndicatorDispatch.validate(expr,prepared.semantic.inferred);
          usesNewTa=true;
        }
        final ta=PineFunctionRegistry.ta[name];
        if(ta!=null&&!ta.tupleResult){
          final slots=ta.bind(expr.arguments.map((a)=>a.name).toList());
          for(var i=0;i<slots.length;i++){
            final slot=slots[i],value=expr.arguments[i].value;
            final type=prepared.semantic.inferred[value];
            final base=type?.type;
            if(base!=null&&base!=PineBaseType.unknown){
              final valid=ta.isBooleanParameter(slot)
                  ?base==PineBaseType.boolType
                  :ta.lengthSlots.contains(slot)
                      ?base==PineBaseType.intType
                      :base==PineBaseType.intType||base==PineBaseType.floatType;
              if(!valid)throw PineRuntimeException('ta_type',
                  'Wrong parameter type for '+ta.name);
            }
            if(ta.lengthSlots.contains(slot)&&value is PineLiteralExpression){
              final length=int.tryParse(value.value);
              if(length==null||length<1||length>500){
                throw const PineRuntimeException('length',
                    'TA literal length must be 1..500');
              }
            }
          }
          if(!ta.legacy)usesNewTa=true;
        }
        if(name==null || !(<String>{
          'indicator','plot','na','nz','input.int','input.float','int','time',
          'math.abs','math.min','math.max',
          ...PineRuntimeMap.names,
          ...PineScalarDispatch.names,
          ...PineSeriesDispatch.names,
          ...PineIndicatorDispatch.names,
          ...PineFunctionRegistry.ta.values.where((s)=>!s.tupleResult).map((s)=>s.name),
          ...functions.keys,
        }).contains(name)) {
          throw PineRuntimeException('unsupported_function',
              'Stage 3a runtime does not execute function: '+(name??'unknown'));
        }
        if(name=='plot') {
          if(!global || plots.length>=8) {
            throw const PineRuntimeException('plot_scope',
                'Plots must be global and limited to eight');
          }
          plots.add(expr);
        }
        for(final arg in expr.arguments) {
          if(name=='plot' && arg.name!=null &&
              arg.name!='title') {
            throw const PineRuntimeException('plot_options',
                'Advanced plot options are not executed by Stage 3a');
          }
          validateExpr(arg.value);
        }
        return;
      }
      throw const PineRuntimeException('unsupported_expression',
          'Stage 3a runtime refuses this AST expression');
    }

    void validateStatements(List<PineStatement> stmts, {bool global=false}) {
      for(final stmt in stmts) {
        if(stmt is PineTupleDeclarationStatement){
          validateExpr(stmt.value);usesNewTa=true;
        }else if(stmt is PineSequenceStatement){
          usesNewTa=true;
          validateStatements(stmt.statements,global:global);
        }else if(stmt is PineReferenceVariableStatement){
          if(stmt.typeName!='map'||stmt.value is! PineCallExpression||(stmt.value as PineCallExpression).name!='map.new'){
            throw const PineRuntimeException('unsupported_reference','Only typed map.new reference declarations are enabled');
          }
          validateExpr(stmt.value);usesNewTa=true;
        }else if(stmt is PineVariableStatement) {
          validateExpr(stmt.value);
          if(global&&prepared.semantic.inferred[stmt.value]?.qualifier==PineQualifier.constant){
            try{constants[stmt.name]=PineExecutionContext.constantValue(stmt.value,constants);}
            on PineRuntimeException{/* Only literal constants are accepted as input metadata. */}
          }
        } else if(stmt is PineAssignmentStatement) {
          validateExpr(stmt.value);
        } else if(stmt is PineExpressionStatement) {
          validateExpr(stmt.expression,global:global);
        } else if(stmt is PineIfStatement) {
          validateExpr(stmt.condition);
          validateStatements(stmt.thenBody);
          validateStatements(stmt.elseBody);
        } else if(stmt is PineForStatement) {
          validateExpr(stmt.from);validateExpr(stmt.to);
          if(stmt.step!=null)validateExpr(stmt.step!);
          validateStatements(stmt.body);
        } else if(stmt is PineWhileStatement) {
          validateExpr(stmt.condition);validateStatements(stmt.body);
        } else if(stmt is PineSwitchStatement) {
          if(stmt.selector!=null)validateExpr(stmt.selector!);
          for(final arm in stmt.arms) {
            if(arm.match!=null)validateExpr(arm.match!);
            validateStatements(arm.body);
          }
        } else if(stmt is PineFunctionStatement) {
          for(final p in stmt.parameters) {
            if(p.defaultValue!=null)validateExpr(p.defaultValue!);
          }
          validateStatements(stmt.body);
        } else if(stmt is! PineControlStatement) {
          throw const PineRuntimeException('unsupported_statement',
              'Stage 3a runtime refuses this AST statement');
        }
      }
    }

    if(legacy==null) {
      // Do not use the new language tier to bypass an existing numeric
      // program's period, plot or syntax restrictions. The new tier is only
      // for scripts that demonstrably use Stage 3a language constructs.
      bool advanced(List<PineStatement> statements) {
        for(final statement in statements){
          if(statement is PineAssignmentStatement ||
              statement is PineIfStatement ||
              statement is PineSwitchStatement ||
              statement is PineForStatement ||
              statement is PineWhileStatement ||
              statement is PineFunctionStatement ||
              (statement is PineVariableStatement &&
                  (statement.mode=='var'||statement.mode=='varip'))) {
            return true;
          }
        }
        return false;
      }
      validateStatements(prepared.ast.statements,global:true);
      if(!advanced(prepared.ast.statements)&&!usesNewTa&&!((preferGeneral||context!=null)&&prepared.legacyProgram!=null)){
        throw const PineRuntimeException('unsupported_legacy',
            'Only previously executable numeric programs or verified Stage 3a language are supported');
      }
      if(plots.isEmpty) {
        throw const PineRuntimeException('missing_plot',
            'Stage 3a numeric language requires at least one global plot');
      }
    }
    return PineV6LanguageProgram._(
        source,prepared.ast,legacy,functions,plots,prepared.semantic.inferred,executionContext,Map.unmodifiable(inputs),Map.unmodifiable(securitySpecs));
  }

  PineV6LanguageInstance newInstance({
    PineRuntimeLimits limits=const PineRuntimeLimits(),
    int maxLoopIterations=2000,
  }) => PineV6LanguageInstance._(this,limits,maxLoopIterations);

  List<PineSubsetPlot> evaluate(List<TradeCandle> verifiedBars, {
    PineRuntimeLimits limits=const PineRuntimeLimits(),
    int maxLoopIterations=2000,
  }) {
    if(legacy!=null) {
      return legacy!.evaluateIncrementally(verifiedBars,limits:limits);
    }
    final instance=newInstance(
        limits:limits,maxLoopIterations:maxLoopIterations);
    instance.rebuild(verifiedBars,verifiedBars.length);
    return instance.outputs;
  }
}

class _PineBinding {
  _PineBinding(this.value,{this.definition,this.callPath=''});
  Object? value;
  final PineStatement? definition;
  final String callPath;
}
class _PineFrame {
  _PineFrame(this.parent);
  final _PineFrame? parent;
  final Map<String,_PineBinding> locals={};
  _PineBinding? find(String name)=>locals[name]??parent?.find(name);
}
class _PineBreak implements Exception {}
class _PineContinue implements Exception {}

/// An instance owns ALL its persistent variables, per-call history, SMA
/// accumulators and output series. No static mutable map and no shared state.
class PineV6LanguageInstance {
  PineV6LanguageInstance._(this.program,this.limits,this.maxLoopIterations)
      : budget=PineRuntimeBudget(limits) {
    _plots=[for(final _ in program._plotCalls)<double?>[]];
  }

  final PineV6LanguageProgram program;
  final PineRuntimeLimits limits;
  final int maxLoopIterations;
  PineRuntimeBudget budget;
  final Map<(String,PineStatement),Object?> _persistent={};
  final Map<(String,PineCallExpression),PineTaState> _ta={};
  final Map<String,List<Object?>> _history={};
  final Map<(String,PineCallExpression),PineRollingSum> _sums={};
  final Map<(String,PineCallExpression),int> _sumLastBar={};
  String _callPath='';
  final Map<(String,PineHistoryExpression),PineCommittedHistory<Object>> _callHistory={};
  final Map<(String,PineCallExpression),PineBarsSinceState> _since={};
  final Map<(String,PineCallExpression),PinePivotState> _pivots={};
  final Map<(String,PineCallExpression),int> _seriesLastBar={};
  final List<TradeCandle> _seen=[];
  late List<List<double?>> _plots;
  int _bar=-1;
  bool _stopped=false;
  final Map<(String,PineCallExpression),PineIndicatorDispatch> _indicators={};
  final Map<(String,PineCallExpression),PineSecurityState> _security={};

  int get completedBars=>_bar+1;
  Object? persistentValue(String name) {
    for(final entry in _persistent.entries) {
      final stmt=entry.key.$2;
      if(stmt is PineVariableStatement&&stmt.name==name&&entry.key.$1=='')return entry.value;
    }
    return null;
  }
  List<PineSubsetPlot> get outputs {
    if(program.legacy!=null) {
      throw const PineRuntimeException('legacy_executor',
          'Use legacy evaluate for previously supported scripts');
    }
    return List.unmodifiable([
      for(var i=0;i<program._plotCalls.length;i++)
        PineSubsetPlot(_plotTitle(program._plotCalls[i],i),
            List<double?>.unmodifiable(_plots[i])),
    ]);
  }

  String _plotTitle(PineCallExpression call,int index){
    for(var i=0;i<call.arguments.length;i++){
      final arg=call.arguments[i];
      if((arg.name=='title'||(arg.name==null&&i==1))&&
          arg.value is PineLiteralExpression){
        return (arg.value as PineLiteralExpression).value
            .replaceAll('"','').replaceAll("'",'');
      }
    }
    return 'Plot '+(index+1).toString();
  }

  void _charge([int work=1])=>budget.consume(work:work);

  Object? _numeric(Object? value){
    if(value==null)return null;
    if(value is num)return value.toDouble();
    throw const PineRuntimeException('type',
        'Expected a numeric Pine value');
  }
  double? _num(Object? value)=>_numeric(value) as double?;
  bool _bool(Object? value){
    if(value is bool)return value;
    throw const PineRuntimeException('type',
        'Pine v6 condition must be bool');
  }
  int _integer(Object? value) {
    final n=_num(value);
    if(n==null||!n.isFinite||n.truncateToDouble()!=n) {
      throw const PineRuntimeException('integer',
          'Pine integer argument is missing or not integral');
    }
    return n.toInt();
  }

  Object? _eval(PineExpression expr,_PineFrame frame) {
    _charge();
    if(expr is PineLiteralExpression){
      return switch(expr.literalType){
        'int'=>int.tryParse(expr.value)?.toDouble(),
        'float'=>double.tryParse(expr.value),
        'bool'=>expr.value=='true',
        'na'=>null,
        'string'=>expr.value.replaceAll('"','').replaceAll("'",''),
        'color'=>PineScalarDispatch.parseColor(expr.value),
        _=>throw const PineRuntimeException('literal',
            'Unsupported literal type'),
      };
    }
    if(expr is PineMemberExpression){
      if(PineExecutionContext.members.contains(expr.qualifiedName))return program.context.member(expr.qualifiedName!);
      return PineScalarDispatch.memberColor(expr.qualifiedName);
    }
    if(expr is PineIdentifierExpression){
      final name=expr.name;
      if(name=='bar_index')return _bar.toDouble();
      final found=frame.find(name);
      if(found!=null)return found.value;
      final candle=_seen.last;
      return switch(name){
        'time'=>candle.timestampMs?.toDouble(),
        'volume'=>candle.volume,
        'close'=>candle.close,
        'open'=>candle.open,
        'high'=>candle.high,
        'low'=>candle.low,
        'hl2'=>(candle.high+candle.low)/2,
        'hlc3'=>(candle.high+candle.low+candle.close)/3,
        'ohlc4'=>(candle.open+candle.high+candle.low+candle.close)/4,
        _=>throw PineRuntimeException('undefined',
            'Unbound variable: '+name),
      };
    }
    if(expr is PineHistoryExpression) {
      final offset=_integer(_eval(expr.offset,frame));
      if(offset<0||offset>=limits.maxHistory) {
        throw const PineRuntimeException('history_limit',
            'History offset outside bounded window');
      }
      final missing=program._types[expr.target]?.type==PineBaseType.boolType?false:null;
      if(expr.target is PineCallExpression){
        final key=(_callPath,expr);
        final history=_callHistory.putIfAbsent(key,()=>PineCommittedHistory<Object>(
          budget,capacity:limits.maxHistory,missing:missing));
        // Commit this bar even when reading a past value. A skipped or repeated
        // call rejects rather than guessing local history semantics.
        final current=_eval(expr.target,frame);
        history.commit(_bar,current);
        return history.read(offset);
      }
      final name=(expr.target as PineIdentifierExpression).name;
      if(offset==0)return _eval(expr.target,frame);
      final index=_bar-offset;
      if(index<0)return missing;
      if(name=='bar_index')return index.toDouble();
      if(<String>{'time','volume','close','open','high','low','hl2','hlc3','ohlc4'}
          .contains(name)){
        final c=_seen[index];
        return switch(name){
          'time'=>c.timestampMs?.toDouble(),'volume'=>c.volume,
          'close'=>c.close,'open'=>c.open,'high'=>c.high,'low'=>c.low,
          'hl2'=>(c.high+c.low)/2,
          'hlc3'=>(c.high+c.low+c.close)/3,
          _=>(c.open+c.high+c.low+c.close)/4,
        };
      }
      final history=_history[name];
      return history==null||index>=history.length?missing:history[index]??missing;
    }
    if(expr is PineTupleExpression){
      return <Object?>[for(final item in expr.values)_eval(item,frame)];
    }
    if(expr is PineUnaryExpression) {
      final x=_eval(expr.value,frame);
      if(expr.operator=='not'||expr.operator=='!')return !_bool(x);
      final n=_num(x);
      return n==null?null:expr.operator=='-'?-n:n;
    }
    if(expr is PineTernaryExpression) {
      return _bool(_eval(expr.condition,frame))
          ?_eval(expr.thenValue,frame):_eval(expr.elseValue,frame);
    }
    if(expr is PineBinaryExpression) {
      if(expr.operator=='and'||expr.operator=='&&') {
        return _bool(_eval(expr.left,frame)) &&
            _bool(_eval(expr.right,frame));
      }
      if(expr.operator=='or'||expr.operator=='||') {
        return _bool(_eval(expr.left,frame)) ||
            _bool(_eval(expr.right,frame));
      }
      final left=_eval(expr.left,frame),right=_eval(expr.right,frame);
      switch(expr.operator) {
        case '==': return left!=null&&right!=null&&left==right;
        case '!=': return left!=null&&right!=null&&left!=right;
        case '<': case '>': case '<=': case '>=':
          final a=_num(left),c=_num(right);
          if(a==null||c==null)return false;
          return switch(expr.operator){
            '<'=>a<c,'>'=>a>c,'<='=>a<=c,_=>a>=c,
          };
      }
      if(expr.operator=='+'&&left is String&&right is String){
        if(left.length+right.length>16384){
          throw const PineRuntimeException('string_limit','Pine string exceeds bounded length');
        }
        _charge(left.length+right.length+1);
        return left+right;
      }
      final a=_num(left),c=_num(right);
      if(a==null||c==null)return null;
      final result=switch(expr.operator){
        '+'=>a+c,'-'=>a-c,'*'=>a*c,
        '/'=>c==0?null:a/c,
        '%'=>c==0?null:a%c,
        _=>throw const PineRuntimeException('operator',
            'Unsupported numeric operator'),
      };
      return result==null||!result.isFinite?null:result;
    }
    if(expr is PineCallExpression) {
      final name=expr.name??'';
      if(name=='indicator')return null;
      if(name=='ticker.standard'||name=='ticker.heikinashi'){
        final raw=_eval(expr.arguments.single.value,frame);
        final ticker=PineRequestedTicker.from(raw);
        return PineRequestedTicker(ticker.symbol,name=='ticker.heikinashi');
      }
      if(name=='request.security'){
        final spec=program._securitySpecs[expr]!;
        final ticker=PineRequestedTicker.from(_eval(spec.symbol,frame));
        final timeframe=_eval(spec.timeframe,frame);
        final state=_security.putIfAbsent((_callPath,expr),()=>PineSecurityState(budget,spec));
        return state.step(_bar,_seen.last,ticker,timeframe,program.context.tickerId!,
          program.context.timeframePeriod!,program.context.externalLookup);
      }
      if(name=='plot') {
        final index=program._plotCalls.indexOf(expr);
        if(index<0||expr.arguments.isEmpty) {
          throw const PineRuntimeException('plot',
              'Missing global plot destination');
        }
        final value=_num(_eval(expr.arguments.first.value,frame));
        budget.consume(work:0,values:1);
        _plots[index].add(value);
        return value;
      }
      if(name=='na')return _eval(expr.arguments.first.value,frame)==null;
      if(name=='nz') {
        final first=_eval(expr.arguments.first.value,frame);
        if(first!=null)return first;
        return expr.arguments.length>1
            ?_eval(expr.arguments[1].value,frame):0.0;
      }
      if(PineIndicatorDispatch.supports(name)){
        final key=(_callPath,expr);
        final args=PineIndicatorDispatch.bind(expr,[for(final arg in expr.arguments)_eval(arg.value,frame)]);
        return _indicators.putIfAbsent(key,()=>PineIndicatorDispatch(name,budget)).step(_bar,args,_seen.last);
      }
      final ta=PineFunctionRegistry.ta[name];
      if(ta!=null&&!ta.tupleResult){
        final args=ta.arguments(expr.arguments.map((a)=>a.name).toList(),
            [for(final arg in expr.arguments)_eval(arg.value,frame)]);
        final key=(_callPath,expr);
        final state=_ta.putIfAbsent(key,()=>PineTaState(ta,budget));
        return state.step(args,_seen.last,_bar==0?null:_seen[_bar-1].close);
      }
      if(PineExecutionContext.inputs.contains(name))return program._inputs[expr]!;
      if(name=='int'){
        final n=_num(_eval(expr.arguments.single.value,frame));
        return n==null?null:n.truncateToDouble();
      }
      if(name=='time'){
        return program.context.sessionTime(expr,[for(final a in expr.arguments)_eval(a.value,frame)],_seen.last.timestampMs);
      }
      if(PineRuntimeMap.names.contains(name)){
        return PineRuntimeMap.execute(expr,[for(final a in expr.arguments)_eval(a.value,frame)],budget);
      }
      if(PineSeriesDispatch.supports(name)){
        final key=(_callPath,expr);
        if((_seriesLastBar[key]??-1)+1!=_bar){
          throw const PineRuntimeException('history_order',
            'Stateful series call must execute once on every closed bar in this tier');
        }
        _seriesLastBar[key]=_bar;
        final args=PineSeriesDispatch.bind(expr,[for(final arg in expr.arguments)_eval(arg.value,frame)],_seen.last);
        if(name=='ta.barssince'){
          return _since.putIfAbsent(key,()=>PineBarsSinceState(budget)).step(_bool(args[0]));
        }
        final capacity=limits.maxHistory<1001?limits.maxHistory:1001;
        final state=_pivots.putIfAbsent(key,()=>PinePivotState(budget,capacity:capacity,high:name=='ta.pivothigh'));
        final left=_integer(args[1]),right=_integer(args[2]);
        if(left<1||right<1||left>500||right>500){
          throw const PineRuntimeException('pivot_length','Pivot legs must be positive bounded integers (1..500)');
        }
        return state.step(_bar,_num(args[0]),left,right);
      }
      if(PineScalarDispatch.supports(name)){
        final values=PineScalarDispatch.bind(expr,
          [for(final arg in expr.arguments)_eval(arg.value,frame)]);
        if(name=='math.sum'){
          final key=(_callPath,expr);
          if(_sumLastBar[key]==_bar){
            throw const PineRuntimeException('unsupported_repeated_series_call',
              'math.sum cannot execute the same written call twice on one closed bar yet');
          }
          _sumLastBar[key]=_bar;
          final capacity=limits.maxHistory<500?limits.maxHistory:500;
          final state=_sums.putIfAbsent(key,()=>PineRollingSum(budget,capacity:capacity));
          return state.step(_num(values[0]),_integer(values[1]));
        }
        return PineScalarDispatch.evaluate(name,values,budget);
      }
      if(name.startsWith('math.')){
        final args=[for(final arg in expr.arguments)_num(_eval(arg.value,frame))];
        if(args.any((x)=>x==null))return null;
        return switch(name){
          'math.abs'=>args.first!.abs(),
          'math.min'=>args.reduce((a,c)=>a!<c!?a:c),
          'math.max'=>args.reduce((a,c)=>a!>c!?a:c),
          _=>throw const PineRuntimeException('unsupported_function',
              'Unsupported math runtime function'),
        };
      }
      final fn=program._functions[name];
      if(fn==null) {
        throw PineRuntimeException('unsupported_function',
            'No Stage 3a function: '+name);
      }
      // The actual AST call expression is the history scope identity.
      // All local vars, SMA calls and persistent variables are keyed by it.
      final values=<String,Object?>{};
      for(var i=0;i<expr.arguments.length;i++) {
        final argument=expr.arguments[i];
        final target=argument.name ??
            (i<fn.parameters.length?fn.parameters[i].name:'');
        values[target]=_eval(argument.value,frame);
      }
      final previousPath=_callPath;
      _callPath=previousPath+'/'+expr.span.line.toString()+':'+expr.span.column.toString();
      final local=_PineFrame(frame);
      try {
        for(final parameter in fn.parameters) {
          Object? value=values[parameter.name];
          if(!values.containsKey(parameter.name)&&
              parameter.defaultValue!=null){
            value=_eval(parameter.defaultValue!,frame);
          }
          local.locals[parameter.name]=_PineBinding(value);
        }
        return _execute(fn.body,local);
      } finally { _callPath=previousPath; }
    }
    throw const PineRuntimeException('unsupported_expression',
        'Unimplemented Stage 3a expression');
  }

  Object? _execute(List<PineStatement> body,_PineFrame frame) {
    Object? last;
    for(final stmt in body) {
      _charge();
      if(stmt is PineTupleDeclarationStatement){
        final result=_eval(stmt.value,frame);
        if(result is! List<Object?>||result.length!=stmt.targets.length){
          throw const PineRuntimeException('tuple_arity','Runtime tuple shape differs from declaration');
        }
        for(var i=0;i<result.length;i++){
          final name=stmt.targets[i].name;
          if(name!='_')frame.locals[name]=_PineBinding(result[i]);
        }
        last=result;
      }else if(stmt is PineSequenceStatement){
        last=_execute(stmt.statements,frame);
      }else if(stmt is PineReferenceVariableStatement){
        final persistent=stmt.mode=='var'||stmt.mode=='varip';
        final key=(_callPath,stmt);
        final value=persistent&&_persistent.containsKey(key)?_persistent[key]:_eval(stmt.value,frame);
        if(persistent&&!_persistent.containsKey(key)){
          budget.consume(work:0,values:1);_persistent[key]=value;
        }
        frame.locals[stmt.name]=_PineBinding(value,definition:persistent?stmt:null,callPath:_callPath);
        last=value;
      }else if(stmt is PineVariableStatement) {
        final persistent=stmt.mode=='var'||stmt.mode=='varip';
        final key=(_callPath,stmt);
        Object? value;
        if(persistent&&_persistent.containsKey(key)) {
          value=_persistent[key];
        }else{
          value=_eval(stmt.value,frame);
          if(persistent){
            budget.consume(work:0,values:1);
            _persistent[key]=value;
          }
        }
        frame.locals[stmt.name]=_PineBinding(value,
            definition:persistent?stmt:null,
            callPath:_callPath);
        last=value;
      }else if(stmt is PineAssignmentStatement){
        final binding=frame.find(stmt.name);
        if(binding==null){
          throw PineRuntimeException('undefined',
              'Reassignment to undeclared '+stmt.name);
        }
        final rhs=_eval(stmt.value,frame);
        final op=stmt.operator;
        if(binding.value is PineRuntimeMap||rhs is PineRuntimeMap){
          throw const PineRuntimeException('unsupported_map_reassign','Map reference reassignment is not enabled');
        }
        if(op==':=') {
          binding.value=rhs;
        }else{
          final a=_num(binding.value),c=_num(rhs);
          binding.value=a==null||c==null?null:switch(op){
            '+='=>a+c,'-='=>a-c,'*='=>a*c,
            '/='=>c==0?null:a/c,'%='=>c==0?null:a%c,
            _=>throw const PineRuntimeException('operator',
                'Unsupported assignment operator'),
          };
        }
        if(binding.definition!=null) {
          _persistent[(binding.callPath,binding.definition!)]=binding.value;
        }
        last=binding.value;
      }else if(stmt is PineExpressionStatement) {
        last=_eval(stmt.expression,frame);
      }else if(stmt is PineIfStatement) {
        last=_execute(_bool(_eval(stmt.condition,frame))
            ?stmt.thenBody:stmt.elseBody,_PineFrame(frame));
      }else if(stmt is PineSwitchStatement) {
        final selector=stmt.selector==null?null:_eval(stmt.selector!,frame);
        for(final arm in stmt.arms){
          if(arm.match==null ||
              (stmt.selector==null
                ?_bool(_eval(arm.match!,frame))
                :selector==_eval(arm.match!,frame))){
            last=_execute(arm.body,_PineFrame(frame));
            break;
          }
        }
      }else if(stmt is PineForStatement) {
        final start=_integer(_eval(stmt.from,frame));
        final finish=_integer(_eval(stmt.to,frame));
        final step=stmt.step==null?1:_integer(_eval(stmt.step!,frame));
        if(step<=0){
          throw const PineRuntimeException('loop_step',
              'Pine for step must be positive');
        }
        final direction=finish>=start?1:-1;
        var iterations=0;
        for(var i=start;direction>0?i<=finish:i>=finish;
            i+=step*direction){
          if(++iterations>maxLoopIterations){
            throw const PineRuntimeException('loop_limit',
                'Pine loop iteration cap exceeded');
          }
          _charge();
          final local=_PineFrame(frame);
          local.locals[stmt.name]=_PineBinding(i.toDouble());
          try{last=_execute(stmt.body,local);}
          on _PineContinue {continue;}
          on _PineBreak {break;}
        }
      }else if(stmt is PineWhileStatement) {
        var iterations=0;
        while(_bool(_eval(stmt.condition,frame))){
          if(++iterations>maxLoopIterations){
            throw const PineRuntimeException('loop_limit',
                'Pine loop iteration cap exceeded');
          }
          _charge();
          try{last=_execute(stmt.body,_PineFrame(frame));}
          on _PineContinue {continue;}
          on _PineBreak {break;}
        }
      }else if(stmt is PineControlStatement) {
        if(stmt.action=='break')throw _PineBreak();
        if(stmt.action=='continue')throw _PineContinue();
      }else if(stmt is PineFunctionStatement){
        continue; // Function definitions are declarations, never side effects.
      }
    }
    return last;
  }

  void advance(TradeCandle closedBar){
    if(_stopped)throw const PineRuntimeException('closed',
        'Indicator runtime was stopped after a prior failure');
    if(program.legacy!=null){
      throw const PineRuntimeException('legacy_executor',
          'Use legacy evaluate for originally supported source');
    }
    try{
      _charge();
      _bar++;
      _seen.add(closedBar);
      budget.consume(work:0,values:1);
      final global=_PineFrame(null);
      _execute(program.ast.statements,global);
      for(final entry in global.locals.entries){
        if(entry.value.value is PineRuntimeMap)continue;
        final history=_history.putIfAbsent(entry.key,()=>[]);
        while(history.length<_bar)history.add(null);
        history.add(entry.value.value);
        budget.consume(work:0,values:1);
      }
      for(final plot in _plots) {
        if(plot.length!=_bar+1) {
          throw const PineRuntimeException('plot_order',
              'A global plot was skipped or evaluated more than once');
        }
      }
    }catch(_){
      _stopped=true;
      rethrow;
    }
  }

  /// Replay is deterministic and NO FUTURE DATA IS READ: only [0,cutoff).
  /// Full prefix replay is O(cutoff * script work), trading memory for
  /// correctness. An unsuccessful rebuild retains the previous instance.
  void rebuild(List<TradeCandle> source,int cutoff){
    if(cutoff<0||cutoff>source.length){
      throw const PineRuntimeException('invalid_cutoff',
          'Replay cutoff is outside verified available candles');
    }
    final candidate=program.newInstance(
        limits:limits,maxLoopIterations:maxLoopIterations);
    try {
      for(var i=0;i<cutoff;i++)candidate.advance(source[i]);
    }catch(_){candidate.close();rethrow;}
    budget.stop();
    _persistent..clear()..addAll(candidate._persistent);
    _ta..clear()..addAll(candidate._ta);
    _sums..clear()..addAll(candidate._sums);
    _sumLastBar..clear()..addAll(candidate._sumLastBar);
    _callHistory..clear()..addAll(candidate._callHistory);
    _since..clear()..addAll(candidate._since);
    _pivots..clear()..addAll(candidate._pivots);
    _seriesLastBar..clear()..addAll(candidate._seriesLastBar);
    _indicators..clear()..addAll(candidate._indicators);
    _security..clear()..addAll(candidate._security);
    _history..clear()..addAll(candidate._history);
    _seen..clear()..addAll(candidate._seen);
    _plots=candidate._plots;
    _bar=candidate._bar;
    _stopped=false;
    budget=candidate.budget;
  }
  void close(){budget.stop();_stopped=true;}
}

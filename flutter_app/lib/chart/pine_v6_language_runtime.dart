import '../data/tradelab_data.dart';
import 'pine_runtime_core.dart';
import 'pine_subset_program.dart';
import 'pine_v6_frontend.dart';
import 'pine_function_registry.dart';
import 'pine_ta_library.dart';

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
      this._functions, this._plotCalls);

  final String source;
  final PineScriptAst ast;
  final PineSubsetProgram? legacy;
  final Map<String, PineFunctionStatement> _functions;
  final List<PineCallExpression> _plotCalls;

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

  static PineV6LanguageProgram compile(String source) {
    final prepared=const PineV6Frontend().prepare(source);
    if(prepared.hasErrors) {
      throw PineRuntimeException('compile_invalid',
          prepared.message??'Invalid Pine syntax or semantics');
    }
    final functions=<String,PineFunctionStatement>{};
    final plots=<PineCallExpression>[];
    for(final stmt in prepared.ast.statements) {
      if(stmt is PineFunctionStatement)functions[stmt.name]=stmt;
    }

    var usesNewTa=false;
    void validateExpr(PineExpression expr, {bool global=false}) {
      if(expr is PineLiteralExpression || expr is PineIdentifierExpression) {
        return;
      }
      if(expr is PineHistoryExpression) {
        if(expr.target is! PineIdentifierExpression) {
          throw const PineRuntimeException('unsupported_history',
              'Stage 3a history requires a named series, not arbitrary expression');
        }
        validateExpr(expr.offset);
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
          'indicator','plot','na','nz','input.int','input.float',
          'math.abs','math.min','math.max',
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
        if(stmt is PineVariableStatement) {
          validateExpr(stmt.value);
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

    if(prepared.legacyProgram==null) {
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
      if(!advanced(prepared.ast.statements)&&!usesNewTa){
        throw const PineRuntimeException('unsupported_legacy',
            'Only previously executable numeric programs or verified Stage 3a language are supported');
      }
      if(plots.isEmpty) {
        throw const PineRuntimeException('missing_plot',
            'Stage 3a numeric language requires at least one global plot');
      }
    }
    return PineV6LanguageProgram._(
        source,prepared.ast,prepared.legacyProgram,functions,plots);
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
  _PineBinding(this.value,{this.definition,this.callSite});
  Object? value;
  final PineVariableStatement? definition;
  final PineCallExpression? callSite;
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
  final Map<(PineCallExpression?,PineVariableStatement),Object?> _persistent={};
  final Map<(PineCallExpression?,PineCallExpression),PineTaState> _ta={};
  final Map<String,List<Object?>> _history={};
  final List<TradeCandle> _seen=[];
  late List<List<double?>> _plots;
  int _bar=-1;
  bool _stopped=false;
  PineCallExpression? _callSite;

  int get completedBars=>_bar+1;
  Object? persistentValue(String name) {
    for(final entry in _persistent.entries) {
      if(entry.key.$2.name==name && entry.key.$1==null)return entry.value;
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
        'color'=>expr.value,
        _=>throw const PineRuntimeException('literal',
            'Unsupported literal type'),
      };
    }
    if(expr is PineIdentifierExpression){
      final name=expr.name;
      if(name=='bar_index')return _bar.toDouble();
      final found=frame.find(name);
      if(found!=null)return found.value;
      final candle=_seen.last;
      return switch(name){
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
      final name=(expr.target as PineIdentifierExpression).name;
      final offset=_integer(_eval(expr.offset,frame));
      if(offset<0||offset>=limits.maxHistory) {
        throw const PineRuntimeException('history_limit',
            'History offset outside bounded window');
      }
      if(offset==0)return _eval(expr.target,frame);
      final index=_bar-offset;
      if(index<0)return null;
      if(name=='bar_index')return index.toDouble();
      if(<String>{'close','open','high','low','hl2','hlc3','ohlc4'}
          .contains(name)){
        final c=_seen[index];
        return switch(name){
          'close'=>c.close,'open'=>c.open,'high'=>c.high,'low'=>c.low,
          'hl2'=>(c.high+c.low)/2,
          'hlc3'=>(c.high+c.low+c.close)/3,
          _=>(c.open+c.high+c.low+c.close)/4,
        };
      }
      final history=_history[name];
      return history==null||index>=history.length?null:history[index];
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
      final ta=PineFunctionRegistry.ta[name];
      if(ta!=null&&!ta.tupleResult){
        final args=ta.arguments(expr.arguments.map((a)=>a.name).toList(),
            [for(final arg in expr.arguments)_eval(arg.value,frame)]);
        final key=(_callSite,expr);
        final state=_ta.putIfAbsent(key,()=>PineTaState(ta,budget));
        return state.step(args,_seen.last,_bar==0?null:_seen[_bar-1].close);
      }
      if(name=='input.int'||name=='input.float') {
        return _eval(expr.arguments.first.value,frame);
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
      final previous=_callSite;
      _callSite=expr;
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
      } finally { _callSite=previous; }
    }
    throw const PineRuntimeException('unsupported_expression',
        'Unimplemented Stage 3a expression');
  }

  Object? _execute(List<PineStatement> body,_PineFrame frame) {
    Object? last;
    for(final stmt in body) {
      _charge();
      if(stmt is PineVariableStatement) {
        final persistent=stmt.mode=='var'||stmt.mode=='varip';
        final key=(_callSite,stmt);
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
            callSite:_callSite);
        last=value;
      }else if(stmt is PineAssignmentStatement){
        final binding=frame.find(stmt.name);
        if(binding==null){
          throw PineRuntimeException('undefined',
              'Reassignment to undeclared '+stmt.name);
        }
        final rhs=_eval(stmt.value,frame);
        final op=stmt.operator;
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
          _persistent[(binding.callSite,binding.definition!)]=binding.value;
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
    _history..clear()..addAll(candidate._history);
    _seen..clear()..addAll(candidate._seen);
    _plots=candidate._plots;
    _bar=candidate._bar;
    _stopped=false;
    budget=candidate.budget;
  }
  void close(){budget.stop();_stopped=true;}
}

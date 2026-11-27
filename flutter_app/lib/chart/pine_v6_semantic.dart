import 'pine_v6_ast.dart';
import 'pine_function_registry.dart';

part 'pine_v6_semantic_registry.dart';

enum PineBaseType { intType, floatType, boolType, stringType, colorType, unknown, tupleType, voidType, mapType, tableType, lookaheadType, gapsType, directionType, ocaType }
enum PineQualifier { constant, input, simple, series }
class PineTypeInfo {
  const PineTypeInfo(this.type,this.qualifier,{this.mapKey,this.mapValue});
  final PineBaseType? mapKey,mapValue;
  final PineBaseType type;
  final PineQualifier qualifier;
  static const unknown=PineTypeInfo(PineBaseType.unknown,PineQualifier.series);
  static const voidType=PineTypeInfo(PineBaseType.voidType,PineQualifier.constant);
  @override String toString() => qualifier.name+' '+type.name;
}
class PineSemanticResult {
  const PineSemanticResult(this.diagnostics,this.inferred,{
    this.completed=true,this.lastVisitedLine=0,
  });
  /// False when the diagnostic cap or resource budget interrupted traversal.
  final bool completed;
  final int lastVisitedLine;
  final List<PineDiagnostic> diagnostics;
  final Map<PineExpression,PineTypeInfo> inferred;
}
class _PineSymbol {
  _PineSymbol(this.name,this.type,{this.function=null,this.params=const [],
      this.isParameter=false});
  final String name;
  PineTypeInfo type;
  final PineFunctionStatement? function;
  final List<PineFunctionParameter> params;
  final bool isParameter;
}
class _PineScope {
  _PineScope(this.parent);
  final _PineScope? parent;
  final Map<String,_PineSymbol> locals={};
  int get depth => (parent?.depth??-1)+1;
  _PineSymbol? lookup(String name) =>
      locals[name]??parent?.lookup(name);
}

class PineV6SemanticAnalyzer {
  PineV6SemanticAnalyzer({
    this.maxSymbols=16000,
    this.maxDuration=const Duration(seconds: 3),
  }):_uncappedAudit=false;
  /// Measurement only: removes the diagnostic cap, not time/node/symbol limits.
  /// Production frontends continue to use the default constructor.
  PineV6SemanticAnalyzer.forDiagnosticAudit({
    this.maxSymbols=16000,
    this.maxDuration=const Duration(seconds: 3),
  }):_uncappedAudit=true;
  final bool _uncappedAudit;
  bool get _atDiagnosticCap=>!_uncappedAudit&&_diagnostics.length>=48;
  bool _resourceInterrupted=false;
  int _lastVisitedLine=0;
  final int maxSymbols;
  final Duration maxDuration;
  final List<PineDiagnostic> _diagnostics=[];
  // Keep syntax-only notices out of the original 48-error budget.
  final List<PineDiagnostic> _unsupportedDiagnostics=[];
  final Map<PineExpression,PineTypeInfo> _inferred={};
  late Stopwatch _clock;
  var _visited=0;
  var _symbols=0;
  String? _functionName;
  int _loopDepth=0;
  _PineScope? _global;

  static const _bases=<String,PineBaseType>{
    'int':PineBaseType.intType,'float':PineBaseType.floatType,
    'bool':PineBaseType.boolType,'string':PineBaseType.stringType,
    'color':PineBaseType.colorType,
  };
  static const _quals=<String,PineQualifier>{
    'const':PineQualifier.constant,'input':PineQualifier.input,
    'simple':PineQualifier.simple,'series':PineQualifier.series,
  };
  static const _plots=<String>{
    'plot','plotshape','plotchar','plotarrow','plotbar','plotcandle',
    'hline','fill','bgcolor','barcolor',
  };
  static const _namespaces=<String>{
    'map','table','position','barmerge','alert','text','font',
    'ta','math','array','color','str','input','timeframe','request',
    'syminfo','barstate','ticker','chart','time','strategy','line','label','box',
    'plot','display','scale','format','shape','location','size','extend',
  };
  static const _builtInFunctions=<String>{
    'indicator','strategy','library','plot','plotshape','plotchar',
    'plotarrow','plotbar','plotcandle','hline','fill','bgcolor','barcolor',
    'nz','na','fixnan','alert','input','timestamp',
  };

  PineSemanticResult analyze(PineScriptAst ast){
    _diagnostics.clear();_unsupportedDiagnostics.clear();_inferred.clear();_symbols=0;_visited=0;
    _functionName=null;_loopDepth=0;_resourceInterrupted=false;_lastVisitedLine=0;
    _clock=Stopwatch()..start();
    final root=_PineScope(null);_global=root;
    for(final name in <String>['open','high','low','close','volume',
        'hl2','hlc3','ohlc4','hlcc4']){
      root.locals[name]=_PineSymbol(name,
          const PineTypeInfo(PineBaseType.floatType,PineQualifier.series));
    }
    for(final name in <String>['bar_index','time','time_close']){
      root.locals[name]=_PineSymbol(name,
          const PineTypeInfo(PineBaseType.intType,PineQualifier.series));
    }
    for(final statement in ast.statements){
      if(statement is PineFunctionStatement) {
        _define(root,statement.name,
          _PineSymbol(statement.name,PineTypeInfo.unknown,
              function:statement,params:statement.parameters),statement.span);
      }
    }
    for(final statement in ast.statements){
      _statement(statement,root);
      if(_atDiagnosticCap)break;
    }
    _clock.stop();
    return PineSemanticResult(
      List.unmodifiable([..._diagnostics,..._unsupportedDiagnostics]),
      Map.unmodifiable(_inferred),
      completed:!_atDiagnosticCap&&!_resourceInterrupted,
      lastVisitedLine:_lastVisitedLine,
    );
  }

  bool _budget(PineSourceSpan loc) {
    _visited++;
    if(_visited>maxSymbols*8||_symbols>maxSymbols) {
      _resourceInterrupted=true;
      _error('semantic_limit','Pine semantic resource budget exceeded',loc);
      return false;
    }
    if((_visited&127)==0&&_clock.elapsed>=maxDuration){
      _resourceInterrupted=true;
      _error('semantic_timeout','Pine semantic deadline exceeded',loc);
      return false;
    }
    if(_atDiagnosticCap)return false;
    if(loc.line>_lastVisitedLine)_lastVisitedLine=loc.line;
    return true;
  }
  void _error(String code,String message,PineSourceSpan loc,
      {PineDiagnosticSeverity severity=PineDiagnosticSeverity.error}){
    final destination=severity==PineDiagnosticSeverity.unsupported
        ?_unsupportedDiagnostics:_diagnostics;
    if(_uncappedAudit||destination.length<48)destination.add(PineDiagnostic(
      PineDiagnosticStage.semantic,code,message,loc,severity:severity));
  }
  void _define(_PineScope scope,String name,_PineSymbol symbol,PineSourceSpan loc){
    if(scope.locals.containsKey(name)) {
      _error('duplicate_name','Name is already defined in this scope: '+name,loc);
      return;
    }
    scope.locals[name]=symbol;
    _symbols++;
  }
  bool _numeric(PineBaseType type) =>
      type==PineBaseType.intType||type==PineBaseType.floatType;
  bool _compatible(PineBaseType target,PineBaseType value)=>
      target==PineBaseType.unknown||value==PineBaseType.unknown||
      target==value||(target==PineBaseType.floatType&&value==PineBaseType.intType);
  PineQualifier _stronger(PineQualifier a,PineQualifier b) =>
      a.index>=b.index?a:b;
  PineTypeInfo _join(PineTypeInfo a,PineTypeInfo b) {
    final qual=_stronger(a.qualifier,b.qualifier);
    if(a.type==PineBaseType.unknown)return PineTypeInfo(b.type,qual);
    if(b.type==PineBaseType.unknown)return PineTypeInfo(a.type,qual);
    if(_numeric(a.type)&&_numeric(b.type)) {
      return PineTypeInfo(a.type==PineBaseType.floatType||
          b.type==PineBaseType.floatType
          ?PineBaseType.floatType:PineBaseType.intType,qual);
    }
    return PineTypeInfo(a.type==b.type?a.type:PineBaseType.unknown,qual);
  }
  bool _require(PineTypeInfo actual,PineBaseType expected,
      PineSourceSpan loc,String code){
    if(actual.type!=PineBaseType.unknown&&
       !_compatible(expected,actual.type)) {
      _error(code,'Expected '+expected.name+', found '+actual.type.name,loc);
      return false;
    }
    return true;
  }
  void _body(List<PineStatement> statements,_PineScope scope){
    for(final statement in statements) {
      if(!_budget(statement.span))break;
      _statement(statement,scope);
    }
  }
  void _syntaxOnly(PineSourceSpan span,String feature){
    _error('syntax_only',feature+' parsed and checked; runtime not implemented yet',
      span,severity:PineDiagnosticSeverity.unsupported);
  }
  List<PineTypeInfo>? _tupleComponents(PineExpression expr,_PineScope scope){
    if(expr is PineTupleExpression){
      final types=[for(final item in expr.values)_inferred[item]??PineTypeInfo.unknown];
      var common=PineQualifier.constant;
      for(final type in types){common=_stronger(common,type.qualifier);}
      return [for(final type in types)PineTypeInfo(type.type,common)];
    }
    if(expr is PineCallExpression){
      const numeric=PineTypeInfo(PineBaseType.floatType,PineQualifier.series);
      // Signature metadata only, not TA implementation or evaluation.
      switch(expr.name){
        case 'ta.macd': case 'ta.bb': case 'ta.dmi':
          return const [numeric,numeric,numeric];
        case 'ta.supertrend':
          return const [numeric,numeric];
        case 'request.security':
          PineCallArgument? requested;
          for(final arg in expr.arguments){
            if(arg.name=='expression')requested=arg;
          }
          if(requested==null&&expr.arguments.length>=3&&
              expr.arguments[2].name==null)requested=expr.arguments[2];
          final value=requested?.value;
          if(value is PineTupleExpression){
            return [for(final type in _tupleComponents(value,scope)!)
              PineTypeInfo(type.type,PineQualifier.series)];
          }
          return null;
      }
      final function=scope.lookup(expr.name??'')?.function;
      if(function!=null&&function.body.isNotEmpty){
        var last=function.body.last;
        if(last is PineSequenceStatement&&last.statements.isNotEmpty){
          last=last.statements.last;
        }
        if(last is PineExpressionStatement&&last.expression is PineTupleExpression){
          return _tupleComponents(last.expression,scope);
        }
      }
    }
    return null;
  }
  void _checkReferenceTypes(List<PineIdentifierExpression> types,
      PineSourceSpan span){
    if(types.length!=2){
      _error('map_type_arity','Map requires key and value type arguments',span);
    }
    for(final type in types){
      if(!_bases.containsKey(type.name)){
        _error('unsupported_type_argument','Type argument not supported: '+type.name,
          type.span);
      }
    }
  }
  void _statement(PineStatement stmt,_PineScope scope){
    if(!_budget(stmt.span))return;
    if(stmt is PineSequenceStatement){
      _syntaxOnly(stmt.span,'Comma-separated statement sequence');
      _body(stmt.statements,scope);
    }else if(stmt is PineTupleDeclarationStatement){
      final rhs=_expression(stmt.value,scope);
      final components=_tupleComponents(stmt.value,scope);
      var valid=true;
      if(stmt.value is PineTupleExpression){
        _error('tuple_source','Tuple declarations require a function or structure result, not a standalone tuple literal',stmt.value.span);
        valid=false;
      }else if(components!=null&&components.length!=stmt.targets.length){
        _error('tuple_arity','Tuple target count does not match returned values',stmt.span);
        valid=false;
      }else if(components==null&&rhs.type!=PineBaseType.unknown&&
          rhs.type!=PineBaseType.tupleType){
        _error('tuple_required','Tuple declaration requires a tuple result',stmt.value.span);
        valid=false;
      }else if(components==null){
        _error('tuple_shape_unknown','Tuple result shape is not resolved',stmt.value.span,
          severity:PineDiagnosticSeverity.unsupported);
      }
      final names=<String>{};
      for(final target in stmt.targets){
        if(target.name=='_')continue;
        if(!names.add(target.name)||scope.locals.containsKey(target.name)){
          _error('duplicate_name','Name is already defined in this scope: '+target.name,
            target.span);
          valid=false;
        }
      }
      // Validate the full declaration before introducing any bindings.
      if(valid){
        for(var i=0;i<stmt.targets.length;i++){
          final target=stmt.targets[i];
          if(target.name=='_')continue;
          final type=components==null?PineTypeInfo.unknown:components[i];
          _define(scope,target.name,_PineSymbol(target.name,type),target.span);
        }
      }
      _syntaxOnly(stmt.span,'Tuple declaration');
    }else if(stmt is PineReferenceVariableStatement){
      final rhs=_expression(stmt.value,scope);
      if(stmt.typeName=='map'){
        _checkReferenceTypes(stmt.typeArguments,stmt.span);
        final value=stmt.value;
        if(value is PineCallExpression&&value.callee is PineGenericReferenceExpression){
          final generic=value.callee as PineGenericReferenceExpression;
          if(value.name=='map.new'&&
              generic.typeArguments.map((t)=>t.name).join(',')!=
              stmt.typeArguments.map((t)=>t.name).join(',')){
            _error('reference_type_mismatch','Map constructor types must match declaration',
              value.span);
          }
        }
      }
      final types=stmt.typeArguments;
      final declared=stmt.typeName=='map'
          ?PineTypeInfo(PineBaseType.mapType,PineQualifier.series,
              mapKey:types.length==2?_bases[types[0].name]:null,
              mapValue:types.length==2?_bases[types[1].name]:null)
          :const PineTypeInfo(PineBaseType.tableType,PineQualifier.series);
      if(!_compatible(declared.type,rhs.type)){
        _error('reference_type_mismatch','Reference initializer has incorrect type',stmt.value.span);
      }
      _define(scope,stmt.name,_PineSymbol(stmt.name,declared),stmt.span);
      _syntaxOnly(stmt.span,'Reference declaration');
    }else if(stmt is PineVariableStatement){
      final rhs=_expression(stmt.value,scope);
      final base=stmt.typeName==null?rhs.type:_bases[stmt.typeName!]??PineBaseType.unknown;
      // Only a literal na (not an unresolved user-function return type)
      // requires an explicit declaration type. Stage 2 cannot infer custom
      // function return types until the Stage 3 execution/type pass.
      if(base==PineBaseType.unknown &&
          stmt.value is PineLiteralExpression &&
          (stmt.value as PineLiteralExpression).literalType=='na') {
        _error('unknown_variable_type',
            'Explicit type required for na initialization',stmt.span);
      }
      if(base==PineBaseType.boolType&&
          stmt.value is PineLiteralExpression&&
          (stmt.value as PineLiteralExpression).literalType=='na'){
        _error('bool_na','Pine v6 bool cannot be na',stmt.value.span);
      }
      if(!_compatible(base,rhs.type)){
        _error('type_mismatch','Cannot initialize '+stmt.name+
          ' as '+base.name+' using '+rhs.type.name,stmt.value.span);
      }
      final declared=stmt.qualifier==null?rhs.qualifier:
          _quals[stmt.qualifier]??PineQualifier.series;
      if(stmt.qualifier!=null&&rhs.qualifier.index>declared.index){
        _error('qualifier_mismatch','Value qualifier exceeds declared qualifier',stmt.value.span);
      }
      _define(scope,stmt.name,_PineSymbol(stmt.name,
        PineTypeInfo(base,declared,mapKey:rhs.mapKey,mapValue:rhs.mapValue)),stmt.span);
    }else if(stmt is PineAssignmentStatement){
      final target=scope.lookup(stmt.name);
      if(target==null){
        _error('undefined_name','Cannot reassign undeclared name: '+stmt.name,stmt.span);
      }else if(target.isParameter){
        _error('immutable_parameter',
          'A user function cannot reassign its parameter',stmt.span);
      }else if(_functionName!=null&&
          _global?.locals[stmt.name]==target){
        _error('function_global_reassignment',
          'A user function cannot reassign a global variable',stmt.span);
      }
      final rhs=_expression(stmt.value,scope);
      if(target!=null&&!_compatible(target.type.type,rhs.type)) {
        _error('type_mismatch','Reassignment has incompatible type',stmt.value.span);
      }
      if(target!=null) {
        target.type=PineTypeInfo(target.type.type,
            _stronger(target.type.qualifier,rhs.qualifier),mapKey:target.type.mapKey,mapValue:target.type.mapValue);
      }
    }else if(stmt is PineExpressionStatement){
      _expression(stmt.expression,scope);
    }else if(stmt is PineIfStatement){
      final cond=_expression(stmt.condition,scope);
      _require(cond,PineBaseType.boolType,stmt.condition.span,'condition_type');
      _body(stmt.thenBody,_PineScope(scope));
      _body(stmt.elseBody,_PineScope(scope));
    }else if(stmt is PineWhileStatement){
      final cond=_expression(stmt.condition,scope);
      _require(cond,PineBaseType.boolType,stmt.condition.span,'condition_type');
      _loopDepth++;
      _body(stmt.body,_PineScope(scope));
      _loopDepth--;
    }else if(stmt is PineForStatement){
      for(final expr in [stmt.from,stmt.to,if(stmt.step!=null)stmt.step!]){
        final type=_expression(expr,scope);
        if(!_numeric(type.type)&&type.type!=PineBaseType.unknown){
          _error('range_type','For loop bounds must be numeric',expr.span);
        }
      }
      final local=_PineScope(scope);
      _define(local,stmt.name,_PineSymbol(stmt.name,
        const PineTypeInfo(PineBaseType.intType,PineQualifier.series)),stmt.span);
      _loopDepth++;
      _body(stmt.body,local);
      _loopDepth--;
    }else if(stmt is PineSwitchStatement){
      final selector=stmt.selector==null?null:_expression(stmt.selector!,scope);
      for(final arm in stmt.arms){
        if(arm.match!=null){
          final caseValue=_expression(arm.match!,scope);
          if(selector==null){
            _require(caseValue,PineBaseType.boolType,
                arm.match!.span,'condition_type');
          }else if(!_compatible(selector.type,caseValue.type)&&
              !_compatible(caseValue.type,selector.type)){
            _error('switch_case_type','Switch arm does not match selector type',
                arm.match!.span);
          }
        }
        _body(arm.body,_PineScope(scope));
      }
    }else if(stmt is PineFunctionStatement){
      if(scope.depth!=0){
        _error('nested_function','Pine function declarations must be global',stmt.span);
        return;
      }
      final saved=_functionName;
      final savedLoopDepth=_loopDepth;
      _functionName=stmt.name;
      _loopDepth=0; // Function bodies cannot inherit caller loop context.
      final child=_PineScope(scope);
      for(final parameter in stmt.parameters){
        if(parameter.defaultValue!=null){
          final rhs=_expression(parameter.defaultValue!,scope);
          if(parameter.typeName!=null &&
              !_compatible(_bases[parameter.typeName]??PineBaseType.unknown,rhs.type)){
            _error('parameter_default_type','Function default has incorrect type',
                parameter.span);
          }
        }
        _define(child,parameter.name,_PineSymbol(parameter.name,
          PineTypeInfo(_bases[parameter.typeName]??PineBaseType.unknown,
            _quals[parameter.qualifier]??PineQualifier.series),
          isParameter:true),parameter.span);
      }
      _body(stmt.body,child);
      _functionName=saved;
      _loopDepth=savedLoopDepth;
    }else if(stmt is PineControlStatement){
      if(_loopDepth==0){
        _error('loop_control_scope',
            stmt.action+' is allowed only within a for/while loop',stmt.span);
      }
    }
  }

  PineTypeInfo _expression(PineExpression expr,_PineScope scope){
    if(!_budget(expr.span))return PineTypeInfo.unknown;
    PineTypeInfo value=PineTypeInfo.unknown;
    if(expr is PineLiteralExpression){
      value=PineTypeInfo(switch(expr.literalType){
        'int'=>PineBaseType.intType,
        'float'=>PineBaseType.floatType,
        'bool'=>PineBaseType.boolType,
        'string'=>PineBaseType.stringType,
        'color'=>PineBaseType.colorType,
        _=>PineBaseType.unknown,
      },PineQualifier.constant);
    }else if(expr is PineIdentifierExpression){
      final symbol=scope.lookup(expr.name);
      if(symbol==null) {
        _error('undefined_name','Undeclared Pine identifier: '+expr.name,expr.span);
      }else{value=symbol.type;}
    }else if(expr is PineMemberExpression){
      final qualified=expr.qualifiedName;
      final base=qualified?.split('.').first;
      final member=_pineMembers[qualified];
      if(member!=null){
        value=member.type;
        if(member.unimplemented)_known(qualified!,expr.span);
      }else if(base!=null&&_namespaces.contains(base)){
        _error('undefined_name','Unknown Pine member: '+qualified!,expr.span);
      }else{
        _expression(expr.target,scope);
      }
    }else if(expr is PineUnaryExpression){
      final x=_expression(expr.value,scope);
      if(expr.operator=='not'||expr.operator=='!'){
        _require(x,PineBaseType.boolType,expr.span,'logical_type');
        value=PineTypeInfo(PineBaseType.boolType,x.qualifier);
      }else{
        if(!_numeric(x.type)&&x.type!=PineBaseType.unknown){
          _error('numeric_type','Unary +/- needs a numeric value',expr.span);
        }
        value=x;
      }
    }else if(expr is PineBinaryExpression){
      final a=_expression(expr.left,scope),c=_expression(expr.right,scope);
      final q=_stronger(a.qualifier,c.qualifier);
      if(['and','or','&&','||'].contains(expr.operator)){
        _require(a,PineBaseType.boolType,expr.left.span,'logical_type');
        _require(c,PineBaseType.boolType,expr.right.span,'logical_type');
        value=PineTypeInfo(PineBaseType.boolType,q);
      }else if(['==','!=','<','>','<=','>='].contains(expr.operator)){
        // Pine v6 rejects direct comparison with the na literal. It is not
        // equivalent to a boolean comparison; use na(x) instead.
        final directNa=(expr.left is PineLiteralExpression &&
                (expr.left as PineLiteralExpression).literalType=='na') ||
            (expr.right is PineLiteralExpression &&
                (expr.right as PineLiteralExpression).literalType=='na');
        if(directNa){
          _error('na_comparison',
              'Use na(x) instead of comparing an expression directly to na',
              expr.span);
        }else if(!_compatible(a.type,c.type)&&!_compatible(c.type,a.type)){
          _error('comparison_type','Cannot compare incompatible Pine types',expr.span);
        }
        value=PineTypeInfo(PineBaseType.boolType,q);
      }else if(expr.operator=='+' &&
        a.type==PineBaseType.stringType&&c.type==PineBaseType.stringType){
        value=PineTypeInfo(PineBaseType.stringType,q);
      }else{
        if((!_numeric(a.type)&&a.type!=PineBaseType.unknown)||
           (!_numeric(c.type)&&c.type!=PineBaseType.unknown)){
          _error('arithmetic_type','Arithmetic requires numeric arguments',expr.span);
        }
        value=_join(a,c);
      }
    }else if(expr is PineTernaryExpression){
      final cond=_expression(expr.condition,scope);
      _require(cond,PineBaseType.boolType,expr.condition.span,'condition_type');
      final yes=_expression(expr.thenValue,scope);
      final no=_expression(expr.elseValue,scope);
      if(!_compatible(yes.type,no.type)&&!_compatible(no.type,yes.type)){
        _error('ternary_type','Conditional branches have incompatible types',expr.span);
      }
      final combined=_join(yes,no);
      value=PineTypeInfo(combined.type,_stronger(cond.qualifier,combined.qualifier));
    }else if(expr is PineHistoryExpression){
      final original=_expression(expr.target,scope);
      final offset=_expression(expr.offset,scope);
      _require(offset,PineBaseType.intType,expr.offset.span,'history_offset');
      final index=expr.offset;
      if(index is PineUnaryExpression && index.operator=='-' &&
          index.value is PineLiteralExpression){
        final literal=index.value as PineLiteralExpression;
        if(literal.literalType=='int' && (int.tryParse(literal.value)??0)>0){
          _error('history_index','Future history index is not allowed',index.span);
        }
      }
      value=PineTypeInfo(original.type,PineQualifier.series);
    }else if(expr is PineTupleExpression){
      for(final child in expr.values)_expression(child,scope);
      value=const PineTypeInfo(PineBaseType.tupleType,PineQualifier.series);
    }else if(expr is PineCallExpression){
      value=_call(expr,scope);
    }
    _inferred[expr]=value;
    return value;
  }

  void _known(String name,PineSourceSpan span){
    _error('known_unimplemented',
        'Known Pine symbol; runtime not implemented yet: '+name,
        span,severity:PineDiagnosticSeverity.unsupported);
  }

  PineTypeInfo _checkLibraryCall(PineCallExpression call,List<PineTypeInfo> info,
      _LibrarySignature signature){
    // Select overload by binding names and checking supplied types, not a
    // namespace prefix. Report the closest candidate if none is valid.
    final options=<List<String>>[];
    for(final spec in signature.parameters) {
      final params=spec.isEmpty?<String>[]:spec.split(' ');
      options.add(params);
    }
    List<String>? best;
    List<int>? bestSlots;
    var bestScore=1<<30;
    for(final params in options){
      final names=params.map((p)=>p.split(':').first.replaceAll('?','')).toList();
      final slots=<int>[];
      final used=<int>{};
      var score=0;
      for(var i=0;i<info.length;i++){
        final arg=call.arguments[i];
        final slot=arg.name==null?i:names.indexOf(arg.name!);
        slots.add(slot);
        if(slot<0||slot>=params.length||!used.add(slot)){score+=4;continue;}
        final rule=params[slot].split(':').last;
        if(!_matchesLibraryRule(rule,info[i],info))score++;
      }
      for(var j=0;j<params.length;j++){
        if(!params[j].split(':').first.endsWith('?')&&!used.contains(j))score+=4;
      }
      if(score<bestScore){best=params;bestSlots=slots;bestScore=score;}
    }
    final params=best!,slots=bestSlots!,used=<int>{};
    for(var i=0;i<info.length;i++){
      final arg=call.arguments[i],slot=slots[i];
      if(slot<0||slot>=params.length){
        _error(arg.name==null?'function_arity':'unknown_named_argument',
          'Invalid argument '+(arg.name??'${i+1}')+' for '+call.name!,arg.span);
      }else if(!used.add(slot)){
        _error('duplicate_parameter_argument','Repeated argument for '+call.name!,arg.span);
      }else if(!_matchesLibraryRule(params[slot].split(':').last,info[i],info)){
        _error('argument_type','Wrong type or qualifier for '+call.name!+'.'+
            params[slot].split(':').first.replaceAll('?',''),arg.span);
      }
    }
    for(var j=0;j<params.length;j++){
      if(!params[j].split(':').first.endsWith('?')&&!used.contains(j)){
        _error('missing_function_argument','Missing '+params[j].split(':').first+
            ' for '+call.name!,call.span);
      }
    }
    final result=signature.result;
    if(result=='ticker'){
      final q=info.isEmpty?PineQualifier.simple:info.first.qualifier;
      return PineTypeInfo(PineBaseType.stringType,
          q==PineQualifier.series?q:PineQualifier.simple);
    }
    if(result=='mapValue'){
      final map=info.where((x)=>x.type==PineBaseType.mapType).firstOrNull;
      return PineTypeInfo(map?.mapValue??PineBaseType.unknown,PineQualifier.series);
    }
    if(result=='security'){
      // Semantic only. Existing tuple shape checking remains responsible for
      // tuple binding. Scalar expressions retain their actual type.
      for(var i=0;i<slots.length;i++){
        if(slots[i]>=0&&slots[i]<params.length&&
            params[slots[i]].startsWith('expression:')){
          return PineTypeInfo(info[i].type,PineQualifier.series);
        }
      }
      return PineTypeInfo.unknown;
    }
    final pair=result.split('/');
    return PineTypeInfo(_libraryTypes[pair[0]]!,
        pair.length==2?_quals[pair[1]]!:PineQualifier.series);
  }

  bool _matchesLibraryRule(String rule,PineTypeInfo actual,List<PineTypeInfo> args){
    if(actual.type==PineBaseType.unknown)return true;
    final parts=rule.split('/');
    if(parts.length>1&&actual.qualifier.index>_quals[parts[1]]!.index)return false;
    for(final type in parts.first.split('|')){
      if(type=='any')return true;
      if(type=='key'||type=='value'){
        final map=args.where((x)=>x.type==PineBaseType.mapType).firstOrNull;
        final expected=type=='key'?map?.mapKey:map?.mapValue;
        if(expected==null||_compatible(expected,actual.type))return true;
      }else{
        final expected=_libraryTypes[type];
        if(expected!=null&&_compatible(expected,actual.type))return true;
      }
    }
    return false;
  }

  PineTypeInfo _call(PineCallExpression call,_PineScope scope){
    final name=call.name;
    if(name==null){
      _expression(call.callee,scope);
      _error('invalid_callee','Expected function name',call.span);
      return PineTypeInfo.unknown;
    }
    final beforeErrors=_diagnostics.length;
    final info=<PineTypeInfo>[];
    final seen=<String>{};
    var named=false;
    for(final arg in call.arguments){
      info.add(_expression(arg.value,scope));
      if(arg.name!=null){
        named=true;
        if(!seen.add(arg.name!)){
          _error('duplicate_argument','Duplicate argument '+arg.name!,arg.span);
        }
      }else if(named){
        _error('positional_after_named','Positional argument after named argument',arg.span);
      }
    }
    if(call.callee is PineGenericReferenceExpression){
      final generic=call.callee as PineGenericReferenceExpression;
      if(name!='map.new'){
        _error('unknown_function','Unknown Pine function: '+name,call.span);
        return PineTypeInfo.unknown;
      }
      _checkReferenceTypes(generic.typeArguments,generic.span);
      if(info.isNotEmpty)_error('function_arity','map.new takes no arguments',call.span);
      _syntaxOnly(call.span,'Generic constructor');
      if(_diagnostics.length==beforeErrors)_known(name,call.span);
      final types=generic.typeArguments;
      return PineTypeInfo(PineBaseType.mapType,PineQualifier.series,
          mapKey:types.length==2?_bases[types[0].name]:null,
          mapValue:types.length==2?_bases[types[1].name]:null);
    }
    if(name=='int'){
      if(info.length!=1){
        _error('cast_arity','int() expects exactly one argument',call.span);
      }else if(!_numeric(info.first.type)&&info.first.type!=PineBaseType.unknown){
        _error('cast_type','int() requires a numeric value',call.arguments.first.span);
      }
      _syntaxOnly(call.span,'int() cast');
      return PineTypeInfo(PineBaseType.intType,
        info.isEmpty?PineQualifier.constant:info.first.qualifier);
    }
    if(_plots.contains(name)&&scope.depth>0){
      _error('plot_local_scope',name+'() is not permitted in a local Pine scope',call.span);
    }
    if(['indicator','strategy','library'].contains(name)&&scope.depth>0){
      _error('declaration_local_scope',name+'() must be declared globally',call.span);
    }
    if(name=='indicator'||name=='strategy'||name=='library') {
      if(info.isNotEmpty)_require(info.first,PineBaseType.stringType,
          call.arguments.first.span,'indicator_title_type');
      return PineTypeInfo.voidType;
    }
    if(_plots.contains(name)) {
      if(['plot','hline'].contains(name)&&info.isNotEmpty&&
          !_numeric(info.first.type)&&info.first.type!=PineBaseType.unknown){
        _error('plot_value_type','Plot series must be numeric',call.arguments.first.span);
      }
      for(var i=0;i<call.arguments.length;i++){
        if(call.arguments[i].name=='title'){
          _require(info[i],PineBaseType.stringType,
              call.arguments[i].span,'plot_title_type');
          if(info[i].qualifier!=PineQualifier.constant) {
            _error('plot_title_qualifier','Plot title must be const string',
                call.arguments[i].span);
          }
        }
      }
      return PineTypeInfo.voidType;
    }
    if(name=='nz'||name=='fixnan'){
      return info.isNotEmpty?info.first:PineTypeInfo.unknown;
    }
    if(name=='na'){
      return const PineTypeInfo(PineBaseType.boolType,PineQualifier.series);
    }
    final function=scope.lookup(name);
    if(function?.function!=null) {
      if(_functionName==name){
        _error('recursive_function','Pine user-defined functions cannot recurse',call.span);
      }
      final params=function!.params;
      // Map positional and named arguments to the *declared* parameters.
      // Counting arguments alone is insufficient: f(x=1, bogus=2) must not
      // accidentally pass the semantic gate when f only declares (x, y).
      final supplied=<String>{};
      final byName={for(final p in params)p.name:p};
      for(var i=0;i<call.arguments.length;i++){
        final arg=call.arguments[i];
        final parameter=arg.name!=null
            ?byName[arg.name]
            :i<params.length?params[i]:null;
        if(parameter==null){
          if(arg.name!=null){
            _error('unknown_named_argument',
                'Unknown named argument '+arg.name!+' in '+name,arg.span);
          }
          continue;
        }
        if(!supplied.add(parameter.name)){
          _error('duplicate_parameter_argument',
            'Function parameter '+parameter.name+' is passed more than once',
            arg.span);
          continue;
        }
        if(parameter.typeName!=null){
          final expected=_bases[parameter.typeName]??PineBaseType.unknown;
          if(!_compatible(expected,info[i].type)){
            _error('function_argument_type',
                'Argument for '+parameter.name+' requires '+expected.name,
                arg.span);
          }
        }
        if(parameter.qualifier!=null){
          final expected=_quals[parameter.qualifier];
          if(expected!=null&&info[i].qualifier.index>expected.index){
            _error('function_argument_qualifier',
                'Argument qualifier is too strong for '+parameter.name,
                arg.span);
          }
        }
      }
      for(final parameter in params){
        if(parameter.defaultValue==null&&!supplied.contains(parameter.name)){
          _error('missing_function_argument',
              'Missing required function argument '+parameter.name,
              call.span);
        }
      }
      if(call.arguments.length>params.length){
        _error('function_arity','Too many arguments to '+name,call.span);
      }
      return function.type;
    }
    final registered=_pineCalls[name];
    if(registered!=null){
      final result=_checkLibraryCall(call,info,registered);
      if(registered.unimplemented&&_diagnostics.length==beforeErrors){
        _known(name,call.span);
      }
      return result;
    }
    if(PineFunctionRegistry.ta.containsKey(name)){
      final signature=PineFunctionRegistry.ta[name];
      if(signature?.booleanResult==true){
        return const PineTypeInfo(PineBaseType.boolType,PineQualifier.series);
      }
      if(signature?.tupleResult==true){
        return const PineTypeInfo(PineBaseType.tupleType,PineQualifier.series);
      }
      // Pine v6 ta.ema() and ta.rsi() expect simple int (or weaker)
      // length; series int and float lengths are invalid.
      if(name=='ta.ema'||name=='ta.rsi'){
        int lengthPosition=1;
        for(var i=0;i<call.arguments.length;i++){
          if(call.arguments[i].name=='length'){
            lengthPosition=i;
            break;
          }
        }
        if(lengthPosition<info.length){
          final length=info[lengthPosition];
          if(length.type!=PineBaseType.intType &&
              length.type!=PineBaseType.unknown){
            _error('argument_type',name+' length must be int',
                call.arguments[lengthPosition].span);
          }
          if(length.qualifier.index>PineQualifier.simple.index){
            _error('argument_qualifier',
                name+' length requires simple int, not series int',
                call.arguments[lengthPosition].span);
          }
          final expr=call.arguments[lengthPosition].value;
          if(expr is PineLiteralExpression &&
              expr.literalType=='int' &&
              (int.tryParse(expr.value)??0)<1){
            _error('invalid_length',
                name+' length must be a positive integer',
                expr.span);
          }
        }
      }
      return const PineTypeInfo(PineBaseType.floatType,PineQualifier.series);
    }

    // https://www.tradingview.com/pine-script-reference/v6/#fun_math.max
    // All-int overloads return int; mixed numeric overloads return float.
    if(name=='math.max'){
      if(info.length<2){
        _error('function_arity','math.max requires at least two numbers',call.span);
      }
      var qual=PineQualifier.constant;
      var type=PineBaseType.intType;
      var unknown=false;
      for(var i=0;i<info.length;i++){
        final t=info[i];
        qual=_stronger(qual,t.qualifier);
        if(t.type==PineBaseType.unknown){unknown=true;}
        else if(!_numeric(t.type)){
          _error('argument_type','math.max requires numeric arguments',call.arguments[i].span);
        }else if(t.type==PineBaseType.floatType){type=PineBaseType.floatType;}
        // The reference exposes numbered variadic parameters.
        final argName=call.arguments[i].name;
        if(argName!=null&&argName!='number$i'){
          _error('unknown_named_argument','Invalid math.max argument: '+argName,call.arguments[i].span);
        }
      }
      return PineTypeInfo(unknown&&type!=PineBaseType.floatType
          ?PineBaseType.unknown:type,qual);
    }
    // https://www.tradingview.com/pine-script-reference/v6/#fun_str.contains
    // const/simple/series string overloads return the corresponding bool.
    if(name=='str.contains'){
      const parameters=['source','str'];
      final supplied=<String>{};
      var qual=PineQualifier.constant;
      for(var i=0;i<info.length;i++){
        final arg=call.arguments[i];
        final parameter=arg.name??(i<parameters.length?parameters[i]:null);
        if(parameter==null||!parameters.contains(parameter)){
          _error('unknown_named_argument','Invalid str.contains argument: '+(arg.name??'${i+1}'),arg.span);
        }else if(!supplied.add(parameter)){
          _error('duplicate_parameter_argument','Repeated str.contains argument: '+parameter,arg.span);
        }
        _require(info[i],PineBaseType.stringType,arg.span,'argument_type');
        qual=_stronger(qual,info[i].qualifier);
      }
      if(supplied.length!=2||info.length!=2){
        _error('function_arity','str.contains requires source and str',call.span);
      }
      if(qual==PineQualifier.input)qual=PineQualifier.simple;
      return PineTypeInfo(PineBaseType.boolType,qual);
    }
    if(const {'math.abs','math.min'}.contains(name)){
      var qual=PineQualifier.constant;
      for(final t in info)qual=_stronger(qual,t.qualifier);
      return PineTypeInfo(PineBaseType.floatType,qual);
    }
    if(!_builtInFunctions.contains(name)){
      _error('unknown_function','Unknown Pine function: '+name,call.span);
    }
    return PineTypeInfo.unknown;
  }
}

import 'pine_v6_ast.dart';
import 'pine_function_registry.dart';

enum PineBaseType { intType, floatType, boolType, stringType, colorType, unknown, tupleType, voidType }
enum PineQualifier { constant, input, simple, series }
class PineTypeInfo {
  const PineTypeInfo(this.type,this.qualifier);
  final PineBaseType type;
  final PineQualifier qualifier;
  static const unknown=PineTypeInfo(PineBaseType.unknown,PineQualifier.series);
  static const voidType=PineTypeInfo(PineBaseType.voidType,PineQualifier.constant);
  @override String toString() => qualifier.name+' '+type.name;
}
class PineSemanticResult {
  const PineSemanticResult(this.diagnostics,this.inferred);
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
  });
  final int maxSymbols;
  final Duration maxDuration;
  final List<PineDiagnostic> _diagnostics=[];
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
    _diagnostics.clear();_inferred.clear();_symbols=0;_visited=0;
    _functionName=null;_loopDepth=0;_clock=Stopwatch()..start();
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
      if(_diagnostics.length>=48)break;
    }
    _clock.stop();
    return PineSemanticResult(
      List.unmodifiable(_diagnostics),
      Map.unmodifiable(_inferred),
    );
  }

  bool _budget(PineSourceSpan loc) {
    _visited++;
    if(_visited>maxSymbols*8||_symbols>maxSymbols) {
      _error('semantic_limit','Pine semantic resource budget exceeded',loc);
      return false;
    }
    if((_visited&127)==0&&_clock.elapsed>=maxDuration){
      _error('semantic_timeout','Pine semantic deadline exceeded',loc);
      return false;
    }
    return _diagnostics.length<48;
  }
  void _error(String code,String message,PineSourceSpan loc,
      {PineDiagnosticSeverity severity=PineDiagnosticSeverity.error}){
    if(_diagnostics.length<48)_diagnostics.add(PineDiagnostic(
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
  void _statement(PineStatement stmt,_PineScope scope){
    if(!_budget(stmt.span))return;
    if(stmt is PineVariableStatement){
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
        PineTypeInfo(base,declared)),stmt.span);
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
            _stronger(target.type.qualifier,rhs.qualifier));
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
      if(base=='color') {
        value=const PineTypeInfo(PineBaseType.colorType,PineQualifier.constant);
      }else if(base=='timeframe'||base=='syminfo') {
        value=const PineTypeInfo(PineBaseType.stringType,PineQualifier.simple);
      }else if(base=='barstate'){
        value=const PineTypeInfo(PineBaseType.boolType,PineQualifier.series);
      }else if(base=='math'&&qualified=='math.pi') {
        value=const PineTypeInfo(PineBaseType.floatType,PineQualifier.constant);
      }else if(base!=null&&_namespaces.contains(base)) {
        value=PineTypeInfo.unknown;
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

  PineTypeInfo _call(PineCallExpression call,_PineScope scope){
    final name=call.name;
    if(name==null){
      _expression(call.callee,scope);
      _error('invalid_callee','Expected function name',call.span);
      return PineTypeInfo.unknown;
    }
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
    if(_plots.contains(name)||name=='alert') {
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
    if(name.startsWith('input.')){
      final kind=name.substring(6);
      return PineTypeInfo(_bases[kind]??PineBaseType.unknown,
          PineQualifier.input);
    }
    if(name.startsWith('ta.')){
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
    if(name.startsWith('request.')){
      return const PineTypeInfo(PineBaseType.floatType,PineQualifier.series);
    }
    if(name.startsWith('math.')){
      var qual=PineQualifier.constant;
      for(final t in info)qual=_stronger(qual,t.qualifier);
      return PineTypeInfo(PineBaseType.floatType,qual);
    }
    if(name.startsWith('str.')){
      return const PineTypeInfo(PineBaseType.stringType,PineQualifier.series);
    }
    if(name.startsWith('color.')){
      return const PineTypeInfo(PineBaseType.colorType,PineQualifier.series);
    }
    if(name.startsWith('array.')||name.startsWith('timeframe.')){
      return PineTypeInfo.unknown;
    }
    if(!_builtInFunctions.contains(name)){
      _error('unknown_function','Unknown Pine function: '+name,call.span);
    }
    return PineTypeInfo.unknown;
  }
}

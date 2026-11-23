import 'pine_v6_ast.dart';

class PineParseResult {
  const PineParseResult(this.ast,this.diagnostics);
  final PineScriptAst ast;
  final List<PineDiagnostic> diagnostics;
}
class _PineSyntaxStop implements Exception {}

/// Front-end grammar, deliberately independent from the existing numeric AST.
/// Produces syntax trees for v6 constructs without making them executable.
class PineV6Parser {
  PineV6Parser(this.tokens, {
    this.maxNodes=16000,
    this.maxDuration=const Duration(seconds: 3),
  });
  final List<PineToken> tokens;
  final int maxNodes;
  final Duration maxDuration;
  final List<PineDiagnostic> _errors=[];
  late final Stopwatch _clock;
  int _i=0,_nodes=0;

  static const _types=<String>{'int','float','bool','string','color'};
  static const _qualifiers=<String>{'const','input','simple','series'};
  static const _assign=<String>{':=','+=','-=','*=','/=','%='};
  static const _precedence=<String,int>{
    'or':1, '||':1, 'and':2, '&&':2,
    '==':3,'!=':3,'<':3,'>':3,'<=':3,'>=':3,
    '+':4,'-':4,'*':5,'/':5,'%':5,
  };

  PineToken get _at => _i<tokens.length?tokens[_i]:tokens.last;
  PineToken get _next => _i+1<tokens.length?tokens[_i+1]:tokens.last;
  bool get _done => _at.kind==PineTokenKind.eof;
  PineToken _take(){final result=_at;if(!_done)_i++;return result;}
  bool _is(String text)=>_at.text==text;
  bool _accept(String text) {
    if(!_is(text))return false;
    _take();return true;
  }
  bool _kind(PineTokenKind kind)=>_at.kind==kind;
  PineToken _expected(String text) {
    if(!_is(text))_fail('expected_token','Expected '+text);
    return _take();
  }
  PineToken _identifier() {
    if(!_kind(PineTokenKind.identifier)) {
      _fail('expected_identifier','Expected Pine identifier');
    }
    return _take();
  }
  Never _fail(String code,String message,[PineToken? where]) {
    if(_errors.length<48) {
      _errors.add(PineDiagnostic(PineDiagnosticStage.parser,
          code,message,(where??_at).span));
    }
    throw _PineSyntaxStop();
  }
  void _budget(){
    _nodes++;
    if(_nodes>maxNodes) {
      _fail('ast_limit','Pine AST node budget exceeded');
    }
    if((_nodes&63)==0 && _clock.elapsed>=maxDuration) {
      _fail('parser_timeout','Pine parser deadline exceeded');
    }
  }
  void _lines(){
    while(_kind(PineTokenKind.newline))_take();
  }
  void _synchronize(){
    while(!_done&&!_kind(PineTokenKind.newline)&&
        !_kind(PineTokenKind.dedent))_take();
    _lines();
  }

  PineParseResult parse(){
    _clock=Stopwatch()..start();
    if(tokens.isEmpty) {
      return PineParseResult(const PineScriptAst([]),
          [const PineDiagnostic(PineDiagnosticStage.parser,
              'empty_tokens','No lexer tokens',PineSourceSpan(1,1))]);
    }
    final result=<PineStatement>[];
    _lines();
    while(!_done){
      if(_kind(PineTokenKind.dedent)||_kind(PineTokenKind.indent)) {
        _errors.add(PineDiagnostic(PineDiagnosticStage.parser,
          'unexpected_indent','Unexpected Pine block boundary',_take().span));
        _lines();continue;
      }
      try {
        final statement = _statement();
        result.add(statement);
        if(!_ownsBlock(statement)&&!_done&&!_kind(PineTokenKind.dedent)&&
            !_kind(PineTokenKind.newline)) {
          _fail('trailing_tokens','Unexpected tokens after statement');
        }
      } on _PineSyntaxStop {
        _synchronize();
      }
      _lines();
      if(_errors.length>=48)break;
    }
    _clock.stop();
    return PineParseResult(PineScriptAst(List.unmodifiable(result)),_errors);
  }

  bool _isFunctionHeader(){
    var cursor=_i;
    if(cursor<tokens.length&&_types.contains(tokens[cursor].text))cursor++;
    if(cursor>=tokens.length||
        tokens[cursor].kind!=PineTokenKind.identifier)return false;
    cursor++;
    if(cursor>=tokens.length||tokens[cursor].text!='(')return false;
    var depth=0;
    for(var j=cursor;j<tokens.length;j++){
      final t=tokens[j];
      if(t.kind==PineTokenKind.newline&&depth==0)return false;
      if(t.text=='(')depth++;
      if(t.text==')')depth--;
      if(depth==0)return j+1<tokens.length&&tokens[j+1].text=='=>';
      if(t.kind==PineTokenKind.eof)return false;
    }
    return false;
  }

  bool _ownsBlock(PineStatement s) =>
      s is PineIfStatement || s is PineForStatement ||
      s is PineWhileStatement || s is PineSwitchStatement ||
      s is PineFunctionStatement;

  PineStatement _statement(){
    _budget();
    final first=_at;
    if(_accept('if'))return _if(first.span);
    if(_accept('for'))return _for(first.span);
    if(_accept('while'))return _while(first.span);
    if(_accept('switch'))return _switch(first.span);
    if(_accept('break'))return PineControlStatement(first.span,'break');
    if(_accept('continue'))return PineControlStatement(first.span,'continue');
    if(_isFunctionHeader())return _function();
    if(_kind(PineTokenKind.identifier)&&_assign.contains(_next.text)){
      final name=_take().text, op=_take().text;
      return PineAssignmentStatement(first.span,name,op,_expression());
    }
    var mode=<String>[];
    if(_is('var')||_is('varip'))mode.add(_take().text);
    String? qualifier,type;
    if(_qualifiers.contains(_at.text))qualifier=_take().text;
    if(_types.contains(_at.text))type=_take().text;
    if(mode.isNotEmpty||qualifier!=null||type!=null||
      (_kind(PineTokenKind.identifier)&&_next.text=='=')){
      final name=_identifier().text;
      _expected('=');
      return PineVariableStatement(first.span,name,_expression(),
          mode:mode.isEmpty?null:mode.first,typeName:type,qualifier:qualifier);
    }
    return PineExpressionStatement(first.span,_expression());
  }

  List<PineStatement> _block(){
    if(!_kind(PineTokenKind.newline)){
      _fail('expected_block','Expected newline before local Pine block');
    }
    _lines();
    if(!_kind(PineTokenKind.indent)){
      _fail('expected_indent','Expected four-space Pine local block');
    }
    _take();
    final body=<PineStatement>[];
    _lines();
    while(!_done&&!_kind(PineTokenKind.dedent)) {
      final before=_i;
      try {
        final statement = _statement();
        body.add(statement);
        if(!_ownsBlock(statement)&&!_done&&!_kind(PineTokenKind.newline)&&
            !_kind(PineTokenKind.dedent)) {
          _fail('trailing_tokens','Trailing tokens in local block');
        }
      } on _PineSyntaxStop { _synchronize(); }
      if(before==_i&&!_done)_take();
      _lines();
      if(body.length>maxNodes||_errors.length>=48)break;
    }
    if(_kind(PineTokenKind.dedent))_take();
    if(body.isEmpty)_errors.add(PineDiagnostic(PineDiagnosticStage.parser,
        'empty_block','Pine local block must contain a statement',_at.span));
    return body;
  }

  PineIfStatement _if(PineSourceSpan loc){
    final condition=_expression();
    final yes=_block();
    final no=<PineStatement>[];
    if(_accept('else')) {
      if(_accept('if')) {
        no.add(_if(loc));
      } else {
        no.addAll(_block());
      }
    }
    return PineIfStatement(loc,condition,yes,no);
  }
  PineForStatement _for(PineSourceSpan loc){
    final name=_identifier().text;
    _expected('=');
    final first=_expression();
    _expected('to');
    final last=_expression();
    PineExpression? step;
    if(_accept('by'))step=_expression();
    return PineForStatement(loc,name,first,last,step,_block());
  }
  PineWhileStatement _while(PineSourceSpan loc){
    final condition=_expression();
    return PineWhileStatement(loc,condition,_block());
  }
  PineSwitchStatement _switch(PineSourceSpan loc){
    PineExpression? selector;
    if(!_kind(PineTokenKind.newline))selector=_expression();
    _lines();
    if(!_kind(PineTokenKind.indent)) {
      _fail('expected_indent','Expected switch arm indentation');
    }
    _take();
    final arms=<PineSwitchArm>[];
    _lines();
    while(!_done&&!_kind(PineTokenKind.dedent)){
      final at=_at.span;
      try{
        PineExpression? key;
        if(!_is('=>'))key=_expression();
        _expected('=>');
        List<PineStatement> body;
        if(_kind(PineTokenKind.newline)){
          body=_block();
        } else {
          body=[PineExpressionStatement(_at.span,_expression())];
        }
        arms.add(PineSwitchArm(at,key,body));
        if(!_kind(PineTokenKind.newline)&&!_kind(PineTokenKind.dedent)&&
            !_done)_fail('trailing_switch','Unexpected tokens after switch arm');
      }on _PineSyntaxStop{_synchronize();}
      _lines();
    }
    if(_kind(PineTokenKind.dedent))_take();
    return PineSwitchStatement(loc,selector,arms);
  }

  PineFunctionStatement _function(){
    final start=_at.span;
    String? returnType;
    if(_types.contains(_at.text))returnType=_take().text;
    final name=_identifier().text;
    _expected('(');
    final parameters=<PineFunctionParameter>[];
    if(!_is(')')){
      do{
        final at=_at.span;
        String? qualifier,type;
        if(_qualifiers.contains(_at.text))qualifier=_take().text;
        if(_types.contains(_at.text))type=_take().text;
        final paramName=_identifier().text;
        PineExpression? def;
        if(_accept('='))def=_expression();
        parameters.add(PineFunctionParameter(at,paramName,
            typeName:type,qualifier:qualifier,defaultValue:def));
        if(parameters.length>64)_fail('parameter_limit','Too many Pine parameters');
        if(!_accept(','))break;
      }while(!_done);
    }
    _expected(')');
    _expected('=>');
    final body=_kind(PineTokenKind.newline)
        ? _block()
        : <PineStatement>[PineExpressionStatement(_at.span,_expression())];
    return PineFunctionStatement(start,name,parameters,body,
        returnType:returnType);
  }

  PineExpression _expression([int min=0]){
    _budget();
    var left=_unary();
    while(true){
      final precedence=_precedence[_at.text];
      if(precedence==null||precedence<min)break;
      final op=_take();
      final right=_expression(precedence+1);
      left=PineBinaryExpression(op.span,left,op.text,right);
    }
    if(min==0&&_accept('?')){
      final yes=_expression();
      _expected(':');
      left=PineTernaryExpression(left.span,left,yes,_expression());
    }
    return left;
  }
  PineExpression _unary(){
    if(_is('not')||_is('!')||_is('-')||_is('+')){
      final op=_take();
      return PineUnaryExpression(op.span,op.text,_unary());
    }
    return _postfix();
  }
  PineExpression _postfix(){
    var expr=_primary();
    while(true){
      if(_accept('.')){
        final member=(_kind(PineTokenKind.identifier)||_kind(PineTokenKind.keyword))
            ? _take().text : _identifier().text;
        expr=PineMemberExpression(expr.span,expr,member);
      }else if(_accept('[')){
        final offset=_expression();
        _expected(']');
        expr=PineHistoryExpression(expr.span,expr,offset);
      }else if(_accept('(')){
        final args=<PineCallArgument>[];
        if(!_is(')')){
          do{
            final where=_at.span;
            String? name;
            if((_kind(PineTokenKind.identifier)||
                 (_kind(PineTokenKind.keyword)&&_is('color')))&&
                _next.text=='='){
              name=_take().text;_take();
            }
            args.add(PineCallArgument(where,_expression(),name:name));
            if(args.length>64)_fail('argument_limit','Too many Pine call arguments');
            if(!_accept(','))break;
          }while(!_done);
        }
        _expected(')');
        expr=PineCallExpression(expr.span,expr,args);
      }else{break;}
    }
    return expr;
  }
  PineExpression _primary(){
    _budget();
    final tok=_at;
    if(_kind(PineTokenKind.number)){
      _take();return PineLiteralExpression(tok.span,tok.text,
          tok.text.contains('.')||tok.text.contains('e')||
          tok.text.contains('E')?'float':'int');
    }
    if(_kind(PineTokenKind.string)||_kind(PineTokenKind.color)){
      _take();return PineLiteralExpression(tok.span,tok.text,
          tok.kind==PineTokenKind.string?'string':'color');
    }
    if(_accept('true')||_accept('false')){
      return PineLiteralExpression(tok.span,tok.text,'bool');
    }
    if(_accept('na'))return PineLiteralExpression(tok.span,'na','na');
    if(_kind(PineTokenKind.identifier)||
        (tok.kind==PineTokenKind.keyword&&
         const {'indicator','strategy','library','input','color'}.contains(tok.text))){
      _take();return PineIdentifierExpression(tok.span,tok.text);
    }
    if(_accept('(')){
      if(_is(')'))_fail('empty_expression','Empty parenthesized expression');
      final expressions=<PineExpression>[_expression()];
      while(_accept(','))expressions.add(_expression());
      _expected(')');
      return expressions.length==1?expressions.single:
          PineTupleExpression(tok.span,expressions);
    }
    if(_accept('[')){
      final values=<PineExpression>[];
      if(!_is(']')){
        do{
          values.add(_expression());
          if(!_accept(','))break;
        }while(!_done);
      }
      _expected(']');
      return PineTupleExpression(tok.span,values);
    }
    _fail('expected_expression','Expected Pine expression',tok);
  }
}

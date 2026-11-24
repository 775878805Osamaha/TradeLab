import 'dart:convert';

enum PineTokenKind { identifier, keyword, number, string, color, symbol, newline, indent, dedent, eof }
class PineSourceSpan {
  const PineSourceSpan(this.line, this.column, [this.endLine, this.endColumn]);
  final int line, column;
  final int? endLine, endColumn;
  @override String toString() => '$line:$column';
}
class PineToken {
  const PineToken(this.kind, this.text, this.span);
  final PineTokenKind kind;
  final String text;
  final PineSourceSpan span;
}
enum PineDiagnosticStage { lexer, parser, semantic, compatibility }
enum PineDiagnosticSeverity { error, warning, unsupported }
class PineDiagnostic {
  const PineDiagnostic(this.stage, this.code, this.message, this.span,
      {this.severity = PineDiagnosticSeverity.error});
  final PineDiagnosticStage stage;
  final String code, message;
  final PineSourceSpan span;
  final PineDiagnosticSeverity severity;
  int get line => span.line;
  int get column => span.column;
  @override String toString() => stage.name + ':' + code + ' at ' +
      span.toString() + ': ' + message;
}
abstract class PineAstNode {
  const PineAstNode(this.span);
  final PineSourceSpan span;
  Map<String, Object?> toJson();
  String get snapshot => jsonEncode(toJson());
}
abstract class PineExpression extends PineAstNode { const PineExpression(super.span); }
abstract class PineStatement extends PineAstNode { const PineStatement(super.span); }

class PineScriptAst extends PineAstNode {
  const PineScriptAst(this.statements) : super(const PineSourceSpan(1, 1));
  final List<PineStatement> statements;
  @override Map<String, Object?> toJson() => {'node':'script','body':statements.map((s)=>s.toJson()).toList()};
}
class PineLiteralExpression extends PineExpression {
  const PineLiteralExpression(super.span,this.value,this.literalType);
  final String value,literalType;
  @override Map<String,Object?> toJson()=>{'node':'literal','type':literalType,'value':value};
}
class PineIdentifierExpression extends PineExpression {
  const PineIdentifierExpression(super.span,this.name);
  final String name;
  @override Map<String,Object?> toJson()=>{'node':'name','name':name};
}
class PineMemberExpression extends PineExpression {
  const PineMemberExpression(super.span,this.target,this.member);
  final PineExpression target;
  final String member;
  String? get qualifiedName {
    if(target is PineIdentifierExpression) {
      return (target as PineIdentifierExpression).name + '.' + member;
    }
    if(target is PineMemberExpression) {
      final base=(target as PineMemberExpression).qualifiedName;
      return base==null?null:base+'.'+member;
    }
    return null;
  }
  @override Map<String,Object?> toJson()=>{'node':'member','target':target.toJson(),'member':member};
}
class PineUnaryExpression extends PineExpression {
  const PineUnaryExpression(super.span,this.operator,this.value);
  final String operator;
  final PineExpression value;
  @override Map<String,Object?> toJson()=>{'node':'unary','op':operator,'value':value.toJson()};
}
class PineBinaryExpression extends PineExpression {
  const PineBinaryExpression(super.span,this.left,this.operator,this.right);
  final PineExpression left,right;
  final String operator;
  @override Map<String,Object?> toJson()=>{'node':'binary','op':operator,'left':left.toJson(),'right':right.toJson()};
}
class PineTernaryExpression extends PineExpression {
  const PineTernaryExpression(super.span,this.condition,this.thenValue,this.elseValue);
  final PineExpression condition,thenValue,elseValue;
  @override Map<String,Object?> toJson()=>{'node':'ternary','condition':condition.toJson(),'yes':thenValue.toJson(),'no':elseValue.toJson()};
}
class PineHistoryExpression extends PineExpression {
  const PineHistoryExpression(super.span,this.target,this.offset);
  final PineExpression target,offset;
  @override Map<String,Object?> toJson()=>{'node':'history','target':target.toJson(),'offset':offset.toJson()};
}
class PineCallArgument extends PineAstNode {
  const PineCallArgument(super.span,this.value,{this.name});
  final String? name;
  final PineExpression value;
  @override Map<String,Object?> toJson()=>{'name':name,'value':value.toJson()};
}
/// A generic constructor reference, distinct from numeric comparisons.
class PineGenericReferenceExpression extends PineExpression {
  const PineGenericReferenceExpression(super.span,this.target,this.typeArguments);
  final PineExpression target;
  final List<PineIdentifierExpression> typeArguments;
  @override Map<String,Object?> toJson()=>{'node':'generic_reference',
    'target':target.toJson(),'types':typeArguments.map((t)=>t.name).toList()};
}
class PineCallExpression extends PineExpression {
  const PineCallExpression(super.span,this.callee,this.arguments);
  final PineExpression callee;
  final List<PineCallArgument> arguments;
  String? get name {
    if(callee is PineIdentifierExpression)return (callee as PineIdentifierExpression).name;
    if(callee is PineMemberExpression)return (callee as PineMemberExpression).qualifiedName;
    if(callee is PineGenericReferenceExpression){
      final target=(callee as PineGenericReferenceExpression).target;
      if(target is PineMemberExpression)return target.qualifiedName;
    }
    return null;
  }
  @override Map<String,Object?> toJson()=>{'node':'call','callee':callee.toJson(),'args':arguments.map((a)=>a.toJson()).toList()};
}
class PineTupleExpression extends PineExpression {
  const PineTupleExpression(super.span,this.values);
  final List<PineExpression> values;
  @override Map<String,Object?> toJson()=>{'node':'tuple','values':values.map((v)=>v.toJson()).toList()};
}
class PineVariableStatement extends PineStatement {
  const PineVariableStatement(super.span,this.name,this.value,{this.mode,this.typeName,this.qualifier});
  final String name;
  final String? mode,typeName,qualifier;
  final PineExpression value;
  @override Map<String,Object?> toJson()=>{'node':'declare','name':name,'mode':mode,'type':typeName,'qualifier':qualifier,'value':value.toJson()};
}
/// Parse-only declarations. They intentionally do not inherit executable
/// scalar declarations or expression statements.
class PineTupleDeclarationStatement extends PineStatement {
  const PineTupleDeclarationStatement(super.span,this.targets,this.value);
  final List<PineIdentifierExpression> targets;
  final PineExpression value;
  @override Map<String,Object?> toJson()=>{'node':'tuple_declare',
    'targets':targets.map((t)=>t.toJson()).toList(),'value':value.toJson()};
}
class PineSequenceStatement extends PineStatement {
  const PineSequenceStatement(super.span,this.statements);
  final List<PineStatement> statements;
  @override Map<String,Object?> toJson()=>{'node':'sequence',
    'body':statements.map((s)=>s.toJson()).toList()};
}
class PineReferenceVariableStatement extends PineStatement {
  const PineReferenceVariableStatement(super.span,this.name,this.typeName,
    this.typeArguments,this.value,{this.mode,this.qualifier});
  final String name,typeName;
  final String? mode,qualifier;
  final List<PineIdentifierExpression> typeArguments;
  final PineExpression value;
  @override Map<String,Object?> toJson()=>{'node':'reference_declare',
    'name':name,'type':typeName,'types':typeArguments.map((t)=>t.name).toList(),
    'mode':mode,'qualifier':qualifier,'value':value.toJson()};
}
class PineAssignmentStatement extends PineStatement {
  const PineAssignmentStatement(super.span,this.name,this.operator,this.value);
  final String name,operator;
  final PineExpression value;
  @override Map<String,Object?> toJson()=>{'node':'assign','name':name,'op':operator,'value':value.toJson()};
}
class PineExpressionStatement extends PineStatement {
  const PineExpressionStatement(super.span,this.expression);
  final PineExpression expression;
  @override Map<String,Object?> toJson()=>{'node':'expression','value':expression.toJson()};
}
class PineIfStatement extends PineStatement {
  const PineIfStatement(super.span,this.condition,this.thenBody,this.elseBody);
  final PineExpression condition;
  final List<PineStatement> thenBody,elseBody;
  @override Map<String,Object?> toJson()=>{'node':'if','condition':condition.toJson(),'then':thenBody.map((s)=>s.toJson()).toList(),'else':elseBody.map((s)=>s.toJson()).toList()};
}
class PineForStatement extends PineStatement {
  const PineForStatement(super.span,this.name,this.from,this.to,this.step,this.body);
  final String name;
  final PineExpression from,to;
  final PineExpression? step;
  final List<PineStatement> body;
  @override Map<String,Object?> toJson()=>{'node':'for','iterator':name,'from':from.toJson(),'to':to.toJson(),'step':step?.toJson(),'body':body.map((s)=>s.toJson()).toList()};
}
class PineWhileStatement extends PineStatement {
  const PineWhileStatement(super.span,this.condition,this.body);
  final PineExpression condition;
  final List<PineStatement> body;
  @override Map<String,Object?> toJson()=>{'node':'while','condition':condition.toJson(),'body':body.map((s)=>s.toJson()).toList()};
}
class PineSwitchArm extends PineAstNode {
  const PineSwitchArm(super.span,this.match,this.body);
  final PineExpression? match;
  final List<PineStatement> body;
  @override Map<String,Object?> toJson()=>{'match':match?.toJson(),'body':body.map((s)=>s.toJson()).toList()};
}
class PineSwitchStatement extends PineStatement {
  const PineSwitchStatement(super.span,this.selector,this.arms);
  final PineExpression? selector;
  final List<PineSwitchArm> arms;
  @override Map<String,Object?> toJson()=>{'node':'switch','selector':selector?.toJson(),'arms':arms.map((a)=>a.toJson()).toList()};
}
class PineFunctionParameter extends PineAstNode {
  const PineFunctionParameter(super.span,this.name,{this.typeName,this.qualifier,this.defaultValue});
  final String name;
  final String? typeName,qualifier;
  final PineExpression? defaultValue;
  @override Map<String,Object?> toJson()=>{'name':name,'type':typeName,'qualifier':qualifier,'default':defaultValue?.toJson()};
}
class PineFunctionStatement extends PineStatement {
  const PineFunctionStatement(super.span,this.name,this.parameters,this.body,{this.returnType});
  final String name;
  final String? returnType;
  final List<PineFunctionParameter> parameters;
  final List<PineStatement> body;
  @override Map<String,Object?> toJson()=>{'node':'function','name':name,'returnType':returnType,'params':parameters.map((p)=>p.toJson()).toList(),'body':body.map((s)=>s.toJson()).toList()};
}
class PineControlStatement extends PineStatement {
  const PineControlStatement(super.span,this.action);
  final String action;
  @override Map<String,Object?> toJson()=>{'node':action};
}

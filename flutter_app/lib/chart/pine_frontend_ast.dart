import 'dart:convert';

/// Stage 2: AST ONLY. No stage-3 control-flow or persistence execution.
enum PineDiagnosticKind { lexical, syntax, semantic, unsupported, resource }

class PineDiagnostic {
  const PineDiagnostic(this.kind, this.code, this.message,
      this.line, this.column);
  final PineDiagnosticKind kind;
  final String code;
  final String message;
  final int line;
  final int column;
  @override
  String toString() => kind.name + ' ' + code + ' at ' +
      line.toString() + ':' + column.toString() + ': ' + message;
  Map<String, Object> toJson() => {
    'kind': kind.name, 'code': code, 'line': line,
    'column': column, 'message': message,
  };
}

class PineSourceSpan {
  const PineSourceSpan(this.line, this.column);
  final int line, column;
  Map<String, int> toJson() => {'line': line, 'column': column};
}

enum PineTokenKind {
  identifier, keyword, number, string, color, symbol,
  newline, indent, dedent, eof,
}
class PineToken {
  const PineToken(this.kind, this.text, this.span);
  final PineTokenKind kind;
  final String text;
  final PineSourceSpan span;
  @override
  String toString() => kind.name + '(' + text + ')@' +
      span.line.toString() + ':' + span.column.toString();
}

enum PineType { unknown, intType, floatType, boolType, stringType, colorType, naType }
enum PineQualifier { constant, input, simple, series }
enum PinePersistence { ordinary, variable, intrabar }
class PineInferredType {
  const PineInferredType(this.type, this.qualifier);
  final PineType type;
  final PineQualifier qualifier;
}

abstract class PineNode {
  const PineNode(this.span);
  final PineSourceSpan span;
  Map<String, Object?> toJson();
  Map<String, Object?> fields(String node, Map<String, Object?> extra) =>
      <String, Object?>{'node': node, 'line': span.line,
        'column': span.column, ...extra};
}
abstract class PineExpression extends PineNode {
  const PineExpression(super.span);
}
class PineLiteral extends PineExpression {
  const PineLiteral(super.span, this.value, this.type);
  final Object? value;
  final PineType type;
  @override
  Map<String, Object?> toJson() =>
      fields('literal', {'value': value, 'type': type.name});
}
class PineIdentifier extends PineExpression {
  const PineIdentifier(super.span, this.name);
  final String name;
  @override
  Map<String, Object?> toJson() => fields('name', {'name': name});
}
class PineUnary extends PineExpression {
  const PineUnary(super.span, this.operator, this.operand);
  final String operator;
  final PineExpression operand;
  @override
  Map<String, Object?> toJson() =>
      fields('unary', {'op': operator, 'value': operand.toJson()});
}
class PineBinary extends PineExpression {
  const PineBinary(super.span, this.operator, this.left, this.right);
  final String operator;
  final PineExpression left, right;
  @override
  Map<String, Object?> toJson() =>
      fields('binary', {'op': operator,
        'left': left.toJson(), 'right': right.toJson()});
}
class PineTernary extends PineExpression {
  const PineTernary(super.span, this.condition, this.yes, this.no);
  final PineExpression condition, yes, no;
  @override
  Map<String, Object?> toJson() => fields('ternary', {
    'condition': condition.toJson(), 'yes': yes.toJson(), 'no': no.toJson(),
  });
}
class PineArgument {
  const PineArgument(this.name, this.value);
  final String? name;
  final PineExpression value;
  Map<String, Object?> toJson() => {
    'name': name, 'value': value.toJson(),
  };
}
class PineCall extends PineExpression {
  const PineCall(super.span, this.target, this.arguments);
  final PineExpression target;
  final List<PineArgument> arguments;
  @override
  Map<String, Object?> toJson() => fields('call', {
    'target': target.toJson(),
    'arguments': arguments.map((a) => a.toJson()).toList(),
  });
}
class PineHistory extends PineExpression {
  const PineHistory(super.span, this.target, this.index);
  final PineExpression target, index;
  @override
  Map<String, Object?> toJson() => fields('history', {
    'target': target.toJson(), 'index': index.toJson(),
  });
}

abstract class PineStatement extends PineNode {
  const PineStatement(super.span);
}
class PineVariableDeclaration extends PineStatement {
  const PineVariableDeclaration(super.span, this.name, this.initializer,
      {this.typeName, this.qualifierName,
       this.persistence = PinePersistence.ordinary});
  final String name;
  final String? typeName;
  final String? qualifierName;
  final PinePersistence persistence;
  final PineExpression initializer;
  @override
  Map<String, Object?> toJson() => fields('declaration', {
    'name': name, 'type': typeName, 'qualifier': qualifierName,
    'persistence': persistence.name, 'value': initializer.toJson(),
  });
}
class PineReassignment extends PineStatement {
  const PineReassignment(super.span, this.name, this.operator, this.value);
  final String name, operator;
  final PineExpression value;
  @override
  Map<String, Object?> toJson() => fields('reassignment', {
    'name': name, 'operator': operator, 'value': value.toJson(),
  });
}
class PineExpressionStatement extends PineStatement {
  const PineExpressionStatement(super.span, this.expression);
  final PineExpression expression;
  @override
  Map<String, Object?> toJson() =>
      fields('expression', {'value': expression.toJson()});
}
class PineConditionalArm {
  const PineConditionalArm(this.condition, this.body);
  final PineExpression? condition;
  final List<PineStatement> body;
  Map<String, Object?> toJson() => {
    'condition': condition?.toJson(),
    'body': body.map((x) => x.toJson()).toList(),
  };
}
class PineIfStatement extends PineStatement {
  const PineIfStatement(super.span, this.arms);
  final List<PineConditionalArm> arms;
  @override
  Map<String, Object?> toJson() =>
      fields('if', {'arms': arms.map((a) => a.toJson()).toList()});
}
class PineSwitchArm {
  const PineSwitchArm(this.key, this.body);
  final PineExpression? key;
  final List<PineStatement> body;
  Map<String, Object?> toJson() => {
    'key': key?.toJson(), 'body': body.map((s) => s.toJson()).toList(),
  };
}
class PineSwitchStatement extends PineStatement {
  const PineSwitchStatement(super.span, this.value, this.arms);
  final PineExpression? value;
  final List<PineSwitchArm> arms;
  @override
  Map<String, Object?> toJson() => fields('switch', {
    'value': value?.toJson(), 'arms': arms.map((a) => a.toJson()).toList(),
  });
}
class PineForStatement extends PineStatement {
  const PineForStatement(super.span, this.variable, this.from,
      this.to, this.step, this.body);
  final String variable;
  final PineExpression from, to;
  final PineExpression? step;
  final List<PineStatement> body;
  @override
  Map<String, Object?> toJson() => fields('for', {
    'variable': variable, 'from': from.toJson(), 'to': to.toJson(),
    'step': step?.toJson(), 'body': body.map((s) => s.toJson()).toList(),
  });
}
class PineWhileStatement extends PineStatement {
  const PineWhileStatement(super.span, this.condition, this.body);
  final PineExpression condition;
  final List<PineStatement> body;
  @override
  Map<String, Object?> toJson() => fields('while', {
    'condition': condition.toJson(),
    'body': body.map((s) => s.toJson()).toList(),
  });
}
class PineFunctionParameter {
  const PineFunctionParameter(this.name, {this.typeName,
      this.qualifierName, this.defaultValue});
  final String name;
  final String? typeName, qualifierName;
  final PineExpression? defaultValue;
  Map<String, Object?> toJson() => {
    'name': name, 'type': typeName, 'qualifier': qualifierName,
    'default': defaultValue?.toJson(),
  };
}
class PineFunctionDeclaration extends PineStatement {
  const PineFunctionDeclaration(super.span, this.name, this.parameters, this.body);
  final String name;
  final List<PineFunctionParameter> parameters;
  final List<PineStatement> body;
  @override
  Map<String, Object?> toJson() => fields('function', {
    'name': name,
    'parameters': parameters.map((p) => p.toJson()).toList(),
    'body': body.map((s) => s.toJson()).toList(),
  });
}
class PineScriptAst extends PineNode {
  const PineScriptAst(super.span, this.statements);
  final List<PineStatement> statements;
  @override
  Map<String, Object?> toJson() => fields('script', {
    'statements': statements.map((s) => s.toJson()).toList(),
  });
  String snapshot() => jsonEncode(toJson());
}

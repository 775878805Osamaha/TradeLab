import 'pine_frontend_ast.dart';

class PineParseResult {
  const PineParseResult(this.ast, this.diagnostics);
  final PineScriptAst ast;
  final List<PineDiagnostic> diagnostics;
}

/// Source-spanned Pratt expression parser and indentation-driven statement
/// parser. Builds control-flow/function AST but DOES NOT execute it.
class PineParser {
  PineParser(this.tokens, {
    this.maxDepth = 48,
    this.maxStatements = 1500,
    this.timeout = const Duration(milliseconds: 900),
  }) : _clock = Stopwatch()..start();

  final List<PineToken> tokens;
  final int maxDepth, maxStatements;
  final Duration timeout;
  final Stopwatch _clock;
  final List<PineDiagnostic> errors = [];
  int _at = 0;
  int _depth = 0;
  int _statements = 0;

  PineToken get current => tokens[_at < tokens.length ? _at : tokens.length - 1];
  PineToken peek([int delta = 1]) =>
      tokens[_at + delta < tokens.length ? _at + delta : tokens.length - 1];
  bool get ended => current.kind == PineTokenKind.eof;
  bool isText(String text) => current.text == text;
  bool isKind(PineTokenKind kind) => current.kind == kind;
  PineToken advance() {
    final now = current;
    if (!ended) _at++;
    return now;
  }
  bool take(String text) {
    if (isText(text)) { advance(); return true; }
    return false;
  }
  bool takeKind(PineTokenKind kind) {
    if (isKind(kind)) { advance(); return true; }
    return false;
  }
  void report(String code, String message, [PineToken? token]) {
    final t = token ?? current;
    if (errors.length < 80) {
      errors.add(PineDiagnostic(
        PineDiagnosticKind.syntax, code, message,
        t.span.line, t.span.column));
    }
  }
  PineToken expect(String value) {
    if (isText(value)) return advance();
    report('expected', 'Expected ' + value);
    return current;
  }
  void separators() {
    while (isKind(PineTokenKind.newline) || isText(';')) advance();
  }
  void synchronize() {
    while (!ended && !isKind(PineTokenKind.newline) &&
        !isKind(PineTokenKind.dedent)) advance();
    if (isKind(PineTokenKind.newline)) advance();
  }
  void check() {
    if (_clock.elapsed >= timeout || _statements > maxStatements) {
      report('budget', 'Pine parser time/statement budget exceeded');
      throw const _PineParseLimit();
    }
    if (_depth > maxDepth) {
      report('depth', 'Pine syntax nesting budget exceeded');
      throw const _PineParseLimit();
    }
  }

  PineParseResult parse() {
    final body = <PineStatement>[];
    try {
      separators();
      while (!ended) {
        check();
        if (takeKind(PineTokenKind.dedent) ||
            takeKind(PineTokenKind.indent)) {
          report('scope', 'Unexpected indentation at global scope');
          continue;
        }
        final before = _at;
        final statement = _statement();
        if (statement != null) {
          body.add(statement);
          _statements++;
        } else {
          synchronize();
        }
        if (_at == before && !ended) advance();
        separators();
      }
    } on _PineParseLimit {
      // Return the valid prefix and a resource diagnostic without crashing UI.
    }
    final span = tokens.isEmpty ? const PineSourceSpan(1, 1) : tokens.first.span;
    return PineParseResult(PineScriptAst(span, body),
        List.unmodifiable(errors));
  }

  PineStatement? _statement() {
    check();
    if (isText('if')) return _ifStatement();
    if (isText('switch')) return _switchStatement();
    if (isText('for')) return _forStatement();
    if (isText('while')) return _whileStatement();
    if (_looksLikeFunction()) return _function();
    final start = current.span;
    PinePersistence persistence = PinePersistence.ordinary;
    if (take('var')) {
      persistence = PinePersistence.variable;
    } else if (take('varip')) {
      persistence = PinePersistence.intrabar;
    }
    String? qualifier;
    if ({'const','input','simple','series'}.contains(current.text)) {
      qualifier = advance().text;
    }
    String? typeName;
    if ({'int','float','bool','string','color'}.contains(current.text) &&
        peek().kind == PineTokenKind.identifier) {
      typeName = advance().text;
    }
    if (current.kind == PineTokenKind.identifier &&
        peek().text == '=') {
      final name = advance().text;
      advance();
      final value = _expression();
      if (value == null) return null;
      return PineVariableDeclaration(start, name, value,
        typeName: typeName, qualifierName: qualifier,
        persistence: persistence);
    }
    if (persistence != PinePersistence.ordinary ||
        qualifier != null || typeName != null) {
      report('declaration', 'Expected variable declaration');
      return null;
    }
    if (current.kind == PineTokenKind.identifier &&
        {':=', '+=','-=','*=','/=','%='}.contains(peek().text)) {
      final name = advance().text;
      final op = advance().text;
      final value = _expression();
      if (value == null) return null;
      return PineReassignment(start, name, op, value);
    }
    final value = _expression();
    return value == null ? null : PineExpressionStatement(start, value);
  }

  bool _looksLikeFunction() {
    if (current.kind != PineTokenKind.identifier || peek().text != '(') {
      return false;
    }
    var level = 0;
    for (var j = _at + 1; j < tokens.length && j < _at + 90; j++) {
      if (tokens[j].text == '(') level++;
      if (tokens[j].text == ')') {
        level--;
        if (level == 0) {
          return j + 1 < tokens.length && tokens[j + 1].text == '=>';
        }
      }
      if (tokens[j].kind == PineTokenKind.newline) return false;
    }
    return false;
  }

  PineFunctionDeclaration? _function() {
    final start = advance();
    expect('(');
    final params = <PineFunctionParameter>[];
    while (!ended && !isText(')') && params.length < 40) {
      String? qualifier;
      String? typeName;
      if ({'const','input','simple','series'}.contains(current.text)) {
        qualifier = advance().text;
      }
      if ({'int','float','bool','string','color'}.contains(current.text) &&
          peek().kind == PineTokenKind.identifier) {
        typeName = advance().text;
      }
      if (current.kind != PineTokenKind.identifier) {
        report('parameter', 'Function parameter name is required');
        return null;
      }
      final name = advance().text;
      PineExpression? fallback;
      if (take('=')) fallback = _expression();
      params.add(PineFunctionParameter(name, typeName: typeName,
          qualifierName: qualifier, defaultValue: fallback));
      if (!take(',')) break;
    }
    expect(')');
    expect('=>');
    final body = _body();
    return PineFunctionDeclaration(start.span, start.text, params, body);
  }

  PineIfStatement _ifStatement() {
    final start = advance().span;
    final arms = <PineConditionalArm>[];
    arms.add(PineConditionalArm(_expression(), _body()));
    while (isText('else')) {
      advance();
      if (take('if')) {
        arms.add(PineConditionalArm(_expression(), _body()));
      } else {
        arms.add(PineConditionalArm(null, _body()));
        break;
      }
    }
    return PineIfStatement(start, arms);
  }

  PineWhileStatement _whileStatement() {
    final start = advance().span;
    final expression = _expression() ??
        PineLiteral(start, false, PineType.boolType);
    return PineWhileStatement(start, expression, _body());
  }

  PineForStatement? _forStatement() {
    final start = advance().span;
    if (isText('int')) advance();
    if (current.kind != PineTokenKind.identifier) {
      report('for_variable', 'Loop variable identifier expected');
      return null;
    }
    final name = advance().text;
    expect('=');
    final from = _expression();
    expect('to');
    final to = _expression();
    PineExpression? step;
    if (take('by')) step = _expression();
    if (from == null || to == null) return null;
    return PineForStatement(start, name, from, to, step, _body());
  }

  PineSwitchStatement _switchStatement() {
    final start = advance().span;
    PineExpression? target;
    if (!isKind(PineTokenKind.newline)) target = _expression();
    if (!takeKind(PineTokenKind.newline) ||
        !takeKind(PineTokenKind.indent)) {
      report('switch_block', 'switch requires an indented body');
      return PineSwitchStatement(start, target, const []);
    }
    final arms = <PineSwitchArm>[];
    separators();
    while (!ended && !isKind(PineTokenKind.dedent) && arms.length < 100) {
      check();
      PineExpression? key;
      if (!isText('=>')) key = _expression();
      expect('=>');
      arms.add(PineSwitchArm(key, _body()));
      separators();
    }
    takeKind(PineTokenKind.dedent);
    return PineSwitchStatement(start, target, arms);
  }

  List<PineStatement> _body() {
    if (!takeKind(PineTokenKind.newline)) {
      final statement = _statement();
      return statement == null ? const [] : [statement];
    }
    separators();
    if (!takeKind(PineTokenKind.indent)) {
      report('block', 'Expected indented Pine block');
      return const [];
    }
    final statements = <PineStatement>[];
    separators();
    while (!ended && !isKind(PineTokenKind.dedent)) {
      check();
      final before = _at;
      final statement = _statement();
      if (statement == null) {
        synchronize();
      } else {
        statements.add(statement);
        _statements++;
      }
      if (before == _at && !ended) advance();
      separators();
    }
    takeKind(PineTokenKind.dedent);
    return statements;
  }

  static const Map<String, int> priority = {
    'or': 1, 'and': 2,
    '==': 3, '!=': 3,
    '<': 4, '>': 4, '<=': 4, '>=': 4,
    '+': 5, '-': 5,
    '*': 6, '/': 6, '%': 6,
  };

  PineExpression? _expression([int minPriority = 0]) {
    if (++_depth > maxDepth) {
      report('depth', 'Expression nesting limit exceeded');
      throw const _PineParseLimit();
    }
    try {
      final first = _prefix();
      if (first == null) return null;
      PineExpression left = first;
      while (true) {
        final power = priority[current.text];
        if (power == null || power < minPriority) break;
        final op = advance().text;
        final right = _expression(power + 1);
        if (right == null) return left;
        left = PineBinary(left.span, op, left, right);
      }
      if (minPriority == 0 && take('?')) {
        final yes = _expression();
        expect(':');
        final no = _expression();
        if (yes != null && no != null) {
          left = PineTernary(left.span, left, yes, no);
        }
      }
      return left;
    } finally {
      _depth--;
    }
  }

  PineExpression? _prefix() {
    final start = current.span;
    if (take('-')) {
      final right = _expression(7);
      return right == null ? null : PineUnary(start, '-', right);
    }
    if (take('+')) {
      final right = _expression(7);
      return right == null ? null : PineUnary(start, '+', right);
    }
    if (take('not')) {
      final right = _expression(7);
      return right == null ? null : PineUnary(start, 'not', right);
    }
    PineExpression? item;
    if (take('(')) {
      item = _expression();
      expect(')');
    } else if (isKind(PineTokenKind.number)) {
      final number = advance();
      final value = num.tryParse(number.text);
      item = PineLiteral(number.span, value,
          number.text.contains('.') || number.text.toLowerCase().contains('e')
              ? PineType.floatType : PineType.intType);
    } else if (isKind(PineTokenKind.string)) {
      final word = advance();
      item = PineLiteral(word.span, word.text, PineType.stringType);
    } else if (isKind(PineTokenKind.color)) {
      final color = advance();
      item = PineLiteral(color.span, color.text, PineType.colorType);
    } else if (isText('true') || isText('false')) {
      final value = advance();
      item = PineLiteral(value.span, value.text == 'true',
          PineType.boolType);
    } else if (take('na')) {
      item = PineLiteral(start, null, PineType.naType);
    } else if (isKind(PineTokenKind.identifier) ||
        {'indicator','strategy','library','input','color'}.contains(current.text)) {
      final name = advance();
      var path = name.text;
      while (take('.')) {
        if (current.kind != PineTokenKind.identifier &&
            current.kind != PineTokenKind.keyword) {
          report('member', 'Expected identifier after dot');
          return PineIdentifier(start, path);
        }
        path += '.' + advance().text;
      }
      item = PineIdentifier(start, path);
    } else {
      report('expression', 'Expected Pine expression');
      return null;
    }
    while (item != null) {
      if (take('(')) {
        final args = <PineArgument>[];
        while (!ended && !isText(')') && args.length < 60) {
          String? name;
          if (current.kind == PineTokenKind.identifier &&
              peek().text == '=') {
            name = advance().text;
            advance();
          }
          final value = _expression();
          if (value == null) break;
          args.add(PineArgument(name, value));
          if (!take(',')) break;
        }
        expect(')');
        item = PineCall(start, item, args);
      } else if (take('[')) {
        final value = _expression();
        expect(']');
        if (value == null) return item;
        item = PineHistory(start, item, value);
      } else {
        break;
      }
    }
    return item;
  }
}

class _PineParseLimit implements Exception {
  const _PineParseLimit();
}

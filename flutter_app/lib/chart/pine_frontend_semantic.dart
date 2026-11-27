import 'pine_frontend_ast.dart';

class PineSymbol {
  const PineSymbol(this.type, this.qualifier,
      {this.parameter = false, this.function = false});
  final PineType type;
  final PineQualifier qualifier;
  final bool parameter, function;
}

class _PineScope {
  _PineScope(this.parent, {this.inFunction = false})
      : depth = (parent?.depth ?? -1) + 1;
  final _PineScope? parent;
  final bool inFunction;
  final int depth;
  final Map<String, PineSymbol> locals = {};

  PineSymbol? lookup(String name) =>
      locals[name] ?? parent?.lookup(name);
  bool containsLocal(String name) => locals.containsKey(name);
}

/// Structural v6 semantic checks; accepted AST syntax is NOT runtime support.
/// This checks primitive types/qualifiers and source scopes for the AST subset.
/// Collections/references/overload resolution are not implemented in Stage 2.
class PineSemanticAnalyzer {
  PineSemanticAnalyzer({
    this.timeout = const Duration(milliseconds: 900),
    this.maxVisits = 25000,
  });
  final Duration timeout;
  final int maxVisits;
  final List<PineDiagnostic> diagnostics = [];
  late Stopwatch _timer;
  int _visits = 0;
  bool _exhausted = false;
  String? _functionName;

  static const globalOnly = <String>{
    'plot','plotshape','plotchar','plotarrow','plotbar','plotcandle',
    'hline','fill','barcolor','bgcolor','alertcondition',
    'indicator','strategy','library',
  };
  static const builtinFields = <String, PineSymbol>{
    'open': PineSymbol(PineType.floatType, PineQualifier.series),
    'high': PineSymbol(PineType.floatType, PineQualifier.series),
    'low': PineSymbol(PineType.floatType, PineQualifier.series),
    'close': PineSymbol(PineType.floatType, PineQualifier.series),
    'hl2': PineSymbol(PineType.floatType, PineQualifier.series),
    'hlc3': PineSymbol(PineType.floatType, PineQualifier.series),
    'ohlc4': PineSymbol(PineType.floatType, PineQualifier.series),
    'volume': PineSymbol(PineType.floatType, PineQualifier.series),
    'bar_index': PineSymbol(PineType.intType, PineQualifier.series),
    'time': PineSymbol(PineType.intType, PineQualifier.series),
  };
  static const namespaces = <String>{
    'ta','math','array','color','str','input','timeframe','request',
    'syminfo','barstate','chart','ticker','matrix','map',
  };
  static const booleanTa = <String>{
    'ta.crossover', 'ta.crossunder', 'ta.cross',
    'ta.rising', 'ta.falling',
  };

  bool _tick(PineNode node) {
    if (_exhausted) return false;
    _visits++;
    if (_visits > maxVisits || _timer.elapsed >= timeout) {
      diagnostics.add(PineDiagnostic(PineDiagnosticKind.resource,
          'semantic_budget', 'Pine semantic analysis budget exceeded',
          node.span.line, node.span.column));
      _exhausted = true;
      return false;
    }
    return true;
  }

  void _error(String code, String detail, PineNode node) {
    if (diagnostics.length < 80) {
      diagnostics.add(PineDiagnostic(PineDiagnosticKind.semantic,
          code, detail, node.span.line, node.span.column));
    }
  }

  static PineType _type(String? type) => switch (type) {
    'int' => PineType.intType,
    'float' => PineType.floatType,
    'bool' => PineType.boolType,
    'string' => PineType.stringType,
    'color' => PineType.colorType,
    _ => PineType.unknown,
  };
  static PineQualifier _qualifier(String? name) => switch (name) {
    'const' => PineQualifier.constant,
    'input' => PineQualifier.input,
    'simple' => PineQualifier.simple,
    _ => PineQualifier.series,
  };
  static PineQualifier _strongest(PineQualifier a, PineQualifier b) =>
      a.index > b.index ? a : b;
  static bool _numeric(PineType type) =>
      type == PineType.intType || type == PineType.floatType ||
      type == PineType.unknown || type == PineType.naType;
  static bool _assignable(PineType target, PineType source) {
    if (target == PineType.unknown || source == PineType.unknown ||
        source == PineType.naType) return true;
    if (target == source) return true;
    return target == PineType.floatType && source == PineType.intType;
  }

  List<PineDiagnostic> analyze(PineScriptAst ast) {
    _timer = Stopwatch()..start();
    diagnostics.clear();
    _visits = 0;
    _exhausted = false;
    final global = _PineScope(null);
    global.locals.addAll(builtinFields);
    // Pine user functions are available to analysis before their first call.
    for (final item in ast.statements) {
      if (item is PineFunctionDeclaration) {
        if (global.containsLocal(item.name)) {
          _error('duplicate_symbol', 'Duplicate Pine function: ' +
              item.name, item);
        } else {
          global.locals[item.name] = const PineSymbol(
              PineType.unknown, PineQualifier.series, function: true);
        }
      }
    }
    for (final stmt in ast.statements) {
      if (_exhausted) break;
      _statement(stmt, global);
    }
    _timer.stop();
    return List.unmodifiable(diagnostics);
  }

  void _statement(PineStatement stmt, _PineScope scope) {
    if (!_tick(stmt)) return;
    switch (stmt) {
      case PineVariableDeclaration():
        final value = _expression(stmt.initializer, scope);
        final declared = _type(stmt.typeName);
        if (scope.containsLocal(stmt.name)) {
          _error('duplicate_symbol',
              'Variable already declared in this scope: ' + stmt.name, stmt);
        }
        if (value.type == PineType.naType && declared == PineType.unknown) {
          _error('na_requires_type',
              'Declare a primitive type before assigning untyped na', stmt);
        }
        if (!_assignable(declared, value.type)) {
          _error('type_mismatch',
              'Cannot assign ' + value.type.name + ' to ' +
              declared.name, stmt);
        }
        final actualType = declared == PineType.unknown ?
            value.type : declared;
        final qualifier = stmt.qualifierName != null
            ? _qualifier(stmt.qualifierName)
            : value.qualifier;
        if (stmt.qualifierName != null &&
            value.qualifier.index > qualifier.index) {
          _error('qualifier_mismatch',
              'Value requires stronger qualifier than declaration', stmt);
        }
        if (!scope.containsLocal(stmt.name)) {
          scope.locals[stmt.name] = PineSymbol(actualType, qualifier);
        }
      case PineReassignment():
        final symbol = scope.lookup(stmt.name);
        final value = _expression(stmt.value, scope);
        if (symbol == null) {
          _error('unknown_symbol',
              'Cannot reassign undefined variable: ' + stmt.name, stmt);
        } else {
          if (!_assignable(symbol.type, value.type)) {
            _error('type_mismatch',
                'Reassignment changes declared type of ' + stmt.name, stmt);
          }
          if (symbol.parameter && scope.inFunction) {
            _error('immutable_parameter',
                'Cannot reassign a function parameter', stmt);
          }
          if (scope.inFunction && !scope.containsLocal(stmt.name) &&
              _isGlobalOwner(scope, stmt.name)) {
            _error('global_reassignment',
                'Function cannot reassign a global value variable', stmt);
          }
        }
      case PineExpressionStatement():
        _expression(stmt.expression, scope);
      case PineIfStatement():
        for (final arm in stmt.arms) {
          if (arm.condition != null) {
            _condition(arm.condition!, scope);
          }
          _block(arm.body,
              _PineScope(scope, inFunction: scope.inFunction));
        }
      case PineSwitchStatement():
        final subject = stmt.value == null ? null :
            _expression(stmt.value!, scope);
        for (final arm in stmt.arms) {
          if (arm.key != null) {
            final item = _expression(arm.key!, scope);
            if (subject != null &&
                !_assignable(subject.type, item.type)) {
              _error('type_mismatch',
                  'switch case type differs from subject', arm.key!);
            }
            if (subject == null) _condition(arm.key!, scope);
          }
          _block(arm.body,
              _PineScope(scope, inFunction: scope.inFunction));
        }
      case PineWhileStatement():
        _condition(stmt.condition, scope);
        _block(stmt.body,
            _PineScope(scope, inFunction: scope.inFunction));
      case PineForStatement():
        final first = _expression(stmt.from, scope);
        final last = _expression(stmt.to, scope);
        if (!_numeric(first.type) || !_numeric(last.type)) {
          _error('type_mismatch',
              'for bounds must be numeric', stmt);
        }
        if (stmt.step != null) {
          final step = _expression(stmt.step!, scope);
          if (!_numeric(step.type)) {
            _error('type_mismatch', 'for step must be numeric', stmt);
          }
        }
        final local = _PineScope(scope, inFunction: scope.inFunction);
        local.locals[stmt.variable] = const PineSymbol(
            PineType.intType, PineQualifier.series);
        _block(stmt.body, local);
      case PineFunctionDeclaration():
        if (scope.depth != 0) {
          _error('nested_function',
              'Function definitions must be global in Pine v6', stmt);
        }
        final previous = _functionName;
        _functionName = stmt.name;
        final local = _PineScope(scope, inFunction: true);
        for (final parameter in stmt.parameters) {
          if (local.containsLocal(parameter.name)) {
            _error('duplicate_parameter',
                'Duplicate function argument: ' + parameter.name, stmt);
          }
          if (parameter.defaultValue != null) {
            _expression(parameter.defaultValue!, scope);
          }
          local.locals[parameter.name] = PineSymbol(
              _type(parameter.typeName),
              _qualifier(parameter.qualifierName),
              parameter: true);
        }
        _block(stmt.body, local);
        _functionName = previous;
    }
  }

  bool _isGlobalOwner(_PineScope scope, String name) {
    var parent = scope.parent;
    while (parent != null) {
      if (parent.containsLocal(name)) return parent.depth == 0;
      parent = parent.parent;
    }
    return false;
  }

  void _block(List<PineStatement> items, _PineScope scope) {
    for (final stmt in items) {
      if (_exhausted) break;
      _statement(stmt, scope);
    }
  }

  void _condition(PineExpression condition, _PineScope scope) {
    final type = _expression(condition, scope);
    // v6 removed implicit numeric-to-bool casts. Keep unknown for recovery:
    // the original undefined-name error remains the primary diagnostic.
    if (type.type != PineType.boolType &&
        type.type != PineType.unknown) {
      _error('type_mismatch',
          'Pine v6 requires a bool condition; use an explicit comparison '
          'or bool() conversion', condition);
    }
  }

  PineInferredType _expression(PineExpression expr, _PineScope scope) {
    if (!_tick(expr)) {
      return const PineInferredType(
          PineType.unknown, PineQualifier.series);
    }
    const unknown = PineInferredType(
        PineType.unknown, PineQualifier.series);
    switch (expr) {
      case PineLiteral():
        return PineInferredType(expr.type, PineQualifier.constant);
      case PineIdentifier():
        final name = expr.name;
        if (name.startsWith('color.') &&
            !name.endsWith('.new') && !name.endsWith('.rgb')) {
          return const PineInferredType(
              PineType.colorType, PineQualifier.constant);
        }
        if (name.startsWith('barstate.')) {
          return const PineInferredType(
              PineType.boolType, PineQualifier.series);
        }
        if (name.startsWith('syminfo.')) return unknown;
        if (name.startsWith('timeframe.')) return unknown;
        if (name.startsWith('plot.style_') ||
            name.startsWith('display.')) return unknown;
        final variable = scope.lookup(name);
        if (variable == null) {
          _error('unknown_symbol', 'Undefined Pine variable: ' + name, expr);
          return unknown;
        }
        return PineInferredType(variable.type, variable.qualifier);
      case PineUnary():
        final value = _expression(expr.operand, scope);
        if (expr.operator == 'not') {
          if (value.type != PineType.boolType &&
              value.type != PineType.unknown) {
            _error('type_mismatch', 'Pine v6 not requires bool', expr);
          }
          return PineInferredType(PineType.boolType, value.qualifier);
        }
        if (!_numeric(value.type)) {
          _error('type_mismatch',
              'Unary arithmetic requires numeric operand', expr);
        }
        return value;
      case PineBinary():
        final left = _expression(expr.left, scope);
        final right = _expression(expr.right, scope);
        final qual = _strongest(left.qualifier, right.qualifier);
        if ({'==','!=','<','<=','>','>=','and','or'}.contains(expr.operator)) {
          if ({'and', 'or'}.contains(expr.operator)) {
            if ((left.type != PineType.boolType &&
                 left.type != PineType.unknown) ||
                (right.type != PineType.boolType &&
                 right.type != PineType.unknown)) {
              _error('type_mismatch',
                  'Pine v6 logical operators require bool operands', expr);
            }
          } else if (left.type == PineType.naType ||
                     right.type == PineType.naType) {
            _error('na_comparison',
                'Use na(x) instead of comparing an expression directly to na', expr);
          } else if ({'<','<=','>','>='}.contains(expr.operator) &&
              (!_numeric(left.type) || !_numeric(right.type))) {
            _error('type_mismatch',
                'Ordered comparison requires numeric operands', expr);
          } else if ({'==','!='}.contains(expr.operator) &&
              !_assignable(left.type, right.type) &&
              !_assignable(right.type, left.type)) {
            _error('type_mismatch',
                'Comparison operands have incompatible types', expr);
          }
          return PineInferredType(PineType.boolType, qual);
        }
        if (expr.operator == '+' &&
            left.type == PineType.stringType &&
            right.type == PineType.stringType) {
          return PineInferredType(PineType.stringType, qual);
        }
        if (!_numeric(left.type) || !_numeric(right.type)) {
          _error('type_mismatch', 'Arithmetic requires numbers', expr);
        }
        return PineInferredType(
          left.type == PineType.intType && right.type == PineType.intType &&
             expr.operator != '/' ? PineType.intType : PineType.floatType,
          qual);
      case PineTernary():
        _condition(expr.condition, scope);
        final yes = _expression(expr.yes, scope);
        final no = _expression(expr.no, scope);
        final kind = _assignable(yes.type, no.type) ? yes.type :
            (_assignable(no.type, yes.type) ? no.type : PineType.unknown);
        if (kind == PineType.unknown &&
            yes.type != PineType.unknown && no.type != PineType.unknown) {
          _error('type_mismatch', 'Ternary branch types differ', expr);
        }
        return PineInferredType(kind,
            _strongest(yes.qualifier, no.qualifier));
      case PineHistory():
        final base = _expression(expr.target, scope);
        final index = _expression(expr.index, scope);
        if (index.type != PineType.intType &&
            index.type != PineType.unknown) {
          _error('history_index', 'History index requires integer', expr.index);
        }
        if (expr.index is PineLiteral) {
          final literal = expr.index as PineLiteral;
          if (literal.value is num && (literal.value as num) < 0) {
            _error('history_index', 'Future history index is not allowed', expr.index);
          }
        }
        return PineInferredType(base.type, PineQualifier.series);
      case PineCall():
        final callee = expr.target;
        if (callee is! PineIdentifier) {
          _error('call_target', 'Unsupported dynamic function target', expr);
          return unknown;
        }
        final name = callee.name;
        final args = <PineInferredType>[];
        for (final item in expr.arguments) {
          args.add(_expression(item.value, scope));
        }
        if (globalOnly.contains(name) && scope.depth > 0) {
          _error('global_only',
              name + '() is illegal inside a Pine local scope', expr);
        }
        if (name == _functionName) {
          _error('recursive_function',
              'Pine user functions cannot call themselves', expr);
        }
        if ({'int', 'float', 'bool', 'string', 'color'}.contains(name)) {
          if (args.length != 1) {
            _error('argument_count',
                name + '() conversion requires one argument', expr);
          }
          return PineInferredType(_type(name),
              args.isEmpty ? PineQualifier.series : args.first.qualifier);
        }
        if (name.startsWith('input.')) {
          final type = switch (name) {
            'input.int' => PineType.intType,
            'input.float' => PineType.floatType,
            'input.bool' => PineType.boolType,
            'input.string' => PineType.stringType,
            'input.color' => PineType.colorType,
            _ => PineType.unknown,
          };
          return PineInferredType(type, PineQualifier.input);
        }
        if (name.startsWith('ta.')) {
          // The documented ta.ema() and ta.rsi() length arguments require a
          // simple int or a weaker qualifier, never a series int.
          if (name == 'ta.ema' || name == 'ta.rsi') {
            PineInferredType? length;
            for (var i = 0; i < expr.arguments.length; i++) {
              if (expr.arguments[i].name == 'length') {
                length = args[i];
                break;
              }
            }
            if (length == null && args.length > 1) length = args[1];
            if (length != null) {
              if (length.type != PineType.intType &&
                  length.type != PineType.unknown) {
                _error('argument_type',
                    name + ' length must be int', expr);
              }
              if (length.qualifier.index > PineQualifier.simple.index) {
                _error('argument_qualifier',
                    name + ' length requires simple int or weaker, not series', expr);
              }
            }
          }
          return PineInferredType(
              booleanTa.contains(name) ? PineType.boolType :
                  PineType.floatType, PineQualifier.series);
        }
        if (name.startsWith('math.')) {
          var q = PineQualifier.constant;
          for (final arg in args) {
            q = _strongest(q, arg.qualifier);
          }
          return PineInferredType(PineType.floatType, q);
        }
        if (name.startsWith('str.')) {
          return const PineInferredType(
              PineType.stringType, PineQualifier.series);
        }
        if (name.startsWith('color.')) {
          return const PineInferredType(
              PineType.colorType, PineQualifier.series);
        }
        if (name.startsWith('timeframe.') ||
            name.startsWith('request.') ||
            name.startsWith('array.') ||
            name.startsWith('map.') ||
            name.startsWith('matrix.')) return unknown;
        if (globalOnly.contains(name)) return unknown;
        if (name == 'nz' || name == 'fixnan') {
          return args.isEmpty ? unknown : args.first;
        }
        if (name == 'na') {
          return const PineInferredType(
              PineType.boolType, PineQualifier.series);
        }
        final symbol = scope.lookup(name);
        if (symbol != null && symbol.function) return unknown;
        _error('unknown_function', 'Unknown Pine function: ' + name, expr);
        return unknown;
    }
    return unknown;
  }
}

import 'pine_frontend_ast.dart';

class PineLexResult {
  const PineLexResult(this.tokens, this.diagnostics, this.version);
  final List<PineToken> tokens;
  final List<PineDiagnostic> diagnostics;
  final int? version;
}

/// Pine v6 physical lexer with source positions and indentation tokens.
/// Parenthesized multiline expressions permit arbitrary indentation (Pine v6
/// December 2025 syntax). A final operator also continues an expression.
/// It does not execute scripts and never reads chart/broker data.
class PineLexer {
  static const keywords = <String>{
    'if','else','switch','for','to','by','while','var','varip',
    'int','float','bool','string','color','const','input','simple','series',
    'true','false','na','and','or','not','break','continue','in',
    'indicator','strategy','library',
  };
  static const operators = <String>{
    ':=', '=>', '==', '!=', '<=', '>=', '+=', '-=', '*=', '/=', '%=',
  };
  static const wraps = <String>{
    '+','-','*','/','%','=',':=',',','?','and','or','<','>','<=','>=','==','!=',
  };

  static PineLexResult scan(String source, {
    int maxChars = 15000,
    int maxTokens = 8000,
    Duration timeout = const Duration(milliseconds: 800),
  }) {
    final errors = <PineDiagnostic>[];
    final tokens = <PineToken>[];
    if (source.length > maxChars) {
      errors.add(const PineDiagnostic(PineDiagnosticKind.resource,
          'source_limit', 'Pine source exceeds the configured character limit',
          1, 1));
      return PineLexResult(const [
        PineToken(PineTokenKind.eof, '', PineSourceSpan(1, 1)),
      ], errors, null);
    }
    final clock = Stopwatch()..start();
    final lines = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
        .split('\n');
    final indents = <int>[0];
    var bracketDepth = 0;
    var continuation = false;
    var exhausted = false;
    int? version;
    bool alpha(String c) => RegExp(r'[A-Za-z_]').hasMatch(c);
    bool digit(String c) => RegExp(r'[0-9]').hasMatch(c);
    bool word(String c) => RegExp(r'[A-Za-z_0-9]').hasMatch(c);
    bool hex(String c) => RegExp(r'[0-9a-fA-F]').hasMatch(c);

    void emit(PineTokenKind kind, String value, int line, int col) {
      if (tokens.length >= maxTokens) {
        if (!exhausted) {
          errors.add(PineDiagnostic(PineDiagnosticKind.resource,
            'token_limit', 'Pine token budget exhausted', line, col));
        }
        exhausted = true;
        return;
      }
      tokens.add(PineToken(kind, value, PineSourceSpan(line, col)));
    }

    for (var lineIndex = 0; lineIndex < lines.length && !exhausted;
         lineIndex++) {
      if (clock.elapsed >= timeout) {
        errors.add(PineDiagnostic(PineDiagnosticKind.resource, 'timeout',
          'Pine lexical deadline exceeded', lineIndex + 1, 1));
        break;
      }
      var raw = lines[lineIndex];
      final numbered = lineIndex + 1;
      final trimmed = raw.trimLeft();
      if (trimmed.startsWith('//@version=')) {
        version = int.tryParse(trimmed.substring('//@version='.length).trim());
      }
      if (trimmed.isEmpty || trimmed.startsWith('//')) continue;
      var indent = 0;
      var offset = 0;
      while (offset < raw.length && (raw[offset] == ' ' || raw[offset] == '\t')) {
        indent += raw[offset] == '\t' ? 4 : 1;
        offset++;
      }
      if (bracketDepth == 0 && !continuation) {
        if (indent > indents.last) {
          if (indent % 4 != 0 || indent - indents.last != 4) {
            errors.add(PineDiagnostic(PineDiagnosticKind.lexical, 'indent',
                'Local block requires one additional four-space indentation',
                numbered, 1));
          }
          indents.add(indent);
          emit(PineTokenKind.indent, '<indent>', numbered, 1);
        } else if (indent < indents.last) {
          while (indents.length > 1 && indent < indents.last) {
            indents.removeLast();
            emit(PineTokenKind.dedent, '<dedent>', numbered, 1);
          }
          if (indent != indents.last) {
            errors.add(PineDiagnostic(PineDiagnosticKind.lexical,
                'dedent', 'Inconsistent Pine indentation', numbered, 1));
          }
        }
      }
      var position = offset;
      while (position < raw.length && !exhausted) {
        if (tokens.length % 256 == 0 && clock.elapsed >= timeout) {
          errors.add(PineDiagnostic(PineDiagnosticKind.resource,
              'timeout', 'Pine lexical deadline exceeded',
              numbered, position + 1));
          exhausted = true;
          break;
        }
        final c = raw[position];
        if (c == ' ' || c == '\t') {
          position++;
          continue;
        }
        if (c == '/' && position + 1 < raw.length &&
            raw[position + 1] == '/') break;
        final spanCol = position + 1;
        if (c == '"' || c == "'") {
          final triple = position + 2 < raw.length &&
              raw[position + 1] == c && raw[position + 2] == c;
          final quoteCount = triple ? 3 : 1;
          final buffer = StringBuffer();
          var currentLine = lineIndex;
          var cursor = position + quoteCount;
          var closed = false;
          while (currentLine < lines.length) {
            final current = lines[currentLine];
            while (cursor < current.length) {
              if (current[cursor] == '\\' && !triple &&
                  cursor + 1 < current.length) {
                buffer.write(current.substring(cursor, cursor + 2));
                cursor += 2;
                continue;
              }
              final isEnd = triple
                  ? cursor + 2 < current.length &&
                      current[cursor] == c && current[cursor + 1] == c &&
                      current[cursor + 2] == c
                  : current[cursor] == c;
              if (isEnd) {
                cursor += quoteCount;
                closed = true;
                break;
              }
              buffer.write(current[cursor]);
              cursor++;
            }
            if (closed || !triple || currentLine + 1 >= lines.length) break;
            buffer.write('\n');
            currentLine++;
            cursor = 0;
          }
          if (!closed) {
            errors.add(PineDiagnostic(PineDiagnosticKind.lexical,
                'unterminated_string', 'Unterminated Pine string',
                numbered, spanCol));
            position = raw.length;
          } else {
            emit(PineTokenKind.string, buffer.toString(), numbered, spanCol);
            lineIndex = currentLine;
            raw = lines[lineIndex];
            position = cursor;
          }
          continue;
        }
        if (c == '#') {
          var until = position + 1;
          while (until < raw.length && hex(raw[until])) until++;
          final count = until - position - 1;
          if (count == 6 || count == 8) {
            emit(PineTokenKind.color, raw.substring(position, until),
                numbered, spanCol);
          } else {
            errors.add(PineDiagnostic(PineDiagnosticKind.lexical,
                'color', 'Hex color must use six or eight digits',
                numbered, spanCol));
          }
          position = until;
          continue;
        }
        if (alpha(c)) {
          var until = position + 1;
          while (until < raw.length && word(raw[until])) until++;
          final text = raw.substring(position, until);
          emit(keywords.contains(text) ? PineTokenKind.keyword :
              PineTokenKind.identifier, text, numbered, spanCol);
          position = until;
          continue;
        }
        if (digit(c) || (c == '.' && position + 1 < raw.length &&
            digit(raw[position + 1]))) {
          final candidate = RegExp(
              r'^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?')
              .firstMatch(raw.substring(position));
          final matched = candidate?.group(0);
          if (matched == null) {
            errors.add(PineDiagnostic(PineDiagnosticKind.lexical,
                'number', 'Invalid numeric literal', numbered, spanCol));
            position++;
          } else {
            emit(PineTokenKind.number, matched, numbered, spanCol);
            position += matched.length;
          }
          continue;
        }
        final pair = position + 1 < raw.length
            ? raw.substring(position, position + 2) : '';
        if (operators.contains(pair)) {
          emit(PineTokenKind.symbol, pair, numbered, spanCol);
          position += 2;
          continue;
        }
        if ('()[]{}.,:+-*/%?=<>'.contains(c)) {
          emit(PineTokenKind.symbol, c, numbered, spanCol);
          if (c == '(' || c == '[') bracketDepth++;
          if (c == ')' || c == ']') {
            bracketDepth--;
            if (bracketDepth < 0) {
              errors.add(PineDiagnostic(PineDiagnosticKind.lexical,
                  'unbalanced', 'Unexpected closing bracket',
                  numbered, spanCol));
              bracketDepth = 0;
            }
          }
          position++;
          continue;
        }
        errors.add(PineDiagnostic(PineDiagnosticKind.lexical,
            'character', 'Unsupported Pine character: ' + c,
            numbered, spanCol));
        position++;
      }
      if (bracketDepth > 0) {
        continuation = true;
      } else {
        final last = tokens.isEmpty ? '' : tokens.last.text;
        continuation = wraps.contains(last);
        if (!continuation && !exhausted) {
          emit(PineTokenKind.newline, '<newline>',
              lineIndex + 1, raw.length + 1);
        }
      }
    }
    if (bracketDepth != 0) {
      errors.add(PineDiagnostic(PineDiagnosticKind.lexical,
          'unbalanced', 'Unclosed bracket', lines.length, 1));
    }
    while (indents.length > 1) {
      indents.removeLast();
      emit(PineTokenKind.dedent, '<dedent>', lines.length, 1);
    }
    emit(PineTokenKind.eof, '<eof>', lines.length, 1);
    if (tokens.isEmpty || tokens.last.kind != PineTokenKind.eof) {
      tokens.add(PineToken(
          PineTokenKind.eof, '<eof>', PineSourceSpan(lines.length, 1)));
    }
    return PineLexResult(List.unmodifiable(tokens),
        List.unmodifiable(errors), version);
  }
}

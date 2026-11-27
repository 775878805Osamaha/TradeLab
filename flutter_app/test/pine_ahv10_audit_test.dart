import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_frontend.dart';
import 'package:tradelab_flutter/chart/pine_v6_language_runtime.dart';

void main() {
  test('AHV10 original fixture diagnostic baseline only; no execution', () {
    final source = File('test/fixtures/pine/ahv10.pine').readAsStringSync();
    expect(const LineSplitter().convert(source).length, 443);
    expect(source.startsWith('//@version=6\n'), isTrue);
    expect(source.endsWith('stop=curStop, limit=targetLine)'), isTrue);
    final result = const PineV6Frontend().prepare(source);
    // ignore: avoid_print
    print('AHV10_STATUS ${result.status.name} tokens=${result.tokens.length} statements=${result.ast.statements.length}');
    final errors=result.diagnostics.where((d)=>d.severity==PineDiagnosticSeverity.error).toList();
    final parser=errors.where((d)=>d.stage==PineDiagnosticStage.parser).toList();
    final semantic=errors.where((d)=>d.stage==PineDiagnosticStage.semantic).toList();
    final sites=errors.map((d)=>'${d.line}:${d.column}').toSet();
    // ignore: avoid_print
    print('AHV10_COUNTS ${jsonEncode({'parserErrors':parser.length,'semanticErrors':semantic.length,'uniqueErrorSites':sites.length,'allDiagnostics':result.diagnostics.length,'semanticDiagnostics':result.semantic.diagnostics.length,'parserSites':parser.map((d)=>'${d.line}:${d.column}').toList()})}');
    expect(parser,isEmpty,reason:'V10-01 syntax-only acceptance');
    for (final d in result.diagnostics) {
      // ignore: avoid_print
      print('AHV10_DIAG ${d.toString()}');
    }
    Object? compileError;
    try {
      PineV6LanguageProgram.compile(source);
    } catch (error) {
      compileError = error;
      // ignore: avoid_print
      print('AHV10_COMPILE $error');
    }
    expect(compileError, isNotNull, reason: 'Compiler must refuse current unsupported strategy');
    expect(result.canExecute, isFalse);
  });
}

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
    for (final d in result.diagnostics) {
      // ignore: avoid_print
      print('AHV10_DIAG ${d.toString()}');
    }
    try {
      PineV6LanguageProgram.compile(source);
      fail('Unexpected execution eligibility; review audit');
    } catch (error) {
      // ignore: avoid_print
      print('AHV10_COMPILE $error');
    }
    expect(result.canExecute, isFalse);
  });
}

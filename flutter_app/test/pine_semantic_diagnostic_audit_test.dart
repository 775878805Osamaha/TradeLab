import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradelab_flutter/chart/pine_v6_frontend.dart';

PineScriptAst parseAudit(String source) {
  final lexed=const PineV6Lexer().lex(source);
  expect(lexed.diagnostics,isEmpty,reason:'Audit requires complete lexical pass');
  final parsed=PineV6Parser(lexed.tokens).parse();
  expect(parsed.diagnostics,isEmpty,reason:'Audit requires complete parse');
  return parsed.ast;
}

String category(PineDiagnostic d) {
  if(d.severity==PineDiagnosticSeverity.unsupported)return 'unsupported_notice';
  if(d.severity!=PineDiagnosticSeverity.error)return 'other_notice';
  if(d.code=='unknown_function'||d.code=='undefined_name')return 'unresolved_name';
  if(d.code.contains('type')||d.code.contains('qualifier')||
      d.code=='bool_na'||d.code=='history_offset')return 'type_error';
  return 'other_error';
}

void main() {
  test('production still stops at 48 errors; audit traverses all 81 lines',(){
    final source=List.generate(80,(i)=>'a$i = missing$i').join('\n')+
        '\nlast = missingLast';
    final ast=parseAudit(source);
    final production=PineV6SemanticAnalyzer().analyze(ast);
    final audit=PineV6SemanticAnalyzer.forDiagnosticAudit().analyze(ast);
    expect(production.diagnostics,hasLength(48));
    expect(production.completed,isFalse);
    expect(production.lastVisitedLine,48);
    expect(audit.diagnostics,hasLength(81));
    expect(audit.completed,isTrue);
    expect(audit.lastVisitedLine,81);
    expect(audit.diagnostics.last.line,81);
    expect(audit.diagnostics.last.message,contains('missingLast'));
    expect(const PineV6Frontend().prepare(source).semantic.diagnostics,
        hasLength(48));
    expect(production.diagnostics.map((d)=>d.toString()),
        audit.diagnostics.take(48).map((d)=>d.toString()));
  });
  test('audit removes unsupported-notice cap but not production cap',(){
    final ast=parseAudit(List.generate(60,(i)=>'a$i = int(close)').join('\n'));
    final production=PineV6SemanticAnalyzer().analyze(ast);
    final audit=PineV6SemanticAnalyzer.forDiagnosticAudit().analyze(ast);
    expect(production.diagnostics.where((d)=>d.code=='syntax_only'),hasLength(48));
    expect(audit.diagnostics.where((d)=>d.code=='syntax_only'),hasLength(60));
    expect(audit.completed,isTrue);
    expect(audit.lastVisitedLine,60);
  });
  test('audit still signals an interrupted resource budget',(){
    final ast=parseAudit(List.generate(20,(i)=>'a$i = close').join('\n'));
    final result=PineV6SemanticAnalyzer.forDiagnosticAudit(maxSymbols:2).analyze(ast);
    expect(result.completed,isFalse);
    expect(result.diagnostics.any((d)=>d.code=='semantic_limit'),isTrue);
  });
  test('original Pine fixture full diagnostic census, no execution',(){
    final source=File('test/fixtures/pine/ahv10.pine').readAsStringSync();
    expect(const LineSplitter().convert(source),hasLength(443));
    final ast=parseAudit(source);
    final result=PineV6SemanticAnalyzer.forDiagnosticAudit().analyze(ast);
    expect(result.completed,isTrue,reason:'Do not report a partial count');
    expect(result.lastVisitedLine,443,reason:'Must inspect final source line');
    final counts=<String,int>{'type_error':0,'unresolved_name':0,
      'other_error':0,'unsupported_notice':0,'other_notice':0};
    for(final d in result.diagnostics) {
      final kind=category(d);
      counts[kind]=counts[kind]!+1;
      // ignore: avoid_print
      print('PINE_FULL_DIAG ${jsonEncode({'category':kind,'stage':d.stage.name,
        'severity':d.severity.name,'code':d.code,'line':d.line,
        'column':d.column,'message':d.message})}');
    }
    // ignore: avoid_print
    print('PINE_FULL_COUNTS ${jsonEncode({'lexer':0,'parser':0,
      'completed':result.completed,'lastVisitedLine':result.lastVisitedLine,
      'total':result.diagnostics.length,...counts})}');
  });
}

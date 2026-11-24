import '../data/tradelab_data.dart';
import 'pine_runtime_core.dart';
import 'pine_subset_program.dart';
import 'pine_v6_ast.dart';
import 'pine_v6_lexer.dart';
import 'pine_v6_parser.dart';
import 'pine_v6_semantic.dart';

export 'pine_v6_ast.dart';
export 'pine_v6_lexer.dart';
export 'pine_v6_parser.dart';
export 'pine_v6_semantic.dart';

enum PineFrontendStatus { executableSubset, parsedButNotExecutable, invalid }

class PineFrontendExecutionException implements Exception {
  const PineFrontendExecutionException(this.code,this.message);
  final String code, message;
  @override String toString() => 'Pine front-end: ' + code + ': ' + message;
}

class PineFrontendResult {
  const PineFrontendResult({
    required this.ast, required this.tokens,
    required this.diagnostics, required this.status,
    required this.semantic, this.legacyProgram,
  });
  final PineScriptAst ast;
  final List<PineToken> tokens;
  final List<PineDiagnostic> diagnostics;
  final PineFrontendStatus status;
  final PineSemanticResult semantic;
  final PineSubsetProgram? legacyProgram;
  bool get canExecute =>
      status == PineFrontendStatus.executableSubset&&legacyProgram!=null;
  bool get hasErrors => diagnostics.any((d)=>
      d.severity==PineDiagnosticSeverity.error);
  String? get message => diagnostics.isEmpty?null:diagnostics.first.toString();

  List<PineSubsetPlot> evaluateSupported(
      List<TradeCandle> candles, {
      PineRuntimeLimits limits = const PineRuntimeLimits(),
    }) {
    if (!canExecute) {
      throw PineFrontendExecutionException(
        status.name, message ?? 'Pine runtime is not yet supported');
    }
    return legacyProgram!.evaluateIncrementally(candles, limits: limits);
  }
}

/// Analysis and execution eligibility are intentionally separate.
/// An AST for valid var/varip/for/while/if/functions does NOT imply runtime
/// support. Existing numeric scripts continue to use the existing compiler.
class PineV6Frontend {
  const PineV6Frontend({
    this.lexer=const PineV6Lexer(),
    this.maxAstNodes=16000,
  });
  final PineV6Lexer lexer;
  final int maxAstNodes;

  PineFrontendResult prepare(String source) {
    final lexed=lexer.lex(source);
    if(lexed.tokens.isEmpty) {
      final empty=PineSemanticResult(const [],const {});
      return PineFrontendResult(ast:const PineScriptAst([]),
        tokens:const [],diagnostics:List.unmodifiable(lexed.diagnostics),
        semantic:empty,status:PineFrontendStatus.invalid);
    }
    final parsed=PineV6Parser(lexed.tokens,maxNodes:maxAstNodes).parse();
    final semantic=PineV6SemanticAnalyzer(
      maxSymbols:maxAstNodes).analyze(parsed.ast);
    final errors=<PineDiagnostic>[
      ...lexed.diagnostics,...parsed.diagnostics,...semantic.diagnostics,
    ];
    // Pine code explicitly tagged for older/newer language versions must
    // never be silently interpreted as v6. Untagged legacy scripts remain
    // accepted for backwards compatibility with the existing numeric subset.
    final directive=RegExp(
      r'^[ \t]*//@version[ \t]*=[ \t]*([^\s/]+)', multiLine: true)
      .firstMatch(source);
    if(directive!=null&&directive.group(1)!='6'){
      final before=source.substring(0,directive.start);
      final line='\n'.allMatches(before).length+1;
      final column=before.length-before.lastIndexOf('\n');
      errors.add(PineDiagnostic(
        PineDiagnosticStage.semantic,'version_mismatch',
        'Only Pine Script v6 is supported by this frontend',
        PineSourceSpan(line,column),
      ));
    }
    final invalid=errors.any((d)=>d.severity==PineDiagnosticSeverity.error);
    PineSubsetProgram? legacy;
    final syntaxOnly=semantic.diagnostics.any((d)=>d.code=='syntax_only'||
        d.code=='tuple_shape_unknown'||d.code=='known_unimplemented');
    if(!invalid&&!syntaxOnly)legacy=PineSubsetProgram.tryCompile(source);
    if(legacy==null&&!invalid) {
      final loc=parsed.ast.statements.isNotEmpty?
          parsed.ast.statements.first.span:const PineSourceSpan(1,1);
      errors.add(PineDiagnostic(PineDiagnosticStage.semantic,
        'not_yet_supported',
        'Valid Pine syntax was analyzed, but its runtime is not yet implemented',
        loc,severity:PineDiagnosticSeverity.unsupported));
    }
    return PineFrontendResult(
      ast:parsed.ast,tokens:List.unmodifiable(lexed.tokens),
      semantic:semantic,diagnostics:List.unmodifiable(errors),
      legacyProgram:legacy,
      status:invalid?PineFrontendStatus.invalid:
          legacy==null?PineFrontendStatus.parsedButNotExecutable:
          PineFrontendStatus.executableSubset,
    );
  }
}

import 'pine_frontend_ast.dart';
import 'pine_frontend_lexer.dart';
import 'pine_frontend_parser.dart';
import 'pine_frontend_semantic.dart';
import 'pine_subset_program.dart';

export 'pine_frontend_ast.dart';
export 'pine_frontend_lexer.dart';
export 'pine_frontend_parser.dart';
export 'pine_frontend_semantic.dart';

class PineFrontendAnalysis {
  const PineFrontendAnalysis({
    required this.ast,
    required this.tokens,
    required this.diagnostics,
    required this.executable,
  });
  final PineScriptAst ast;
  final List<PineToken> tokens;
  final List<PineDiagnostic> diagnostics;

  /// The ONLY executable output is the existing tested PineSubsetProgram.
  /// This frontend never compiles control-flow or user functions into a
  /// fake runtime implementation.
  final PineSubsetProgram? executable;
  bool get canExecute => executable != null;

  String? get diagnosticMessage => canExecute ? null :
      diagnostics.isEmpty ? 'غير مدعوم بعد في محرك Pine' :
      diagnostics.map((e) => e.toString()).join('\n');
  bool get hasSyntaxErrors => diagnostics.any((d) =>
      d.kind == PineDiagnosticKind.lexical ||
      d.kind == PineDiagnosticKind.syntax ||
      d.kind == PineDiagnosticKind.resource);
}

/// An additive, safe route for scripts: parse/analyze v6 source, but preserve
/// the existing bounded AST runtime byte-for-byte for supported scripts.
class PineFrontend {
  const PineFrontend._();

  static PineFrontendAnalysis analyze(String source, {
    Duration deadline = const Duration(milliseconds: 1000),
    int maxSource = 15000,
  }) {
    final clock = Stopwatch()..start();
    final lex = PineLexer.scan(source, maxChars: maxSource,
        timeout: deadline);
    final parser = PineParser(lex.tokens, timeout: deadline);
    final parsed = parser.parse();
    final errors = <PineDiagnostic>[
      ...lex.diagnostics, ...parsed.diagnostics,
    ];
    if (lex.version != null && lex.version != 6) {
      errors.add(PineDiagnostic(PineDiagnosticKind.unsupported,
          'version', 'Only Pine v6 frontend analysis is supported',
          1, 1));
    }
    if (errors.isEmpty && clock.elapsed < deadline) {
      final semantic = PineSemanticAnalyzer(
          timeout: deadline - clock.elapsed);
      errors.addAll(semantic.analyze(parsed.ast));
    }
    if (clock.elapsed >= deadline &&
        !errors.any((e) => e.code == 'timeout' ||
            e.code == 'semantic_budget')) {
      errors.add(const PineDiagnostic(PineDiagnosticKind.resource,
          'timeout', 'Pine analysis deadline exceeded', 1, 1));
    }
    PineSubsetProgram? legacy;
    if (errors.isEmpty) {
      try {
        // Existing compiler is the sole source of executable capabilities.
        legacy = PineSubsetProgram.tryCompile(source);
      } catch (_) {
        errors.add(const PineDiagnostic(PineDiagnosticKind.unsupported,
            'legacy_rejected',
            'Unsupported Pine feature cannot run in the current interpreter',
            1, 1));
      }
    }
    if (legacy == null && errors.isEmpty) {
      errors.add(const PineDiagnostic(PineDiagnosticKind.unsupported,
          'runtime_unavailable',
          'Pine AST validated; execution of this language feature is not supported yet',
          1, 1));
    }
    clock.stop();
    return PineFrontendAnalysis(
      ast: parsed.ast,
      tokens: lex.tokens,
      diagnostics: List.unmodifiable(errors),
      executable: legacy,
    );
  }
}

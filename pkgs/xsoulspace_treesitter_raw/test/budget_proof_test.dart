// Budget proof (ADR 0035 §7 clause 4): a meaning cut built from the mapped
// TS node kinds (node facts + ONE point-cut) must still fit the 4k AFM
// tier's graduated profile — 1,424 chars/4 → cutBudget 628 (PLAN.md row).
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_treesitter_raw/xsoulspace_treesitter_raw.dart';

void main() {
  final dylibPath = findGrammarDylib();
  final skipReason = dylibPath == null
      ? 'grammar_dylib_missing — run tool/build_grammar.sh'
      : false;

  test(
    'the graduated profile row reproduces: 1,424 chars/4 → cutBudget 628',
    () {
      // window = cutBudget + ceil(profileChars / charsPerToken)
      //        = 628 + 356 = 984 — the 4k tier window the row implies.
      expect(
        budgetProfile.windowTokens,
        budgetProfile.cutBudgetTokens +
            (budgetProfile.profileBaselineChars / budgetProfile.charsPerToken)
                .ceil(),
      );
      expect(budgetProfile.windowTokens, 984);
    },
  );

  test(
    'a meaning cut over the mapped TS file fits the 4k tier (fits=true)',
    skip: skipReason,
    () {
      final parser = TreeSitterParser.open();
      try {
        final source = File('test/fixtures/calculator.ts').readAsStringSync();
        final root = parser.parse(source);
        final bridge = Utf8Utf16SpanBridge(source);
        final mapper = GrammarMapper(
          mapping: GrammarMapping.validate(tsMappingTable),
        );
        final symbols = mapper.map(
          root,
          source,
          bridge: bridge,
          fileName: 'calculator.ts',
        );
        // The point-cut: the `greet` member's span read through the span
        // bridge (exactly what the budgeted span reader would serve).
        final greet = symbols.firstWhere(
          (s) => s.kind == SymbolKind.member && s.name == 'greet',
        );
        final greetNode = root.walk().firstWhere(
          (n) => n.type == greet.grammarType && n.startByte == greet.startByte,
        );
        final pointCutText = bridge.span(greetNode).text;

        final cut = renderMeaningCut(
          path: 'calculator.ts',
          symbols: symbols,
          pointCutName: 'Calculator.greet',
          pointCutText: pointCutText,
        );
        final verdict = checkBudget(cut);
        // ignore: avoid_print
        print('--- budget proof (clause 4) ---');
        // ignore: avoid_print
        print(
          'profile row: ${budgetProfile.profileBaselineChars} chars/4 → '
          'cutBudget ${budgetProfile.cutBudgetTokens} '
          '(window ${budgetProfile.windowTokens})',
        );
        // ignore: avoid_print
        print(
          'mapped nodes: ${symbols.length} '
          '(file ${symbols.where((s) => s.kind == SymbolKind.file).length}, '
          'sym ${symbols.where((s) => s.kind == SymbolKind.sym).length}, '
          'member ${symbols.where((s) => s.kind == SymbolKind.member).length})',
        );
        // ignore: avoid_print
        print(verdict);
        expect(
          verdict.fits,
          isTrue,
          reason:
              'the 4k AFM tier must still fund the cut with the new '
              'node kinds (ADR 0035 §7 clause 4)',
        );
        expect(verdict.cutTokens, lessThanOrEqualTo(628));
      } finally {
        parser.dispose();
      }
    },
  );
}

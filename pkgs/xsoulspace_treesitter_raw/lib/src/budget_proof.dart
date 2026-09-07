// ignore_for_file: lines_longer_as_80_chars

/// ADR 0035 §7 clause 4 — the budget proof: a meaning cut built from the
/// mapped node kinds (node facts + one point-cut) must still fit the 4k
/// AFM tier's graduated profile.
///
/// The graduated math (PLAN.md, measured row, ADR 0034/0035):
///   1,424 chars / 4 (chars-per-token) → 356 tokens of profile overhead
///   → cutBudget 628 = window(984) − 356, fits=true.
/// The window (984 tokens) is derived from that SAME measured row:
/// 628 + 356 = 984 — this package reproduces the row as a constant
/// discipline check, it does not re-derive the harness equation.
///
/// The spike's verdict: the SAMPLE CUT (what the model actually receives
/// for one mapped TS file — the node-fact rows + ONE member span cut)
/// fits within the cutBudget (628 tokens × 4 chars = 2,512 chars) with
/// the new node kinds (sym + member + file) included. The verdict is
/// DATA: chars measured, tokens derived, fits boolean — no argument.
library;

import 'grammar_mapper.dart';

/// The graduated-profile constants (see the library doc — sourced from the
/// measured rows in PLAN.md / ADR 0034, NOT re-derived here).
const budgetProfile = (
  profileBaselineChars: 1424, // measured graduated row
  charsPerToken: 4, // house chars-per-token convention
  cutBudgetTokens: 628, // measured graduated row (4k AFM tier)
  windowTokens: 984, // 628 + 1424/4 — the tier window this implies
);

/// The verdict for one meaning cut.
class BudgetVerdict {
  const BudgetVerdict({
    required this.cutChars,
    required this.cutTokens,
    required this.cutBudgetTokens,
    required this.fits,
  });

  /// The sample cut (node facts + point-cut), measured in CHARS.
  final int cutChars;

  /// chars / charsPerToken — the derived token cost.
  final int cutTokens;

  /// The graduated tier's cut budget (tokens).
  final int cutBudgetTokens;

  /// cutTokens ≤ cutBudgetTokens.
  final bool fits;

  @override
  String toString() =>
      'BudgetVerdict(cutChars: $cutChars, cutTokens: $cutTokens, '
      'cutBudgetTokens: $cutBudgetTokens, fits: $fits)';
}

/// Renders the meaning cut for one mapped file: the node-fact rows
/// (kind + name + parent + span props — the zoom outline) plus ONE
/// point-cut (the member's source text, read through the span bridge).
String renderMeaningCut({
  required String path,
  required List<MappedSymbol> symbols,
  required String pointCutText,
  required String pointCutName,
}) {
  final b = StringBuffer();
  for (final s in symbols) {
    final parent = switch (s.kind) {
      SymbolKind.file => '',
      SymbolKind.sym => '',
      SymbolKind.member => ' parent=${s.parentName ?? 'file'}',
    };
    b.writeln(
      '${s.kind.name} ${s.grammarType} ${s.name}$parent '
      'span=${s.startByte}..${s.endByte} '
      'pt=${s.startRow}:${s.startColumn}',
    );
  }
  b.writeln('--- point-cut: $pointCutName ---');
  b.write(pointCutText);
  return b.toString();
}

/// Verifies the rendered cut against the graduated profile.
BudgetVerdict checkBudget(String cut) {
  final chars = cut.length;
  final tokens = (chars / budgetProfile.charsPerToken).ceil();
  return BudgetVerdict(
    cutChars: chars,
    cutTokens: tokens,
    cutBudgetTokens: budgetProfile.cutBudgetTokens,
    fits: tokens <= budgetProfile.cutBudgetTokens,
  );
}

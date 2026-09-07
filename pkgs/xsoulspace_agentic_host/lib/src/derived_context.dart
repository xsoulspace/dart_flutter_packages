library;

import 'dart:math' as math;

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show EnvConfig;

/// ADR 0033 — the derived context equation. D7's "harness-owned derived
/// context" closed into ONE formula across the four layers that previously
/// carried four unrelated constants ([ProjectionBudget] 4,000, the client
/// pre-flight `maxContextTokens` 3,800, the native window 4,096, the output
/// reserve 1,024).
///
/// ```text
/// cutBudget = window(native, measured)
///           − ceil(overhead(live registry, chars/4) × nativeTruthFactor)
///           − outputReserve
///           − margin
/// ```
///
/// Every term is measured, never tuned: the window and the reserve come
/// from the on-device rows (R9.1 investigation A, finding 18), the
/// native-truth factor from ADR 0028 §Context.3, and the overhead from the
/// LIVE registry the actor actually sees (ADR 0033 §2 — one truth).

/// ADR 0028 §Context.3 (MEASURED, on-device): chars/4 UNDERCOUNTS the
/// native tokenizer ~45% on JSON-heavy content. Multiplying an estimator
/// figure by this factor yields a native-truth estimate.
const double nativeTruthFactor = 1.45;

/// R9.1 investigation A (MEASURED): the true AFM window is 4,096
/// (`model.contextSize`).
const int afmNativeWindowTokens = 4096;

/// Finding 18 (MEASURED, on-device): the model must decode its response
/// inside the same window the input occupies — this much generation space
/// is reserved out of the window.
const int afmOutputReserveTokens = 1024;

/// ADR 0033 §1: safety margin — this fraction of the remaining window is
/// held back so the derivation is conservative in both directions.
const double derivationMarginFraction = 0.10;

/// ADR 0033 §1: the minimum cut that can fund a DECISION — goal slot +
/// last verdict + one observation. A derived budget below this cannot run
/// a decision at all; `fits` is false and the named condition is "the
/// profile does not fit the tier" (repair: ADR 0030 surface convergence,
/// never a bigger constant). Without this floor a 36-token "fit" would
/// silently truncate every cut to nothing — the failure must be NAMED,
/// not silent.
const int minCutBudgetTokens = 600;

/// Config keys (ADR 0008 [EnvConfig]: process env → `./.xsoulspace/
/// config.json` → global). The window is BACKEND-dependent: AFM measures
/// 4,096 native (`model.contextSize`), an OpenRouter model may expose
/// 8k–1M — set `derived_context_window_tokens` per project/inference and
/// the SAME equation derives that tier's cut budget. Every key falls back
/// to the MEASURED default; a malformed value is a named error, never a
/// silent fallback.
const windowConfigKey = 'derived_context_window_tokens';
const reserveConfigKey = 'derived_context_output_reserve_tokens';
const nativeTruthConfigKey = 'derived_context_native_truth_factor';
const marginConfigKey = 'derived_context_margin_fraction';
const minCutConfigKey = 'derived_context_min_cut_tokens';

// Const aliases so the [DerivedContextLimits] constructor defaults can
// reference the measured constants without shadowing (the field names
// collide with the top-level consts inside the class scope).
const double _kNativeTruthFactor = nativeTruthFactor;
const double _kMarginFraction = derivationMarginFraction;

/// The configured limits the equation consumes. [forBackend] names the
/// inference the derivation is for (e.g. `apple_foundation_afm`) — set
/// `<key>_<backend>` to scope a value to ONE backend; the unscoped key is
/// the fallback.
class DerivedContextLimits {
  const DerivedContextLimits({
    this.windowTokens = afmNativeWindowTokens,
    this.outputReserveTokens = afmOutputReserveTokens,
    this.nativeTruthFactor = _kNativeTruthFactor,
    this.marginFraction = _kMarginFraction,
    this.minCutTokens = minCutBudgetTokens,
  });

  /// Resolves the limits from [config] (may be null — callers without a
  /// store get the measured AFM defaults). Precedence per key:
  /// `<key>_<backend>` → `<key>` → measured default.
  factory DerivedContextLimits.resolve({
    EnvConfig? config,
    String backend = 'apple_foundation_afm',
  }) {
    int intFor(String key, int fallback) {
      final raw = config?.get('${key}_$backend') ?? config?.get(key);
      if (raw == null || raw.isEmpty) return fallback;
      final value = int.tryParse(raw);
      if (value == null || value <= 0) {
        throw StateError(
          'config "$key" must be a positive integer, got "$raw"',
        );
      }
      return value;
    }

    double doubleFor(String key, double fallback) {
      final raw = config?.get('${key}_$backend') ?? config?.get(key);
      if (raw == null || raw.isEmpty) return fallback;
      final value = double.tryParse(raw);
      if (value == null || value <= 0) {
        throw StateError(
          'config "$key" must be a positive number, got "$raw"',
        );
      }
      return value;
    }

    return DerivedContextLimits(
      windowTokens: intFor(windowConfigKey, afmNativeWindowTokens),
      outputReserveTokens: intFor(reserveConfigKey, afmOutputReserveTokens),
      nativeTruthFactor: doubleFor(
        nativeTruthConfigKey,
        _kNativeTruthFactor,
      ),
      marginFraction: doubleFor(marginConfigKey, _kMarginFraction),
      minCutTokens: intFor(minCutConfigKey, minCutBudgetTokens),
    );
  }

  final int windowTokens;
  final int outputReserveTokens;
  final double nativeTruthFactor;
  final double marginFraction;
  final int minCutTokens;
}

/// The derived projection budget: the tokens (estimator scale) a cut may
/// spend for the request to fit the native window at native truth with the
/// output reserve and margin held back.
///
/// Returns 0 when the FIXED overhead alone fills the window — a NAMED
/// condition (the profile does not fit the tier; the repair is ADR 0030
/// surface convergence, never a bigger constant).
int deriveProjectionBudgetTokens({
  /// Fixed overhead (system prompt + tool schemas) in estimator tokens,
  /// metered from the LIVE registry the actor actually sees.
  required int overheadTokens,

  /// The native window (`model.contextSize` on AFM).
  int nativeWindowTokens = afmNativeWindowTokens,

  /// Generation space reserved out of [nativeWindowTokens] (finding 18).
  int outputReserveTokens = afmOutputReserveTokens,

  /// chars/4 → native undercount multiplier (ADR 0028, measured).
  double nativeTruthFactor = nativeTruthFactor,

  /// Fraction of the post-overhead remainder held back as margin.
  double marginFraction = derivationMarginFraction,

  /// The minimum cut that can fund a decision (see [minCutBudgetTokens]).
  int minCutTokens = minCutBudgetTokens,
}) {
  final nativeOverhead = (overheadTokens * nativeTruthFactor).ceil();
  final afterOverhead =
      nativeWindowTokens - nativeOverhead - outputReserveTokens;
  if (afterOverhead <= 0) return 0;
  final margin = (afterOverhead * marginFraction).floor();
  // The budget is in ESTIMATOR tokens (what [ProjectionBudget] and the cut
  // meter): convert the native remainder back through the same factor.
  final nativeBudget = afterOverhead - margin;
  return math.max(0, (nativeBudget / nativeTruthFactor).floor());
}

/// The full derivation row — every named term, for the run log and the
/// overhead gate's published printout. Printing the row IS the audit:
/// a number that moved names the term that moved.
({int window, int reserve, double nativeTruthFactor, int nativeOverhead, int margin, int derivedBudget, bool fits})
deriveContextRow({
  required int overheadTokens,
  int nativeWindowTokens = afmNativeWindowTokens,
  int outputReserveTokens = afmOutputReserveTokens,
  double nativeTruthFactor = nativeTruthFactor,
  double marginFraction = derivationMarginFraction,
  int minCutTokens = minCutBudgetTokens,
}) {
  final nativeOverhead = (overheadTokens * nativeTruthFactor).ceil();
  final afterOverhead =
      nativeWindowTokens - nativeOverhead - outputReserveTokens;
  final margin = afterOverhead > 0
      ? (afterOverhead * marginFraction).floor()
      : 0;
  final derivedBudget = deriveProjectionBudgetTokens(
    overheadTokens: overheadTokens,
    nativeWindowTokens: nativeWindowTokens,
    outputReserveTokens: outputReserveTokens,
    nativeTruthFactor: nativeTruthFactor,
    marginFraction: marginFraction,
  );
  return (
    window: nativeWindowTokens,
    reserve: outputReserveTokens,
    nativeTruthFactor: nativeTruthFactor,
    nativeOverhead: nativeOverhead,
    margin: margin,
    derivedBudget: derivedBudget,
    fits: derivedBudget >= minCutTokens,
  );
}

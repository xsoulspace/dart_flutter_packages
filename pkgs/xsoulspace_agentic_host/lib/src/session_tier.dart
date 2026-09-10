// ignore_for_file: lines_longer_than_80_chars

/// Session-actor tier contract (build order item 1) — an actor declares its
/// tier ONCE per session; the cut budget and the per-op read budgets become
/// TIER-SOURCED (derived from the same measured equation as ADR 0033) instead
/// of hardcoded constants scattered across layers.
///
/// **A tier is a READING property only.** It widens or narrows what an actor
/// may SEE per op (read budgets) and how much a decision may spend — never
/// what an actor may DO. Consent (the review gate, `consent.json` plans,
/// `request_permission`) and the closed op set are orthogonal: a 200k hosted
/// actor has NO verb a 4k AFM actor lacks, and no budget amount grants an
/// unconsented mutation.
///
/// Derivation (mechanical, from [DerivedContextLimits.resolve] — one truth,
/// the ADR 0033 equation; never tuned here):
///
/// ```text
/// perOpReadBudget = clamp(windowTokens ~/ 32, 512, 4096)
/// verdictBudget   = max(1200, perOpReadBudget * 2)
/// ```
///
/// Measured tiers: the 4k AFM window derives 512 / 1,200 — EXACTLY the
/// daemon's current hardcoded defaults (`perOpResultBudgetTokens`,
/// `defaultProgramVerdictBudgetTokens`), so the AFM behavior is preserved
/// bit-for-bit. Hosted big-window backends derive the large budgets: a
/// 131,072 window (128k) derives 4,096 / 8,192; a 200,000 window clamps at
/// 4,096 / 8,192. Both are configurable per backend (ADR 0008 [EnvConfig]
/// conventions: `<key>_<backend>` → `<key>` → derived); a malformed value is
/// a NAMED error, never a silent fallback.
library;

import 'dart:math' as math;

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show EnvConfig;

import 'derived_context.dart';

/// Config keys (ADR 0008 [EnvConfig]: process env → `./.xsoulspace/
/// config.json` → global). Scoped per backend as `{key}_{backend}`; the
/// unscoped key is the fallback; absence derives from the window. A
/// malformed value is a named error (same conventions as
/// [DerivedContextLimits.resolve]).
const perOpReadBudgetConfigKey = 'session_tier_per_op_read_budget';
const verdictBudgetConfigKey = 'session_tier_verdict_budget';

/// The window at/above which a backend is a HOSTED big-window tier. The
/// ladder itself is continuous (`window ~/ 32`, clamped); this constant only
/// names the boundary the docs and gate rows refer to (128k and 200k hosted
/// windows derive the maximum per-op budget).
const hostedLargeWindowTokens = 65536;

/// The per-op read-budget ladder floor: EXACTLY the daemon's current
/// hardcoded default (`perOpResultBudgetTokens` in the read program) — the
/// AFM tier reproduces today's behavior bit-for-bit.
const minPerOpReadBudgetTokens = 512;

/// The per-op read-budget ladder ceiling: the hosted big-window budget
/// (128k/200k windows derive this).
const maxPerOpReadBudgetTokens = 4096;

/// The verdict-budget floor: EXACTLY the daemon's current hardcoded default
/// (`defaultProgramVerdictBudgetTokens`) — the AFM tier reproduces it.
const minVerdictBudgetTokens = 1200;

// Const aliases so the [SessionTierProfile] constructor defaults can
// reference the measured constants without shadowing (the field names
// collide with the top-level consts inside the class scope) — the same
// convention [DerivedContextLimits] uses.
const double _kNativeTruthFactor = nativeTruthFactor;
const double _kMarginFraction = derivationMarginFraction;

/// The immutable, once-per-session tier declaration. Pure budget data —
/// no capability, no verb, no consent field (a tier is a READING property;
/// see the library doc).
class SessionTierProfile {
  const SessionTierProfile({
    required this.backend,
    required this.windowTokens,
    required this.perOpReadBudget,
    required this.verdictBudget,
    this.outputReserveTokens = afmOutputReserveTokens,
    this.nativeTruthFactor = _kNativeTruthFactor,
    this.marginFraction = _kMarginFraction,
    this.minCutTokens = minCutBudgetTokens,
  });

  /// The inference the tier is declared for (the [DerivedContextLimits]
  /// backend scoping key, e.g. `apple_foundation_afm`).
  final String backend;

  // --- the ADR 0033 derived-context terms (one truth, restated) ---
  final int windowTokens;
  final int outputReserveTokens;
  final double nativeTruthFactor;
  final double marginFraction;
  final int minCutTokens;

  // --- the tier-sourced READ budgets (this contract's addition) ---
  /// The default per-op read budget of a read program op (`zoom`/`read`
  /// budget when the op omits one). Sourced from the window, never a
  /// hardcoded 2048.
  final int perOpReadBudget;

  /// The default verdict budget across a read program's envelope.
  final int verdictBudget;
}

/// The per-op read-budget ladder: `window ~/ 32` clamped to
/// `[minPerOpReadBudgetTokens, maxPerOpReadBudgetTokens]`. Named as data so
/// the extension mirror and the gate rows derive the SAME number.
int derivePerOpReadBudgetTokens(int windowTokens) {
  final raw = windowTokens ~/ 32;
  return math.max(
    minPerOpReadBudgetTokens,
    math.min(maxPerOpReadBudgetTokens, raw),
  );
}

/// The verdict budget: twice the per-op read budget, floored at the current
/// hardcoded default so the AFM tier reproduces today's behavior.
int deriveVerdictBudgetTokens(int perOpReadBudget) =>
    math.max(minVerdictBudgetTokens, perOpReadBudget * 2);

/// Resolves the session actor's tier ONCE per session from [config] (may be
/// null — callers without a store get the measured AFM defaults). Derives
/// from [DerivedContextLimits.resolve] (ADR 0033, one truth) and layers the
/// tier-sourced read budgets on top. Precedence per tier key:
/// `<key>_<backend>` → `<key>` → derived from the window. Malformed values
/// throw a NAMED error naming the key — never a silent fallback.
SessionTierProfile resolveSessionTier({
  EnvConfig? config,
  String backend = 'apple_foundation_afm',
}) {
  final limits = DerivedContextLimits.resolve(config: config, backend: backend);

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

  final perOpReadBudget = intFor(
    perOpReadBudgetConfigKey,
    derivePerOpReadBudgetTokens(limits.windowTokens),
  );
  return SessionTierProfile(
    backend: backend,
    windowTokens: limits.windowTokens,
    outputReserveTokens: limits.outputReserveTokens,
    nativeTruthFactor: limits.nativeTruthFactor,
    marginFraction: limits.marginFraction,
    minCutTokens: limits.minCutTokens,
    perOpReadBudget: perOpReadBudget,
    verdictBudget: intFor(
      verdictBudgetConfigKey,
      deriveVerdictBudgetTokens(perOpReadBudget),
    ),
  );
}

/// Server-side tier enforcement (follow-up 1) — parses the tier a client
/// declared at session/new: `_meta.sessionTier` is the ONCE-PER-SESSION
/// declaration, and the DAEMON honors it too so non-extension clients get
/// tier-sourced defaults (the pi extension sources the same numbers
/// client-side; see r7_harnessd_extension.ts `resolveSessionTier`).
///
/// The wire shape is the extension's `SessionTierProfile` interface —
/// exactly `{backend, windowTokens, outputReserveTokens, perOpReadBudget,
/// verdictBudget}`. The three ADR 0033 cut terms the wire omits default to
/// the measured AFM constants (the declaring client resolved its own tier
/// through the same equation — the daemon never re-derives a declared
/// tier, one declaration per session).
///
/// Returns null when `_meta` is absent or carries no `sessionTier` — the
/// current hardcoded defaults, bit-for-bit. A malformed value is a NAMED
/// error naming `_meta.sessionTier.<field>` — never a silent fallback.
SessionTierProfile? parseSessionTierMeta(Map<String, Object?>? meta) {
  if (meta == null) return null;
  final raw = meta['sessionTier'];
  if (raw == null) return null;
  if (raw is! Map) {
    throw StateError(
      '_meta.sessionTier must be a JSON object, got "${raw.runtimeType}"',
    );
  }
  final map = Map<String, Object?>.from(raw);

  int intFor(String field) {
    final value = map[field];
    final parsed = value is int ? value : int.tryParse('$value');
    if (parsed == null || parsed <= 0) {
      throw StateError(
        '_meta.sessionTier.$field must be a positive integer, got "$value"',
      );
    }
    return parsed;
  }

  final backend = map['backend'];
  return SessionTierProfile(
    backend: backend is String && backend.isNotEmpty
        ? backend
        : 'apple_foundation_afm',
    windowTokens: intFor('windowTokens'),
    perOpReadBudget: intFor('perOpReadBudget'),
    verdictBudget: intFor('verdictBudget'),
  );
}

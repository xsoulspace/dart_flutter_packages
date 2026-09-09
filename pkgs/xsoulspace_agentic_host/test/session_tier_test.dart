// Session-actor tier contract (build order item 1) — the gate rows.
//
// Rows: the AFM tier reproduces the measured row bit-for-bit (window 4,096 →
// perOpRead 512 / verdict 1,200 — the exact numbers the daemon hardcodes
// today — and the published one-truth derivation row cutBudget 628,
// fits=true); the hosted big-window tiers (128k, 200k) derive the large
// per-op budgets (4,096); config overrides win; malformed values are NAMED
// errors (EnvConfig conventions). LLM-free: pure derivation, a temp
// config store, and the ADR 0033 equation.
// ignore_for_file: unnecessary_library_directive
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/src/meaning/meaning_read_program.dart'
    show defaultProgramVerdictBudgetTokens, perOpResultBudgetTokens;
import 'package:xsoulspace_agentic_host/src/derived_context.dart'
    show deriveContextRow;
import 'package:xsoulspace_agentic_host/src/session_tier.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show EnvConfig;

/// The published one-truth fixed overhead of the ADR 0034 §3 graduation row:
/// 1,420 chars/4 → cutBudget 628, fits=true on the 4k AFM tier. The tier
/// contract must REPRODUCE this row from its sourced terms.
const publishedGraduationRowOverheadTokens = 1420;

void main() {
  late Directory store;
  late String globalPath;
  late String localPath;

  setUp(() {
    store = Directory.systemTemp.createTempSync('session_tier_');
    globalPath = '${store.path}/global.json';
    localPath = '${store.path}/local.json';
  });
  tearDown(() => store.deleteSync(recursive: true));

  Future<EnvConfig> configWith(Map<String, String> values) {
    File(localPath).writeAsStringSync(jsonEncode(values));
    // An isolated global scope: the test must never read the operator's
    // real ~/.config store (one truth per row, no ambient drift).
    return EnvConfig.load(globalPath: globalPath, localPath: localPath);
  }

  test('AFM row reproduces: window 4096 → perOpRead 512, verdict 1200, '
      'and the published graduation row (cutBudget 628, fits=true)', () {
    // No config at all — the measured AFM defaults, exactly as the daemon
    // (and the read program) hardcode them today.
    final tier = resolveSessionTier();
    expect(tier.backend, 'apple_foundation_afm');
    expect(tier.windowTokens, 4096);
    expect(tier.outputReserveTokens, 1024);
    expect(tier.nativeTruthFactor, 1.45);
    expect(tier.marginFraction, 0.10);
    expect(tier.minCutTokens, 600);
    // THE TIER-SOURCED BUDGETS: bit-identical to the hardcoded defaults the
    // read program carries today (perOpResultBudgetTokens 512,
    // defaultProgramVerdictBudgetTokens 1200) — the AFM behavior is
    // preserved exactly, now DERIVED.
    expect(tier.perOpReadBudget, 512);
    expect(tier.verdictBudget, 1200);

    // The published graduation row (ADR 0034 §3): the one-truth surface's
    // fixed overhead 1,420 chars/4 through the tier's OWN terms reproduces
    // cutBudget 628, fits=true — the 4k AFM tier funds a minimal cut.
    final row = deriveContextRow(
      overheadTokens: publishedGraduationRowOverheadTokens,
      nativeWindowTokens: tier.windowTokens,
      outputReserveTokens: tier.outputReserveTokens,
      nativeTruthFactor: tier.nativeTruthFactor,
      marginFraction: tier.marginFraction,
      minCutTokens: tier.minCutTokens,
    );
    expect(row.window, 4096);
    expect(row.derivedBudget, 628, reason: 'the published AFM row must '
        'reproduce from the tier-sourced terms (overhead 1,420 chars/4)');
    expect(row.fits, isTrue);

    // CROSS-TRUTH row (the harness package imports NEITHER the host nor
    // this test — ADR 0015 layering: host → harness, never reverse): the
    // tier-sourced AFM budgets must equal the read program's hardcoded
    // defaults BIT-FOR-BIT, so tier-sourcing is behavior-preserving
    // on-device. If either side moves, THIS gate names it.
    expect(tier.perOpReadBudget, perOpResultBudgetTokens,
        reason: 'the AFM per-op read budget (512) must equal the read '
            "program's hardcoded per-op default — re-measure and "
            're-publish if either moved');
    expect(tier.verdictBudget, defaultProgramVerdictBudgetTokens,
        reason: 'the AFM verdict budget (1200) must equal the read '
            "program's hardcoded verdict default");
  });

  test('hosted big-window tiers derive large per-op budgets: 128k → 4096, '
      '200k clamps at 4096', () async {
    for (final window in [131072, 200000]) {
      final tier = resolveSessionTier(
        backend: 'open_router',
        config: await configWith({
          'derived_context_window_tokens_open_router': '$window',
        }),
      );
      expect(tier.windowTokens, window, reason: 'window $window');
      expect(tier.perOpReadBudget, 4096,
          reason: 'a hosted big-window tier reads 4,096 tokens per op');
      expect(tier.verdictBudget, 8192);
      // A tier is a READING property only — it widens BUDGETS, never
      // capabilities: the profile carries no verbs, no consent field, and
      // the min-cut floor is the SAME 600 for every tier.
      expect(tier.minCutTokens, 600);
    }
  });

  test('config override row: session_tier keys win over the derivation, '
      'per-backend scope beats unscoped', () async {
    final tier = resolveSessionTier(
      backend: 'open_router',
      config: await configWith({
        'derived_context_window_tokens_open_router': '131072',
        // Unscoped override beats the derivation…
        'session_tier_per_op_read_budget': '1024',
        // …and the backend-scoped value beats the unscoped one.
        'session_tier_per_op_read_budget_open_router': '2048',
        'session_tier_verdict_budget_open_router': '5000',
      }),
    );
    expect(tier.perOpReadBudget, 2048);
    expect(tier.verdictBudget, 5000);
    // Another backend reads the unscoped key (its own scope is absent).
    final other = resolveSessionTier(
      backend: 'another_backend',
      config: await configWith({
        'session_tier_per_op_read_budget': '1024',
      }),
    );
    expect(other.perOpReadBudget, 1024);
  });

  test('malformed values are NAMED errors — never a silent fallback',
      () async {
    const malformed = <(String, String)>{
      ('session_tier_per_op_read_budget', 'abc'),
      ('session_tier_per_op_read_budget', '0'),
      ('session_tier_per_op_read_budget', '-5'),
      ('session_tier_verdict_budget', '1.5'),
      ('session_tier_verdict_budget', 'x'),
    };
    for (final (key, value) in malformed) {
      final cfg = await configWith({key: value});
      expect(
        () => resolveSessionTier(
          backend: 'open_router',
          config: cfg,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(key),
          ),
        ),
        reason: '$key="$value" must name the key',
      );
    }
    // The upstream ADR 0033 keys keep their named errors too (the tier
    // derives through them — one truth, one error convention).
    final windowCfg =
        await configWith({'derived_context_window_tokens': 'four'});
    expect(
      () => resolveSessionTier(
        backend: 'open_router',
        config: windowCfg,
      ),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('derived_context_window_tokens'),
      )),
    );
  });
}

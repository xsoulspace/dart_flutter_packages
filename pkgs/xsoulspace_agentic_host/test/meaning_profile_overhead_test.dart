// ignore_for_file: lines_longer_than_80_chars

/// R7 PRODUCTION #2, as amended by ADR 0033 §1–2 + ADR 0034 — the
/// meaning-profile overhead vs the AFM window, metered from the ONE-TRUTH
/// surface.
///
/// History: this gate previously claimed "the EXACT registry
/// runCodingAgentOnce wires — one truth, not a rebuilt list" while
/// hand-registering 6 tools; the runner registered 9. ADR 0033 §2: both
/// the runner and this gate call `buildMeaningProfileSurface` — drift is
/// structurally impossible.
///
/// ADR 0033 §1: the binding is the DERIVED CONTEXT EQUATION, not a hand
/// constant: window(native, measured) − native-truth overhead − output
/// reserve − margin, with a named min-cut floor (600).
///
/// ADR 0034: ONE edit verb — doc sections (sec_…) and config keys (key_…)
/// edit through `edit_symbol`'s class-routed union. The per-format verbs
/// (`edit_section`, `edit_key`) are GONE from the model surface; the row
/// below proves the union still fits the 4k AFM tier (the pre-graduation
/// variant measured 1,823 → fits=false; the unified verb removed it).
///
/// The range assertion has teeth: any verb, action, or description change
/// moves the metered number and forces re-publication.
///
/// LLM-free: constructs the one-truth surface and meters it with the
/// SAME chars/4 estimator the harness uses everywhere (`overheadTokens`).
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot;
import 'package:xsoulspace_agentic_host/xsoulspace_agentic_host.dart';
import 'package:xsoulspace_agentic_host/src/derived_context.dart'
    show deriveContextRow;
import 'package:xsoulspace_agentic_host/src/meaning_profile_surface.dart'
    show buildMeaningProfileSurface;

/// The P1 pre-flight budget (AppleFoundationNativeClient.maxContextTokens).
const afmBudgetTokens = 3800;

void main() {
  test(
    'GRADUATED meaning-profile overhead: one-truth surface, one edit '
    'verb, the row FITS the 4k AFM tier',
    () async {
      final world = World()..addPlugin(AgentPlugin());
      world.upsertResource(ToolRegistryResource());
      final jail = Directory.systemTemp.createTempSync('overhead_probe_');
      addTearDown(() => jail.deleteSync(recursive: true));

      final surface = await buildMeaningProfileSurface(
        world: world,
        workspace: jail,
        fsRoot: FsToolsRoot(jail.path),
        refreshTree: false,
      );
      final tools = surface.registry.tools.values.toList();
      final systemTokens = overheadTokens(
        systemPrompt: meaningProfileSystemPrompt,
        tools: const [],
      );
      // The published row (the printed lines ARE the row's source).
      // ignore: avoid_print
      print(
        'GRADUATED — surface: ${tools.map((t) => t.name.value).join(", ")}',
      );
      // ignore: avoid_print
      print('system prompt: $systemTokens');
      final perTool = {
        for (final t in tools)
          t.name.value: overheadTokens(systemPrompt: '', tools: [t]),
      };
      for (final entry in perTool.entries) {
        // ignore: avoid_print
        print('tool ${entry.key}: ${entry.value}');
      }
      final total = overheadTokens(
        systemPrompt: meaningProfileSystemPrompt,
        tools: tools,
      );
      final derivation = deriveContextRow(overheadTokens: total);
      // ignore: avoid_print
      print(
        'FIXED OVERHEAD TOTAL: $total → derived: window=${derivation.window} '
        'reserve=${derivation.reserve} nativeTruth=${derivation.nativeTruthFactor} '
        'nativeOverhead=${derivation.nativeOverhead} margin=${derivation.margin} '
        '→ cutBudget=${derivation.derivedBudget} fits=${derivation.fits}',
      );
      // ignore: avoid_print
      print(
        'pre-flight budget (P1 maxContextTokens): $afmBudgetTokens → '
        'estimator working memory: ${afmBudgetTokens - total}',
      );

      // ADR 0034 §1 — ONE edit verb: the per-format verbs are GONE from
      // the model surface.
      expect(perTool.containsKey('edit_section'), isFalse,
          reason: 'edit_section left the model surface (ADR 0034)');
      expect(perTool.containsKey('edit_key'), isFalse,
          reason: 'edit_key left the model surface (ADR 0034)');
      expect(perTool.containsKey('edit_symbol'), isTrue);

      // ONE-TRUTH binding (ADR 0033 §2): the metered total must sit in the
      // published range. Any verb, action, or description change moves
      // this number → re-measure, re-print, re-publish.
      // Measured 2026-09-07 (graduated + ONE edit verb: etl + program +
      // edit_symbol(705) + run; the union absorbed edit_section/edit_key;
      // teaching prose deduplicated — bounces/system-prompt carry the
      // arg-shape repair). fits=true: cutBudget 628 ≥ the 600 floor.
      expect(
        total,
        inExclusiveRange(1380, 1460),
        reason: 'the graduated one-truth overhead drifted out of the '
            'published range — re-measure and re-publish the row',
      );

      // THE GRADUATION ROW (ADR 0030 §3 + ADR 0034): the profile must FIT
      // the 4k AFM tier at native truth — cutBudget ≥ the min-cut floor
      // (600). Was FALSE pre-graduation (cutBudget 36).
      expect(
        derivation.fits,
        isTrue,
        reason: 'the graduated profile must fund a minimal cut on the 4k '
            'AFM tier — if this regresses, the surface grew or the '
            'derivation constants moved',
      );
    },
  );
}

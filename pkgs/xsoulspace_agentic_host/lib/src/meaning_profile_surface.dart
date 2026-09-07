import 'dart:io';

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show EditExecutableWire;
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_read_program.dart'
    show meaningProgramTool;
import 'package:xsoulspace_agentic_harness/src/meaning/meaning_tree.dart'
    show MeaningIndex;
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FsToolsRoot, JailWriteGateway, runTool;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show ToolDef;
import 'package:xsoulspace_agentic_workspace/xsoulspace_agentic_workspace.dart'
    show
        SpanEditMaterializer,
        SpanEditPlan,
        editKeyTool,
        editMdTool,
        editSymbolTool,
        meaningSpanReader,
        repoEtlTool,
        writeReviewTool;

import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart'
    show ToolRegistry, World;

/// ADR 0033 §2 — the ONE-TRUTH meaning-profile tool surface.
///
/// `runCodingAgentOnce` wires EXACTLY this builder; the overhead gate
/// (`meaning_profile_overhead_test.dart`) meters EXACTLY this builder.
/// Before this function there were two lists: the runner's 9 verbs and
/// the gate's hand-built 6 — `meaning_locate`, `edit_md`, `edit_key`
/// were invisible to the gate while the surface grew (the wave gate
/// measured 2,268 in-run against a 1,600 gate target, every gate green).
/// "One truth" is a function, not a comment.
///
/// The gate's comment previously claimed "the EXACT registry
/// runCodingAgentOnce wires" while rebuilding a subset by hand. This
/// builder is the seam that makes the claim true structurally: drift
/// between what runs and what is metered is now impossible without
/// editing this function.
class MeaningProfileSurface {
  const MeaningProfileSurface({required this.registry, required this.etl});

  /// The registry registered under 'default' for meaning-profile actors.
  final ToolRegistry registry;

  /// The repo ETL tool (the caller runs the mechanical refresh tick and
  /// the task-grammar pre-pass through it).
  final ToolDef etl;
}

/// Builds the meaning-profile surface. [refreshTree] runs the host-side
/// mechanical refresh tick when the tree is already built (zero model
/// tokens) — the runner does this; the gate passes `false` (metering
/// only, no workspace).
Future<MeaningProfileSurface> buildMeaningProfileSurface({
  required World world,
  required Directory workspace,

  /// The jail root the fs-tier tools are bounded to.
  required FsToolsRoot fsRoot,

  /// The consent-gated escape-hatch write gateway (ADR 0024 §4). Null →
  /// `write_review` is NOT registered (deny-by-default is structural).
  JailWriteGateway? gateway,

  /// R7c item 3: host edit approver for `edit_symbol` (deny-by-default).
  Future<bool> Function(SpanEditPlan plan)? editApprover,

  /// P1 trusted-author tier: the pack-write consent gate.
  bool Function(EditExecutableWire wire, String authoredBodyDiff)?
  packConsent,

  /// Runner: true (refresh changed files before the actor sees the tree).
  /// Gate: false (metering only).
  bool refreshTree = true,
}) async {
  final registry = ToolRegistry();
  final etl = repoEtlTool(world, workspace);
  if (refreshTree && world.getResource<MeaningIndex>().nodeCount > 0) {
    // Host-side mechanical refresh tick: mtime-changed files re-scan
    // before the actor sees the tree (zero model tokens).
    await etl.execute({'action': 'refresh'});
  }
  registry.register(etl);
  // ADR 0030 §3 GRADUATION (2026-09-07): the read program REPLACES the
  // three verbs it subsumes — meaning_locate, meaning_zoom,
  // meaning_impact schemas are OUT, the program schema is IN. The
  // profile SHRINKS, never grows; the interpreter CALLS the existing
  // tool implementations (ranking, budgets and repair hints are
  // inherited, never reimplemented). The read surface is paid ONCE for
  // N reads.
  registry.register(
    meaningProgramTool(world, spanReader: meaningSpanReader(fsRoot)),
  );
  // P1 trusted-author tier: when the host carries an edit approver or a
  // pack-write consent gate, the materializer is built HERE so both
  // land on the same instance (the pack load loop realizes authored_body
  // entries only through the consent gate).
  final materializer = editApprover == null && packConsent == null
      ? null
      : SpanEditMaterializer(
          world: world,
          workspace: workspace,
          approver: editApprover,
          packConsent: packConsent,
        );
  registry.register(editSymbolTool(world, workspace, materializer: materializer));
  // ADR 0034 — ONE edit verb: doc sections (sec_…) and config keys
  // (key_…) edit through the SAME verb, class-routed. There are NO
  // edit_section/edit_key model verbs — new formats register a
  // MaterializerSpec, never a surface entry.
  // fs tier (ADR 0024 §4): the escape-hatch WRITE — registered ONLY when a
  // review gateway exists (no approver, no verb).
  if (gateway != null) {
    registry.register(writeReviewTool(fsRoot, gateway));
  }
  // R7 production #7 finding: the run tool in the meaning profile is
  // CONSTRAINED to the convention commands — the free-form arm was a
  // write hole (`perl -pi` edited files through it; measured in the pi
  // row). File mutation goes through the edit verbs, never the shell.
  registry.register(
    runTool(
      fsRoot,
      allowlist: const [
        ['dart', 'analyze'],
        ['dart', 'test'],
        ['dart', 'run'],
        ['flutter', 'analyze'],
        ['flutter', 'test'],
      ],
    ),
  );
  return MeaningProfileSurface(registry: registry, etl: etl);
}

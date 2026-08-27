// ignore_for_file: lines_longer_than_80_chars

/// Declarative composition surface over ADR 0007's five seams (ADR 0014).
///
/// The "general agent" — a coding agent that also writes long articles /
/// screenplays / books and holds long conversations — is *different loops, not
/// different models*. This library exports loops, tool surfaces, and
/// evals/datasets as **data**:
///
/// - [FlowSpec]: name + archetype + ordered [StageSpec]s + a [ToolSurface]
///   gate. [renderFlow] maps model [DecideStage]s onto the existing
///   [DecisionFlow] builders (ADR 0005); [VerifyStage]s are deterministic
///   mechanical checks that never touch an LLM.
/// - [ToolSurface] / [applyToolSurface]: which registered seam-3 tools a flow
///   may wire; the registry resolves real bodies.
/// - [DatasetSpec] / [EvalTier]: evals declared once, run many ways; the tier
///   split keeps deterministic-checkable rows (`passable`) honest relative to
///   evidence-only rows (`evidence`, never a loud pass label).
///
/// Two hard rules keep this from becoming a framework (ADR 0014 §1):
/// 1. **Closed shape-set**: the declarative keys are fixed;
///    [FlowSpec.fromYaml] rejects unknown key. Any task needing real control
///    flow past these is a *missing seam* (ADR 0007 three-failures rule), not
///    a DSL feature.
/// 2. **No domain content, no core loop**: rendering produces the existing
///    [DecisionFlow]; the mechanical verifies are plain data; nothing here
///    understands what a "prose flow" or a "coding flow" *is* — the host owns
///    that meaning and supplies it as the [FlowSpec.archetype] label + tools.
///
/// Deterministic, LLM-free testable by construction.
library;

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show ToolDef, ToolName;

import 'package:yaml/yaml.dart';

import '../decisions/decision_flow.dart';

// --------------------------------------------------------------------------
// Eval tiers & backends (generic) + tool surface
// --------------------------------------------------------------------------

/// Whether a dataset row may carry a loud pass/fail.
///
/// Deterministic-checkable evals (e.g. coding) → `passable`. Domains with no
/// falsifiable oracle (long-form prose, dialogue) → `evidence` rows report
/// structured evidence and are **never** labeled `pass` (ADR 0014 §3). The
/// tier is a generic evaluation concept; the *choice* of tier for a given
/// domain is the host's, not the core's.
enum EvalTier {
  passable('passable'),
  evidence('evidence');

  const EvalTier(this.key);
  final String key;
}

enum EvalBackend {
  scripted('scripted'),
  native('native'),
  guided('guided'),
  pi('pi');

  const EvalBackend(this.key);
  final String key;

  static EvalBackend parse(String k) =>
      values.firstWhere((b) => b.key == k, orElse: () => EvalBackend.scripted);
}

/// Which registered seam-3 tools a [FlowSpec] may expose to its actor.
class ToolSurface {
  const ToolSurface({this.allowAll = false, this.allowed = const {}});
  final bool allowAll;
  final Set<String> allowed;

  bool allows(ToolName name) => allowAll || allowed.contains(name.value);
}

/// Filter [all] to the tools a surface allows, preserving order.
List<ToolDef> applyToolSurface(List<ToolDef> all, ToolSurface surface) => [
  for (final t in all)
    if (surface.allows(t.name)) t,
];

// --------------------------------------------------------------------------
// Stages
// --------------------------------------------------------------------------

/// When a model-facing decision stage fires (maps to an ADR 0005 trigger).
enum DecisionTrigger {
  toolResult('tool_result'),
  error('error'),
  idleEveryNTicks('idle_every_n_ticks');

  const DecisionTrigger(this.key);
  final String key;

  static DecisionTrigger parse(String k) => values.firstWhere(
        (t) => t.key == k,
        orElse: () => DecisionTrigger.toolResult,
      );
}

/// A model-facing decision stage; [renderFlow] turns it into a
/// [DecisionFlow] policy.
class DecideStageSpec {
  const DecideStageSpec({
    required this.name,
    required this.trigger,
    required this.prompt,
    this.everyNTicks = 0,
    this.priority = 0,
    this.escalate = false,
  });

  final String name;
  final DecisionTrigger trigger;
  final String prompt;

  /// Tick interval for [DecisionTrigger.idleEveryNTicks].
  final int everyNTicks;
  final int priority;

  /// Route to a stronger tier — legitimate for hosts whose domain is
  /// content-rich (prose/dialogue); a fallback for coding (ADR 0014 §4).
  final bool escalate;
}

/// A deterministic, LLM-free mechanical stage (verify/lint/format).
class VerifySpec {
  const VerifySpec({required this.name, required this.kind, this.path});
  final String name;
  final String kind; // a coding-suite checker kind, e.g. 'contains'
  final String? path;
}

/// A step of a flow: either a model decision or a mechanical verify.
sealed class StageSpec {
  const StageSpec();
}

class DecideStage extends StageSpec {
  const DecideStage(this.spec);
  final DecideStageSpec spec;
}

class VerifyStage extends StageSpec {
  const VerifyStage(this.spec);
  final VerifySpec spec;
}

// --------------------------------------------------------------------------
// FlowSpec + declarative YAML (closed shape-set)
// --------------------------------------------------------------------------

class FlowSpec {
  FlowSpec({
    required this.name,
    this.archetype = '',
    this.stages = const [],
    this.toolSurface = const ToolSurface(allowAll: true),
  });

  /// Parse a declarative flow from YAML. **Closed keys**: anything not in the
  /// known key set throws — enforcing ADR 0014 §1 (no framework breadth).
  factory FlowSpec.fromYaml(String source) {
    final doc = loadYamlNode(source);
    if (doc is! YamlMap) throw ArgumentError('flow must be a YAML map');
    final name = doc['name'] as String? ?? 'unnamed';
    // Free-form label supplied by the host (e.g. 'dialogue', 'screenplay',
    // 'code_edit'). The core does NOT interpret it — it is domain content
    // that lives above the seams (ADR 0014 §1 / boundary correction).
    final archetype = doc['archetype'] as String? ?? '';
    var surface = const ToolSurface(allowAll: true);
    final toolMap = doc['tools'];
    if (toolMap is YamlMap) {
      final allowAll = toolMap['allow_all'] == true;
      final allowed = {...?(toolMap['allowed'] as YamlList?)?.cast<String>()};
      surface = ToolSurface(allowAll: allowAll, allowed: allowed);
    }
    final stages = <StageSpec>[];
    for (final s in (doc['stages'] as YamlList?) ?? const []) {
      final m = s as YamlMap;
      final kind = switch (m['kind']) { final String k => k, _ => 'decide' };
      if (kind == 'verify') {
        final spec = VerifySpec(
          name: m['name'] as String? ?? 'verify',
          kind: m['check'] as String? ?? 'verbose',
          path: m['path'] as String?,
        );
        stages.add(VerifyStage(spec));
        continue;
      }
      if (kind != 'decide') {
        throw ArgumentError('unknown stage kind "$kind" (closed shape-set)');
      }
      final spec = DecideStageSpec(
        name: m['name'] as String? ?? 'decide',
        trigger: DecisionTrigger.parse(m['trigger'] as String? ?? 'tool_result'),
        prompt: m['prompt'] as String? ?? '',
        everyNTicks: (m['every_n_ticks'] as int?) ?? 0,
        priority: (m['priority'] as int?) ?? 0,
        escalate: m['escalate'] == true,
      );
      stages.add(DecideStage(spec));
    }
    return FlowSpec(
      name: name,
      archetype: archetype,
      stages: stages,
      toolSurface: surface,
    );
  }

  final String name;

  /// Free-form loop label owned by the host/domain, never interpreted here.
  final String archetype;
  final List<StageSpec> stages;
  final ToolSurface toolSurface;
}

// --------------------------------------------------------------------------
// Rendering → existing DecisionFlow (ADR 0005)
// --------------------------------------------------------------------------

/// Lower a [FlowSpec] onto the existing machinery.
///
/// Model [DecideStage]s become [DecisionFlow] policies (via the ADR 0005
/// builders); mechanical [VerifyStage]s are returned so a deterministic
/// verifier (no LLM) can run them. The default ReAct continuation is included
/// when the flow declares no model stages, so the loop never stalls.
({DecisionFlow flow, List<VerifySpec> verifies}) renderFlow(FlowSpec spec) {
  final policies = <DecisionPolicy>[];
  final verifies = <VerifySpec>[];
  for (final s in spec.stages) {
    switch (s) {
      case DecideStage(:final spec):
        policies.addAll(_policyFor(spec));
      case VerifyStage(:final spec):
        verifies.add(spec);
    }
  }
  if (policies.isEmpty) policies.add(ReActContinuationPolicy());
  return (flow: DecisionFlow(policies), verifies: verifies);
}

List<DecisionPolicy> _policyFor(DecideStageSpec spec) => switch (spec.trigger) {
      DecisionTrigger.toolResult => [
        onToolResult().thenOpen(
          prompt: spec.prompt,
          priority: spec.priority,
          escalate: spec.escalate,
        ),
      ],
      DecisionTrigger.error => [
        onError().thenOpen(
          prompt: spec.prompt,
          priority: spec.priority,
          escalate: spec.escalate,
        ),
      ],
      DecisionTrigger.idleEveryNTicks => [
        whenIdleEveryNTicks(spec.everyNTicks).thenOpen(
          prompt: spec.prompt,
          priority: spec.priority,
          escalate: spec.escalate,
        ),
      ],
    };

// --------------------------------------------------------------------------
// DatasetSpec (eval-as-data) + honest summary
// --------------------------------------------------------------------------

class DatasetSpec {
  DatasetSpec({
    required this.id,
    this.tier = EvalTier.passable,
    this.taskRefs = const [],
    this.backends = const [],
  });

  factory DatasetSpec.fromYaml(String source) {
    final doc = loadYamlNode(source);
    if (doc is! YamlMap) throw ArgumentError('dataset must be a YAML map');
    final backends =
        ((doc['backends'] as YamlList?) ?? const [])
            .cast<String>()
            .map(EvalBackend.parse)
            .toList();
    final tier = EvalTier.values.firstWhere(
      (t) => t.key == (doc['tier'] ?? 'passable'),
      orElse: () => EvalTier.passable,
    );
    return DatasetSpec(
      id: doc['id'] as String? ?? 'dataset',
      tier: tier,
      taskRefs: ((doc['tasks'] as YamlList?) ?? const []).cast<String>(),
      backends: backends,
    );
  }

  final String id;
  final EvalTier tier;

  /// Fixture/task identifiers this dataset runs (paths or ids), declared once.
  final List<String> taskRefs;

  /// Backends to run against, shared across the matrix driver.
  final List<EvalBackend> backends;
}

/// One eval row — comparable across backends; [passed] is null for evidence.
class DatasetRow {
  const DatasetRow({
    required this.task,
    required this.backend,
    required this.tokens,
    required this.calls,
    this.wallMs = 0,
    this.escalations = 0,
    this.passed,
    this.evidence,
  });

  final String task;
  final EvalBackend backend;
  final int tokens;
  final int calls;
  final int wallMs;
  final int escalations;
  final bool? passed;
  final String? evidence;

  Map<String, Object?> toJson() => {
    'task': task,
    'backend': backend.key,
    'tokens': tokens,
    'calls': calls,
    if (wallMs > 0) 'wall_ms': wallMs,
    'escalations': escalations,
    if (passed != null) 'passed': passed,
    if (evidence != null) 'evidence': evidence,
  };
}

/// Honest summary honoring [EvalTier]: pass-rate is computed **only** over
/// `passable` rows; `evidence` rows (prose/dialogue) are counted and their
/// tokens/report measured but never praised as pass (ADR 0014 §3).
class DatasetResultSummary {
  DatasetResultSummary(this.rows);
  final List<DatasetRow> rows;

  int get passableCount => rows.where((r) => r.passed != null).length;
  int get passedCount => rows.where((r) => r.passed == true).length;
  int get evidenceCount => rows.where((r) => r.passed == null).length;
  int get totalTokens => rows.fold(0, (a, r) => a + r.tokens);
  int get totalCalls => rows.fold(0, (a, r) => a + r.calls);

  double get passRate => passableCount == 0
      ? 0.0
      : passedCount / passableCount;

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('| task | backend | tokens | calls | pass/evidence |')
      ..writeln('|---|---|---|---|---|');
    for (final r in rows) {
      final cell = r.passed != null
          ? (r.passed! ? '✅ pass' : '❌ fail')
          : 'evidence';
      b.writeln(
        '| ${r.task} | ${r.backend.key} | ${r.tokens} | ${r.calls} | $cell |',
      );
    }
    b
      ..writeln()
      ..writeln(
        '$passedCount/$passableCount passable passed '
        '(${(passRate * 100).toStringAsFixed(0)}%), '
        '$evidenceCount evidence rows, $totalTokens tokens, '
        '$totalCalls calls.',
      );
    return b.toString();
  }
}

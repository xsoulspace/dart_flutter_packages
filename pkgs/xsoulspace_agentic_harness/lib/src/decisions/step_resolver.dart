// ignore_for_file: lines_longer_as_80_chars

/// ADR 0009 Amendment (2026-09-08) — the STEP RESOLVER: mechanical
/// resolution lives IN the frontier, never in a parallel pre-pass.
///
/// The wave measurement (afm_wave_results.md § DECIDED): across every
/// failed step in all 5 failed trusted runs + md/yaml, **0% needed model
/// composition and 100% was mechanically resolvable** — the target
/// identifier was in the prompt (the model never queried it once; every
/// focusId/query was invented; every edit bounce was an id/action
/// problem). The resolver turns that measurement into machinery:
///
/// - **pack executables** name the symbol (`apply <executableId> to
///   <Symbol>` — the proven task-grammar path, row 1, pass@1 ×3);
/// - **grammar verbs** parse the sentence (`fix` / `rename` / `run` /
///   `apply`);
/// - **prompt-named anchors**: a section heading or a config keypath named
///   in the prompt resolves to its node id over the tree (the md/yaml
///   wave-row class — file, section/keypath and value ALL named in the
///   prompt; the failures were id invention and early stop).
///
/// **TOTAL or bounce (the locate-hints law)**: resolution ends in exactly
/// one of [ReadyStep] (the ready decision args — the actor CARRIES the
/// move, never composes ids), [AmbiguousStep] (a NAMED reason + real
/// candidate ids — never a guess), [HostVerbStep] (the host verb owns it;
/// the normal decision path is the right surface), or [TierRoutedStep]
/// (no mechanical pattern covers the sentence — ADR 0009 amendment §4
/// projects it as tier-routed DATA; the routing machinery itself is
/// named-not-built until the first unresolvable task fires the
/// three-failures rule).
///
/// Zero-token mechanical actors may work consented [ReadyStep] moves
/// while the model actor works (the accelerate-and-predict behavior —
/// see mechanical_actor.dart).
library;

import 'dart:convert';

import 'package:ecsly/ecsly.dart';

import '../data_models/data_models.dart' show StepAction, StepStatus;
import '../meaning/meaning_tree.dart';
import '../narrative/narrative.dart'
    show Step, StepVerificationKind;
import '../tools/task_grammar.dart';

/// The resolution outcome — TOTAL or bounce, never a guess.
sealed class StepResolution {
  const StepResolution();
}

/// The step resolved MECHANICALLY: [args] are the EXACT tool-call
/// arguments (edit_symbol shape today) — the ready decision. The actor
/// carries them verbatim (the row-1 pattern, pass@1 ×3 on-device).
class ReadyStep extends StepResolution {
  const ReadyStep(this.args, {required this.toolName, required this.source});

  /// The exact tool-call arguments (ids resolved over the tree).
  final Map<String, Object?> args;

  /// The tool the args are legal for (`edit_symbol` today, `run` for a
  /// host-verb expansion).
  final String toolName;

  /// Which resolver source matched: `pack_executable` | `grammar_verb` |
  /// `prompt_named_anchor`.
  final String source;
}

/// The target was named but resolution is AMBIGUOUS: a named reason plus
/// REAL candidate ids (the locate-hints law — bounded, mechanical, never
/// a guess). The next decision's cut carries the candidates; the model
/// picks one or zooms — it never invents an id.
class AmbiguousStep extends StepResolution {
  const AmbiguousStep(this.reason, this.candidates);

  /// Named failure class (`ambiguous_target` | `target_not_in_tree` |
  /// `anchor_not_in_tree` | `no_executable_for_class` | …).
  final String reason;

  /// Real node ids from the tree (≤5, ranked by label match), or empty
  /// when the tree has no same-kind node at all.
  final List<String> candidates;
}

/// The host verb owns the step (`run <check>` — the allowlisted run tool
/// is the right surface; the normal decision path handles it). No ready
/// directive is emitted — this is NOT tier routing.
class HostVerbStep extends StepResolution {
  const HostVerbStep(this.reason);
  final String reason;
}

/// No mechanical pattern covers the sentence — projected as TIER-ROUTED
/// data (ADR 0009 amendment §4: up-front routing property; the J8.2
/// overseer stays the fallback). NAMED-NOT-BUILT as machinery: the build
/// trigger is the first real unresolvable task (the three-failures rule).
class TierRoutedStep extends StepResolution {
  const TierRoutedStep(this.reason);
  final String reason;
}

/// Resolves ONE task prompt mechanically over the meaning tree. Order:
/// grammar verbs (pack executables) → prompt-named anchors → total-or-
/// bounce. Deterministic; zero model tokens.
StepResolution resolveTaskPrompt(World world, String taskPrompt) {
  // 1. The grammar verbs (the proven row-1 path): fix/rename/apply over
  //    pack executables + symbol resolution.
  final reading = parseTaskSentence(taskPrompt);
  if (reading is TaskGrammarMatch) {
    final lookup = executableDecisionForTask(world, reading);
    if (lookup.matched && lookup.decision != null) {
      return ReadyStep(
        Map<String, Object?>.of(lookup.decision!),
        toolName: 'edit_symbol',
        source: 'pack_executable',
      );
    }
    switch (lookup.reason) {
      case 'run_is_host_verb':
        return HostVerbStep('run_is_host_verb');
      case 'no_executables_in_tree':
      case 'no_executable_for_class':
      case 'target_symbol_missing':
        // The verb parsed; the inventory/anchor did not resolve. Bounce
        // with what the tree actually has (the locate-hints law).
        return AmbiguousStep(lookup.reason, _candidateIds(world, reading));
      case 'ambiguous_target':
      case 'target_not_in_tree':
        return AmbiguousStep(lookup.reason, _candidateIds(world, reading));
    }
  }

  // 2. Prompt-named anchors — position-independent mechanical patterns
  //    over the sentence (the md/yaml trusted-row classes).
  final anchor = _resolvePromptNamedAnchor(world, taskPrompt);
  if (anchor != null) return anchor;

  // 3. Total-or-bounce: nothing mechanical covers the sentence.
  return TierRoutedStep(
    'no mechanical pattern covers the sentence — the sentence carries no '
    'grammar verb and no prompt-named file+anchor/keypath',
  );
}

/// Candidate ids for a bounce: same-kind node labels that exist, ranked
/// by simple containment against the parse target (≤5 — the cursor cap).
List<String> _candidateIds(World world, TaskGrammarMatch? match) {
  final index = world.maybeGetResource<MeaningIndex>();
  if (index == null) return const [];
  final wanted = match?.target.toLowerCase();
  final scored = <(int, String)>[];
  for (final entry in index.byId.entries) {
    final node = meaningComponentOf<MeaningNode>(world, entry.value);
    if (node == null) continue;
    if (node.kind != 'symbol' && node.kind != 'section' && node.kind != 'key') {
      continue;
    }
    final label = node.label.toLowerCase();
    var score = 0;
    if (wanted != null && wanted.isNotEmpty) {
      if (label == wanted) {
        score = 3;
      } else if (label.contains(wanted)) {
        score = 2;
      } else if (wanted.contains(label)) {
        score = 1;
      }
    }
    scored.add((score, entry.key));
  }
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  return [
    for (final (_, id) in scored.take(5)) id,
  ];
}

/// Regex scores for the prompt-named anchor patterns (mechanical, fixed
/// shapes — the wave-row prompt class; prose that does not fit bounces
/// honestly, never guesses).
final _sectionPattern = RegExp(
  r'replace\s+the\s+([^,.;:!?`"\n]+?)\s+section\s+of\s+([\w./-]+)',
  caseSensitive: false,
);
final _keypathPattern = RegExp(
  r'\bset\s+([\w][\w.]*[\w])\s+to\s+.+?\s+in\s+([\w./-]+)',
  caseSensitive: false,
);
final _backtickToken = RegExp(r'`([^`]+)`');
final _pathToken = RegExp(r'\b[\w-]+(?:[/\\][\w.-]+)+\b');

/// Resolves a prompt-named file+anchor (md section heading or a config
/// keypath) or a prompt-named symbol+executable (the trusted-row class)
/// to the ready edit args. Null when no pattern fits — never a guess.
StepResolution? _resolvePromptNamedAnchor(World world, String prompt) {
  // (a) md section: "Replace the <Heading> section of <file> …"
  final section = _sectionPattern.firstMatch(prompt);
  if (section != null) {
    final heading = section.group(1)!.trim();
    final file = section.group(2)!;
    final hit = _resolveAnchorNode(
      world,
      file: _trimTokenTail(section.group(2)!),
      kind: 'section',
      label: heading,
    );
    if (hit == null) {
      return AmbiguousStep(
        'anchor_not_in_tree',
        _anchorCandidates(world, file: file, kind: 'section'),
      );
    }
    return ReadyStep(
      {
        'action': 'replace_section',
        'symbolId': hit,
        'source': 'prompt_named_anchor',
      },
      toolName: 'edit_symbol',
      source: 'prompt_named_anchor',
    );
  }

  // (b) config keypath: "Set <keypath> to <value> in <file> …"
  final key = _keypathPattern.firstMatch(prompt);
  if (key != null) {
    final keypath = key.group(1)!;
    final file = key.group(2)!;
    final hit = _resolveAnchorNode(
      world,
      file: _trimTokenTail(key.group(2)!),
      kind: 'key',
      label: keypath,
    );
    if (hit == null) {
      return AmbiguousStep(
        'anchor_not_in_tree',
        _anchorCandidates(world, file: file, kind: 'key'),
      );
    }
    return ReadyStep(
      {
        'action': 'replace_value',
        'symbolId': hit,
        'source': 'prompt_named_anchor',
      },
      toolName: 'edit_symbol',
      source: 'prompt_named_anchor',
    );
  }

  // (c) trusted-author: a backticked symbol + path + a backticked pack
  //     executable id (`dart/author_area`) — the CONSENTED executable the
  //     prompt names. The body is pack data; the ids resolve here.
  final mentionsPack =
      prompt.contains('executable') || prompt.contains('pack');
  if (mentionsPack) {
    final tokens = [
      for (final m in _backtickToken.allMatches(prompt)) m.group(1)!,
    ];
    final executableIds = [
      for (final t in tokens)
        if (t.contains('/') && !t.contains(' ')) t,
    ];
    final paths = [
      for (final m in _pathToken.allMatches(prompt)) m.group(0)!,
    ];
    if (executableIds.isNotEmpty && paths.isNotEmpty) {
      final execId = executableIds.first;
      final inventory = _executableInventory(world);
      if (!inventory.contains(execId)) {
        return AmbiguousStep(
          'no_executable_for_class',
          [for (final e in inventory.take(5)) e],
        );
      }
      // The symbol: a backticked token near "in <path>" — mechanical
      // extraction, then the SAME exact-label resolution the span editor
      // performs (R7e: labels beat raw ids).
      final symbolToken = tokens
          .where((t) => !t.contains('/') && _identifierRe.hasMatch(t))
          .toList();
      final inPath = RegExp(
        r'`([^`]+)`\s+(?:function|symbol|class|method)?\s*in\s+([\w./-]+)',
        caseSensitive: false,
      ).firstMatch(prompt);
      final symbolName = inPath?.group(1) ?? symbolToken.firstOrNull;
      final file = inPath?.group(2) ?? paths.first;
      if (symbolName == null) {
        return AmbiguousStep('target_symbol_missing', const []);
      }
      final hit = _resolveAnchorNode(
        world,
        file: _trimTokenTail(file),
        kind: 'symbol',
        label: symbolName,
      );
      if (hit == null) {
        return AmbiguousStep(
          'target_not_in_tree',
          _anchorCandidates(world, file: file, kind: 'symbol'),
        );
      }
      return ReadyStep(
        {
          'action': 'apply_executable',
          'executableId': execId,
          'symbolId': hit,
          'executableParams': const {},
          'source': 'prompt_named_anchor',
        },
        toolName: 'edit_symbol',
        source: 'pack_executable',
      );
    }
  }
  return null;
}

final _identifierRe = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// The tree's executable inventory ids (capability nodes), sorted.
List<String> _executableInventory(World world) {
  final index = world.maybeGetResource<MeaningIndex>();
  if (index == null) return const [];
  final ids = <String>[];
  for (final entry in index.byId.entries) {
    final node = meaningComponentOf<MeaningNode>(world, entry.value);
    if (node == null || node.kind != 'executable') continue;
    final props =
        meaningComponentOf<MeaningProps>(world, entry.value)?.props ?? const {};
    ids.add(props['executableId'] as String? ?? node.label);
  }
  ids.sort();
  return ids;
}

/// Mechanical anchor resolution over the tree: the FILE node whose label
/// matches [file] (exact relative path, or basename tail), then its
/// [kind] child whose label equals [label]. Sub-node id conventions:
/// fs-tier sub-nodes (section/key) embed the file node id
/// (`<fileNodeId>_<tail>`); code symbols follow the code_etl stableId
/// law (`sym_<file with / → _>_<label>`) — both file constraints are id
/// prefixes, never guesses.
String? _resolveAnchorNode(
  World world, {
  required String file,
  required String kind,
  required String label,
}) {
  final index = world.maybeGetResource<MeaningIndex>();
  if (index == null || index.byId.isEmpty) return null;
  final labelTrim = label.trim();
  if (kind == 'symbol') {
    // Code-symbol convention: sym_<file with / → _>_<label>.
    final prefix = 'sym_${file.replaceAll('/', '_')}_';
    String? constrained;
    var constrainedCount = 0;
    var labelMatches = 0;
    for (final entry in index.byId.entries) {
      final node = meaningComponentOf<MeaningNode>(world, entry.value);
      if (node == null || node.kind != 'symbol') continue;
      if (node.label.trim() != labelTrim) continue;
      labelMatches++;
      if (entry.key.startsWith(prefix)) {
        constrained = entry.key;
        constrainedCount++;
      }
    }
    if (constrainedCount == 1) return constrained;
    // Fall back to a UNIQUE exact-label match (the R7e law: labels beat
    // raw ids) — multiple hits stay ambiguous (null).
    return labelMatches == 1 ? constrained ?? _byLabel(index, labelTrim, world) : null;
  }
  // fs-tier sub-nodes carry the file's rel path as the `path` prop (the
  // binding-stamped id is `<bindingPrefix><fileNodeId>_<tail>` — sec_ /
  // key_ / tsym_ / csym_ — so match the PROP first, then the declared
  // prefixes; never a hardcoded per-format literal).
  for (final entry in index.byId.entries) {
    final node = meaningComponentOf<MeaningNode>(world, entry.value);
    if (node == null || node.kind != kind) continue;
    final props = meaningComponentOf<MeaningProps>(world, entry.value)?.props ?? const {};
    if (props['path'] != file) continue;
    if (node.label.trim() == labelTrim) return entry.key;
  }
  final fileId = _fileNodeId(world, file);
  if (fileId == null) return null;
  for (final prefix in const ['sec_', 'key_', 'tsym_', 'csym_', '']) {
    for (final entry in index.byId.entries) {
      if (!entry.key.startsWith('$prefix${fileId}_')) continue;
      final node = meaningComponentOf<MeaningNode>(world, entry.value);
      if (node == null || node.kind != kind) continue;
      if (node.label.trim() == labelTrim) return entry.key;
    }
  }
  return null;
}

String? _byLabel(MeaningIndex index, String label, World world) {
  String? hit;
  for (final entry in index.byId.entries) {
    final node = meaningComponentOf<MeaningNode>(world, entry.value);
    if (node == null || node.kind != 'symbol') continue;
    if (node.label.trim() == label) {
      if (hit != null) return null; // ambiguous — never a guess
      hit = entry.key;
    }
  }
  return hit;
}

/// Greedy token classes swallow sentence punctuation — a mechanical trim,
/// never a guess (the task-grammar `_trimTail` law).
String _trimTokenTail(String s) => s.replaceAll(RegExp(r'[\s.,:;!]+$'), '');

/// The file node for [file]: exact label match first, then basename-tail
/// match (`README.md` matches `docs/README.md`). Deterministic: exact
/// beats tail; among tails the shortest label wins.
String? _fileNodeId(World world, String file) {
  final index = world.maybeGetResource<MeaningIndex>();
  if (index == null) return null;
  String? exact;
  final tails = <(int, String)>[];
  for (final entry in index.byId.entries) {
    final node = meaningComponentOf<MeaningNode>(world, entry.value);
    if (node == null || node.kind != 'file') continue;
    if (node.label == file) {
      exact = entry.key;
      break;
    }
    if (node.label.endsWith('/$file') || node.label == file) {
      tails.add((node.label.length, entry.key));
    }
  }
  if (exact != null) return exact;
  if (tails.isEmpty) return null;
  tails.sort((a, b) => a.$1.compareTo(b.$1));
  return tails.first.$2;
}

/// Bounded anchor candidates for a bounce: same-kind labels under the
/// resolved file (by the binding-stamped `path` prop, then the id
/// prefixes), or globally when the file itself did not resolve.
List<String> _anchorCandidates(
  World world, {
  required String file,
  required String kind,
}) {
  final index = world.maybeGetResource<MeaningIndex>();
  if (index == null) return const [];
  final fileId = _fileNodeId(world, file);
  final candidates = <String>[];
  for (final entry in index.byId.entries) {
    final node = meaningComponentOf<MeaningNode>(world, entry.value);
    if (node == null || node.kind != kind) continue;
    final props = meaningComponentOf<MeaningProps>(world, entry.value)?.props ?? const {};
    final underFile = props['path'] == file ||
        (fileId != null &&
            const ['sec_', 'key_', 'tsym_', 'csym_', '']
                .any((p) => entry.key.startsWith('$p${fileId}_')));
    if (fileId != null && !underFile) continue;
    candidates.add(entry.key);
    if (candidates.length >= 5) break;
  }
  return candidates;
}

/// Renders the READY MOVE directive (the row-1 shape, measured pass@1 ×3):
/// imperative, LEADS, forbids the natural first moves (scan/zoom).
String readyStepDirective(ReadyStep ready) {
  // The payload IS the exact tool-call args (source classification rides
  // along — the edit tool tolerates the provenance arg; the applied
  // decision carries its resolver attribution for the audit).
  final payload = ready.args;
  // CLASS-AWARE tail (the 2026-09-08 on-device row taught this the hard
  // way: a generic "carry the body/value" line on a pack-executable move
  // sent the 4k model hunting for a body that does not exist — 67
  // decisions of invented-query exploration): a section/key move carries
  // its body/value from the task text; a pack-executable move composes
  // NOTHING (the pack carries the body).
  const carriesBody = {
    'replace_section', 'insert_section', 'append_to_section',
    'set_key', 'replace_value', 'append_list_item',
  };
  final tail = carriesBody.contains(ready.args['action'])
      ? 'Carry the body/value from the task text into the body slot.'
      : 'No body is composed — the pack executable carries it.';
  return 'READY MOVE — execute this harness_edit call NOW with EXACTLY '
      'these args. Do NOT scan (the meaning tree is already built), do '
      'NOT zoom or explore first. This READY MOVE REPLACES any '
      'scan/locate/zoom flow the task text describes — do not follow '
      'it:\n'
      'harness_edit ${jsonEncode(payload)}\n'
      '(host frontier resolver, 0 tokens: ${ready.source}. $tail After '
      'the move, end your turn.)';
}

/// Renders the AMBIGUOUS bounce directive: the candidates are REAL ids —
/// the model picks one or zooms; it never invents an id (the locate-hints
/// law applied at the frontier).
String ambiguousStepDirective(AmbiguousStep ambiguous) => 'The frontier '
    'resolver could not resolve this step UNIQUELY (${ambiguous.reason}). '
    'Do NOT invent an id. The real candidates from the tree are:\n'
    '${ambiguous.candidates.join("\n")}\n'
    'zoom ONE of them (or locate the exact label) to confirm, then edit. '
    'If none fits, state which and stop.';

/// Lands the resolved step on the frontier as GRAPH DATA (ADR 0009 §2 +
/// the 2026-09-08 Amendment): claim + the RESOLVED [StepAction] (the
/// ready decision args) + the resolver classification riding
/// `StepAction.outcome`. The projection/metrics and the mechanical actor
/// read the tree, never prose. Returns the step entity.
Entity spawnResolvedStep(
  World world,
  ReadyStep ready, {
  required String claim,
}) {
  final stepEntity = world.spawnComponents([
    Step(claim: claim, verificationKind: StepVerificationKind.mechanical),
    StepAction(ready.toolName, {
      for (final e in ready.args.entries)
        if (e.key != 'source') e.key: e.value,
    }),
    StepStatus('open'),
  ]);
  if (world.getEntity(stepEntity).$1.get<StepAction>() case final action?) {
    action.outcome = {'source': ready.source};
  }
  world.flush();
  return stepEntity;
}

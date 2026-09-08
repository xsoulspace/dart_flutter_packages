// ignore_for_file: lines_longer_than_80_chars

/// P2 — the task-grammar classifier (PLAN §NOW, decision amortization):
/// a PURE HOST parse of a task sentence into `{verb-class, target, params}`
/// — zero model tokens, before the model.
///
/// Working with code is highly structural (pipeline_coding.md §Directions
/// 1): most task sentences parse mechanically. This module covers the
/// STRUCTURED patterns only — never prose:
///
/// | sentence shape                                   | verb-class | target      |
/// |--------------------------------------------------|------------|-------------|
/// | `fix <Symbol> [in <file>]`                       | fix        | symbol      |
/// | `rename <A> to <B> [in <file>]`                  | rename     | symbol      |
/// | `run <check>`                                    | run        | check       |
/// | `apply <executableId> [to <Symbol>]`             | apply      | executable  |
///
/// A sentence that does NOT parse to the grammar FAILS HONESTLY — a named
/// failure class (`no_sentence` / `no_verb` / `unstructured_prose` /
/// `missing_target`), never a guess. The structured 80%, never prose.
///
/// On a parse hit, [executableDecisionForTask] looks up a pack executable
/// whose repair class matches the verb-class (fix → `replace_member_body`,
/// rename → `rename_symbol`, apply → the named id) over the tree's
/// `'executable'` inventory nodes (capability_nodes.dart), resolves the
/// target symbol mechanically (exact label match over the tree — the same
/// resolution the span editor performs), and emits the READY
/// `apply_executable` decision data. The host pre-pass spends ZERO
/// decisions; the actor's next decision carries the data verbatim.
library;

import 'package:ecsly/ecsly.dart';

import '../meaning/capability_nodes.dart';
import '../meaning/meaning_tree.dart';

/// One mechanical reading of a task sentence.
sealed class TaskGrammarReading {
  const TaskGrammarReading();
}

/// The sentence parsed to the structured grammar.
class TaskGrammarMatch extends TaskGrammarReading {
  const TaskGrammarMatch({
    required this.verbClass,
    required this.target,
    required this.targetKind,
    this.params = const {},
  });

  /// `fix` | `rename` | `run` | `apply`.
  final String verbClass;

  /// The parse's primary target (a symbol label, check, or executable id).
  final String target;

  /// `symbol` | `executable` | `check`.
  final String targetKind;

  /// Bounded parameters the pattern extracted (`newName`, `file`, `symbol`).
  final Map<String, String> params;
}

/// HONEST no-parse: a NAMED class, never a guess. The loop falls through
/// to the normal decision path.
class TaskGrammarNoParse extends TaskGrammarReading {
  const TaskGrammarNoParse(this.failureClass, this.detail);

  /// `no_sentence` (only directives/boilerplate — no task sentence at all)
  /// | `no_verb` (does not start with a known imperative verb)
  /// | `unstructured_prose` (a known verb whose rest does not fit the
  ///   mechanical patterns) | `missing_target` (the verb alone).
  final String failureClass;
  final String detail;
}

/// The host-side teaching suffixes the runner/daemon append to a task
/// sentence (fixed constants — stripping them is mechanical, not prose
/// understanding).
const _knownSuffixes = [
  'Work through the meaning tree: repo_etl scan, meaning_program read '
      'ops (locate/zoom/impact/read) to read, edit_symbol to act on '
      'code, write_review for non-code files (the human consents). '
      'Never touch files directly.',
  'Verify with the run tool — the check must exit 0.',
];

/// Strips mechanical directive tokens (`[scan]`, `[verify]`, `harness_x
/// {…}` payloads — brace-balanced) and the known teaching suffixes, leaving
/// the bare task sentence (or '').
String stripDirectivesAndBoilerplate(String text) {
  var s = text;
  // harness_x {…} payloads — brace-balanced scan (mechanical).
  final payload = RegExp(r'harness_\w+\s*\{');
  for (final m in payload.allMatches(s).toList().reversed) {
    var depth = 0;
    var end = m.start;
    for (var i = m.start; i < s.length; i++) {
      if (s[i] == '{') depth++;
      if (s[i] == '}') {
        depth--;
        if (depth == 0) {
          end = i + 1;
          break;
        }
      }
    }
    s = s.replaceRange(m.start, end, ' ');
  }
  s = s.replaceAll(RegExp(r'\[[a-z_]+\]'), ' ');
  for (final suffix in _knownSuffixes) {
    s = s.replaceFirst(suffix, '');
  }
  return s.trim();
}

const _identifier = '[A-Za-z_][A-Za-z0-9_]*';
const _fileToken = '[A-Za-z0-9_./-]+';

/// Greedy tokens can swallow sentence punctuation (`geometry.dart.`) — a
/// mechanical trim, never a guess.
String _trimTail(String s) => s.replaceAll(RegExp(r'[\s.,:;!]+$'), '');

/// Parses ONE task sentence into the structured grammar — mechanical
/// patterns only, honest named failure otherwise.
TaskGrammarReading parseTaskSentence(String sentence) {
  final s = stripDirectivesAndBoilerplate(sentence);
  if (s.isEmpty) {
    return const TaskGrammarNoParse(
      'no_sentence',
      'the prompt carries only directives/boilerplate — no task sentence',
    );
  }
  final verb = RegExp(r'^([A-Za-z]+)\b').firstMatch(s)?.group(1) ?? '';
  switch (verb.toLowerCase()) {
    case 'fix':
      final m = RegExp(
        '^fix\\s+(?:the\\s+)?($_identifier)(?:\\s+in\\s+($_fileToken))?'
        '[\\s.,:;!]',
        caseSensitive: false,
      ).firstMatch('$s ');
      if (m == null) {
        return TaskGrammarNoParse(
          RegExp('^fix\\s*\$').hasMatch(s.trim())
              ? 'missing_target'
              : 'unstructured_prose',
          'fix-pattern is `fix <Symbol> [in <file>]`',
        );
      }
      return TaskGrammarMatch(
        verbClass: 'fix',
        target: _trimTail(m.group(1)!),
        targetKind: 'symbol',
        params: {if (m.group(2) != null) 'file': _trimTail(m.group(2)!)},
      );
    case 'rename':
      final m = RegExp(
        '^rename\\s+(?:the\\s+)?($_identifier)\\s+to\\s+($_identifier)'
        '(?:\\s+in\\s+($_fileToken))?[\\s.,:;!]*\$',
        caseSensitive: false,
      ).firstMatch(s);
      if (m == null) {
        return const TaskGrammarNoParse(
          'unstructured_prose',
          'rename-pattern is `rename <A> to <B> [in <file>]`',
        );
      }
      return TaskGrammarMatch(
        verbClass: 'rename',
        target: _trimTail(m.group(1)!),
        targetKind: 'symbol',
        params: {
          'newName': m.group(2)!,
          if (m.group(3) != null) 'file': _trimTail(m.group(3)!),
        },
      );
    case 'run':
      final m = RegExp(
        '^run\\s+(?:the\\s+)?($_fileToken( $_fileToken)*)[\\s.,:;!]*\$',
        caseSensitive: false,
      ).firstMatch(s);
      if (m == null) {
        return const TaskGrammarNoParse(
          'unstructured_prose',
          'run-pattern is `run <check>`',
        );
      }
      return TaskGrammarMatch(
        verbClass: 'run',
        target: _trimTail(m.group(1)!.trim()),
        targetKind: 'check',
      );
    case 'apply':
      final m = RegExp(
        '^apply\\s+($_fileToken)(?:\\s+(?:to|on)\\s+(?:the\\s+)?'
        '($_identifier))?[\\s.,:;!]',
        caseSensitive: false,
      ).firstMatch('$s ');
      if (m == null) {
        return const TaskGrammarNoParse(
          'unstructured_prose',
          'apply-pattern is `apply <executableId> [to <Symbol>]`',
        );
      }
      return TaskGrammarMatch(
        verbClass: 'apply',
        target: _trimTail(m.group(1)!),
        targetKind: 'executable',
        params: {if (m.group(2) != null) 'symbol': m.group(2)!},
      );
    default:
      return TaskGrammarNoParse('no_verb', 'unknown imperative verb "$verb"');
  }
}

/// The lookup outcome: either the ready decision data or a NAMED reason
/// (never a guess, never a crash).
class TaskDecisionLookup {
  const TaskDecisionLookup.matched(this.decision)
    : matched = true,
      reason = '';

  const TaskDecisionLookup.missed(this.reason)
    : matched = false,
      decision = null;

  final bool matched;

  /// `no_executables_in_tree` | `run_is_host_verb` |
  /// `no_executable_for_class` | `target_symbol_missing` |
  /// `target_not_in_tree` | `ambiguous_target`.
  final String reason;

  /// The READY apply_executable decision data (source-stamped) — the actor
  /// carries it verbatim in its next decision.
  final Map<String, Object?>? decision;
}

/// Looks up a pack executable whose repair class matches the parse
/// (verb-class + target kind) over the tree's `'executable'` inventory
/// nodes, and emits the ready decision data. Deterministic: candidates
/// sorted by executable id.
TaskDecisionLookup executableDecisionForTask(
  World world,
  TaskGrammarMatch match,
) {
  if (match.verbClass == 'run') {
    // Running a check is a HOST verb (the allowlisted run tool) — no pack
    // executable expands for it; the normal path owns it.
    return const TaskDecisionLookup.missed('run_is_host_verb');
  }
  final index = world.maybeGetResource<MeaningIndex>();
  if (index == null || index.byId.isEmpty) {
    return const TaskDecisionLookup.missed('no_executables_in_tree');
  }
  // The inventory: every 'executable' node (capability_nodes.dart).
  final wantedKind = switch (match.verbClass) {
    'fix' => 'replace_member_body',
    'rename' => 'rename_symbol',
    _ => null, // 'apply' matches by id below
  };
  final candidates = <CapabilityEntry>[];
  for (final entry in index.byId.entries) {
    final node = meaningComponentOf<MeaningNode>(world, entry.value);
    if (node == null || node.kind != 'executable') continue;
    final props =
        meaningComponentOf<MeaningProps>(world, entry.value)?.props ?? const {};
    final execId = props['executableId'] as String? ?? node.label;
    final kind = props['kind'] as String? ?? '';
    if (match.verbClass == 'apply'
        ? execId == match.target
        : kind == wantedKind) {
      candidates.add(
        CapabilityEntry(
          executableId: execId,
          kind: kind,
          params: [
            if (props['params'] is List)
              for (final p in props['params'] as List)
                if (p is String) p,
          ],
        ),
      );
    }
  }
  if (candidates.isEmpty) {
    return const TaskDecisionLookup.missed('no_executable_for_class');
  }
  candidates.sort((a, b) => a.executableId.compareTo(b.executableId));
  final exec = candidates.first;
  if (match.verbClass == 'apply' && (match.params['symbol'] == null)) {
    return const TaskDecisionLookup.missed('target_symbol_missing');
  }
  final targetLabel = match.verbClass == 'apply'
      ? match.params['symbol']!
      : match.target;
  // Mechanical target resolution: exact label match over the tree's
  // symbol nodes (the SAME resolution the span editor performs on
  // `label` — R7e finding: labels beat raw ids).
  final hits = <String>[];
  for (final entry in index.byId.entries) {
    final node = meaningComponentOf<MeaningNode>(world, entry.value);
    if (node != null && node.kind == 'symbol' && node.label == targetLabel) {
      hits.add(entry.key);
    }
  }
  if (hits.isEmpty) {
    return TaskDecisionLookup.missed('target_not_in_tree');
  }
  if (hits.length > 1) {
    return TaskDecisionLookup.missed('ambiguous_target');
  }
  return TaskDecisionLookup.matched({
    'action': 'apply_executable',
    'executableId': exec.executableId,
    'symbolId': hits.single,
    if (match.params['newName'] != null)
      'executableParams': {'newName': match.params['newName']},
    'source': 'task_grammar',
  });
}

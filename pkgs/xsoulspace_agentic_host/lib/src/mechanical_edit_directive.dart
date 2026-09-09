// ignore_for_file: lines_longer_than_80_chars

/// ADR 0027 amendment — MECHANICAL EDITS: the directive classifier for the
/// daemon's deterministic `harness_edit {…}` route.
///
/// Measured failure this closes (surface_gaps.md, lane C′ follow-up,
/// 2026-09-06): `harness_edit` had NO mechanical directive path — in
/// remote-mover mode it was ALWAYS a graded mover task, and three real
/// delegations each ended `mover_refusal: empty move` (walls 103 / 117 /
/// 183 s) burning a root-convention fallback verify, with the touched-file
/// beat never landing. A structured edit payload is DATA plus the human's
/// consent — the mover model has nothing to decide (the same law the
/// mechanical write path already enforces).
///
/// The classifier lives in the HOST (transport + host policy, ADR 0025)
/// and performs MINIMAL LOCAL shape checks only: the action union as data
/// (ADR 0034 §2 — the dart union of the closed `edit_symbol` enum) and
/// slot presence/types. Deep validation (fences, coverage, label→id
/// resolution, chain compilation) stays in the workspace materializer —
/// it bounces as structured data with the exact repair move, never
/// guessed around. Layering: this file imports NOTHING from the
/// workspace package (dep direction: host → workspace is one-way; the
/// classifier must stay usable from any host entrypoint).
///
/// Deny-by-default on ambiguity: a prompt that carries ANYTHING besides
/// the payload(s) — prose, other directive forms, mixed mutation verbs —
/// NEVER takes the mechanical path (mixed prompts are graded tasks, the
/// mover decides). A balanced, pure payload whose JSON decodes but fails
/// the action-union/slot validation BOUNCES as named data on the
/// mechanical path (the mover is never reached for what is structurally
/// not a directive). A payload with unbalanced braces cannot be
/// extracted at all — the leftover text reads as prose and the prompt is
/// honestly a task.
library;

import 'dart:convert';

/// The DART edit action union the mechanical path accepts — the closed
/// `edit_symbol` dart actions (ADR 0034 §2). The doc-tier / config-tier
/// actions (`replace_section`, `set_key`, …) and `remove_member` do NOT
/// take this path: the mechanical route is the mover-refusal repair
/// surface for the graded dart edit tier, nothing more.
const mechanicalEditActions = <String>{
  'replace_member_body',
  'insert_member',
  'apply_executable',
};

/// One VALIDATED mechanical edit payload: the action plus the exact
/// `edit_symbol` args (executed verbatim — never rewritten, never
/// repaired into a guess).
class MechanicalEditPayload {
  const MechanicalEditPayload({required this.action, required this.args});

  /// The validated dart edit action (one of [mechanicalEditActions]).
  final String action;

  /// The exact args for the `edit_symbol` tool call.
  final Map<String, dynamic> args;
}

/// The classification of one prompt against the mechanical edit route.
typedef MechanicalEditClassification = ({
  /// Payloads that parsed AND passed the minimal shape validation.
  List<MechanicalEditPayload> payloads,

  /// Balanced `{…}` groups after the tag that failed to decode as JSON.
  int malformed,

  /// Balanced groups that decoded but failed the shape validation.
  int invalid,

  /// True iff the prompt carries ≥1 `harness_edit` payload, NO other
  /// directive/mutation form, and NO leftover prose — the deny-by-default
  /// rule that keeps mixed prompts on the graded task path.
  bool pure,
});

/// Is [text] a MECHANICAL EDIT directive? True iff it carries ≥1
/// well-formed `harness_edit {…}` payload, NO other directive form, and
/// NO leftover prose. A pure payload that fails shape validation does NOT
/// fall through to the mover: it takes the mechanical path to bounce as
/// named data (use [classifyMechanicalEditDirective] for the details).
bool isMechanicalEditDirective(String text) {
  final c = classifyMechanicalEditDirective(text);
  if (!c.pure) return false;
  // A pure prompt rides the mechanical path even when every payload is
  // invalid — the bounce IS the answer (never a mover round-trip for
  // structurally invalid directives).
  return c.payloads.isNotEmpty || c.invalid > 0 || c.malformed > 0;
}

/// Classify [text] for the mechanical edit route (see the library doc).
MechanicalEditClassification classifyMechanicalEditDirective(String text) {
  if (_hasForeignDirective(text)) {
    return (payloads: const [], malformed: 0, invalid: 0, pure: false);
  }
  final extracted = extractEditPayloads(text);
  if (extracted.groups.isEmpty) {
    return (payloads: const [], malformed: 0, invalid: 0, pure: false);
  }
  // Purity: every tag occurrence must have been consumed as a balanced
  // payload group (none dropped), and whatever remains must be whitespace.
  final pure = extracted.droppedUnbalanced == 0 &&
      stripEditPayloads(text).trim().isEmpty;
  final payloads = <MechanicalEditPayload>[];
  var invalid = 0;
  for (final args in extracted.groups) {
    final payload = validateMechanicalEditPayload(args);
    if (payload == null) {
      invalid++;
    } else {
      payloads.add(payload);
    }
  }
  return (
    payloads: payloads,
    malformed: extracted.malformed,
    invalid: invalid,
    pure: pure,
  );
}

/// Any other directive/mutation form denies the mechanical path — the
/// prompt is a task (mixed prompts NEVER take it).
bool _hasForeignDirective(String text) =>
    text.contains('harness_run') ||
    text.contains('harness_fs_write') ||
    text.contains('harness_meaning_program') ||
    RegExp(r'\[scan\]').hasMatch(text) ||
    RegExp(r'\[zoom[ \]]').hasMatch(text) ||
    RegExp(r'\[verify\]').hasMatch(text) ||
    RegExp(r'\[edit[ \]]').hasMatch(text) ||
    text.contains('[read-only]');

/// Minimal LOCAL shape validation of one decoded `harness_edit` payload
/// (see the library doc — the materializer owns the deep checks and
/// bounces with the exact repair move). Null → invalid (named bounce).
MechanicalEditPayload? validateMechanicalEditPayload(Map<String, dynamic> args) {
  final action = args['action'];
  if (action is! String || !mechanicalEditActions.contains(action)) {
    return null;
  }
  final symbolId = args['symbolId'];
  // ONE required id: the symbol this move targets (for insert_member the
  // HOST CLASS) — the R7e contract the schema itself enforces.
  if (symbolId is! String || symbolId.isEmpty) return null;
  switch (action) {
    case 'replace_member_body':
      // The host compiles the chain — a body replacement without one is
      // structurally incomplete (never guessed into prose).
      if (!_validOpChain(args['opChain'])) return null;
    case 'insert_member':
      final name = args['name'];
      if (name is! String || name.isEmpty) return null;
      if (!_validOpChain(args['opChain'])) return null;
    case 'apply_executable':
      final executableId = args['executableId'];
      if (executableId is! String || executableId.isEmpty) return null;
  }
  return MechanicalEditPayload(action: action, args: args);
}

bool _validOpChain(Object? raw) {
  if (raw is! List || raw.isEmpty) return false;
  for (final row in raw) {
    if (row is! Map) return false;
    final label = row['label'];
    if (label is! String || label.isEmpty) return false;
  }
  return true;
}

/// Extracted `harness_edit {…}` payload groups + the honesty counters.
typedef ExtractedEditPayloads = ({
  /// Balanced groups after the tag that decoded as JSON objects.
  List<Map<String, dynamic>> groups,

  /// Balanced groups that failed to decode (never guessed around).
  int malformed,

  /// Tag occurrences with no balanced `{…}` group (or no `{` at all) —
  /// unextractable, so they honestly remain prose.
  int droppedUnbalanced,

  /// Tag occurrences that WERE consumed as balanced groups.
  int consumed,
});

/// Extracts every balanced `{…}` payload following a `harness_edit` tag in
/// [text] (the same rescan discipline as the daemon's payload parser: a
/// broken group never swallows a well-formed payload that follows it).
ExtractedEditPayloads extractEditPayloads(String text) {
  const tag = 'harness_edit';
  final groups = <Map<String, dynamic>>[];
  var malformed = 0;
  var droppedUnbalanced = 0;
  var consumed = 0;
  var from = 0;
  while (true) {
    final tagIdx = text.indexOf(tag, from);
    if (tagIdx < 0) break;
    from = tagIdx + tag.length;
    final open = text.indexOf('{', from);
    if (open < 0) {
      droppedUnbalanced++;
      break;
    }
    var depth = 0;
    String? payload;
    for (var i = open; i < text.length; i++) {
      final c = text[i];
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) {
          payload = text.substring(open, i + 1);
          from = i + 1;
          break;
        }
      }
    }
    if (payload == null) {
      droppedUnbalanced++;
      // Rescan AFTER this '{' — keep looking for well-formed groups.
      from = open + 1;
      continue;
    }
    consumed++;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        groups.add(decoded);
      } else {
        malformed++;
      }
    } on FormatException {
      malformed++;
      from = open + 1;
    }
  }
  return (
    groups: groups,
    malformed: malformed,
    droppedUnbalanced: droppedUnbalanced,
    consumed: consumed,
  );
}

/// Strips every balanced `harness_edit {…}` group (plus the tag) — the
/// purity check runs on what remains.
String stripEditPayloads(String text) {
  const tag = 'harness_edit';
  var out = text;
  var from = 0;
  while (true) {
    final tagIdx = out.indexOf(tag, from);
    if (tagIdx < 0) break;
    final open = out.indexOf('{', tagIdx);
    if (open < 0) break;
    var depth = 0;
    var closed = false;
    for (var i = open; i < out.length; i++) {
      if (out[i] == '{') depth++;
      if (out[i] == '}') {
        depth--;
        if (depth == 0) {
          out = out.replaceRange(tagIdx, i + 1, '');
          from = tagIdx;
          closed = true;
          break;
        }
      }
    }
    if (!closed) break;
  }
  return out;
}

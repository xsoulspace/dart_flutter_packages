// ignore_for_file: lines_longer_as_80_chars

/// The YAML/JSON MATERIALIZER (ADR 0024 §2 — the yaml + json file-class
/// specs, realized). PLAN §NOW P1 item 5.
///
/// The specs are DATA — registered in `file_class_spec.dart` as
/// `materializerSpecs['yaml']` and `materializerSpecs['json']` (both with
/// `verb: edit_key`; the fs tier stamps `edit_verb: edit_key` on their
/// file nodes):
/// `{fileClass: yaml|json, span currency: keypath, map format: keypath_tree
/// (dot/bracket paths; lists indexed), emitter: keypath_splice,
/// oracle: parse_semantic_diff, anchors: keypath}`.
///
/// Uniform edit-verb shape (ADR 0024 §3 — ONE verb, `edit_key`, for BOTH
/// classes; the host dispatches on the file class mechanically):
/// - required anchor slot (the keypath) — resolved MECHANICALLY from a
///   fresh parse of the file (never stale tree offsets): the dot/bracket
///   keypath (`deps.build`, `jobs.build[0].name`) or the keypath node id
///   (`key_…_<slug>`) from meaning_zoom; missing/ambiguous bounces as
///   named data with the outline + the exact repair move;
/// - body-as-data (the scalar/fragment — evidence-tier data, never code
///   tokens), byte-bounded by [KeypathMaterializer.maxKeyBodyChars];
/// - host-spliced KEYPATH emitter: bytes are spliced ONLY inside the
///   target keypath's span — sibling lines, comments, blank lines and
///   formatting stay byte-identical (mechanically asserted at plan time:
///   the bytes before and after the affected range must be identical);
/// - named oracle `parse_semantic_diff`: after EVERY apply the file is
///   re-parsed with the REAL parser (package:yaml / jsonDecode — the yaml
///   package does NOT round-trip comments, so re-serialization is
///   forbidden and the splice is by source offsets) and the semantic diff
///   (before vs after parse trees) must be EXACTLY the intended change —
///   nothing else. A violating edit AUTO-REVERTS with the named class.
///
/// COMMENT-PRESERVING is the hard requirement (yaml especially): the
/// splice edits only the target keypath's lines; the semantic diff proves
/// the only semantic change is the intended one and the byte assertion
/// proves every line outside the target span is untouched.
///
/// The map half (`parseKeypathTree`) is the SAME parser the fs tier's map
/// builder consumes (`fs_etl._indexKeypaths` delegates here), so the
/// anchors the model zooms and the anchors the emitter splices can never
/// disagree. A class with NO oracle has NO edit verb — the oracle is
/// named above, which is what makes the verb lawful.
///
/// v1 honest limitations (documented, never silent): block scalars
/// (`key: |`) are consumed as content (never mis-parsed as keys); plain
/// multi-line scalar continuations, quoted yaml keys, anchors/aliases and
/// multi-document (`---`) streams are not indexed; json keys with escape
/// sequences beyond the raw text and flow collections spanning lines are
/// not indexed. The parse oracle catches any splice the map missed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';
import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FileLockTable, FsToolsRoot;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;

import 'file_class_spec.dart' show fileClassOf;

// ---------------------------------------------------------------------------
// The map half — the ONE keypath parser (fs tier's map builder + this
/// emitter share it, so zoom anchors and splice anchors agree byte-precise)
// ---------------------------------------------------------------------------

/// One parsed keypath entry (pure data; line indexes + byte offsets into
/// the source). Mapping keys AND list items both land here (lists are
/// indexed — bracket paths); the fs tier's map emits mapping-key nodes,
/// the emitter resolves both.
class KeypathEntry {
  const KeypathEntry({
    required this.keypath,
    required this.indent,
    required this.lineIdx,
    required this.endLine,
    required this.start,
    required this.end,
    required this.isListItem,
    required this.hasInlineValue,
    required this.isBlockScalar,
  });

  /// Dot/bracket path, e.g. `deps.build`, `jobs[0].name`, `[2]`.
  final String keypath;

  /// Leading spaces of the entry's own line.
  final int indent;

  /// 0-based line of the key/dash.
  final int lineIdx;

  /// 0-based last line of the entry's block (inclusive).
  final int endLine;

  /// Byte offset of the block start (the key/dash line start).
  final int start;

  /// Byte offset of the block end (end of the last line's content — the
  /// trailing newline is NOT included).
  final int end;

  /// True for `- ` list items (bracket paths).
  final bool isListItem;

  /// True when the entry's line carries an inline scalar value
  /// (`key: value`) — replace_value requires this.
  final bool hasInlineValue;

  /// True when the value is a yaml block scalar indicator (`|`/`>`).
  final bool isBlockScalar;

  @override
  String toString() =>
      '$keypath (line ${lineIdx + 1}, indent $indent'
      '${isListItem ? ", item" : ""})';
}

final RegExp _yamlKeyRe = RegExp(r'^([ ]*)([A-Za-z_][\w.\-/ ]*?)\s*:(?:\s|$)');
final RegExp _yamlItemRe = RegExp(r'^([ ]*)-(?:\s+(.*))?$');
final RegExp _jsonKeyRe = RegExp(r'^([ ]*)"((?:[^"\\]|\\.)+)"\s*:');
final RegExp _blockScalarRe = RegExp(r'^[|>][+-]?\d*$');

class _YamlFrame {
  _YamlFrame(this.indent, this.path, {required this.isItem});
  final int indent;
  final String path;
  final bool isItem;
  int itemCount = 0;
}

class _JsonFrame {
  _JsonFrame(this.type, this.path);
  final String type; // object | array
  final String path;
  int itemCount = 0;
}

/// A json builder entry still awaiting its end line.
class _OpenEntry {
  _OpenEntry(this.entry, this.depth);
  final int indexPlaceholder; // unused, keeps analyzer quiet about lint
  final KeypathEntry entry;
  final int depth;
}

/// Parses [content] into keypath entries — the ONE parser shared by the
/// fs tier's map builder (zoom anchors) and this materializer's emitter
/// (splice anchors). Mapping keys AND list items (bracket-indexed).
List<KeypathEntry> parseKeypathTree(String content, {required bool isJson}) =>
    isJson ? _parseJsonKeypaths(content) : _parseYamlKeypaths(content);

List<int> _lineOffsets(List<String> lines) {
  final offsets = <int>[];
  var off = 0;
  for (final line in lines) {
    offsets.add(off);
    off += line.length + 1;
  }
  return offsets;
}

KeypathEntry _entry(
  String keypath,
  int indent,
  int lineIdx,
  int endLine,
  List<int> offsets,
  List<String> lines, {
  required bool isListItem,
  required bool hasInlineValue,
  required bool isBlockScalar,
}) =>
    KeypathEntry(
      keypath: keypath,
      indent: indent,
      lineIdx: lineIdx,
      endLine: endLine < lineIdx ? lineIdx : endLine,
      start: offsets[lineIdx],
      end: offsets[endLine < lineIdx ? lineIdx : endLine] +
          lines[endLine < lineIdx ? lineIdx : endLine].length,
      isListItem: isListItem,
      hasInlineValue: hasInlineValue,
      isBlockScalar: isBlockScalar,
    );

/// Closes [open] entries nested at or under the frame depth [fromDepth]
/// with end line [endLine] (exclusive-of-the-closer rule: the closer line
/// itself belongs to the parent).
void _finalize(
  List<_OpenEntry> open,
  int fromDepth,
  int endLine,
) {
  for (var i = open.length - 1; i >= 0; i--) {
    if (open[i].depth >= fromDepth) {
      final e = open.removeAt(i).entry;
      if (e.endLine < e.lineIdx) {
        // Mutate via a new entry (fields are final) — replace in place.
        e = e; // ignore: unnecessary_statements
      }
    }
  }
}

/// Parses pretty-printed JSON: object keys (nested via a frame stack) and
/// array elements (bracket-indexed). One key/element per line — the
/// canonical shape; flow collections spanning lines are not indexed.
List<KeypathEntry> _parseJsonKeypaths(String content) {
  final lines = content.split('\n');
  final offsets = _lineOffsets(lines);
  final entries = <KeypathEntry>[];
  final open = <_OpenEntry>[];
  final frames = <_JsonFrame>[];
  void finalizeAt(int endLine) {
    for (var i = open.length - 1; i >= 0; i--) {
      if (open[i].depth > frames.length) {
        final o = open.removeAt(i);
        entries[o.index0] = _entry(
          o.entry.keypath,
          o.entry.indent,
          o.entry.lineIdx,
          endLine < o.entry.lineIdx ? o.entry.lineIdx : endLine,
          offsets,
          lines,
          isListItem: o.entry.isListItem,
          hasInlineValue: o.entry.hasInlineValue,
          isBlockScalar: false,
        );
      }
    }
  }

  // A mutable working record per open entry (index into entries while the
  // end line is unknown: entries stored with endLine == lineIdx until
  // finalized — replaced wholesale on finalize).
  final pendingIdx = <int, int>{}; // unused
  // ignore: unused_local_variable
  final _ = pendingIdx;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    // 1) Closer-only (or closer-leading) lines pop frames.
    var work = trimmed;
    var popped = false;
    while (work.startsWith('}') || work.startsWith(']')) {
      if (frames.isNotEmpty) frames.removeLast();
      popped = true;
      work = work.substring(1);
      if (work.startsWith(',')) work = work.substring(1);
      work = work.trim();
    }
    if (popped) finalizeAt(i - 1 < 0 ? 0 : i - 1);
    if (work.isEmpty) continue;

    // 2) Key line?
    final km = _jsonKeyRe.firstMatch(line);
    if (km != null && !work.startsWith('}') && !work.startsWith(']')) {
      final parent = frames.isEmpty ? '' : frames.last.path;
      final key = km.group(2)!;
      final keypath = parent.isEmpty ? key : '$parent.$key';
      final depth = frames.length;
      final idx = entries.length;
      entries.add(_entry(
        keypath,
        km.group(1)!.length,
        i,
        i,
        offsets,
        lines,
        isListItem: false,
        hasInlineValue: true,
        isBlockScalar: false,
      ));
      open.add(_OpenEntry(entries[idx], depth));
      // Value part: does it open exactly one container?
      final valuePart = work.substring(work.indexOf(':') + 1).trim();
      final opener = _singleTrailingOpener(valuePart);
      if (opener != null) {
        frames.add(_JsonFrame(opener, keypath));
      } else if (valuePart.startsWith('{') || valuePart.startsWith('[')) {
        // inline (balanced) collection — leaf, no frame.
      }
      continue;
    }

    // 3) Element line under an array frame?
    if (frames.isNotEmpty && frames.last.type == 'array') {
      final parent = frames.last;
      final keypath = '${parent.path}[${parent.itemCount}]';
      parent.itemCount++;
      final depth = frames.length;
      final idx = entries.length;
      entries.add(_entry(
        keypath,
        line.length - line.trimLeft().length,
        i,
        i,
        offsets,
        lines,
        isListItem: true,
        hasInlineValue: true,
        isBlockScalar: false,
      ));
      open.add(_OpenEntry(entries[idx], depth));
      final opener = _singleTrailingOpener(trimmed);
      if (opener != null) frames.add(_JsonFrame(opener, keypath));
      continue;
    }
    // 4) Anything else under an object frame (raw opener lines, commas) —
    // not indexed (honest v1 limitation).
  }
  finalizeAt(lines.length - 1);
  return entries;
}

/// Returns '{' or '[' when [value] (a json value part) opens exactly one
/// unmatched container; null when balanced or ambiguous.
String? _singleTrailingOpener(String value) {
  var opens = 0;
  var kind = '';
  var inString = false;
  var escaped = false;
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
    } else if (c == '{' || c == '[') {
      opens++;
      kind = c;
    } else if (c == '}' || c == ']') {
      opens--;
    }
  }
  if (opens == 1) return kind;
  return null;
}

/// Parses YAML: mapping keys + `- ` list items (bracket-indexed), block
/// scalars consumed as content, comments/blank lines belong to blocks.
List<KeypathEntry> _parseYamlKeypaths(String content) {
  final lines = content.split('\n');
  final offsets = _lineOffsets(lines);
  final entries = <KeypathEntry>[];
  final frames = <_YamlFrame>[];
  int? skipBelowIndent; // inside a block scalar: consume deeper lines

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    if (skipBelowIndent != null) {
      if (trimmed.isEmpty || line.length - trimmed.length > skipBelowIndent) {
        continue;
      }
      skipBelowIndent = null;
    }
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    final im = _yamlItemRe.firstMatch(line);
    final km = im == null ? _yamlKeyRe.firstMatch(line) : null;
    if (km != null) {
      final indent = km.group(1)!.length;
      final key = km.group(2)!.trim();
      while (frames.isNotEmpty && frames.last.indent >= indent) {
        frames.removeLast();
      }
      final parent = frames.isEmpty ? '' : frames.last.path;
      final keypath = parent.isEmpty ? key : '$parent.$key';
      final rawValue = _rawValuePart(line, km);
      final commentIdx = _yamlCommentStart(rawValue);
      final valueOnly = (commentIdx >= 0 ? rawValue.substring(0, commentIdx) : rawValue)
          .trim();
      final isBlock = _blockScalarRe.hasMatch(valueOnly);
      if (isBlock) skipBelowIndent = indent;
      entries.add(_entry(
        keypath,
        indent,
        i,
        lines.length - 1,
        offsets,
        lines,
        isListItem: false,
        hasInlineValue: valueOnly.isNotEmpty && !isBlock,
        isBlockScalar: isBlock,
      ));
      frames.add(_YamlFrame(indent, keypath, isItem: false));
      continue;
    }
    if (im != null) {
      final indent = im.group(1)!.length;
      final content_ = im.group(2);
      while (frames.isNotEmpty &&
          (frames.last.indent > indent ||
              (frames.last.isItem && frames.last.indent == indent))) {
        frames.removeLast();
      }
      if (frames.isEmpty) continue; // parentless top-level item: not indexed
      final parent = frames.last;
      final keypath = '${parent.path}[${parent.itemCount}]';
      parent.itemCount++;
      entries.add(_entry(
        keypath,
        indent,
        i,
        lines.length - 1,
        offsets,
        lines,
        isListItem: true,
        hasInlineValue: content_ != null && content_.trim().isNotEmpty,
        isBlockScalar: false,
      ));
      frames.add(_YamlFrame(indent, keypath, isItem: true));
      continue;
    }
    // Continuation lines / plain scalars — content, not entries.
  }

  // Close every block at the last line (the trailing split '' is the final
  // newline — same convention the old fs map used).
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (e.endLine < lines.length - 1) continue;
    // default endLine was lines.length-1 — tighten to the next closing
    // entry (none left) or keep. Compute per-entry: already default.
  }
  // Tighten blocks: entry ends before the next entry that closes it.
  for (var i = 0; i < entries.length; i++) {
    final a = entries[i];
    var endLine = lines.length - 1;
    for (var j = i + 1; j < entries.length; j++) {
      final b = entries[j];
      final closes = b.isListItem
          ? (b.indent < a.indent || (b.indent == a.indent && a.isListItem))
          : (b.indent <= a.indent);
      if (closes) {
        endLine = b.lineIdx - 1;
        break;
      }
    }
    entries[i] = _entry(
      a.keypath,
      a.indent,
      a.lineIdx,
      endLine < a.lineIdx ? a.lineIdx : endLine,
      offsets,
      lines,
      isListItem: a.isListItem,
      hasInlineValue: a.hasInlineValue,
      isBlockScalar: a.isBlockScalar,
    );
  }
  return entries;
}

/// The raw value part of a yaml key line (everything after the key's
/// colon, per the regex match).
String _rawValuePart(String line, RegExpMatch km) {
  final keyEnd = km.group(2)!.length + km.group(1)!.length;
  final colon = line.indexOf(':', keyEnd);
  return colon < 0 ? '' : line.substring(colon + 1);
}

/// Index of the yaml comment start in [value] (a `#` at value start or
/// preceded by whitespace, outside quotes); -1 when none.
int _yamlCommentStart(String value) {
  var quote = '';
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (quote.isNotEmpty) {
      if (quote == '"' && c == r'\') {
        i++; // skip escaped char
      } else if (c == quote) {
        quote = '';
      }
      continue;
    }
    if (c == '\'' || c == '"') {
      quote = c;
    } else if (c == '#' && (i == 0 || value[i - 1] == ' ' || value[i - 1] == '\t')) {
      return i;
    }
  }
  return -1;
}

// ---------------------------------------------------------------------------
// The oracle — parse (REAL parsers) + intended-change semantic diff
// ---------------------------------------------------------------------------

/// One semantic change between the before/after parse trees: named kind +
/// the dot/bracket path + the values (evidence for the repair move).
class SemanticChange {
  const SemanticChange(this.kind, this.path, this.before, this.after);
  final String kind; // added | removed | changed
  final String path;
  final Object? before;
  final Object? after;

  @override
  String toString() => '$kind $path'
      '${kind == "added" ? " = ${_short(after)}" : kind == "removed" ? " (was ${_short(before)})" : ": ${_short(before)} → ${_short(after)}"}';
}

String _short(Object? v) {
  final s = '${v is Map || v is List ? (v is Map ? "{…${v.length}}" : "[…${v.length}]") : v}';
  return s.length > 40 ? '${s.substring(0, 40)}…' : s;
}

bool _deepEq(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_deepEq(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEq(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// The named oracle's diff half: leaf-level semantic diff of the before /
/// after parse trees. added/removed record the WHOLE divergent subtree as
/// one change (the topmost divergence is what "exactly the intended
/// change" is checked against).
List<SemanticChange> semanticDiff(Object? before, Object? after,
        [String path = '']) =>
    _diff(before, after, path);

List<SemanticChange> _diff(Object? a, Object? b, String path) {
  final out = <SemanticChange>[];
  if (a is Map && b is Map) {
    final keys = <String>{
      for (final k in a.keys) '$k',
      for (final k in b.keys) '$k',
    }.toList()..sort();
    for (final k in keys) {
      final child = path.isEmpty ? k : '$path.$k';
      final av = a[k];
      final bv = b[k];
      if (a.containsKey(k) && !b.containsKey(k)) {
        out.add(SemanticChange('removed', child, av, null));
      } else if (!a.containsKey(k) && b.containsKey(k)) {
        out.add(SemanticChange('added', child, null, bv));
      } else {
        out.addAll(_diff(av, bv, child));
      }
    }
    return out;
  }
  if (a is List && b is List) {
    final minLen = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < minLen; i++) {
      out.addAll(_diff(a[i], b[i], '$path[$i]'));
    }
    for (var i = minLen; i < b.length; i++) {
      out.add(SemanticChange('added', '$path[$i]', null, b[i]));
    }
    for (var i = minLen; i < a.length; i++) {
      out.add(SemanticChange('removed', '$path[$i]', a[i], null));
    }
    return out;
  }
  if (!_deepEq(a, b)) out.add(SemanticChange('changed', path, a, b));
  return out;
}

/// Parses [content] with the REAL parser (package:yaml / jsonDecode) into
/// plain Dart structures. Throws on parse failure (the caller classifies).
Object? keypathParse(String content, {required bool isJson}) {
  if (isJson) return jsonDecode(content);
  final node = loadYaml(content);
  return _plain(node);
}

Object? _plain(Object? node) {
  if (node is YamlMap) {
    return {
      for (final k in node.keys) '$k': _plain(node[k]),
    };
  }
  if (node is YamlList) {
    return [for (final v in node) _plain(v)];
  }
  return node;
}

// ---------------------------------------------------------------------------
// The materializer — plan (mechanical anchor resolution + splice + byte
/// fence) / apply (atomic write + parse + semantic diff + auto-revert)
// ---------------------------------------------------------------------------

/// Mechanical bounce BEFORE any byte is touched: error + the exact repair
/// move + navigable hints (B2 dialect, named failure class).
class KeypathEditBounce implements Exception {
  KeypathEditBounce(this.error, this.repair, this.failureClass,
      {this.hints = const []});
  final String error;
  final String repair;
  final String failureClass;
  final List<String> hints;

  Map<String, dynamic> toJson() => {
        'ok': false,
        'bounce': true,
        'error': error,
        'repair': repair,
        'failureClass': failureClass,
        if (hints.isNotEmpty) 'hints': hints,
      };

  @override
  String toString() => '[$failureClass] $error — $repair';
}

/// A validated keypath edit: the host resolved the anchor, spliced the
/// bytes, fenced the untouched lines, and the result is ready to write +
/// oracle-check.
class KeypathEditPlan {
  const KeypathEditPlan({
    required this.path,
    required this.op,
    required this.isJson,
    required this.anchorKeypath,
    required this.body,
    required this.target,
    required this.content,
    required this.keepStart,
    required this.keepEnd,
    required this.description,
  });
  final String path; // workspace-relative
  final String op; // set_key | replace_value | delete_key | append_list_item
  final bool isJson;
  final String anchorKeypath;

  /// The body-as-data (the scalar/fragment the model supplied).
  final String body;

  /// The resolved target entry (null only for set_key creation).
  final KeypathEntry? target;

  /// The FULL post-splice file content (host-computed, byte-precise).
  final String content;

  /// The BYTE FENCE: bytes before [keepStart] and from [keepEnd] on are
  /// identical in original and content — only the target keypath's span
  /// was touched (asserted at plan time).
  final int keepStart;
  final int keepEnd;
  final String description;
}

/// The outcome of a keypath edit. Failures are classified data — never
/// dropped.
class KeypathEditOutcome {
  const KeypathEditOutcome({
    required this.ok,
    required this.reverted,
    required this.detail,
    this.bounce = false,
    this.failureClass = '',
    this.op = '',
    this.path = '',
    this.anchor = '',
    this.repair,
    this.hints = const [],
    this.changes = const [],
  });
  final bool ok;

  /// True when bytes were written and then restored (the oracle failed).
  final bool reverted;

  /// True when the move was a mechanical PRE-apply bounce (nothing ran).
  final bool bounce;
  final String detail;
  final String failureClass;
  final String op;
  final String path;
  final String anchor;
  final String? repair;
  final List<String> hints;
  final List<SemanticChange> changes;

  bool get appliedClean => ok && !reverted;

  Map<String, dynamic> toJson() => {
        'ok': ok,
        'reverted': reverted,
        if (bounce) 'bounce': true,
        'op': op,
        'path': path,
        if (anchor.isNotEmpty) 'anchor': anchor,
        'detail': detail,
        if (failureClass.isNotEmpty) 'failureClass': failureClass,
        if (repair != null) 'repair': repair,
        if (hints.isNotEmpty) 'hints': hints,
        if (changes.isNotEmpty)
          'changes': [for (final c in changes) c.toString()],
      };
}

/// The yaml/json materializer: plan (pure validation + splice + byte
/// fence, never touches bytes) + apply (atomic write → parse_semantic_diff
/// oracle → auto-revert on any violation, with failure attribution).
/// Single-writer via the shared [FileLockTable] (the same table the span
/// editor and the md materializer claim).
class KeypathMaterializer {
  KeypathMaterializer({
    required this.root,
    FileLockTable? locks,
    this.owner = 'keypath_materializer',
  }) : locks = locks ?? FileLockTable();

  final FsToolsRoot root;
  final FileLockTable locks;
  final Object owner;

  /// The body budget (body-as-data, budgeted): a single move past this
  /// bound bounces with the split-it repair move.
  static const maxKeyBodyChars = 10000;

  static const ops = <String>{
    'set_key',
    'replace_value',
    'delete_key',
    'append_list_item',
  };

  KeypathEditPlan plan({
    required String? path,
    required String? op,
    required String? anchor,
    required String? body,
  }) {
    if (path == null || path.isEmpty) {
      throw KeypathEditBounce(
        'missing path',
        're-send with path as a workspace-relative yaml/json path (the id '
            'from meaning_zoom, e.g. "pubspec.yaml")',
        'invalid_path',
      );
    }
    final String abs;
    try {
      abs = root.resolve(path);
      // ignore: avoid_catching_errors
    } on ArgumentError catch (e) {
      throw KeypathEditBounce(
        'path escapes the workspace jail: $path',
        'use a workspace-relative path (no .., no absolute) — zoom the '
            'file node for the canonical rel',
        'path_escapes_workspace',
        hints: ['$e'],
      );
    }
    final fc = fileClassOf(path);
    if (fc != 'yaml' && fc != 'json') {
      throw KeypathEditBounce(
        '$path is class "$fc" — edit_key edits yaml/json only',
        'dart moves through edit_symbol; md through edit_section; this '
            'class has no materializer verb yet — its edits route through '
            'the review gate (write_review) until a spec lands',
        'not_keypath_class',
      );
    }
    final isJson = fc == 'json';
    final f = File(abs);
    if (!f.existsSync()) {
      throw KeypathEditBounce(
        'file not found: $path',
        'zoom the tree (meaning_zoom) for existing files; a NEW file lands '
            'through the host materializer bootstrap, never a guessed path',
        'file_not_found',
      );
    }
    if (op == null || !ops.contains(op)) {
      throw KeypathEditBounce(
        'unknown op: $op',
        're-send with op as one of: ${ops.toList()..sort()}',
        'unknown_op',
      );
    }
    if (body == null) {
      throw KeypathEditBounce(
        'missing body',
        're-send with body as the scalar/fragment (data) — set_key may '
            'pass an empty string to set a null value; delete_key ignores '
            'it but must still carry an empty string',
        'invalid_body',
      );
    }
    if (body.length > maxKeyBodyChars) {
      throw KeypathEditBounce(
        'body over budget: ${body.length} chars (max $maxKeyBodyChars)',
        'split the edit into multiple keypath moves (one anchor per '
            'move) — the budget is per move, the file is not',
        'body_over_budget',
      );
    }
    final multiline = body.contains('\n');
    if (multiline && (op == 'replace_value' || op == 'append_list_item')) {
      throw KeypathEditBounce(
        '$op takes a single-line scalar body; a ${body.split('\n').length}-'
            'line fragment was supplied',
        op == 'replace_value'
            ? 'replace_value swaps ONE inline value — use set_key with the '
                'multi-line fragment (including the key line) to replace a '
                'whole subtree'
            : 'append_list_item appends ONE scalar item — use set_key with '
                'the fragment to restructure the container',
        'invalid_body',
      );
    }
    if (!multiline && op == 'replace_value' && body.trim().isEmpty) {
      throw KeypathEditBounce(
        'empty body for replace_value',
        'replace_value swaps in a value; use delete_key to remove the key '
            'or set_key with an empty body to set null',
        'invalid_body',
      );
    }

    final content = f.readAsStringSync();
    final entries = parseKeypathTree(content, isJson: isJson);
    final fileNodeId = 'f_${path.replaceAll('/', '_')}';

    // Mechanical anchor resolution: fresh parse of the CURRENT bytes.
    if (anchor == null || anchor.isEmpty) {
      throw KeypathEditBounce(
        'missing anchor (the keypath to edit)',
        're-send with anchor as a dot/bracket keypath of THIS file — zoom '
            'the file node ($fileNodeId) for the keypath outline, then '
            'retry',
        'keypath_not_found',
        hints: _outlineHints(entries),
      );
    }
    KeypathEntry? target;
    if (anchor.startsWith('key_')) {
      final prefix = 'key_${fileNodeId}_';
      if (!anchor.startsWith(prefix)) {
        throw KeypathEditBounce(
          'keypath id "$anchor" belongs to another file',
          're-send the node id from THIS file\'s meaning_zoom outline (or '
              'the bare keypath)',
          'keypath_not_found',
          hints: _outlineHints(entries),
        );
      }
      final slug = anchor.substring(prefix.length);
      final hits =
          entries.where((e) => _slug(e.keypath) == slug).toList();
      if (hits.isEmpty) {
        throw KeypathEditBounce(
          'keypath id "$anchor" does not resolve in the current bytes of '
              '$path (the file changed since the tree was built?)',
          'refresh the tree (repo_etl refresh), re-zoom, then re-send the '
              'anchor as the fresh node id or the bare keypath',
          'keypath_not_found',
          hints: _outlineHints(entries),
        );
      }
      if (hits.length > 1) {
        throw KeypathEditBounce(
          'ambiguous keypath id "$anchor": the slug matches '
              '${hits.length} entries in $path',
          're-send the anchor as the exact dot/bracket keypath of the '
              'entry you mean (candidates below)',
          'ambiguous_keypath',
          hints: [for (final h in hits) _candidate(h)],
        );
      }
      target = hits.single;
    } else {
      final hits = entries.where((e) => e.keypath == anchor).toList();
      if (hits.length > 1) {
        throw KeypathEditBounce(
          'ambiguous keypath "$anchor": ${hits.length} entries share it in '
              '$path (duplicate keys?)',
          're-send anchor as the keypath NODE ID from meaning_zoom (one '
              'of the candidates below); duplicate keys are a data smell '
              'the parse oracle refuses',
          'ambiguous_keypath',
          hints: [for (final h in hits) _candidate(h)],
        );
      }
      if (hits.length == 1) target = hits.single;
    }

    final lines = content.split('\n');
    final offsets = _lineOffsets(lines);

    switch (op) {
      case 'replace_value':
        return _planReplaceValue(
            path, isJson, anchor, body, target, entries, lines, offsets);
      case 'set_key':
        return _planSetKey(
            path, isJson, anchor, body, target, entries, lines, offsets);
      case 'delete_key':
        return _planDeleteKey(
            path, isJson, anchor, body, target, lines, offsets);
      case 'append_list_item':
        return _planAppendItem(
            path, isJson, anchor, body, target, entries, lines, offsets);
      default:
        throw KeypathEditBounce(
            'unknown op: $op', 'host bug — report as data', 'unknown_op');
    }
  }

  String _slug(String keypath) => keypath.replaceAll(RegExp(r'[^\w]'), '_');

  String _candidate(KeypathEntry e) => '${_slug(e.keypath)} — ${e.keypath}'
      ' (line ${e.lineIdx + 1})';

  List<String> _outlineHints(List<KeypathEntry> entries) => [
        for (final e in entries.take(12))
          'key path "${e.keypath}" (line ${e.lineIdx + 1})',
        if (entries.isEmpty)
          'this file has no indexed keypaths — the map needs `key: value` '
              'lines (v1)',
        if (entries.length > 12)
          '…${entries.length - 12} more — zoom the file node for the full '
              'outline',
      ];

  // -- op emitters -----------------------------------------------------------

  KeypathEditPlan _planReplaceValue(
    String path,
    bool isJson,
    String anchor,
    String body,
    KeypathEntry? target,
    List<KeypathEntry> entries,
    List<String> lines,
    List<int> offsets,
  ) {
    if (target == null) {
      throw KeypathEditBounce(
        'keypath not found: no entry "$anchor" in $path',
        're-send with anchor as a keypath of THIS file — zoom the file '
            'node for the outline, then retry',
        'keypath_not_found',
        hints: _outlineHints(entries),
      );
    }
    if (target.isListItem) {
      throw KeypathEditBounce(
        '"$anchor" is a list item — list items are values, not keyed '
            'slots',
        'use set_key on the item path with the new value as the fragment',
        'keypath_is_list_item',
        hints: [_candidate(target)],
      );
    }
    if (target.isBlockScalar) {
      throw KeypathEditBounce(
        '"$anchor" holds a block scalar (| or >) — there is no inline '
            'value to swap',
        'use set_key with the full fragment (including the key line) to '
            'replace the whole subtree',
        'keypath_is_block_scalar',
        hints: [_candidate(target)],
      );
    }
    if (!target.hasInlineValue) {
      throw KeypathEditBounce(
        '"$anchor" has no inline value (nested block or comment-only)',
        'use set_key to replace the whole subtree, or delete_key to '
            'remove it',
        'keypath_has_nested_block',
        hints: [_candidate(target)],
      );
    }
    final line = lines[target.lineIdx];
    final valueStart = _valueStartOffset(line, isJson);
    var newLine = line.substring(0, valueStart);
    if (isJson) {
      final trailing = line.trim().endsWith(',');
      newLine += _jsonValueLiteral(body);
      if (trailing) newLine += ',';
    } else {
      // yaml: preserve an inline `# comment` after the value — replace_value
      // swaps the VALUE, never the comment.
      final valuePart = line.substring(valueStart);
      final commentIdx = _yamlCommentStart(valuePart);
      if (commentIdx >= 0) {
        newLine += '${body.trimRight()} ${valuePart.substring(commentIdx)}';
      } else {
        newLine += body;
      }
    }
    final spliced = content_replaceLine(lines, offsets, target.lineIdx, newLine);
    final keepStart = offsets[target.lineIdx] + valueStart;
    final keepEnd = target.lineIdx + 1 < lines.length
        ? offsets[target.lineIdx + 1]
        : content_keepEndOfFile(lines, offsets);
    _assertUntouched(path, content_of(lines), spliced, keepStart, keepEnd);
    return KeypathEditPlan(
      path: path,
      op: 'replace_value',
      isJson: isJson,
      anchorKeypath: anchor,
      body: body,
      target: target,
      content: spliced,
      keepStart: keepStart,
      keepEnd: keepEnd,
      description: 'replace_value $anchor (line ${target.lineIdx + 1}) in '
          '$path',
    );
  }

  KeypathEditPlan _planSetKey(
    String path,
    bool isJson,
    String anchor,
    String body,
    KeypathEntry? target,
    List<KeypathEntry> entries,
    List<String> lines,
    List<int> offsets,
  ) {
    final multiline = body.contains('\n');
    if (target != null) {
      // UPDATE: replace the whole block with the rendered lines.
      final indent = ' ' * target.indent;
      final key = _lastSegment(anchor);
      String rendered;
      if (multiline) {
        // The fragment is DATA — spliced verbatim (the model composed it
        // from the zoomed span; the parse oracle proves the shape).
        rendered = body;
      } else if (isJson) {
        final trailing = lines[target.lineIdx].trim().endsWith(',');
        rendered = '$indent"${_jsonKeyText(key)}": ${_jsonValueLiteral(body)}'
            '${trailing ? "," : ""}';
      } else {
        rendered = '$indent$key: $body';
      }
      final keepStart = offsets[target.lineIdx];
      final keepEnd = target.endLine + 1 < lines.length
          ? offsets[target.endLine + 1]
          : content_keepEndOfFile(lines, offsets);
      var spliced = content_replaceRange(
          lines, offsets, target.lineIdx, target.endLine, rendered);
      // json comma fix-up: a property following the block needs the comma.
      if (isJson && !multiline && !rendered.trimEnd().endsWith(',')) {
        final next = target.endLine + 1 < lines.length
            ? lines[target.endLine + 1].trim()
            : '';
        final needsComma = _jsonKeyRe.firstMatch(next) != null ||
            next.startsWith('}') ||
            next.startsWith(']');
        if (needsComma) {
          spliced = content_replaceLine(
              _splitOf(spliced), _lineOffsets(_splitOf(spliced)),
              target.lineIdx, '${rendered.trimEnd()},');
        }
      }
      _assertUntouched(path, content_of(lines), spliced, keepStart, keepEnd);
      return KeypathEditPlan(
        path: path,
        op: 'set_key',
        isJson: isJson,
        anchorKeypath: anchor,
        body: body,
        target: target,
        content: spliced,
        keepStart: keepStart,
        keepEnd: keepEnd,
        description: 'set_key $anchor (line ${target.lineIdx + 1}) in $path',
      );
    }
    // CREATE: the parent (anchor minus its last segment) must resolve.
    final parentPath = _parentPath(anchor);
    KeypathEntry? parent;
    if (parentPath.isNotEmpty) {
      final hits = entries.where((e) => e.keypath == parentPath).toList();
      if (hits.length > 1) {
        throw KeypathEditBounce(
          'ambiguous parent keypath "$parentPath": ${hits.length} entries '
              'share it in $path',
          're-send anchor as the keypath NODE ID from meaning_zoom of the '
              'parent, then set the child (candidates below)',
          'ambiguous_keypath',
          hints: [for (final h in hits) _candidate(h)],
        );
      }
      if (hits.isEmpty) {
        throw KeypathEditBounce(
          'parent keypath not found: "$parentPath" (from anchor "$anchor") '
              'does not resolve in $path',
          'create the parent first (one set_key per level), or zoom the '
              'file node for the existing outline',
          'keypath_not_found',
          hints: _outlineHints(entries),
        );
      }
      parent = hits.single;
      if (parent.isBlockScalar) {
        throw KeypathEditBounce(
          'parent "$parentPath" holds a block scalar (| or >) — children '
              'cannot nest inside scalar content',
          'set the parent to a mapping first (set_key with the full '
              'fragment), then add the child',
          'parent_is_block_scalar',
          hints: [_candidate(parent)],
        );
      }
      if (parent.hasInlineValue && !parent.isListItem) {
        throw KeypathEditBounce(
          'parent "$parentPath" holds an inline scalar value — a child '
              'cannot nest under a scalar',
          'set_key the parent to a mapping/fragment first, or replace its '
              'value',
          'parent_not_a_container',
          hints: [_candidate(parent)],
        );
      }
    }
    final host = parent; // null → top-level creation (end of file)
    final insertLine = host == null
        ? lines.length - 1 < 0
            ? 0
            : _lastContentLine(lines) + 1
        : host.endLine + 1;
    final baseIndent = host == null ? 0 : host.indent + 2;
    final key = _lastSegment(anchor);
    final indentStr = ' ' * baseIndent;
    String rendered;
    if (multiline) {
      rendered = body.endsWith('\n') ? body.substring(0, body.length - 1) : body;
    } else if (isJson) {
      rendered =
          '$indentStr"${_jsonKeyText(key)}": ${_jsonValueLiteral(body)}';
    } else {
      rendered = body.isEmpty ? '$indentStr$key:' : '$indentStr$key: $body';
    }
    final keepStart = insertLine < offsets.length ? offsets[insertLine] : _eof(content_of(lines));
    final keepEnd = keepStart;
    final spliced = content_insertLine(lines, offsets, insertLine, rendered);
    _assertUntouched(path, content_of(lines), spliced, keepStart, keepEnd);
    return KeypathEditPlan(
      path: path,
      op: 'set_key',
      isJson: isJson,
      anchorKeypath: anchor,
      body: body,
      target: parent,
      content: spliced,
      keepStart: keepStart,
      keepEnd: keepEnd,
      description:
          'set_key $anchor (new, under ${parentPath.isEmpty ? "<root>" : parentPath}) in $path',
    );
  }

  KeypathEditPlan _planDeleteKey(
    String path,
    bool isJson,
    String anchor,
    String body,
    KeypathEntry? target,
    List<String> lines,
    List<int> offsets,
  ) {
    if (target == null) {
      throw KeypathEditBounce(
        'keypath not found: no entry "$anchor" to delete in $path (zoom '
            'the file node for the outline)',
        're-send with anchor as an existing keypath — delete_key removes '
            'the key and its whole block',
        'keypath_not_found',
      );
    }
    final keepStart = offsets[target.lineIdx];
    final keepEnd = target.endLine + 1 < lines.length
        ? offsets[target.endLine + 1]
        : content_keepEndOfFile(lines, offsets);
    final spliced =
        content_deleteRange(lines, offsets, target.lineIdx, target.endLine);
    _assertUntouched(path, content_of(lines), spliced, keepStart, keepEnd);
    return KeypathEditPlan(
      path: path,
      op: 'delete_key',
      isJson: isJson,
      anchorKeypath: anchor,
      body: body,
      target: target,
      content: spliced,
      keepStart: keepStart,
      keepEnd: keepEnd,
      description:
          'delete_key $anchor (lines ${target.lineIdx + 1}-'
          '${target.endLine + 1}) in $path',
    );
  }

  KeypathEditPlan _planAppendItem(
    String path,
    bool isJson,
    String anchor,
    String body,
    KeypathEntry? target,
    List<KeypathEntry> entries,
    List<String> lines,
    List<int> offsets,
  ) {
    if (target == null) {
      throw KeypathEditBounce(
        'keypath not found: no list "$anchor" in $path',
        're-send with anchor as an existing keypath — append_list_item '
            'adds one scalar item to the list it holds',
        'keypath_not_found',
        hints: _outlineHints(entries),
      );
    }
    if (target.isListItem) {
      throw KeypathEditBounce(
        '"$anchor" is itself a list item — append to the LIST key, not '
            'an item',
        're-send anchor as the list\'s keypath (e.g. "${_parentPath(anchor)}")',
        'keypath_is_list_item',
        hints: [_candidate(target)],
      );
    }
    final item = body.startsWith('- ') ? body.substring(2) : body;
    // Find the list style: the first `- ` line in the block sets the item
    // indent; otherwise the item nests under the key (indent + 2).
    var itemIndent = target.indent + 2;
    for (var i = target.lineIdx + 1; i <= target.endLine && i < lines.length; i++) {
      final m = RegExp(r'^(\s*)-\s').firstMatch(lines[i]);
      if (m != null) {
        itemIndent = m.group(1)!.length;
        break;
      }
    }
    final insertLine = target.endLine + 1;
    final blockHasItems = insertLine > target.lineIdx + 1;
    final keepStart = blockHasItems || target.hasInlineValue
        ? (target.endLine < lines.length ? offsets[target.endLine] : _eof(content_of(lines)))
        : (insertLine < offsets.length ? offsets[insertLine] : _eof(content_of(lines)));
    final keepEnd = keepStart;
    String rendered;
    if (isJson) {
      // json: the element must land INSIDE the array — before its closer.
      var closerLine = -1;
      for (var i = target.lineIdx + 1; i <= target.endLine && i < lines.length; i++) {
        final t = lines[i].trim();
        if (t.startsWith(']')) {
          closerLine = i;
          break;
        }
      }
      if (closerLine < 0) {
        throw KeypathEditBounce(
          '"$anchor" has no multi-line array to append to',
          'use set_key to set the whole array value in one line, or '
              'reformat it multi-line first (one element per line)',
          'unsupported_inline_container',
          hints: [_candidate(target)],
        );
      }
      final elemIndent = itemIndent;
      var fixed = List<String>.of(lines);
      // The previous last element needs a trailing comma.
      for (var i = closerLine - 1; i > target.lineIdx; i--) {
        final t = fixed[i].trim();
        if (t.isEmpty) continue;
        if (!t.endsWith(',') && !t.endsWith('[')) {
          fixed[i] = '${fixed[i].trimRight()},';
        }
        break;
      }
      fixed.insert(closerLine, '${' ' * elemIndent}${_jsonValueLiteral(item)}');
      final spliced = fixed.join('\n');
      _assertUntouched(path, content_of(lines), spliced,
          _offsetAfterCommaFix(lines, offsets, closerLine), _eof(content_of(lines)));
      return KeypathEditPlan(
        path: path,
        op: 'append_list_item',
        isJson: isJson,
        anchorKeypath: anchor,
        body: body,
        target: target,
        content: spliced,
        keepStart: _offsetAfterCommaFix(lines, offsets, closerLine),
        keepEnd: _eof(content_of(lines)),
        description:
            'append_list_item $anchor (element ${_lastSegment(anchor)}'
            '[?], line ${closerLine + 1}) in $path',
      );
    }
    rendered = '${' ' * itemIndent}- $item';
    final spliced = content_insertLine(lines, offsets, insertLine, rendered);
    _assertUntouched(path, content_of(lines), spliced, keepStart, keepEnd);
    return KeypathEditPlan(
      path: path,
      op: 'append_list_item',
      isJson: isJson,
      anchorKeypath: anchor,
      body: body,
      target: target,
      content: spliced,
      keepStart: keepStart,
      keepEnd: keepEnd,
      description:
          'append_list_item $anchor (item at line ${insertLine + 1}) in '
          '$path',
    );
  }

  int _offsetAfterCommaFix(
      List<String> lines, List<int> offsets, int closerLine) {
    // The comma fix touches the last element line BEFORE the closer; keep
    // bytes from that line's start — conservative fence.
    for (var i = closerLine - 1; i > 0; i--) {
      final t = lines[i].trim();
      if (t.isEmpty) continue;
      return offsets[i];
    }
    return closerLine > 0 ? offsets[closerLine] : 0;
  }

  /// The BYTE FENCE: everything before [keepStart] and from [keepEnd] on
  /// must be byte-identical between original and spliced — the splice may
  /// only ever touch the target keypath's span (comments, siblings and
  /// blank lines stay byte-identical; mechanically asserted at plan time).
  void _assertUntouched(
      String path, String original, String spliced, int keepStart, int keepEnd) {
    final origSuffix = original.length >= keepEnd
        ? original.substring(keepEnd.clamp(0, original.length))
        : '';
    final splSuffix = spliced.length >= keepEnd
        ? spliced.substring(
            spliced.length - origSuffix.length.clamp(0, spliced.length))
        : '';
    if (original.substring(0, keepStart.clamp(0, original.length)) !=
            spliced.substring(0, keepStart.clamp(0, spliced.length)) ||
        origSuffix != splSuffix) {
      throw KeypathEditBounce(
        'the emitter touched bytes outside the target keypath span in '
            '$path (byte fence violated)',
        'host bug — report as data: the keypath_splice emitter must edit '
            'ONLY the target span',
        'emitter_violation',
      );
    }
  }

  // -- apply: atomic write + parse_semantic_diff + auto-revert ---------------

  KeypathEditOutcome apply(KeypathEditPlan plan) {
    final rel = plan.path;
    if (!locks.claim(rel, owner)) {
      final holder = locks.ownerOf(rel);
      return KeypathEditOutcome(
        ok: false,
        reverted: false,
        op: plan.op,
        path: rel,
        anchor: plan.anchorKeypath,
        detail: 'lock conflict on $rel (held by $holder) — the move '
            'claimed no bytes',
        failureClass: 'lock_conflict',
      );
    }
    try {
      final abs = root.resolve(rel);
      final f = File(abs);
      final original = f.readAsStringSync();
      Object? before;
      try {
        before = keypathParse(original, isJson: plan.isJson);
      } on Object catch (e) {
        return KeypathEditOutcome(
          ok: false,
          reverted: false,
          op: plan.op,
          path: rel,
          anchor: plan.anchorKeypath,
          detail:
              'the CURRENT file does not parse (${plan.isJson ? "jsonDecode" : "yaml"}: '
              '${_oneLine(e)}) — the parse oracle refuses to edit a file '
              'it cannot verify',
          failureClass: 'parse_failed',
        );
      }
      f.writeAsStringSync(plan.content, flush: true);
      Object? after;
      try {
        after = keypathParse(plan.content, isJson: plan.isJson);
      } on Object catch (e) {
        // AUTO-REVERT: an unparseable result never lands.
        f.writeAsStringSync(original, flush: true);
        return KeypathEditOutcome(
          ok: false,
          reverted: true,
          op: plan.op,
          path: rel,
          anchor: plan.anchorKeypath,
          detail: 'parse_semantic_diff FAILED after ${plan.description}: '
              'the spliced file does not parse '
              '(${plan.isJson ? "jsonDecode" : "yaml"}: ${_oneLine(e)}) — '
              'ALL bytes reverted',
          failureClass: 'parse_failed',
          hints: const [
            'check the fragment\'s indentation/quoting against the '
                'siblings you zoomed, then re-send the move',
          ],
        );
      }
      // THE NAMED ORACLE — the semantic diff must be EXACTLY the intended
      // change: nothing more, nothing elsewhere.
      final changes = semanticDiff(before, after);
      final violation = _envelopeViolation(plan, before, after, changes);
      if (violation != null) {
        f.writeAsStringSync(original, flush: true);
        return KeypathEditOutcome(
          ok: false,
          reverted: true,
          op: plan.op,
          path: rel,
          anchor: plan.anchorKeypath,
          detail: 'parse_semantic_diff FAILED after ${plan.description}: '
              '$violation — ALL bytes reverted',
          failureClass: 'semantic_diff_mismatch',
          hints: const [
            'the only allowed change is the intended one at the anchor — '
                'check the body and re-send the move',
          ],
          changes: changes,
        );
      }
      return KeypathEditOutcome(
        ok: true,
        reverted: false,
        op: plan.op,
        path: rel,
        anchor: plan.anchorKeypath,
        detail: '${plan.description} — spliced byte-precise '
            '(${original.length} → ${plan.content.length} bytes); '
            'parse_semantic_diff green (exactly the intended change). The '
            'tree re-derives the keypath map on the next tick.',
      );
    } finally {
      locks.release(rel, owner);
    }
  }

  /// The envelope each op's diff must satisfy — null when green.
  String? _envelopeViolation(
    KeypathEditPlan plan,
    Object? before,
    Object? after,
    List<SemanticChange> changes,
  ) {
    final target = plan.anchorKeypath;
    bool within(String p) =>
        p == target || p.startsWith('$target.') || p.startsWith('$target[');
    switch (plan.op) {
      case 'replace_value':
      case 'set_key' when plan.target != null && !plan.body.contains('\n'):
        if (changes.length != 1) {
          return 'expected exactly 1 change, got ${changes.length}: '
              '${changes.take(5)}';
        }
        final c = changes.single;
        if (c.kind != 'changed' || c.path != target) {
          return 'expected one changed at "$target", got ${c.kind} at '
                  '"${c.path}"';
        }
        return null;
      case 'set_key' when plan.body.contains('\n'):
        if (changes.isEmpty) return 'the fragment changed nothing';
        for (final c in changes) {
          if (!within(c.path)) {
            return 'change outside the target subtree: ${c.kind} '
                    '"${c.path}"';
          }
        }
        return null;
      case 'set_key':
        if (changes.length != 1) {
          return 'expected exactly 1 change (the new key), got '
                  '${changes.length}: ${changes.take(5)}';
        }
        final c = changes.single;
        if (c.kind != 'added' || c.path != target) {
          return 'expected one added at "$target", got ${c.kind} at '
                  '"${c.path}"';
        }
        return null;
      case 'delete_key':
        if (changes.length != 1) {
          return 'expected exactly 1 change (the removal), got '
                  '${changes.length}: ${changes.take(5)}';
        }
        final c = changes.single;
        if (c.kind != 'removed' || c.path != target) {
          return 'expected one removed at "$target", got ${c.kind} at '
                  '"${c.path}"';
        }
        return null;
      case 'append_list_item':
        if (changes.length != 1) {
          return 'expected exactly 1 change (the new item), got '
                  '${changes.length}: ${changes.take(5)}';
        }
        final c = changes.single;
        if (c.path != target) {
          return 'expected the change at "$target", got ${c.kind} at '
                  '"${c.path}"';
        }
        if (c.kind != 'added' && c.kind != 'changed') {
          return 'expected added/changed at "$target", got ${c.kind}';
        }
        if (c.kind == 'changed') {
          // null → list (the key held no value before): after must be a
          // 1-element list.
          final av = after is Map ? after[_rootKey(target)] : null;
          if (av is! List || av.length != 1) {
            return 'appending to an empty key must yield a 1-element '
                    'list, got: ${_short(av)}';
          }
        }
        return null;
      default:
        return 'unknown op ${plan.op}';
    }
  }

  String _rootKey(String keypath) {
    final dot = keypath.indexOf('.');
    final bracket = keypath.indexOf('[');
    var end = keypath.length;
    if (dot >= 0) end = dot;
    if (bracket >= 0 && bracket < end) end = bracket;
    return keypath.substring(0, end);
  }

  /// One move, plan + apply. Bounces surface as the outcome's structured
  /// detail (the non-throwing shape the tool layer prefers).
  KeypathEditOutcome perform({
    String? path,
    String? op,
    String? anchor,
    String? body,
  }) {
    try {
      return apply(plan(path: path, op: op, anchor: anchor, body: body));
    } on KeypathEditBounce catch (b) {
      return KeypathEditOutcome(
        ok: false,
        reverted: false,
        bounce: true,
        op: op ?? '',
        path: path ?? '',
        anchor: anchor ?? '',
        detail: b.error,
        failureClass: b.failureClass,
        repair: b.repair,
        hints: b.hints,
      );
    }
  }
}

// -- pure line/offset helpers (plan-time splice arithmetic) -----------------

List<String> _splitOf(String content) =>
    content.isEmpty ? const [''] : content.split('\n');

String content_of(List<String> lines) => lines.join('\n');

int content_keepEndOfFile(List<String> lines, List<int> offsets) {
  final last = lines.length - 1;
  return offsets[last] + lines[last].length;
}

int _eof(String content) => content.length;

int _lastContentLine(List<String> lines) {
  for (var i = lines.length - 1; i >= 0; i--) {
    if (lines[i].trim().isNotEmpty) return i;
  }
  return -1;
}

String content_replaceLine(
    List<String> lines, List<int> offsets, int lineIdx, String newLine) {
  final start = offsets[lineIdx];
  final end = start + lines[lineIdx].length;
  final content = lines.join('\n');
  return content.replaceRange(start, end, newLine);
}

String content_replaceRange(List<String> lines, List<int> offsets,
    int startLine, int endLine, String replacement) {
  final content = lines.join('\n');
  final start = offsets[startLine];
  final end = endLine + 1 < lines.length
      ? offsets[endLine + 1]
      : content_keepEndOfFile(lines, offsets);
  final sep = replacement.isEmpty || replacement.endsWith('\n') ? '' : '\n';
  final tail = content.substring(end);
  final needsSep = tail.isNotEmpty && !replacement.endsWith('\n') && sep.isEmpty
      ? ''
      : sep;
  return '${content.substring(0, start)}$replacement$needsSep$tail';
}

String content_deleteRange(List<String> lines, List<int> offsets,
    int startLine, int endLine) {
  final content = lines.join('\n');
  final start = offsets[startLine];
  final end = endLine + 1 < lines.length
      ? offsets[endLine + 1]
      : content_keepEndOfFile(lines, offsets);
  return content.replaceRange(start, end, '');
}

String content_insertLine(
    List<String> lines, List<int> offsets, int atLine, String newLine) {
  final content = lines.join('\n');
  final at = atLine < offsets.length ? offsets[atLine] : _eof(content);
  final prefix = content.substring(0, at);
  final tail = content.substring(at);
  final needSepBefore =
      prefix.isNotEmpty && !prefix.endsWith('\n') ? '\n' : '';
  return '$prefix$needSepBefore$newLine\n$tail';
}

/// Byte offset where the inline value begins on a key line (just past the
/// separating colon/spaces).
int _valueStartOffset(String line, bool isJson) {
  if (isJson) {
    final m = _jsonKeyRe.firstMatch(line);
    var idx = m == null ? line.indexOf(':') : m.end;
    while (idx < line.length && line[idx] == ' ') {
      idx++;
    }
    return idx;
  }
  final m = _yamlKeyRe.firstMatch(line);
  if (m != null) {
    final keyEnd = m.group(1)!.length + m.group(2)!.length;
    final colon = line.indexOf(':', keyEnd);
    var idx = colon < 0 ? line.length : colon + 1;
    while (idx < line.length && line[idx] == ' ') {
      idx++;
    }
    return idx;
  }
  return line.length;
}

/// The json literal for a body-as-data value: already-valid json syntax
/// passes verbatim; anything else is json-encoded (quoted/escaped).
String _jsonValueLiteral(String body) {
  final t = body.trim();
  try {
    final v = jsonDecode(t);
    if (v is num || v is bool || v == null || v is String) {
      return t;
    }
    // ignore: avoid_catching_errors
  } on FormatException {
    // fall through to encode
  }
  return jsonEncode(body.trim());
}

/// The json key text for a rendered line: strips surrounding quotes when
/// the model already supplied them.
String _jsonKeyText(String key) {
  final t = key.trim();
  if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
    return t.substring(1, t.length - 1);
  }
  return t;
}

/// The last dot/bracket segment of a keypath (`a.b[0]` → `b[0]`).
String _lastSegment(String keypath) {
  for (var i = keypath.length - 1; i >= 0; i--) {
    if (keypath[i] == '.') return keypath.substring(i + 1);
  }
  return keypath;
}

/// The keypath minus its last segment (`a.b[0]` → `a.b`, `a` → ``).
String _parentPath(String keypath) {
  for (var i = keypath.length - 1; i >= 0; i--) {
    if (keypath[i] == '.') return keypath.substring(0, i);
  }
  return '';
}

String _oneLine(Object e) =>
    '$e'.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');

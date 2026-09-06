// ignore_for_file: lines_longer_as_80_chars

/// The MD MATERIALIZER (ADR 0024 §2 — the md file-class spec, realized):
/// the edit tier for Markdown. PLAN §NOW P1 "Docs oracle for md".
///
/// The spec is DATA — registered in `file_class_spec.dart` as
/// `materializerSpecs['md']` (the `md` entry, with `verb: edit_section`;
/// the fs tier stamps `edit_verb` on md file nodes):
/// `{fileClass: md, span currency: section, map format: heading_tree
/// (ATX outline, fences inert — ADR 0019), emitter: section_splice,
/// oracle: zero_broken_links, anchors: heading_path}`.
///
/// Uniform edit-verb shape (ADR 0024 §3 — ONE verb, `edit_section`, never a
/// bespoke tool family):
/// - required anchor slot (the section) — resolved MECHANICALLY from a
///   fresh parse of the file (never from stale tree offsets): exact
///   section label, or the section node id (`sec_…_<ordinal>`) from
///   meaning_zoom; ambiguity/missing bounces as named data with
///   navigable hints;
/// - body-as-data (PROSE — evidence tier, pipeline_coding.md Scope: free
///   text is allowed there; the fences are anchor-resolution + oracle,
///   not op-chains), byte-bounded by [maxMdBodyChars];
/// - host-spliced SECTION emitter: bytes are spliced between heading
///   anchors (byte-precise — the heading line itself is preserved on
///   replace; nothing reflows elsewhere in the file);
/// - named oracle `zero_broken_links` (0-BROKEN-LINKS): after EVERY apply the
///   file is re-parsed and every link must resolve — relative file links
///   to existing files, `#slug` heading anchors against the parsed
///   headings, cross-file `file.md#slug` against the target's headings;
///   code fences are inert. A broken-link edit AUTO-REVERTS with the
///   named failure class.
///
/// The map half (`parseMdSections`) is the SAME parser the fs tier's map
/// builder consumes (`fs_etl._indexMdSections` delegates here), so the
/// anchors the model zooms and the anchors the emitter splices can never
/// disagree. A class with NO oracle has NO edit verb — md's oracle is
/// named above, which is what makes the verb lawful.
library;

import 'dart:io';

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FileLockTable, FsToolsRoot;
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart'
    show FM, SchemaBundle, ToolDef, ToolName;

import 'file_class_spec.dart' show fileClassOf;

// ---------------------------------------------------------------------------
// The map half — the ONE heading parser (fs tier's map builder + this
/// emitter share it, so zoom anchors and splice anchors agree byte-precise)
// ---------------------------------------------------------------------------

/// One parsed heading section (pure data; byte offsets into the source).
class MdSection {
  const MdSection({
    required this.ordinal,
    required this.level,
    required this.title,
    required this.start,
    required this.headingEnd,
    required this.end,
    required this.line,
  });

  /// 1-based among the file's headings (stable node-id tail).
  final int ordinal;
  final int level; // 1..6
  final String title;

  /// Byte offset of the heading line start.
  final int start;

  /// Byte offset just past the heading line's newline (splice origin for
  /// replace — the heading line itself is preserved byte-for-byte).
  final int headingEnd;

  /// Byte offset of the section end (next heading line start, or EOF).
  final int end;

  /// 1-based source line of the heading.
  final int line;
}

/// Parses ATX headings (`#`..`######`) into a section tree flat-list.
/// Code fences (``` / ~~~) are INERT (ADR 0019): a `#` line inside a fence
/// is content, never a heading. Setext headings are honestly skipped (the
/// same v1 map limitation the fs tier documents). Byte-exact with the
/// fs-tier map builder.
List<MdSection> parseMdSections(String content) {
  final unitRe = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');
  final fenceRe = RegExp(r'^\s*(```|~~~)');
  var offset = 0;
  var inFence = false;
  final headings = <(int, int, int, String)>[]; // (start, lineLen, level, title)
  for (final line in content.split('\n')) {
    final lineStart = offset;
    offset += line.length + 1;
    if (fenceRe.hasMatch(line)) {
      inFence = !inFence; // ``` and ~~~ toggle (an opening fence's marker)
      continue;
    }
    if (inFence) continue; // fences are INERT (ADR 0019)
    final m = unitRe.firstMatch(line);
    if (m == null) continue;
    headings.add((lineStart, line.length, m.group(1)!.length, m.group(2)!));
  }
  final out = <MdSection>[];
  for (var i = 0; i < headings.length; i++) {
    final (start, lineLen, level, title) = headings[i];
    final end = i + 1 < headings.length ? headings[i + 1].$1 : content.length;
    var headingEnd = start + lineLen + 1;
    if (headingEnd > content.length) headingEnd = content.length;
    out.add(
      MdSection(
        ordinal: i + 1,
        level: level,
        title: title,
        start: start,
        headingEnd: headingEnd,
        end: end,
        line: content.substring(0, start).split('\n').length,
      ),
    );
  }
  return out;
}

// ---------------------------------------------------------------------------
// The oracle — md_docs_oracle (0-BROKEN-LINKS)
// ---------------------------------------------------------------------------

/// One oracle problem: named failure class + the offending target + line.
class MdLinkProblem {
  const MdLinkProblem(this.failureClass, this.target, this.line, this.detail);
  final String failureClass; // broken_relative_link | broken_heading_anchor
  final String target;
  final int line;
  final String detail;

  @override
  String toString() => '$line: [$failureClass] ${target.isEmpty ? "?" : target}'
      ' — $detail';
}

/// The named docs oracle: 0 broken links. Re-parses [content] (the
/// POST-edit bytes — never trusted from the plan) and resolves every
/// inline link outside code fences:
/// - `[x](#slug)` → a heading of THIS document whose GitHub-slug matches;
/// - `[x](relative/path.md#slug)` → the file exists (inside the workspace
///   jail) AND, when it is md, the slug resolves in THAT file;
/// - `[x](relative/path)` → the file exists;
/// - absolute paths / `..` escapes / unknown schemes (`http:` etc. pass —
///   external links are not fetchable) are classified as named data.
/// Fences are inert (a broken link inside ``` is content, per ADR 0019).
List<MdLinkProblem> mdDocsOracle(
  String content, {
  required String rel,
  required String rootPath,
}) {
  final sections = parseMdSections(content);
  final slugs = <String>{for (final s in sections) githubSlug(s.title)};
  final problems = <MdLinkProblem>[];
  final linkRe = RegExp(r'\[[^\]]*\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)');
  final fenceRe = RegExp(r'^\s*(```|~~~)');
  var offset = 0;
  var inFence = false;
  for (final line in content.split('\n')) {
    final lineNo = content.substring(0, offset).split('\n').length;
    offset += line.length + 1;
    if (fenceRe.hasMatch(line)) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    // Inline code spans are inert too (`[x](y)` in backticks is literal).
    final prose = line.replaceAll(RegExp(r'`[^`]*`'), ' ');
    for (final m in linkRe.allMatches(prose)) {
      final target = m.group(1)!;
      final col = lineNo;
      if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:').hasMatch(target)) {
        continue; // external scheme (http:, mailto:) — not fetchable, pass
      }
      if (target.startsWith('/')) {
        problems.add(
          MdLinkProblem('broken_relative_link', target, col,
              'absolute link targets are outside the docs workspace jail'),
        );
        continue;
      }
      final hash = target.indexOf('#');
      final pathPart = hash < 0 ? target : target.substring(0, hash);
      final frag = hash < 0 ? '' : target.substring(hash + 1);
      if (pathPart.isEmpty) {
        // Same-document heading anchor: must resolve against THIS doc's
        // headings ("heading anchors still resolve").
        if (!slugs.contains(githubSlug(frag))) {
          problems.add(
            MdLinkProblem(
                'broken_heading_anchor', target, col,
                'no heading of this document slugs to "#$frag"'),
          );
        }
        continue;
      }
      final resolved = _normalizeRel(pathPart, _dirOf(rel));
      if (resolved == null) {
        problems.add(
          MdLinkProblem('broken_relative_link', target, col,
              'the path escapes the workspace (.. above the root)'),
        );
        continue;
      }
      final abs = '$rootPath/$resolved';
      if (!File(abs).existsSync()) {
        problems.add(
          MdLinkProblem('broken_relative_link', target, col,
              'no file at $resolved (relative to the workspace root)'),
        );
        continue;
      }
      // file.md#slug — the heading anchor must resolve in the TARGET file.
      if (frag.isNotEmpty && RegExp(r'\.mdx?$', caseSensitive: false).hasMatch(resolved)) {
        final targetSlugs = {
          for (final s in parseMdSections(File(abs).readAsStringSync()))
            githubSlug(s.title),
        };
        if (!targetSlugs.contains(githubSlug(frag))) {
          problems.add(
            MdLinkProblem('broken_heading_anchor', target, col,
                'no heading of $resolved slugs to "#$frag"'),
          );
        }
      }
    }
  }
  return problems;
}

/// GitHub-style heading slug (lowercase; punctuation stripped except word
/// chars and hyphens; spaces → hyphens). Deterministic — the oracle and
/// the doc convention agree on exactly this form.
String githubSlug(String title) {
  var s = title.trim().toLowerCase();
  s = s.replaceAll(RegExp(r'[^\w\- ]'), '');
  s = s.replaceAll(' ', '-');
  return s;
}

String _dirOf(String rel) {
  final slash = rel.lastIndexOf('/');
  return slash < 0 ? '' : rel.substring(0, slash);
}

/// Lexical POSIX normalize of [path] against [baseDir]; null when the path
/// climbs above the workspace root.
String? _normalizeRel(String path, String baseDir) {
  final segments = <String>[
    if (baseDir.isNotEmpty) ...baseDir.split('/'),
    ...path.split('/'),
  ];
  final out = <String>[];
  for (final seg in segments) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (out.isEmpty) return null;
      out.removeLast();
      continue;
    }
    out.add(seg);
  }
  return out.join('/');
}

// ---------------------------------------------------------------------------
// The materializer — plan (mechanical anchor resolution + splice) / apply
// (atomic write + oracle + in-memory auto-revert)
// ---------------------------------------------------------------------------

/// Mechanical bounce BEFORE any byte is touched: error + the exact repair
/// move + navigable hints (B2 dialect, named failure class).
class MdEditBounce implements Exception {
  MdEditBounce(this.error, this.repair, this.failureClass,
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

/// A validated md edit: the host has resolved the anchor, spliced the
/// bytes, and the result is ready to write + oracle-check.
class MdEditPlan {
  const MdEditPlan({
    required this.path,
    required this.op,
    required this.anchorLabel,
    required this.body,
    required this.section,
    required this.content,
    required this.description,
  });
  final String path; // workspace-relative
  final String op; // replace_section | insert_section | append_to_section
  final String anchorLabel;
  final String body;
  final MdSection section;

  /// The FULL post-splice file content (host-computed, byte-precise).
  final String content;
  final String description;
}

/// The outcome of an md edit. Failures are classified data — never dropped.
class MdEditOutcome {
  const MdEditOutcome({
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
    this.problems = const [],
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
  final List<MdLinkProblem> problems;

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
        if (problems.isNotEmpty)
          'problems': [for (final p in problems) p.toString()],
      };
}

/// The md materializer: plan (pure validation + splice, never touches
/// bytes) + apply (atomic write → md_docs_oracle → auto-revert on any
/// broken link, with failure attribution). Single-writer via the shared
/// [FileLockTable] (squad discipline — the same table the span editor
/// claims).
class MdMaterializer {
  MdMaterializer({
    required this.root,
    FileLockTable? locks,
    this.owner = 'md_materializer',
  }) : locks = locks ?? FileLockTable();

  final FsToolsRoot root;
  final FileLockTable locks;
  final Object owner;

  /// The body budget (body-as-data, budgeted): prose travels whole, but a
  /// single move past this bound bounces with the split-it repair move.
  static const maxMdBodyChars = 20000;

  MdEditPlan plan({
    required String? path,
    required String? op,
    required String? anchor,
    required String? body,
  }) {
    if (path == null || path.isEmpty) {
      throw MdEditBounce(
        'missing path',
        're-send with path as a workspace-relative .md path (the id/label '
            'from meaning_zoom, e.g. "docs/guide.md")',
        'invalid_path',
      );
    }
    final String abs;
    try {
      abs = root.resolve(path);
      // ignore: avoid_catching_errors
    } on ArgumentError catch (e) {
      throw MdEditBounce(
        'path escapes the workspace jail: $path',
        'use a workspace-relative path (no .., no absolute) — zoom the '
            'file node for the canonical rel',
        'path_escapes_workspace',
        hints: ['$e'],
      );
    }
    if (fileClassOf(path) != 'md') {
      throw MdEditBounce(
        '$path is class "${fileClassOf(path)}" — edit_section edits md only',
        'the md materializer is the first non-dart spec (ADR 0024 '
            'sequencing: md → yaml/json); yaml/json edits still route '
            'through the review gate until their specs land',
        'not_md_class',
      );
    }
    final f = File(abs);
    if (!f.existsSync()) {
      throw MdEditBounce(
        'file not found: $path',
        'zoom the tree (meaning_zoom) for existing files; a NEW file lands '
            'through the host materializer bootstrap, never a guessed path',
        'file_not_found',
      );
    }
    const ops = {'replace_section', 'insert_section', 'append_to_section'};
    if (op == null || !ops.contains(op)) {
      throw MdEditBounce(
        'unknown op: $op',
        're-send with op as one of: ${ops.join(", ")}',
        'unknown_op',
      );
    }
    if (body == null) {
      throw MdEditBounce(
        'missing body',
        're-send with body as the section prose (data — replace_section '
            'may pass an empty string to clear the content; insert/append '
            'require non-empty prose)',
        'invalid_body',
      );
    }
    if (body.length > maxMdBodyChars) {
      throw MdEditBounce(
        'body over budget: ${body.length} chars (max $maxMdBodyChars)',
        'split the edit into multiple section moves (one anchor per '
            'move) — the budget is per move, the doc is not',
        'body_over_budget',
      );
    }
    if (op != 'replace_section' && body.trim().isEmpty) {
      throw MdEditBounce(
        'empty body for $op',
        'insert_section/append_to_section carry the new prose as data; '
            'only replace_section may pass an empty body (it clears the '
            'section content, heading preserved)',
        'empty_body',
      );
    }

    // Mechanical anchor resolution: fresh parse of the CURRENT bytes —
    // never the tree's (possibly stale) offsets. Accepts the section
    // label (exact) or the section node id (sec_…_<ordinal>).
    final content = f.readAsStringSync();
    final sections = parseMdSections(content);
    final fileNodeId = 'f_${path.replaceAll('/', '_')}';
    MdSection? section;
    var idHit = false;
    if (anchor != null && anchor.startsWith('sec_')) {
      // The node id form is sec_<fileNodeId>_<ordinal> — resolve the
      // ordinal mechanically against the fresh parse.
      final prefix = 'sec_${fileNodeId}_';
      if (anchor.startsWith(prefix)) {
        final ordinal = int.tryParse(anchor.substring(prefix.length));
        if (ordinal != null && ordinal >= 1 && ordinal <= sections.length) {
          section = sections[ordinal - 1];
          idHit = true;
        }
      }
      if (!idHit) {
        throw MdEditBounce(
          'section id "$anchor" does not resolve in the current bytes of '
              '$path (the file changed since the tree was built?)',
          'refresh the tree (repo_etl refresh), re-zoom, then re-send the '
              'anchor as the section label or the fresh node id',
          'anchor_not_found',
          hints: [for (final s in sections) 'sec_${fileNodeId}_${s.ordinal}: ${s.title}'],
        );
      }
    } else if (anchor != null && anchor.isNotEmpty) {
      final hits = sections.where((s) => s.title == anchor).toList();
      if (hits.length == 1) {
        section = hits.single;
      } else if (hits.length > 1) {
        throw MdEditBounce(
          'ambiguous anchor "$anchor": ${hits.length} sections share the '
              'label in $path',
          're-send anchor as the section NODE ID from meaning_zoom (one '
              'of the candidates below)',
          'ambiguous_anchor',
          hints: [
            for (final s in hits) 'sec_${fileNodeId}_${s.ordinal}: ${s.title}',
          ],
        );
      }
    }
    if (section == null) {
      throw MdEditBounce(
        anchor == null || anchor.isEmpty
            ? 'missing anchor (the section to edit)'
            : 'anchor not found: no section labeled "$anchor" in $path',
        're-send with anchor as a section label of THIS file — zoom the '
            'file node ($fileNodeId) for the outline, then retry',
        'anchor_not_found',
        hints: [
          for (final s in sections)
            'sec_${fileNodeId}_${s.ordinal}: ${s.title}',
          if (sections.isEmpty)
            'this file has no ATX headings — the md map needs headings to '
                'anchor sections',
        ],
      );
    }
    if (op == 'insert_section') {
      final firstLine = body.trimLeft().split('\n').first.trim();
      if (!RegExp(r'^#{1,6}\s+\S').hasMatch(firstLine)) {
        throw MdEditBounce(
          'insert_section body must START with a heading line (it inserts '
              'a NEW section after the anchor)',
          're-send body as "<#-heading>\\n\\n<prose>", or use '
              'append_to_section to extend the anchor\'s own content',
          'insert_needs_heading',
        );
      }
    }

    final spliced = _splice(content, section, op, body);
    return MdEditPlan(
      path: path,
      op: op,
      anchorLabel: section.title,
      body: body,
      section: section,
      content: spliced,
      description:
          '$op ${section.title} (sec_${fileNodeId}_${section.ordinal}, '
          'level ${section.level}) in $path',
    );
  }

  /// The SECTION EMITTER: host-spliced, byte-precise — replaces / inserts
  /// the section's lines between heading anchors and never reflows any
  /// other byte of the file (parsed offsets, never guessed).
  String _splice(String content, MdSection s, String op, String body) {
    switch (op) {
      case 'replace_section':
        // The heading line itself is preserved byte-for-byte; the content
        // lines between it and the next heading are replaced by the body.
        final normalized = body.isEmpty ? '' : _withTrailingNewline(body);
        final sep = _needsNewlineSep(content, s.headingEnd) ? '\n' : '';
        return content.replaceRange(
            s.headingEnd, s.end, '$sep$normalized');
      case 'insert_section':
      case 'append_to_section':
        // Both land at the section boundary (end = next heading start or
        // EOF): insert_section adds a NEW section (heading-validated),
        // append_to_section extends THIS section's content — same splice
        // point, different validation.
        final sep = _needsNewlineSep(content, s.end) ? '\n' : '';
        return content.replaceRange(s.end, s.end, '$sep${_withTrailingNewline(body)}');
      default:
        throw MdEditBounce('unknown op: $op', 'host bug — report as data',
            'unknown_op');
    }
  }

  /// True when the byte just before [offset] is not a newline (a heading
  /// as the last line without a trailing newline) — the splice then needs
  /// a separating newline so lines never glue.
  bool _needsNewlineSep(String content, int offset) =>
      offset > 0 && offset <= content.length && content[offset - 1] != '\n';

  String _withTrailingNewline(String body) =>
      body.endsWith('\n') ? body : '$body\n';

  MdEditOutcome apply(MdEditPlan plan) {
    final rel = plan.path;
    if (!locks.claim(rel, owner)) {
      final holder = locks.ownerOf(rel);
      return MdEditOutcome(
        ok: false,
        reverted: false,
        op: plan.op,
        path: rel,
        anchor: plan.anchorLabel,
        detail: 'lock conflict on $rel (held by $holder) — the move '
            'claimed no bytes',
        failureClass: 'lock_conflict',
      );
    }
    try {
      final abs = root.resolve(rel);
      final f = File(abs);
      final original = f.readAsStringSync();
      f.writeAsStringSync(plan.content, flush: true);
      // THE NAMED ORACLE — after EVERY apply: re-parse the post bytes and
      // assert 0 broken relative links + heading anchors still resolve.
      final problems = mdDocsOracle(
        plan.content,
        rel: rel,
        rootPath: root.rootPath,
      );
      if (problems.isNotEmpty) {
        // AUTO-REVERT: a broken-link edit never lands (ADR 0021/0024 —
        // the failure carries its named class).
        f.writeAsStringSync(original, flush: true);
        final classes = problems.map((p) => p.failureClass).toSet();
        return MdEditOutcome(
          ok: false,
          reverted: true,
          op: plan.op,
          path: rel,
          anchor: plan.anchorLabel,
          detail: 'md_docs_oracle FAILED after ${plan.description}: '
              '${problems.length} broken link(s) — ALL bytes reverted',
          failureClass: classes.length == 1
              ? classes.single
              : classes.join('+'),
          hints: const [
            'fix the link target (or create the file) and re-send the '
                'move — the doc must satisfy 0-broken-links to land',
          ],
          problems: problems,
        );
      }
      return MdEditOutcome(
        ok: true,
        reverted: false,
        op: plan.op,
        path: rel,
        anchor: plan.anchorLabel,
        detail: '${plan.description} — spliced byte-precise '
            '(${original.length} → ${plan.content.length} bytes); '
            'md_docs_oracle green (0 broken links). The tree re-derives '
            'the section map on the next tick.',
      );
    } finally {
      locks.release(rel, owner);
    }
  }

  /// One move, plan + apply. Bounces surface as the outcome's structured
  /// detail (the non-throwing shape the tool layer prefers).
  MdEditOutcome perform({
    String? path,
    String? op,
    String? anchor,
    String? body,
  }) {
    try {
      return apply(plan(path: path, op: op, anchor: anchor, body: body));
    } on MdEditBounce catch (b) {
      return MdEditOutcome(
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

// ---------------------------------------------------------------------------
// The ONE edit verb — same registry discipline as edit_symbol (the model
// supplies {anchor, op, body-as-data}; the HOST resolves, splices, oracles)
// ---------------------------------------------------------------------------

/// `edit_section`: the fs tier's md edit verb (ADR 0024 §2/§3 — the FIRST
/// non-dart materializer). md edits must NOT be raw writes: the model
/// names the section (anchor), the op, and the prose (body-as-data,
/// budgeted); the host resolves the anchor mechanically, splices the bytes
/// between heading anchors, and runs the named `md_docs_oracle` — a
/// broken-link edit auto-reverts with the named failure class.
ToolDef editMdTool(
  FsToolsRoot root, {
  FileLockTable? locks,
  Object owner = 'md_materializer',
}) {
  final mat = MdMaterializer(root: root, locks: locks, owner: owner);
  return ToolDef.encode(
    name: const ToolName('edit_section'),
    description:
        'Edit a Markdown section by heading anchor. Args: path (.md), op '
        '(replace_section | insert_section | append_to_section), anchor '
        '(exact section label or section node id), body (prose as data). '
        'The host splices byte-precisely (heading preserved) and runs the '
        'zero_broken_links oracle — a violating edit AUTO-REVERTS. Misses '
        'bounce with the outline.',
    argsSchema: SchemaBundle(
      root: FM.object('edit_section', properties: () => [
            FM.prop('path', FM.string()),
            FM.prop(
              'op',
              FM.enum_('op', const [
                'replace_section',
                'insert_section',
                'append_to_section',
              ]),
            ),
            FM.prop('anchor', FM.string()),
            FM.prop('body', FM.string()),
          ]),
    ),
    execute: (args) async {
      final map = args is Map ? args : const {};
      final outcome = mat.perform(
        path: map['path'] as String?,
        op: map['op'] as String?,
        anchor: map['anchor'] as String?,
        body: map['body'] as String?,
      );
      return outcome.toJson();
    },
  );
}

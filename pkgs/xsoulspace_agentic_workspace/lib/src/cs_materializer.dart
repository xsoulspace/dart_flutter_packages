// ignore_for_file: lines_longer_as_80_chars

/// The C# MATERIALIZER (ADR 0035 §6 — Tier C v1, the second full-code
/// non-Dart family). The binding is the unit of extension (ADR 0035 §1):
/// this file + one registry entry (materializer_binding.dart) land the
/// whole `cs` class; the engine, router, fs tier and model surface are
/// closed code. The structure MIRRORS ts_materializer.dart (the landed
/// template) — same perform shape, same bounce classes, same envelope.
///
/// The spec is DATA — registered as the cs BINDING in
/// `materializer_binding.dart` (the fs tier stamps `edit_actions` on cs
/// file nodes):
/// `{fileClass: cs, span currency: member_span (UTF-8 byte spans — the
/// meaning-tree span-prop currency), map format: symbol_tree,
/// emitter: member_splice, oracle: dotnet_build, anchors: node_id}`.
///
/// MAP HALF (Tier C v1 — the mechanical, dependency-light scanner, repo
/// precedent: `scanDartFile`, `tsScanSymbols`, regex md headings):
/// [csScanSymbols] extracts symbols AND MEMBER SYMBOLS day one (decision
/// 2026-09-07) — class/interface/enum/struct/record declarations and
/// namespaces (BOTH forms, see below) as `sym` nodes; methods,
/// properties, fields and constructors as `member` nodes under their
/// declaring parent — using the tree-sitter-c-sharp node-kind vocabulary
/// (so the conformance delta is measurable as data, ADR 0035 §8 item 5).
/// Spans are BYTE-precise (UTF-8 byte offsets — the span reader's
/// currency; the multibyte discipline). Attributes (`[Foo]`) on members
/// RIDE the member span (the immediately preceding contiguous
/// attribute-only lines are absorbed into the span start — no phantom
/// nodes). Shapes the scanner cannot span reliably are honestly OMITTED
/// or bounced (`unsupported_shape`) — never a wrong span.
///
/// NAMESPACE handling (documented per the §6 brief): namespaces map to
/// `sym` nodes in BOTH forms — block-scoped `namespace X { }` maps as
/// `namespace_declaration`, file-scoped `namespace X;` maps as
/// `file_scoped_namespace_declaration` (tree-sitter-c-sharp's own kinds).
/// A file-scoped namespace pushes a scope at the CURRENT depth, so
/// declarations that follow it at depth 0 carry `parentName` = the
/// namespace name (nearest mapped ancestor); block-scoped bodies do the
/// same for declarations inside the braces. The namespace node itself is
/// NOT an insert_member target (declaring type bodies only).
///
/// EDIT HALF — actions REUSE the dart names VERBATIM (ADR 0035 §5;
/// class-agnostic semantics):
/// - `insert_member {anchor: declaring sym node, body}` — brace-aware
///   member insertion at the container's closing-brace boundary,
///   byte-precise (everything outside the touched span byte-identical);
/// - `remove_member {anchor: member node}` — full-line removal of the
///   member's span (attributes ride along), byte-precise;
/// - `apply_executable {anchor: member node, body: executableId}` —
///   member-body edits arrive via PACK EXECUTABLES only (the
///   trusted-author tier is language-agnostic, ADR 0035 §6 v1): the
///   consented authored body is spliced into the member's body span.
///
/// **replace_member_body is deliberately OMITTED from the declared
/// actions** (the v1 limitation IS the registry data, never prose —
/// ADR 0035 §5: bodies are not model-composed for this class in v1;
/// op-chain back-ends are v2, evidence-gated). The illegal-action bounce
/// teaches the limitation mechanically with the class-scoped legal list.
///
/// NAMED ORACLE `dotnet_build`: after EVERY apply, `dotnet build` grades
/// the jail (the first `*.csproj` found — root first, then a bounded
/// walk skipping bin/obj/VCS dirs). The analyzer binary resolves from
/// the jail's `.dotnet/dotnet` first, then PATH (host-injected override
/// supported for tests). When the analyzer or a project file is
/// UNAVAILABLE the move bounces with failureClass `oracle_unavailable`
/// BEFORE any byte is touched — named, never a silent pass (the honesty
/// law, ADR 0024 §6). A failing build AUTO-REVERTS with failureClass
/// `cs_error`. The test convention (`dotnet test` when the jail carries
/// a project) rides the outcome as DATA — graded by the verify tier,
/// never silently claimed here (honest null when the jail has none).library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FileLockTable, FsToolsRoot;

import 'edit_pack.dart' show EditPackRegistry;
import 'file_class_spec.dart' show MappedSubNode;
import 'materializer_binding.dart' show NodeEditRequest;

// ---------------------------------------------------------------------------
// The map half — the ONE cs symbol scanner (fs tier's map builder + this
/// emitter share it, so zoom anchors and splice anchors agree byte-precise)
// ---------------------------------------------------------------------------

/// One scanned cs symbol (pure data; spans in UTF-8 BYTE offsets — the
/// meaning-tree span-prop currency). [grammarType] uses the
/// tree-sitter-c-sharp node-kind vocabulary, so scanner output is
/// directly comparable to a future FFI mapper's output (ADR 0035 §8).
class CsSymbol {
  const CsSymbol({
    required this.kind,
    required this.grammarType,
    required this.name,
    required this.parentName,
    required this.startByte,
    required this.endByte,
    required this.line,
    required this.indent,
  });

  /// `sym` (declaration) or `member` (under a declaring parent).
  final String kind;

  /// The tree-sitter-c-sharp grammar node kind (the shared vocabulary):
  /// namespace_declaration, file_scoped_namespace_declaration,
  /// class_declaration, interface_declaration, enum_declaration,
  /// struct_declaration, record_declaration, method_declaration,
  /// constructor_declaration, property_declaration, field_declaration.
  final String grammarType;
  final String name;

  /// The declaring parent's name (members AND nested/file-scoped
  /// declarations); null → attached to the file.
  final String? parentName;

  /// UTF-8 byte offsets (never code units — the multibyte discipline).
  final int startByte;
  final int endByte;

  /// 1-based source line of the declaration start.
  final int line;

  /// Leading spaces of the declaration line.
  final int indent;

  @override
  String toString() =>
      'CsSymbol($kind $grammarType $name'
      '${parentName == null ? '' : ' <- $parentName'}, '
      'bytes $startByte..$endByte, line $line)';
}

/// The stable sub-node id tail for [s]: syms by name; members by
/// `<parent>_<name>` (constructors repeat the parent —
/// `<parent>_<parent>`). Same-name shapes (method+property overloads)
/// get a deterministic `_2`/`_3` ordinal suffix in scan order — the SAME
/// scheme the materializer's fresh-scan anchor resolution recomputes, so
/// zoom ids and splice anchors agree.
String csSymbolIdTail(CsSymbol s, Map<String, int> usedTails) {
  final bare = s.kind == 'sym'
      ? s.name
      : (s.parentName == null ? s.name : '${s.parentName}_${s.name}');
  final key = '${s.kind}|${s.grammarType}|${s.parentName ?? ''}|$bare';
  final count = (usedTails[key] ?? 0) + 1;
  usedTails[key] = count;
  return count == 1 ? bare : '${bare}_$count';
}

// -- masked view: strings / comments are INERT (ADR 0019) -------------------

/// Returns [src] with every character inside strings (normal `"…"`,
/// char `'…'`, verbatim `@"…"`, interpolated `$"…"` masked WHOLE
/// including holes, raw `"""…"""`) and comments replaced by spaces —
/// same length, same newlines. Braces/parens inside masked regions stop
/// counting as structure; a brace inside a string can never corrupt the
/// depth tracking or a splice. v1 masking decision (mirrors the ts
/// template-literal rule): interpolated holes are masked whole, so
/// braces inside holes do not count as structure.
String _maskContent(String src) {
  final out = List<int>.from(src.codeUnits);
  var i = 0;
  while (i < src.length) {
    final c = src[i];
    if (c == '/' && i + 1 < src.length) {
      final n = src[i + 1];
      if (n == '/') {
        while (i < src.length && src[i] != '\n') {
          out[i] = 0x20;
          i++;
        }
        continue;
      }
      if (n == '*') {
        out[i] = 0x20;
        out[i + 1] = 0x20;
        i += 2;
        while (i < src.length) {
          if (src[i] == '*' && i + 1 < src.length && src[i + 1] == '/') {
            out[i] = 0x20;
            out[i + 1] = 0x20;
            i += 2;
            break;
          }
          if (src[i] != '\n') out[i] = 0x20;
          i++;
        }
        continue;
      }
    }
    // Verbatim/interpolated string prefixes: `@"`, `$"`, `$@"`, `@$"`.
    if (c == r'@' || c == r'$') {
      var j = i;
      var verbatim = false;
      while (j < src.length && (src[j] == r'@' || src[j] == r'$')) {
        if (src[j] == r'@') verbatim = true;
        j++;
      }
      if (j < src.length && src[j] == '"') {
        i = _maskQuoted(src, out, i, j, verbatim);
        continue;
      }
      // Not a string prefix (e.g. a verbatim identifier like `@class`):
      // advance past the prefix characters without masking.
      i = j;
      continue;
    }
    if (c == '"') {
      // Raw string `"""` … `"""`.
      if (src.startsWith('"""', i)) {
        final close = src.indexOf('"""', i + 3);
        final end = close < 0 ? src.length : close + 3;
        while (i < end) {
          if (src[i] != '\n') out[i] = 0x20;
          i++;
        }
        continue;
      }
      i = _maskQuoted(src, out, i, i, false);
      continue;
    }
    if (c == "'") {
      i = _maskQuoted(src, out, i, i, false);
      continue;
    }
    i++;
  }
  return String.fromCharCodes(out);
}

/// Masks one quoted string: [openQuote] is the quote index, [from] the
/// first prefix character to mask. [verbatim] → no backslash escapes
/// (but `""` is an escaped quote); else backslash escapes. Newlines are
/// always preserved (masked regions keep line structure).
int _maskQuoted(
  String src,
  List<int> out,
  int from,
  int openQuote,
  bool verbatim,
) {
  for (var k = from; k <= openQuote; k++) {
    out[k] = 0x20;
  }
  var i = openQuote + 1;
  while (i < src.length) {
    final c = src[i];
    if (c == '"' && verbatim) {
      if (i + 1 < src.length && src[i + 1] == '"') {
        out[i] = 0x20;
        out[i + 1] = 0x20;
        i += 2;
        continue;
      }
      out[i] = 0x20;
      return i + 1;
    }
    if (c == r'\\' && !verbatim) {
      if (i + 1 < src.length && src[i + 1] != '\n') {
        out[i] = 0x20;
        out[i + 1] = 0x20;
        i += 2;
        continue;
      }
    }
    if (c == '"') {
      out[i] = 0x20;
      return i + 1;
    }
    if (c != '\n') out[i] = 0x20;
    i++;
  }
  return i;
}

/// Code-unit index → UTF-8 byte offset (the ONE sanctioned conversion —
/// the span-bridge discipline, ADR 0035 §8). Surrogate pairs (emoji) map
/// both code units to the scalar's byte start; index [s.length] → total
/// bytes.
List<int> _utf16ToUtf8Map(String s) {
  final bytes = utf8.encode(s);
  final map = List<int>.filled(s.length + 1, 0);
  var bi = 0;
  var ci = 0;
  while (bi < bytes.length && ci < s.length) {
    final b = bytes[bi];
    final len = b < 0x80 ? 1 : (b < 0xE0 ? 2 : (b < 0xF0 ? 3 : 4));
    final units = len == 4 ? 2 : 1;
    for (var k = 0; k < units && ci + k < s.length; k++) {
      map[ci + k] = bi;
    }
    ci += units;
    bi += len;
  }
  map[s.length] = bytes.length;
  return map;
}

// -- declaration patterns (the tree-sitter-c-sharp vocabulary) --------------

final RegExp _nsRe =
    RegExp(r'^namespace\s+([\p{L}_][\p{L}\p{N}_.]*)', unicode: true);
final RegExp _classRe =
    RegExp(r'^class\s+([\p{L}_][\p{L}\p{N}_]*)', unicode: true);
final RegExp _interfaceRe =
    RegExp(r'^interface\s+([\p{L}_][\p{L}\p{N}_]*)', unicode: true);
final RegExp _structRe =
    RegExp(r'^struct\s+([\p{L}_][\p{L}\p{N}_]*)', unicode: true);
final RegExp _enumRe =
    RegExp(r'^enum\s+([\p{L}_][\p{L}\p{N}_]*)', unicode: true);
final RegExp _recordRe = RegExp(
    r'^record\s+(?:class\s+|struct\s+)?([\p{L}_][\p{L}\p{N}_]*)',
    unicode: true);

/// Access modifiers / qualifiers that may prefix any declaration — the
/// declaration KEYWORD follows them (the sym span starts at the keyword;
/// member spans INCLUDE them, byte-precise).
final RegExp _modifiersRe = RegExp(
  r'^(?:(?:public|private|protected|internal|static|sealed|abstract|virtual'
  r'|override|async|const|readonly|extern|new|unsafe|partial|ref|required'
  r'|file|volatile|scoped)\s+)*',
  unicode: true,
);

/// Constructor head: `Name(` where Name equals the containing type.
final RegExp _ctorRe =
    RegExp(r'^([\p{L}_][\p{L}\p{N}_]*)\s*\(', unicode: true);

/// Method head: `Type Name(` (the type may carry generics/dots/commas/
/// nullable/array markers and one space inside `Dictionary<string, int>`;
/// generic constraints after the parameter list ride the span).
final RegExp _methodRe = RegExp(
  r'^[\p{L}_][\p{L}\p{N}_<>\[\],.?\s]*\s+([\p{L}_][\p{L}\p{N}_]*)\s*'
  r'(?:<[^>()]*>)?\s*\(',
  unicode: true,
);

/// Property head: `Type Name {` or `Type Name =>` (auto/expression-
/// bodied; accessor lists ride the body span).
final RegExp _propertyRe = RegExp(
  r'^[\p{L}_][\p{L}\p{N}_<>\[\],.?\s]*\s+([\p{L}_][\p{L}\p{N}_]*)\s*(\{|=>)',
  unicode: true,
);

/// Field head: `Type Name =` / `Type Name;` / `Type Name,` / end-of-line
/// (multi-declarator statements index the FIRST declarator only — same
/// v1 rule as the ts scanner).
final RegExp _fieldRe = RegExp(
  r'^[\p{L}_][\p{L}\p{N}_<>\[\],.?\s]*\s+([\p{L}_][\p{L}\p{N}_]*)\s*(?:=|;|,|$)',
  unicode: true,
);

/// The namespace grammar kinds (declaration-bearing scopes — a
/// block-scoped namespace body's declarations attach to it as parent;
/// NOT container kinds: insert_member targets TYPE bodies only).
const _namespaceKinds = <String>{
  'namespace_declaration',
  'file_scoped_namespace_declaration',
};

/// The class-like container kinds whose bodies take members (the
/// insert_member targets and the member-attachment parents).
const _containerKinds = <String>{
  'class_declaration',
  'interface_declaration',
  'struct_declaration',
  'record_declaration',
};

/// One open lexical scope (a mapped ancestor the member attachment
/// resolves against — the scanner-side ancestor stack).
class _Scope {
  _Scope(this.grammarType, this.name, this.entryDepth);
  final String grammarType;
  final String name;

  /// Absolute brace depth INSIDE the body (the opener's depth + 1).
  final int entryDepth;
}

/// Scans [content] into symbols: line/brace-based extraction (dependency-
/// light, deterministic). Honest v1 limitations (never a wrong span):
/// delegates, operator overloads and indexers are not indexed; local
/// functions and method-body statements are not indexed; the first
/// declarator of a multi-declarator field only; enum members are not
/// indexed; attributes are absorbed into the following declaration's
/// span (no phantom symbols); interpolated-string holes are masked whole
/// (braces inside holes never count as structure). One-declaration-per-
/// line discipline is assumed for the scope stack (same v1 rule as the
/// ts scanner).
List<CsSymbol> csScanSymbols(String content) {
  final masked = _maskContent(content);
  final maskedLines = masked.split('\n');
  final srcLines = content.split('\n');
  final cuToByte = _utf16ToUtf8Map(content);
  // Cumulative depth at each line start — braceAtLine[i] is the depth
  // BEFORE line i (so braceAtLine[i+1] is the depth AFTER line i).
  final braceAtLine = List<int>.filled(maskedLines.length + 1, 0);
  final parenAtLine = List<int>.filled(maskedLines.length + 1, 0);
  final lineStart = List<int>.filled(maskedLines.length + 1, 0);
  var off = 0;
  var brace = 0;
  var paren = 0;
  for (var i = 0; i < maskedLines.length; i++) {
    lineStart[i] = off;
    braceAtLine[i] = brace;
    parenAtLine[i] = paren;
    for (var j = 0; j < maskedLines[i].length; j++) {
      final c = maskedLines[i][j];
      if (c == '{') {
        brace++;
      } else if (c == '}') {
        brace--;
      } else if (c == '(' || c == '[') {
        paren++;
      } else if (c == ')' || c == ']') {
        paren--;
      }
    }
    off += maskedLines[i].length + 1;
  }
  braceAtLine[maskedLines.length] = brace;
  parenAtLine[maskedLines.length] = paren;
  lineStart[maskedLines.length] = masked.length;

  // Source-line starts (content coordinates — for attribute absorption).
  final srcStart = List<int>.filled(srcLines.length, 0);
  var srcOff = 0;
  for (var i = 0; i < srcLines.length; i++) {
    srcStart[i] = srcOff;
    srcOff += srcLines[i].length + 1;
  }

  /// True when line [i] is attribute-only (`[…]`) — the span-absorption
  /// walk's input (masked view, so string contents cannot fake it).
  bool attrLine(int i) {
    final t = maskedLines[i].trim();
    return t.startsWith('[') && t.endsWith(']');
  }

  final out = <CsSymbol>[];
  final scopes = <_Scope>[];

  for (var i = 0; i < maskedLines.length; i++) {
    final mLine = maskedLines[i];
    final trimmed = mLine.trim();
    final lineParen = parenAtLine[i];
    final beforeDepth = braceAtLine[i];
    final afterDepth = braceAtLine[i + 1];
    // Pop scopes whose body closed on an earlier line (or by this
    // line's close): the AFTER-line depth is exact for both the
    // opener-on-next-line discipline and the plain close.
    while (scopes.isNotEmpty && afterDepth < scopes.last.entryDepth) {
      scopes.removeLast();
    }
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('#')) continue; // preprocessor: never symbols
    if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;
    if (attrLine(i)) continue; // attributes ride the NEXT declaration

    final top = scopes.isEmpty ? null : scopes.last;
    final inContainer =
        top != null && _containerKinds.contains(top.grammarType);
    final atContainerMember = inContainer && beforeDepth == top.entryDepth;
    // A namespace body carries declarations too (block-scoped forms at
    // the body depth; the file-scoped scope sits at the CURRENT depth).
    // The namespace is NOT a container kind — insert_member still
    // targets declaring TYPE bodies only (the doc contract above).
    final inNamespace = top != null && _namespaceKinds.contains(top.grammarType);
    final atNamespaceDepth = inNamespace && beforeDepth == top.entryDepth;

    // ---- namespaces (BOTH forms map — sym nodes, documented) ----------
    final nsm = atTopLevelGuard(beforeDepth, lineParen)
        ? _nsRe.firstMatch(trimmed)
        : null;
    if (nsm != null) {
      final name = nsm.group(1)!;
      final fileScoped = trimmed.contains(';');
      final grammarType = fileScoped
          ? 'file_scoped_namespace_declaration'
          : 'namespace_declaration';
      out.add(_addSymbol(
        kind: 'sym',
        grammarType: grammarType,
        name: name,
        parentName: top?.name,
        mLine: mLine,
        lineIdx: i,
        lineStart: lineStart[i],
        srcLines: srcLines,
        srcStart: srcStart,
        attrLine: attrLine,
        masked: masked,
        cuToByte: cuToByte,
      ));
      // File-scoped: push at the CURRENT depth (declarations that follow
      // at depth 0 attach to the namespace). Block-scoped: push at +1
      // (the opener may sit on the next line — the after-depth pop rule
      // keeps the scope alive across a brace-only line).
      scopes.add(_Scope(grammarType, name, fileScoped ? beforeDepth : beforeDepth + 1));
      continue;
    }

    // ---- declarations (top-level, in a namespace body, or nested in a
    // container) ----------------------------------------------------------
    if ((beforeDepth == 0 && lineParen == 0) ||
        atContainerMember ||
        atNamespaceDepth) {
      final dm = _declOf(trimmed);
      if (dm != null) {
        out.add(_addSymbol(
          kind: 'sym',
          grammarType: dm.$1,
          name: dm.$2,
          parentName: top?.name,
          mLine: mLine,
          lineIdx: i,
          lineStart: lineStart[i],
          srcLines: srcLines,
          srcStart: srcStart,
          attrLine: attrLine,
          masked: masked,
          cuToByte: cuToByte,
        ));
        // Brace-bodied containers push at +1 uniformly (opener on this
        // line or the next — the after-depth pop rule handles both; a
        // `;`-terminated record is popped by the next top-level line).
        scopes.add(_Scope(dm.$1, dm.$2, beforeDepth + 1));
        continue;
      }
    }

    // ---- container members (methods/properties/fields/ctors) ----------
    if (atContainerMember) {
      final container = top;
      final stripped = trimmed.replaceFirst(_modifiersRe, '');
      final head = _headOf(stripped, container.name);
      if (head != null) {
        final name = head.$1;
        final grammarType = head.$2;
        out.add(_addSymbol(
          kind: 'member',
          grammarType: grammarType,
          name: name,
          parentName: container.name,
          mLine: mLine,
          lineIdx: i,
          lineStart: lineStart[i],
          srcLines: srcLines,
          srcStart: srcStart,
          attrLine: attrLine,
          masked: masked,
          cuToByte: cuToByte,
        ));
        // Body-carrying members push a scope so accessor lines and
        // locals never classify (and pop exactly at the body close; an
        // expression-bodied member is popped by the very next line).
        if (grammarType == 'method_declaration' ||
            grammarType == 'constructor_declaration' ||
            grammarType == 'property_declaration') {
          scopes.add(_Scope(grammarType, name, beforeDepth + 1));
        }
        continue;
      }
    }
    // Anything else is content — never a symbol (honest v1).
  }
  return out;
}

bool atTopLevelGuard(int beforeDepth, int lineParen) =>
    beforeDepth == 0 && lineParen == 0;

(String, String)? _declOf(String trimmed) {
  final stripped = trimmed.replaceFirst(_modifiersRe, '');
  var m = _classRe.firstMatch(stripped);
  if (m != null) return ('class_declaration', m.group(1)!);
  m = _interfaceRe.firstMatch(stripped);
  if (m != null) return ('interface_declaration', m.group(1)!);
  m = _structRe.firstMatch(stripped);
  if (m != null) return ('struct_declaration', m.group(1)!);
  m = _enumRe.firstMatch(stripped);
  if (m != null) return ('enum_declaration', m.group(1)!);
  m = _recordRe.firstMatch(stripped);
  if (m != null) return ('record_declaration', m.group(1)!);
  return null;
}

/// The member head of a container-member line: `(name, grammarType)` or
/// null (content — never a symbol). Order: constructor → method →
/// property → field (a `(` head wins over the type heads; `{`/`=>` wins
/// over `=`/`;`).
(String, String)? _headOf(String stripped, String containerName) {
  final cm = _ctorRe.firstMatch(stripped);
  if (cm != null && cm.group(1) == containerName) {
    return (cm.group(1)!, 'constructor_declaration');
  }
  final mm = _methodRe.firstMatch(stripped);
  if (mm != null) return (mm.group(1)!, 'method_declaration');
  final pm = _propertyRe.firstMatch(stripped);
  if (pm != null) return (pm.group(1)!, 'property_declaration');
  final fm = _fieldRe.firstMatch(stripped);
  if (fm != null) return (fm.group(1)!, 'field_declaration');
  return null;
}

/// True when [i] and the contiguous lines above it are attribute-only
/// (`[…]`) — the span-absorption walk's input.
typedef _AttrLine = bool Function(int i);

CsSymbol _addSymbol({
  required String kind,
  required String grammarType,
  required String name,
  required String? parentName,
  required String mLine,
  required int lineIdx,
  required int lineStart,
  required List<String> srcLines,
  required List<int> srcStart,
  required _AttrLine attrLine,
  required String masked,
  required List<int> cuToByte,
}) {
  // Attribute absorption: the span starts at the `[` of the first line
  // of the contiguous attribute block immediately above (attributes RIDE
  // the declared span — ADR 0035 §6 brief). No phantom attribute nodes.
  final leadWs = mLine.length - mLine.trimLeft().length;
  var startCu = lineStart + leadWs;
  var walk = lineIdx - 1;
  var last = -1;
  while (walk >= 0 && attrLine(walk)) {
    last = walk;
    walk--;
  }
  if (last >= 0) {
    final aLine = srcLines[last];
    startCu = srcStart[last] + (aLine.length - aLine.trimLeft().length);
  }
  final endCu = _statementEnd(masked, lineStart + leadWs, _braceBodied(grammarType));
  return CsSymbol(
    kind: kind,
    grammarType: grammarType,
    name: name,
    parentName: parentName,
    startByte: cuToByte[startCu],
    endByte: cuToByte[endCu],
    line: lineIdx + 1,
    indent: leadWs,
  );
}

/// Brace-bodied grammar kinds: the span ends at the matching `}`
/// (methods/ctors/properties/containers); the rest end at `;`/EOL.
bool _braceBodied(String grammarType) =>
    grammarType == 'method_declaration' ||
    grammarType == 'constructor_declaration' ||
    grammarType == 'property_declaration' ||
    grammarType == 'class_declaration' ||
    grammarType == 'interface_declaration' ||
    grammarType == 'struct_declaration' ||
    grammarType == 'record_declaration' ||
    grammarType == 'enum_declaration' ||
    grammarType == 'namespace_declaration' ||
    grammarType == 'file_scoped_namespace_declaration';

/// The end (code-unit offset, exclusive) of a declaration: brace-bodied →
/// the matching `}` + 1; otherwise the first `;` at depth 0 + 1 (or the
/// last non-space char + 1 of the logical line — never a wrong span). A
/// brace-bodied declaration whose opener sits on a LATER line keeps
/// searching (bounded by 10 header lines — the scanner limit).
int _statementEnd(String masked, int startCu, bool braceBodied) {
  var brace = 0;
  var paren = 0;
  var bracket = 0;
  var sawBrace = false;
  var lastNonSpace = startCu;
  var headerLines = 0;
  for (var i = startCu; i < masked.length; i++) {
    final c = masked[i];
    if (c == '{') {
      brace++;
      sawBrace = true;
    } else if (c == '}') {
      brace--;
      if (braceBodied && sawBrace && brace == 0 && paren == 0) return i + 1;
    } else if (c == '(') {
      paren++;
    } else if (c == ')') {
      paren--;
    } else if (c == '[') {
      bracket++;
    } else if (c == ']') {
      bracket--;
    } else if (c == ';' && brace == 0 && paren == 0 && bracket == 0) {
      return i + 1;
    } else if (c == '\n' && brace == 0 && paren == 0 && bracket == 0) {
      if (braceBodied && !sawBrace) {
        // The body opener sits on a later line (multi-line header).
        headerLines++;
        if (headerLines > 10) return lastNonSpace + 1; // scanner limit
        continue;
      }
      // A brace-bodied declaration whose body never closed (scanner
      // limit) or an unterminated statement: end at the last content.
      return lastNonSpace + 1;
    }
    if (c != ' ' && c != '\t' && c != '\n' && c != '\r') lastNonSpace = i;
  }
  return masked.length;
}

/// The map parser the cs binding registers (ADR 0035 §2): scan → sub-node
/// DATA; the fs tier stamps ids/edges/budgets (prefix `csym_`,
/// binding-declared). Kind vocabulary = the scanner's (`sym`/`member`);
/// props carry the byte spans + the parent attachment (the zoom cut's
/// memberOf) + the grammar type (the anchor-resolution identity).
List<MappedSubNode> csMapParser(String content) {
  final usedTails = <String, int>{};
  return [
    for (final s in csScanSymbols(content))
      MappedSubNode(
        kind: s.kind,
        label: s.name,
        idTail: csSymbolIdTail(s, usedTails),
        props: {
          'symbol': s.name,
          'grammar_type': s.grammarType,
          if (s.parentName != null) 'member_of': s.parentName,
          'span_start': s.startByte,
          'span_end': s.endByte,
          'line': s.line,
          'indent': s.indent,
        },
      ),
  ];
}

// ---------------------------------------------------------------------------
// The convention half — the test runner the jail declares (honest null)
// ---------------------------------------------------------------------------

/// Resolves the test convention of the workspace at [root] through the
/// workspace-conventions pattern (mechanical, LLM-free): a jail carrying
/// a `*.csproj` project declares the .NET test runner — `dotnet test`.
/// No project → HONEST NULL (the host never invents a criterion the
/// workspace does not declare). DATA on the outcome — graded by the
/// verify tier, never claimed as run by the materializer.
List<String>? resolveCsConvention(Directory root) {
  final project = findCsProject(root);
  return project == null ? null : const ['dotnet', 'test'];
}

const _csWalkSkipDirs = {
  'bin',
  'obj',
  '.git',
  'build',
  '.dart_tool',
  'node_modules',
};

/// The first `*.csproj` in [rootDir] (root first, then a bounded walk
/// that skips bin/obj/build/VCS dirs). Null when the jail carries no
/// project. Workspace-relative when nested.
String? findCsProject(Directory rootDir) {
  if (!rootDir.existsSync()) return null;
  final rootPath =
      rootDir.path.endsWith('/') || rootDir.path.endsWith(r'\')
          ? rootDir.path.substring(0, rootDir.path.length - 1)
          : rootDir.path;
  for (final e in rootDir.listSync(followLinks: false)) {
    if (e is File && e.path.endsWith('.csproj')) {
      return e.uri.pathSegments.last;
    }
  }
  final stack = <Directory>[
    for (final e in rootDir.listSync(followLinks: false))
      if (e is Directory &&
          !_csWalkSkipDirs.contains(e.uri.pathSegments.reversed.skip(1).first))
        e,
  ];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    for (final e in dir.listSync(followLinks: false)) {
      if (e is File && e.path.endsWith('.csproj')) {
        final rel = e.path
            .substring(rootPath.length)
            .replaceAll('\\', '/')
            .replaceFirst(RegExp(r'^/'), '');
        return rel;
      }
      if (e is Directory &&
          !_csWalkSkipDirs.contains(e.uri.pathSegments.reversed.skip(1).first)) {
        stack.add(e);
      }
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// The binding realizations (ADR 0035 §1/§2) — the perform fn + the pack
// registry the cs binding registers. The router reaches them ONLY through
// the registry (class-routed); nothing dispatches on a kind switch.
// ---------------------------------------------------------------------------

/// The cs pack registry: pack-declared executables the cs materializer
/// serves (v1: authored-body executables only — the dart op-chain
/// compiler emits Dart, so op-chain kinds are honestly unsupported for
/// this class until the v2 emitter lands, ADR 0035 §6). Hosts REPLACE
/// this to wire the pack-write consent gate (deny-by-default — same law
/// as the span editor's packConsent); the model never authors the body.
EditPackRegistry csEditPacks = EditPackRegistry();

/// The cs binding's perform fn (the proven shape
/// `{action, anchor, body} → outcome.toJson()` over one request envelope —
/// zero-arg-delta, ADR 0035 §5).
Map<String, dynamic> csMaterializerPerform(NodeEditRequest r) =>
    CsMaterializer(root: r.root, locks: r.locks, owner: r.owner)
        .perform(action: r.action, anchor: r.anchor, body: r.body)
        .toJson();

/// Mechanical bounce BEFORE any byte is touched: error + the exact repair
/// move + navigable hints (mechanism-first, ADR 0035 §5 — the repair
/// names the read-program move and the node's own props, never a format).
class CsEditBounce implements Exception {
  CsEditBounce(this.error, this.repair, this.failureClass,
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

/// The outcome of a cs edit. Failures are classified data — never dropped.
class CsEditOutcome {
  const CsEditOutcome({
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
    this.convention,
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

  /// The jail's declared test convention (`dotnet test`) — DATA on the
  /// outcome; honest null when the jail declares none.
  final List<String>? convention;

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
        'convention': convention == null ? null : [...?convention],
      };
}

/// The cs materializer: plan (mechanical anchor re-resolution from a FRESH
/// scan — never stale tree offsets — + splice + byte fence, never touches
/// bytes) + apply (atomic write → `dotnet build` → auto-revert on
/// failure, with failure attribution). Single-writer via the shared
/// [FileLockTable] (the same table md/keypath/span editors claim).
class CsMaterializer {
  CsMaterializer({
    required this.root,
    FileLockTable? locks,
    this.owner = 'cs_materializer',
    this.dotnetBin,
    this.packs,
  }) : locks = locks ?? FileLockTable();

  final FsToolsRoot root;
  final FileLockTable locks;
  final Object owner;

  /// Analyzer override (host-injected; null → PATH).
  final String? dotnetBin;

  /// The pack registry (null → the package-level [csEditPacks]).
  final EditPackRegistry? packs;

  /// The body budget (body-as-data, budgeted): a single move past this
  /// bound bounces with the split-it repair move.
  static const maxCsBodyChars = 20000;

  static const actions = <String>{
    'insert_member',
    'remove_member',
    'apply_executable',
  };

  CsEditOutcome perform({
    required String action,
    required String anchor,
    String? body,
  }) {
    try {
      return _perform(action: action, anchor: anchor, body: body);
    } on CsEditBounce catch (b) {
      return CsEditOutcome(
        ok: false,
        reverted: false,
        bounce: true,
        op: action,
        path: '',
        anchor: anchor,
        detail: b.error,
        failureClass: b.failureClass,
        repair: b.repair,
        hints: b.hints,
        convention: resolveCsConvention(Directory(root.rootPath)),
      );
    }
  }

  CsEditOutcome _perform({
    required String action,
    required String anchor,
    required String? body,
  }) {
    if (!actions.contains(action)) {
      // Mechanism-first (§5): legality is the BINDING's declared union —
      // this bounce names THIS node's legal actions AND points at the
      // node's own edit_actions prop. Zero per-class recipe prose; the
      // v1 limitation (bodies via packs only) is taught by the union.
      throw CsEditBounce(
        'action "$action" is not legal for this node',
        're-send with action as one of: ${actions.toList()..sort()} — the '
            "node's edit_actions prop carries the same list AND the anchor "
            'currency; member-body text is pack-fed (apply_executable), '
            'never model-composed',
        'unknown_action',
      );
    }
    if (body != null && body.length > maxCsBodyChars) {
      throw CsEditBounce(
        'body over budget: ${body.length} chars (max $maxCsBodyChars)',
        'split the edit into multiple member moves (one anchor per '
            'move) — the budget is per move, the file is not',
        'body_over_budget',
      );
    }
    if (anchor.isEmpty) {
      throw CsEditBounce(
        'missing anchor (the node id to edit)',
        'run the read program (locate, then zoom the target) — zoom rows '
            'stamp the id; re-send with the stamped node id as anchor',
        'anchor_not_found',
      );
    }
    final path = _fileOfAnchor(anchor);
    if (path == null) {
      throw CsEditBounce(
        'anchor "$anchor" does not name a scanned file',
        're-send with the stamped node id from the zoom cut '
            '(csym_<file>_<symbol>) — zoom the file node for the outline',
        'anchor_not_found',
      );
    }
    final abs = root.resolve(path);
    final f = File(abs);
    if (!f.existsSync()) {
      throw CsEditBounce(
        'file not found: $path',
        'the file moved under the tree — refresh the tree (repo_etl '
            'scan) and re-zoom',
        'file_not_found',
      );
    }
    final content = f.readAsStringSync();
    final before = csScanSymbols(content);
    final target = _resolveTail(anchor, before, path, content);
    final convention = resolveCsConvention(Directory(root.rootPath));

    final plan = switch (action) {
      'insert_member' => _planInsert(target, before, content, body, path),
      'remove_member' => _planRemove(target, before, content, path),
      'apply_executable' => _planApplyExecutable(
          target, before, content, path, (body ?? '').trim()),
      _ => throw CsEditBounce(
          'unknown action: $action', 'host bug — report as data', 'unknown_action'),
    };
    final spliced = plan.content;
    final description = plan.description;

    // BYTE FENCE: everything outside the touched span must be
    // byte-identical (mechanically asserted — the emitter edits ONLY the
    // member span boundary).
    _assertByteFence(content, spliced, plan.touchedStart, plan.touchedEnd);

    // ORACLE AVAILABILITY — before any byte is touched: the named
    // analyzer must exist (PATH, or the host-injected override) AND a
    // project file must be gradeable. Unavailable = a NAMED bounce,
    // never a silent pass.
    final oracle = _resolveAnalyzer();
    if (oracle == null) {
      throw CsEditBounce(
        'the named analyzer oracle (dotnet_build) is unavailable: no '
            'binary on PATH',
        'install the .NET SDK (the analyzer ships as `dotnet` on PATH) '
            'or wire the analyzer path — edits to this class never land '
            'unverified',
        'oracle_unavailable',
      );
    }
    final project = findCsProject(Directory(root.rootPath));
    if (project == null) {
      throw CsEditBounce(
        'the named analyzer oracle (dotnet_build) cannot grade this '
            'jail: no *.csproj project file found',
        'stage a project file for the jail (the build is the grading '
            'unit) — edits to this class never land unverified',
        'oracle_unavailable',
      );
    }

    return _apply(
      path: path,
      original: content,
      spliced: spliced,
      description: description,
      touchedStart: plan.touchedStart,
      touchedEnd: plan.touchedEnd,
      before: before,
      action: action,
      anchor: anchor,
      targetSymbol: target.symbol,
      oracleInfo: (oracle: oracle, project: project),
      convention: convention,
      exeId: action == 'apply_executable' ? (body ?? '').trim() : null,
    );
  }

  // -- anchor resolution (fresh scan; ids recomputed, never tree offsets) --

  /// The workspace-relative file an anchor belongs to: the id form is
  /// `csym_<fileNodeId>_<idTail>` and the file node id is
  /// `f_<rel with / → _>`.
  String? _fileOfAnchor(String anchor) {
    if (!anchor.startsWith('csym_')) return null;
    // The id form is `csym_<fileNodeId>_<idTail>` and the file node id is
    // `f_<rel with / → _>` (fs_etl) — BOTH parts may contain underscores
    // (the rel itself is path-flattened), so the file/tail boundary is
    // resolved by matching against the files the jail actually scans
    // (longest file id wins; file ids are unique per file).
    final candidates = <String>[];
    final rootDir = Directory(root.rootPath);
    if (!rootDir.existsSync()) return null;
    final stack = <Directory>[rootDir];
    while (stack.isNotEmpty) {
      final dir = stack.removeLast();
      for (final e in dir.listSync(followLinks: false)) {
        if (e is Directory) {
          if (!_csWalkSkipDirs
              .contains(e.uri.pathSegments.reversed.skip(1).first)) {
            stack.add(e);
          }
          continue;
        }
        if (e is! File) continue;
        final rel = e.path
            .substring(rootDir.path.length)
            .replaceAll('\\', '/')
            .replaceFirst(RegExp(r'^/'), '');
        if (rel.endsWith('.cs')) {
          candidates.add(rel);
        }
      }
    }
    candidates.sort((a, b) => b.length.compareTo(a.length));
    for (final rel in candidates) {
      final fileId = 'f_${rel.replaceAll('/', '_')}';
      if (anchor.startsWith('csym_$fileId') &&
          anchor.length > 'csym_'.length + fileId.length) {
        return rel;
      }
    }
    return null;
  }

  _ResolvedTarget _resolveTail(
    String anchor,
    List<CsSymbol> symbols,
    String path,
    String content,
  ) {
    // The file id is `f_<rel with / → _>` — the tail is the anchor's
    // remainder after `csym_<fileId>_` (same boundary [_fileOfAnchor]
    // resolved; both parts may contain underscores, so the prefix comes
    // from the RESOLVED path, never a guess).
    final fileId = 'f_${path.replaceAll('/', '_')}';
    final prefix = 'csym_$fileId';
    if (!anchor.startsWith('$prefix')) {
      throw CsEditBounce(
        'anchor "$anchor" does not name a node of $path',
        're-send with the stamped node id from the zoom cut '
            '(csym_<file>_<symbol>) — zoom the file node for the outline',
        'anchor_not_found',
      );
    }
    final tail = anchor.substring(prefix.length + 1);
    // Recompute the SAME id tails over the fresh scan (deterministic) —
    // the anchor is the id, the span comes from CURRENT bytes.
    final usedTails = <String, int>{};
    final byTail = <String, CsSymbol>{
      for (final s in symbols) csSymbolIdTail(s, usedTails): s,
    };
    final hit = byTail[tail];
    if (hit == null) {
      throw CsEditBounce(
        'anchor "$anchor" does not resolve in the current bytes of $path '
            '(the file changed since the tree was built?)',
        'refresh the tree (repo_etl scan), re-zoom the file node, then '
            're-send the stamped id',
        'anchor_not_found',
        hints: _outlineHints(symbols),
      );
    }
    // Unsupported-shape honesty: a symbol the scanner cannot span
    // reliably is never served to the emitter (empty/degenerate span).
    if (hit.endByte <= hit.startByte) {
      throw CsEditBounce(
        'symbol "${hit.name}" has no reliable span in the current bytes '
            '(${hit.grammarType})',
        'restructure the declaration to a plain shape (the scanner '
            'spans plain declarations) or route the move through the '
            'review gate',
        'unsupported_shape',
      );
    }
    return _ResolvedTarget(anchor, tail, hit);
  }

  List<String> _outlineHints(List<CsSymbol> symbols) => [
        for (final s in symbols.take(12))
          'csym ${s.kind} ${s.grammarType} ${s.name}'
              '${s.parentName == null ? '' : ' (in ${s.parentName})'} '
              '(line ${s.line})',
        if (symbols.isEmpty)
          'this file has no indexed symbols — the map needs plain '
              'declarations (v1 scanner)',
        if (symbols.length > 12)
          '…${symbols.length - 12} more — zoom the file node for the full '
              'outline',
      ];

  // -- op emitters (byte-precise splices + fences) --------------------------

  ({String content, String description, int touchedStart, int touchedEnd})
      _planInsert(
    _ResolvedTarget target,
    List<CsSymbol> before,
    String content,
    String? body,
    String path,
  ) {
    final s = target.symbol;
    if (!_containerKinds.contains(s.grammarType)) {
      throw CsEditBounce(
        '"${s.name}" is a ${s.grammarType} — insert_member targets a '
            'DECLARING body (a container node from the zoom cut)',
        'zoom the declaring parent (its sym node owns the body) and '
            're-send the move with that node id as anchor',
        'not_a_container',
      );
    }
    if (body == null || body.trim().isEmpty) {
      throw CsEditBounce(
        'missing body',
        're-send with body as the new member source (data — the '
            'dotnet_build oracle verifies it before it lands)',
        'invalid_body',
      );
    }
    if (body.contains(r'\\') && _unbalanced(body)) {
      throw CsEditBounce(
        'body has unbalanced braces/parens/brackets',
        're-send the member source balanced — a partial construct cannot '
            'splice',
        'unbalanced_body',
      );
    }
    final cuToByte = _utf16ToUtf8Map(content);
    // Brace-aware: the container's body span (first `{` at depth 0 from
    // the declaration start → its match). Honest bounce when the braces
    // cannot be matched (never a wrong splice).
    final bodySpan = _containerBodySpan(content, s, cuToByte);
    if (bodySpan == null) {
      throw CsEditBounce(
        '"${s.name}" body braces cannot be matched in the current bytes',
        'the declaration must be a plain brace body to splice into — '
            'route the move through the review gate otherwise',
        'unsupported_shape',
      );
    }
    final closeCu = bodySpan.$2;
    final closeLineStart = content.lastIndexOf('\n', closeCu - 1) + 1;
    final beforeClose = content.substring(closeLineStart, closeCu);
    final closeBraceAlone = beforeClose.trim().isEmpty;
    // Member indent: existing members of this container, else opener
    // indent + 4 (the convention C# style guides encode).
    final openLineStart =
        content.lastIndexOf('\n', bodySpan.$1 - 1 < 0 ? 0 : bodySpan.$1 - 1) + 1;
    var containerIndent = 0;
    for (var i = openLineStart; i < content.length && content[i] == ' '; i++) {
      containerIndent++;
    }
    var memberIndent = containerIndent + 4;
    for (final m in before) {
      if (m.kind == 'member' && m.parentName == s.name) {
        // Recover the member's leading spaces from the source line.
        final ls = _lineStartOfByte(content, m.startByte, cuToByte);
        var ind = 0;
        while (ls + ind < content.length && content[ls + ind] == ' ') {
          ind++;
        }
        if (ind > containerIndent) {
          memberIndent = ind;
          break;
        }
      }
    }
    final pad = ' ' * memberIndent;
    final lines = body.trimRight().split('\n');
    final minIndent = _minIndentOf(lines);
    final reindented = [
      for (final l in lines)
        l.trim().isEmpty ? '' : '$pad${l.substring(minIndent.clamp(0, l.length))}',
    ];
    final insertAt = closeBraceAlone ? closeLineStart : closeCu;
    final text =
        '${closeBraceAlone ? '' : '\n'}${reindented.join('\n')}\n';
    final spliced = content.replaceRange(insertAt, insertAt, text);
    return (
      content: spliced,
      description: 'insert_member into ${s.name} (${target.anchor}) in '
          '$path (line ${_lineOf(content, insertAt)})',
      touchedStart: insertAt,
      touchedEnd: insertAt + text.length,
    );
  }

  ({String content, String description, int touchedStart, int touchedEnd})
      _planRemove(
    _ResolvedTarget target,
    List<CsSymbol> before,
    String content,
    String path,
  ) {
    final s = target.symbol;
    if (s.kind != 'member' && s.kind != 'sym') {
      throw CsEditBounce(
        'unsupported kind for remove_member',
        'host bug — report as data',
        'unsupported_shape',
      );
    }
    final cuToByte = _utf16ToUtf8Map(content);
    final startCu = _byteToCu(cuToByte, s.startByte);
    final endCu = _byteToCu(cuToByte, s.endByte);
    final lineStart = content.lastIndexOf('\n', startCu - 1) + 1;
    var lineEnd = content.indexOf('\n', endCu);
    if (lineEnd < 0) {
      lineEnd = content.length;
    } else {
      lineEnd += 1;
    }
    final spliced = content.replaceRange(lineStart, lineEnd, '');
    return (
      content: spliced,
      description: 'remove_member ${s.name} (${target.anchor}) in $path '
          '(lines ${_lineOf(content, lineStart)})',
      touchedStart: lineStart,
      touchedEnd: lineEnd,
    );
  }

  ({String content, String description, int touchedStart, int touchedEnd})
      _planApplyExecutable(
    _ResolvedTarget target,
    List<CsSymbol> before,
    String content,
    String path,
    String exeId,
  ) {
    if (exeId.isEmpty) {
      throw CsEditBounce(
        'missing executable id',
        're-send with body as the executable id from the pack (the '
            'body travels with the PACK — you supply ids only)',
        'invalid_body',
      );
    }
    final registry = packs ?? csEditPacks;
    final wire = registry.executables[exeId];
    if (wire == null) {
      throw CsEditBounce(
        'unknown executable: $exeId',
        'locate the pack inventory in the tree (the capability nodes) '
            'and re-send a registered executable id',
        'unknown_executable',
      );
    }
    if (wire.kind.wire != 'authored_body') {
      // v1 honesty: op-chain kinds compile DART only — unsupported for
      // this class until the v2 emitter lands (ADR 0035 §6, evidence-
      // gated). Named, never silent.
      throw CsEditBounce(
        'executable "$exeId" is kind ${wire.kind.wire} — op-chain '
            'executables compile Dart only; this class serves '
            'authored-body executables in v1',
        'declare the pack entry with kind: authored_body (consented at '
            'pack-write) or land the op-chain emitter (v2, measured)',
        'unsupported_executable',
      );
    }
    final authored = registry.authoredBodies[exeId];
    if (authored == null || authored.trim().isEmpty) {
      throw CsEditBounce(
        'executable "$exeId" carries no consented body',
        'fix the pack entry — the consent gate never passes an empty '
            'body',
        'unsupported_executable',
      );
    }
    final s = target.symbol;
    const bodyKinds = {
      'method_declaration',
      'constructor_declaration',
    };
    if (!bodyKinds.contains(s.grammarType)) {
      throw CsEditBounce(
        '"${s.name}" is a ${s.grammarType} — authored bodies replace the '
            'bodies of brace-bodied executable members only',
        'target a brace-bodied member node from the zoom cut',
        'unsupported_shape',
      );
    }
    final cuToByte = _utf16ToUtf8Map(content);
    final startCu = _byteToCu(cuToByte, s.startByte);
    final endCu = _byteToCu(cuToByte, s.endByte);
    final openCu = _firstOpenBrace(content, startCu, endCu);
    if (openCu == null) {
      throw CsEditBounce(
        '"${s.name}" carries no brace body to replace',
        'the member must be brace-bodied — expression-bodied members and '
            'signatures have no body span',
        'unsupported_shape',
      );
    }
    var closeCu = _matchingClose(content, openCu);
    if (closeCu == null) {
      throw CsEditBounce(
        '"${s.name}" body braces cannot be matched in the current bytes',
        'the body must be a plain brace body to splice into',
        'unsupported_shape',
      );
    }
    final memberIndent = _indentAt(content, startCu);
    final bodyIndent = ' ' * (memberIndent + 4);
    final bodyText = authored
        .trim()
        .split('\n')
        .map((l) => l.trim().isEmpty ? '' : '$bodyIndent$l')
        .join('\n');
    final spliced = content.replaceRange(
      openCu + 1,
      closeCu,
      '\n$bodyText\n${' ' * memberIndent}',
    );
    return (
      content: spliced,
      description: 'apply_executable $exeId (authored body) ${s.name} '
          '(${target.anchor}) in $path',
      touchedStart: _byteToCu(cuToByte, s.startByte),
      touchedEnd: _byteToCu(cuToByte, s.endByte),
    );
  }

  // -- apply: atomic write + dotnet_build + scan envelope + auto-revert -----

  CsEditOutcome _apply({
    required String path,
    required String original,
    required String spliced,
    required String description,
    required int touchedStart,
    required int touchedEnd,
    required List<CsSymbol> before,
    required String action,
    required String anchor,
    required CsSymbol targetSymbol,
    required ({String oracle, String project}) oracleInfo,
    required List<String>? convention,
    String? exeId,
  }) {
    final rel = path;
    if (!locks.claim(rel, owner)) {
      final holder = locks.ownerOf(rel);
      return CsEditOutcome(
        ok: false,
        reverted: false,
        op: action,
        path: rel,
        anchor: anchor,
        detail: 'lock conflict on $rel (held by $holder) — the move '
            'claimed no bytes',
        failureClass: 'lock_conflict',
        convention: convention,
      );
    }
    try {
      final abs = root.resolve(rel);
      final f = File(abs);
      // STRUCTURAL ENVELOPE — the fresh post-splice scan must differ by
      // EXACTLY the intended symbol change (the parse_semantic_diff
      // discipline, class-shaped): nothing more, nothing elsewhere.
      final after = csScanSymbols(spliced);
      final violation = _envelopeViolation(action, before, after, targetSymbol);
      if (violation != null) {
        return CsEditOutcome(
          ok: false,
          reverted: false,
          op: action,
          path: rel,
          anchor: anchor,
          detail: 'the splice would change symbols beyond the intended '
              'move: $violation — no bytes written',
          failureClass: 'scan_envelope_mismatch',
          hints: const [
            'check the body against the zoomed span and re-send the move',
          ],
          convention: convention,
        );
      }
      f.writeAsStringSync(spliced, flush: true);
      // THE NAMED ORACLE — dotnet build after EVERY apply.
      final check = _runDotnet(oracleInfo.oracle, oracleInfo.project);
      if (!check.ok) {
        // AUTO-REVERT: a failing check never lands.
        f.writeAsStringSync(original, flush: true);
        return CsEditOutcome(
          ok: false,
          reverted: true,
          op: action,
          path: rel,
          anchor: anchor,
          detail: 'dotnet_build FAILED after $description — ALL bytes '
              'reverted (${_oneLine(check.output)})',
          failureClass: check.failureClass,
          hints: const [
            'fix the member source against the analyzer report and '
                're-send the move — the edit must satisfy 0 build '
                'errors to land',
          ],
          convention: convention,
        );
      }
      return CsEditOutcome(
        ok: true,
        reverted: false,
        op: action,
        path: rel,
        anchor: anchor,
        detail: '$description — spliced byte-precise '
            '(${original.length} → ${spliced.length} bytes); dotnet_build '
            'green. The tree re-derives the symbol map on the next tick.'
            '${convention == null ? '' : ' Test convention: ${convention.join(" ")} (verify tier).'}',
        convention: convention,
      );
    } finally {
      locks.release(rel, owner);
    }
  }

  /// The envelope each op's post-scan must satisfy — null when green.
  String? _envelopeViolation(
    String action,
    List<CsSymbol> before,
    List<CsSymbol> after,
    CsSymbol target,
  ) {
    String key(CsSymbol s) =>
        '${s.kind}|${s.grammarType}|${s.parentName ?? ''}|${s.name}';
    final beforeKeys = [for (final s in before) key(s)];
    final afterKeys = [for (final s in after) key(s)];
    final beforeBag = <String, int>{};
    for (final k in beforeKeys) {
      beforeBag[k] = (beforeBag[k] ?? 0) + 1;
    }
    final afterBag = <String, int>{};
    for (final k in afterKeys) {
      afterBag[k] = (afterBag[k] ?? 0) + 1;
    }
    final added = <String>[];
    final removed = <String>[];
    for (final e in afterBag.entries) {
      final delta = e.value - (beforeBag[e.key] ?? 0);
      for (var i = 0; i < delta; i++) {
        added.add(e.key);
      }
    }
    for (final e in beforeBag.entries) {
      final delta = e.value - (afterBag[e.key] ?? 0);
      for (var i = 0; i < delta; i++) {
        removed.add(e.key);
      }
    }
    switch (action) {
      case 'insert_member':
        if (removed.isNotEmpty) {
          return 'symbols removed: $removed';
        }
        if (added.length != 1 || !added.single.contains('|${target.name}')) {
          return 'expected exactly 1 added member under "${target.name}", '
              'got: $added';
        }
        return null;
      case 'remove_member':
        if (added.isNotEmpty) {
          return 'symbols added: $added';
        }
        if (removed.length != 1 || removed.single != key(target)) {
          return 'expected exactly the target removed (${key(target)}), got '
              '$removed';
        }
        return null;
      case 'apply_executable':
        if (added.isNotEmpty || removed.isNotEmpty) {
          return 'a body replacement must change NO symbols: added '
              '$added, removed $removed';
        }
        return null;
      default:
        return 'unknown action $action';
    }
  }

  // -- the analyzer oracle ---------------------------------------------------

  /// Resolves the analyzer binary: the jail-local `.dotnet/dotnet`
  /// first (the jail's own toolchain — the mirror of the ts jail's
  /// `node_modules/.bin/tsc`), then PATH (the .NET SDK ships `dotnet`
  /// on PATH), or the host-injected override. Null → unavailable (the
  /// named pre-apply bounce).
  String? _resolveAnalyzer() {
    if (dotnetBin != null) {
      // Host-injected override — trust it verbatim (availability is
      // proven by the run itself).
      return dotnetBin!;
    }
    final jailBin = File('${root.rootPath}/.dotnet/dotnet');
    if (jailBin.existsSync()) {
      return jailBin.path;
    }
    try {
      final probe = Process.runSync('dotnet', const ['--version']);
      if (probe.exitCode == 0) {
        return 'dotnet';
      }
      // ignore: avoid_catching_errors
    } on ProcessException {
      return null;
    }
    return null;
  }

  ({bool ok, String failureClass, String output}) _runDotnet(
    String oracle,
    String project,
  ) {
    final args = ['build', project];
    final ProcessResult r;
    try {
      r = Process.runSync(oracle, args, workingDirectory: root.rootPath);
    } on ProcessException catch (e) {
      return (ok: false, failureClass: 'oracle_unavailable', output: '$e');
    }
    if (r.exitCode != 0) {
      return (
        ok: false,
        failureClass: 'cs_error',
        output: '${r.stderr}${r.stdout}',
      );
    }
    return (ok: true, failureClass: '', output: '');
  }

  // -- splice helpers --------------------------------------------------------

  /// The container's body span (code units): the first `{` at depth 0
  /// from the declaration start → its match. Null when unmatchable.
  (int, int)? _containerBodySpan(
    String content,
    CsSymbol s,
    List<int> cuToByte,
  ) {
    final masked = _maskContent(content);
    final startCu = _byteToCu(cuToByte, s.startByte);
    final openCu = _firstOpenBrace(masked, startCu, masked.length);
    if (openCu == null) return null;
    final closeCu = _matchingClose(masked, openCu);
    if (closeCu == null) return null;
    return (openCu, closeCu);
  }

  int? _firstOpenBrace(String masked, int from, int to) {
    var depth = 0;
    for (var i = from; i < to && i < masked.length; i++) {
      final c = masked[i];
      if (c == '{') {
        if (depth == 0) return i;
        depth++;
      } else if (c == '}') {
        depth--;
      }
    }
    return null;
  }

  int? _matchingClose(String masked, int openCu) {
    var depth = 0;
    for (var i = openCu; i < masked.length; i++) {
      final c = masked[i];
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return null;
  }

  bool _unbalanced(String body) {
    var depth = 0;
    for (final c in _maskContent(body).split('\n').join(' ').split('')) {
      if (c == '{' || c == '(' || c == '[') {
        depth++;
      } else if (c == '}' || c == ')' || c == ']') {
        depth--;
        if (depth < 0) return true;
      }
    }
    return depth != 0;
  }

  int _minIndentOf(List<String> lines) {
    var min = 1 << 30;
    for (final l in lines) {
      if (l.trim().isEmpty) continue;
      var n = 0;
      while (n < l.length && l[n] == ' ') {
        n++;
      }
      if (n < min) min = n;
    }
    return min == 1 << 30 ? 0 : min;
  }

  int _indentAt(String content, int cu) {
    final ls = content.lastIndexOf('\n', cu - 1) + 1;
    var n = 0;
    while (ls + n < content.length && content[ls + n] == ' ') {
      n++;
    }
    return n;
  }

  int _lineStartOfByte(String content, int byte, List<int> cuToByte) {
    final cu = _byteToCu(cuToByte, byte);
    return content.lastIndexOf('\n', cu - 1 < 0 ? 0 : cu - 1) + 1;
  }

  int _lineOf(String content, int cu) =>
      content.substring(0, cu).split('\n').length;

  int _byteToCu(List<int> cuToByte, int byte) {
    for (var i = 0; i < cuToByte.length; i++) {
      if (cuToByte[i] >= byte) return i;
    }
    return cuToByte.length - 1;
  }

  /// The BYTE FENCE: bytes before [touchedStart] and after [touchedEnd]
  /// (in original coordinates) must be byte-identical in the spliced
  /// content — mechanically asserted at plan time.
  void _assertByteFence(
    String original,
    String spliced,
    int touchedStart,
    int touchedEnd,
  ) {
    final origPrefix = original.substring(0, touchedStart.clamp(0, original.length));
    if (spliced.length < origPrefix.length ||
        spliced.substring(0, origPrefix.length) != origPrefix) {
      throw CsEditBounce(
        'the emitter touched bytes before the target span (byte fence '
            'violated)',
        'host bug — report as data: member_splice edits ONLY the target '
            'span boundary',
        'emitter_violation',
      );
    }
    final origSuffix = original.substring(
        touchedEnd.clamp(0, original.length) > original.length
            ? original.length
            : touchedEnd.clamp(0, original.length));
    if (!spliced.endsWith(origSuffix)) {
      throw CsEditBounce(
        'the emitter touched bytes after the target span (byte fence '
            'violated)',
        'host bug — report as data: member_splice edits ONLY the target '
            'span boundary',
        'emitter_violation',
      );
    }
  }
}

class _ResolvedTarget {
  _ResolvedTarget(this.anchor, this.tail, this.symbol);
  final String anchor;
  final String tail;
  final CsSymbol symbol;
}

String _oneLine(Object e) =>
    '$e'.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');

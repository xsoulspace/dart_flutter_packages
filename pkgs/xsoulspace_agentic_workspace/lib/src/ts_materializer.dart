// ignore_for_file: lines_longer_as_80_chars

/// The TS MATERIALIZER (ADR 0035 §6 — Tier C v1, the first full-code
/// non-Dart family). The binding is the unit of extension (ADR 0035 §1):
/// this file + one registry entry (materializer_binding.dart) land the
/// whole `ts` class; the engine, router, fs tier and model surface are
/// closed code.
///
/// The spec is DATA — registered as the ts BINDING in
/// `materializer_binding.dart` (the fs tier stamps `edit_actions` on ts
/// file nodes):
/// `{fileClass: ts, span currency: member_span (UTF-8 byte spans — the
/// meaning-tree span-prop currency), map format: symbol_tree,
/// emitter: member_splice, oracle: tsc_no_emit, anchors: node_id}`.
///
/// MAP HALF (Tier C v1 — the mechanical, dependency-light scanner, repo
/// precedent: `scanDartFile`, regex md headings, indentation keypaths):
/// [tsScanSymbols] extracts symbols AND MEMBER SYMBOLS day one (decision
/// 2026-09-07) — class/interface/enum/function/type-alias declarations as
/// `sym` nodes; methods, signatures, fields and const/let/var
/// declarations as `member` nodes under their declaring parent — using
/// the SAME node-kind vocabulary as the tree-sitter spike
/// (xsoulspace_treesitter_raw's mapping table: `sym`/`member`/`file` and
/// the tree-sitter grammar types, so the conformance delta is measurable
/// as data, ADR 0035 §8 item 5). Spans are BYTE-precise (UTF-8 byte
/// offsets — the span reader's currency; the multibyte discipline).
/// Shapes the scanner cannot span reliably are honestly OMITTED or
/// bounced (`unsupported_shape`) — never a wrong span.
///
/// EDIT HALF — actions REUSE the dart names VERBATIM (ADR 0035 §5;
/// class-agnostic semantics):
/// - `insert_member {anchor: declaring sym node, body}` — brace-aware
///   member insertion at the container's closing-brace boundary,
///   byte-precise (everything outside the touched span byte-identical);
/// - `remove_member {anchor: member node}` — full-line removal of the
///   member's span, byte-precise;
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
/// NAMED ORACLE `tsc_no_emit`: after EVERY apply, `tsc --noEmit` grades
/// the jail (project tsconfig when present, else the edited file). The
/// analyzer binary resolves from the jail's `node_modules/.bin/tsc`
/// first, then `PATH`. When the analyzer is UNAVAILABLE the move bounces
/// with failureClass `oracle_unavailable` BEFORE any byte is touched —
/// named, never a silent pass (the honesty law, ADR 0024 §6). A failing
/// check AUTO-REVERTS with failureClass `tsc_error`. The test convention
/// (vitest/jest, resolved from the jail's package.json through the
/// workspace-conventions pattern) rides the outcome as DATA — it is
/// graded by the verify tier, never silently claimed here (honest null
/// when the jail declares no runner).
library;

import 'dart:convert';
import 'dart:io';

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FileLockTable, FsToolsRoot;

import 'edit_pack.dart' show EditPackRegistry;
import 'file_class_spec.dart' show MappedSubNode;
import 'materializer_binding.dart' show NodeEditRequest;

// ---------------------------------------------------------------------------
// The map half — the ONE ts symbol scanner (fs tier's map builder + this
/// emitter share it, so zoom anchors and splice anchors agree byte-precise)
// ---------------------------------------------------------------------------

/// One scanned ts symbol (pure data; spans in UTF-8 BYTE offsets — the
/// meaning-tree span-prop currency). [grammarType] uses the tree-sitter
/// node-kind vocabulary (the spike's mapping table), so scanner output is
/// directly comparable to the FFI mapper's output (ADR 0035 §8 delta).
class TsSymbol {
  const TsSymbol({
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

  /// The tree-sitter grammar node kind (the shared vocabulary):
  /// class_declaration, abstract_class_declaration, interface_declaration,
  /// enum_declaration, type_alias_declaration, function_declaration,
  /// generator_function_declaration, method_definition, method_signature,
  /// property_signature, public_field_definition, lexical_declaration,
  /// variable_declaration.
  final String grammarType;
  final String name;

  /// The declaring parent's name (members only); null → attached to the
  /// file (the spike's `memberOf: file` semantics — nearest mapped
  /// ancestor, else the file).
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
      'TsSymbol($kind $grammarType $name'
      '${parentName == null ? '' : ' <- $parentName'}, '
      'bytes $startByte..$endByte, line $line)';
}

/// The stable sub-node id tail for [s]: syms by name; members by
/// `<parent>_<name>` (bare `<name>` when file-attached). Same-name shapes
/// (overloads) get a deterministic `_2`/`_3` ordinal suffix in scan order
/// — the SAME scheme the materializer's fresh-scan anchor resolution
/// recomputes, so zoom ids and splice anchors agree.
String tsSymbolIdTail(TsSymbol s, Map<String, int> usedTails) {
  final bare = s.kind == 'sym'
      ? s.name
      : (s.parentName == null ? s.name : '${s.parentName}_${s.name}');
  final key = '${s.kind}|${s.grammarType}|${s.parentName ?? ''}|$bare';
  final count = (usedTails[key] ?? 0) + 1;
  usedTails[key] = count;
  return count == 1 ? bare : '${bare}_$count';
}

// -- masked view: strings / templates / comments are INERT (ADR 0019) ------

/// Returns [src] with every character inside strings ('…'/"…"), template
/// literals (`…`, `${…}` masked whole) and comments replaced by spaces —
/// same length, same newlines. Braces/parens inside masked regions stop
/// counting as structure; a brace inside a string can never corrupt the
/// depth tracking or a splice.
String _maskContent(String src) {
  // Start from the SOURCE code units; masked regions are overwritten with
  // spaces below — same length, same newlines.
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
    if (c == '"' || c == "'" || c == '`') {
      final quote = c;
      i++; // keep the opening delimiter position (masked below)
      out[i - 1] = 0x20;
      while (i < src.length && src[i] != quote) {
        if (src[i] == r'\\' && i + 1 < src.length && src[i + 1] != '\n') {
          out[i] = 0x20;
          out[i + 1] = 0x20;
          i += 2;
          continue;
        }
        if (src[i] != '\n') out[i] = 0x20;
        i++;
      }
      if (i < src.length) {
        out[i] = 0x20; // closing delimiter
        i++;
      }
      continue;
    }
    i++;
  }
  return String.fromCharCodes(out);
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

// -- declaration patterns (the tree-sitter grammar-type vocabulary) --------

final RegExp _identRe = RegExp(r'[\p{L}_$][\p{L}\p{N}_$]*', unicode: true);
final RegExp _classRe = RegExp(
  r'^(?:export\s+)?(?:default\s+)?(abstract\s+)?class\s+([\p{L}_$][\p{L}\p{N}_$]*)',
  unicode: true,
);
final RegExp _interfaceRe = RegExp(
  r'^(?:export\s+)?interface\s+([\p{L}_$][\p{L}\p{N}_$]*)',
  unicode: true,
);
final RegExp _enumRe = RegExp(
  r'^(?:export\s+)?(?:const\s+)?enum\s+([\p{L}_$][\p{L}\p{N}_$]*)',
  unicode: true,
);
final RegExp _typeAliasRe = RegExp(
  r'^(?:export\s+)?type\s+([\p{L}_$][\p{L}\p{N}_$]*)\s*=',
  unicode: true,
);
final RegExp _functionRe = RegExp(
  r'^(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*(\*)?\s*'
  r'([\p{L}_$][\p{L}\p{N}_$]*)',
  unicode: true,
);
final RegExp _varDeclRe = RegExp(
  r'^(?:export\s+)?(?:declare\s+)?(const|let|var)\s+([\p{L}_$][\p{L}\p{N}_$]*)',
  unicode: true,
);
final RegExp _modifiersRe = RegExp(
  r'^(?:(?:public|private|protected|readonly|static|abstract|override|async|declare)\s+)+',
);
final RegExp _accessorRe = RegExp(
  r'^(get|set)\s+([\p{L}_$][\p{L}\p{N}_$]*)\s*(?:<[^>()]*>)?\s*\(',
  unicode: true,
);
final RegExp _methodRe = RegExp(
  r'^([\p{L}_$][\p{L}\p{N}_$]*)\s*(?:<[^>()]*>)?\s*\(',
  unicode: true,
);
final RegExp _fieldTypeRe = RegExp(
  r'^([\p{L}_$][\p{L}\p{N}_$]*)\s*[?!]?\s*:',
  unicode: true,
);
final RegExp _fieldInitRe = RegExp(
  r'^([\p{L}_$][\p{L}\p{N}_$]*)\s*[?!]?\s*=',
  unicode: true,
);

/// One open lexical scope (a mapped ancestor the member attachment
/// resolves against — the scanner-side equivalent of the spike's
/// `ancestorStack`).
class _Scope {
  _Scope(this.grammarType, this.name, this.entryDepth);
  final String grammarType;
  final String name;

  /// Absolute brace depth INSIDE the body (depth right after the opener).
  final int entryDepth;
}

/// Scans [content] into symbols: line/brace-based extraction (dependency-
/// light, deterministic). Honest v1 limitations (never a wrong span):
/// nested-block declarations (inside `if`/loop bodies) are not indexed;
/// the first declarator of a multi-declarator statement only; enum
/// members are not indexed (the spike's mapping table has no entry);
/// decorators are skipped without phantom symbols.
List<TsSymbol> tsScanSymbols(String content) {
  final masked = _maskContent(content);
  final maskedLines = masked.split('\n');
  final lines = content.split('\n');
  final cuToByte = _utf16ToUtf8Map(content);
  // Cumulative depth at each line start.
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
  lineStart[maskedLines.length] = off - 1 < 0 ? 0 : masked.length;

  final out = <TsSymbol>[];
  final scopes = <_Scope>[];
  final usedTails = <String, int>{};
  final tailsBySymbol = <int, String>{}; // scan index → idTail

  for (var i = 0; i < maskedLines.length; i++) {
    final mLine = maskedLines[i];
    final trimmed = mLine.trim();
    final lineParen = parenAtLine[i];
    var depth = braceAtLine[i];
    // Pop scopes whose body closed on an earlier line.
    while (scopes.isNotEmpty && depth < scopes.last.entryDepth) {
      scopes.removeLast();
    }
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('@')) continue; // decorators: never symbols
    if (trimmed.startsWith('//') || trimmed.startsWith('/*')) continue;

    // Where are we? depth 0 = file level; inside a class/interface body =
    // top of stack is a container AND depth == its entryDepth.
    final inContainer =
        scopes.isNotEmpty &&
        (scopes.last.grammarType == 'class_declaration' ||
            scopes.last.grammarType == 'abstract_class_declaration' ||
            scopes.last.grammarType == 'interface_declaration') &&
        depth == scopes.last.entryDepth;
    final atTopLevel = depth == 0 && lineParen == 0;
    final atContainerMember = inContainer && lineParen == 0;

    // ---- containers + functions + top-level/var members ---------------
    // Function bodies are included (the _inFunctionBody guard on the
    // var-decl branch below): function-local consts ARE member nodes
    // (the multibyte fixture's 縮める.ラベル shape — nearest mapped
    // ancestor). The sym regexes stay atTopLevel-guarded individually.
    if (atTopLevel || atContainerMember || _inFunctionBody(scopes, depth)) {
      final cm = _classRe.firstMatch(trimmed);
      if (cm != null && atTopLevel) {
        out.add(_symbol(
          kind: 'sym',
          grammarType:
              cm.group(1) != null ? 'abstract_class_declaration' : 'class_declaration',
          name: cm.group(2)!,
          parentName: null,
          content: content,
          masked: masked,
          mLine: mLine,
          lineIdx: i,
          lineStart: lineStart[i],
          cuToByte: cuToByte,
          braceBodied: true,
          usedTails: usedTails,
          tailsBySymbol: tailsBySymbol,
          out: out,
        ));
        final entry = _depthAfterOpener(mLine, depth);
        scopes.add(_Scope('class_declaration', cm.group(2)!, entry));
        continue;
      }
      final im = _interfaceRe.firstMatch(trimmed);
      if (im != null && atTopLevel) {
        out.add(_symbol(
          kind: 'sym',
          grammarType: 'interface_declaration',
          name: im.group(1)!,
          parentName: null,
          content: content,
          masked: masked,
          mLine: mLine,
          lineIdx: i,
          lineStart: lineStart[i],
          cuToByte: cuToByte,
          braceBodied: true,
          usedTails: usedTails,
          tailsBySymbol: tailsBySymbol,
          out: out,
        ));
        scopes.add(_Scope(
            'interface_declaration', im.group(1)!, _depthAfterOpener(mLine, depth)));
        continue;
      }
      final em = _enumRe.firstMatch(trimmed);
      if (em != null && atTopLevel) {
        out.add(_symbol(
          kind: 'sym',
          grammarType: 'enum_declaration',
          name: em.group(1)!,
          parentName: null,
          content: content,
          masked: masked,
          mLine: mLine,
          lineIdx: i,
          lineStart: lineStart[i],
          cuToByte: cuToByte,
          braceBodied: true,
          usedTails: usedTails,
          tailsBySymbol: tailsBySymbol,
          out: out,
        ));
        // Enum members are NOT indexed (no mapping-table entry): the body
        // is pushed as a neutral scope so its lines classify nothing.
        scopes.add(_Scope('enum_declaration', em.group(1)!, _depthAfterOpener(mLine, depth)));
        continue;
      }
      final fm = _functionRe.firstMatch(trimmed);
      if (fm != null && atTopLevel) {
        final parent = scopes.isEmpty ? null : scopes.last.name;
        out.add(_symbol(
          kind: 'sym',
          grammarType: fm.group(1) != null
              ? 'generator_function_declaration'
              : 'function_declaration',
          name: fm.group(2)!,
          parentName: parent,
          content: content,
          masked: masked,
          mLine: mLine,
          lineIdx: i,
          lineStart: lineStart[i],
          cuToByte: cuToByte,
          braceBodied: true,
          usedTails: usedTails,
          tailsBySymbol: tailsBySymbol,
          out: out,
        ));
        scopes.add(_Scope(
            'function_declaration', fm.group(2)!, _depthAfterOpener(mLine, depth)));
        continue;
      }
      final tm = _typeAliasRe.firstMatch(trimmed);
      if (tm != null && atTopLevel) {
        out.add(_symbol(
          kind: 'sym',
          grammarType: 'type_alias_declaration',
          name: tm.group(1)!,
          parentName: null,
          content: content,
          masked: masked,
          mLine: mLine,
          lineIdx: i,
          lineStart: lineStart[i],
          cuToByte: cuToByte,
          braceBodied: false,
          usedTails: usedTails,
          tailsBySymbol: tailsBySymbol,
          out: out,
        ));
        continue;
      }
      final vm = _varDeclRe.firstMatch(trimmed);
      if (vm != null && (atTopLevel || _inFunctionBody(scopes, depth))) {
        final parent = scopes.isEmpty ? null : scopes.last.name;
        out.add(_symbol(
          kind: 'member',
          grammarType: vm.group(1) == 'var' ? 'variable_declaration' : 'lexical_declaration',
          name: vm.group(2)!,
          parentName: parent,
          content: content,
          masked: masked,
          mLine: mLine,
          lineIdx: i,
          lineStart: lineStart[i],
          cuToByte: cuToByte,
          braceBodied: false,
          usedTails: usedTails,
          tailsBySymbol: tailsBySymbol,
          out: out,
        ));
        // An arrow/arrow-body const opens a scope (`const f = () => {`):
        // nested declarations attach to it (the spike's ancestor-stack
        // semantics — nearest mapped ancestor).
        final entry = _depthAfterOpener(mLine, depth);
        if (entry > depth) {
          scopes.add(_Scope('lexical_declaration', vm.group(2)!, entry));
        }
        continue;
      }
    }

    // ---- class/interface members --------------------------------------
    if (atContainerMember) {
      final container = scopes.last;
      final isInterface = container.grammarType == 'interface_declaration';
      final stripped = trimmed.replaceFirst(_modifiersRe, '');
      final leadWs = mLine.length - mLine.trimLeft().length;
      final modSkip = trimmed.length - stripped.length;
      final declLine = mLine; // spans include modifiers (byte-precise)
      String? name;
      var grammarType = '';
      var braceBodied = false;
      final am = _accessorRe.firstMatch(stripped);
      final mm = am == null ? _methodRe.firstMatch(stripped) : null;
      if (am != null || mm != null) {
        name = (am ?? mm)!.group(am != null ? 2 : 1)!;
        braceBodied = true; // ends at ';' (signature) or '}' (body)
        grammarType = isInterface ? 'method_signature' : 'method_definition';
      } else {
        final ftm = _fieldTypeRe.firstMatch(stripped);
        final fim = ftm == null ? _fieldInitRe.firstMatch(stripped) : null;
        if (ftm != null || fim != null) {
          name = (ftm ?? fim)!.group(1)!;
          braceBodied = false;
          grammarType = isInterface ? 'property_signature' : 'public_field_definition';
        }
      }
      if (name != null && grammarType.isNotEmpty) {
        out.add(_memberSymbol(
          grammarType: grammarType,
          name: name,
          parentName: container.name,
          content: content,
          masked: masked,
          declLine: declLine,
          lineIdx: i,
          lineStart: lineStart[i],
          leadWs: leadWs,
          modSkip: modSkip,
          cuToByte: cuToByte,
          braceBodied: braceBodied,
          usedTails: usedTails,
          tailsBySymbol: tailsBySymbol,
        ));
        final entry = _depthAfterOpener(mLine, depth);
        if (entry > depth) {
          // A brace-bodied member opens a scope: nested consts attach to
          // the METHOD (nearest mapped ancestor — spike semantics).
          scopes.add(_Scope(grammarType, name, entry));
        }
        continue;
      }
    }
    // Anything else is content — never a symbol (honest v1).
  }
  return out;
}

/// True when the top of [scopes] is a function-like body whose depth we
/// are directly inside (`const` inside a function → its member, with the
/// FUNCTION as parent — the multibyte fixture's `縮める.ラベル` shape).
bool _inFunctionBody(List<_Scope> scopes, int depth) =>
    scopes.isNotEmpty &&
    (scopes.last.grammarType == 'function_declaration' ||
        scopes.last.grammarType == 'generator_function_declaration' ||
        scopes.last.grammarType == 'lexical_declaration' ||
        scopes.last.grammarType == 'method_definition') &&
    depth == scopes.last.entryDepth;

/// Absolute brace depth right after the body opener on [mLine] (masked) —
/// the entry depth of a pushed scope. Returns [depth] when the line opens
/// no body (no trailing `{` at depth 0).
int _depthAfterOpener(String mLine, int depth) {
  var d = depth;
  var opened = false;
  for (var j = 0; j < mLine.length; j++) {
    final c = mLine[j];
    if (c == '{') {
      d++;
      opened = true;
    } else if (c == '}') {
      d--;
    }
  }
  return opened ? d : depth;
}

TsSymbol _symbol({
  required String kind,
  required String grammarType,
  required String name,
  required String? parentName,
  required String content,
  required String masked,
  required String mLine,
  required int lineIdx,
  required int lineStart,
  required List<int> cuToByte,
  required bool braceBodied,
  required Map<String, int> usedTails,
  required Map<int, String> tailsBySymbol,
  required List<TsSymbol> out,
}) {
  final leadWs = mLine.length - mLine.trimLeft().length;
  // Span starts at the declaration KEYWORD (class/interface/enum/function/
  // type/const), not at `export` — the tree-sitter node's own start.
  final kw = mLine.trimLeft();
  final kwOffset = leadWs;
  final endCu = _statementEnd(masked, lineStart + kwOffset, braceBodied);
  final s = TsSymbol(
    kind: kind,
    grammarType: grammarType,
    name: name,
    parentName: parentName,
    startByte: cuToByte[lineStart + kwOffset],
    endByte: cuToByte[endCu],
    line: lineIdx + 1,
    indent: leadWs,
  );
  tailsBySymbol[out.length] = tsSymbolIdTail(s, usedTails);
  return s;
}

TsSymbol _memberSymbol({
  required String grammarType,
  required String name,
  required String parentName,
  required String content,
  required String masked,
  required String declLine,
  required int lineIdx,
  required int lineStart,
  required int leadWs,
  required int modSkip,
  required List<int> cuToByte,
  required bool braceBodied,
  required Map<String, int> usedTails,
  required Map<int, String> tailsBySymbol,
}) {
  final startCu = lineStart + leadWs; // span includes modifiers
  final endCu = _statementEnd(masked, startCu, braceBodied);
  final s = TsSymbol(
    kind: 'member',
    grammarType: grammarType,
    name: name,
    parentName: parentName,
    startByte: cuToByte[startCu],
    endByte: cuToByte[endCu],
    line: lineIdx + 1,
    indent: leadWs,
  );
  tailsBySymbol[-1] = tsSymbolIdTail(s, usedTails); // (unused handle)
  return s;
}

/// The end (code-unit offset, exclusive) of a declaration: brace-bodied →
/// the matching `}` + 1; otherwise the first `;` at depth 0 + 1 (or the
/// last non-space char + 1 of the logical line — never a wrong span).
int _statementEnd(String masked, int startCu, bool braceBodied) {
  var brace = 0;
  var paren = 0;
  var sawBrace = false;
  var lastNonSpace = startCu;
  for (var i = startCu; i < masked.length; i++) {
    final c = masked[i];
    if (c == '{') {
      brace++;
      sawBrace = true;
    } else if (c == '}') {
      brace--;
      if (braceBodied && brace == 0 && sawBrace && paren == 0) return i + 1;
    } else if (c == '(' || c == '[') {
      paren++;
    } else if (c == ')' || c == ']') {
      paren--;
    } else if (c == ';' && brace == 0 && paren == 0) {
      return i + 1;
    } else if (c == '\n' && brace == 0 && paren == 0) {
      // A brace-bodied declaration whose body never closed (scanner limit)
      // or an unterminated statement: end at the last content of the line.
      return lastNonSpace + 1;
    }
    if (c != ' ' && c != '\t' && c != '\n' && c != '\r') lastNonSpace = i;
  }
  return masked.length;
}

/// The map parser the ts binding registers (ADR 0035 §2): scan → sub-node
/// DATA; the fs tier stamps ids/edges/budgets (prefix `tsym_`,
/// binding-declared). Kind vocabulary = the spike's (`sym`/`member`);
/// props carry the byte spans + the parent attachment (the zoom cut's
/// memberOf) + the grammar type (the anchor-resolution identity).
List<MappedSubNode> tsMapParser(String content) {
  final usedTails = <String, int>{};
  return [
    for (final s in tsScanSymbols(content))
      MappedSubNode(
        kind: s.kind,
        label: s.name,
        idTail: tsSymbolIdTail(s, usedTails),
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
/// workspace-conventions pattern (mechanical, LLM-free): the jail's
/// package.json `scripts.test` names the runner — `vitest` →
/// `npx vitest run`, `jest` → `npx jest`. No declared runner → HONEST
/// NULL (the host never invents a criterion the workspace does not
/// declare). DATA on the outcome — graded by the verify tier, never
/// claimed as run by the materializer.
List<String>? resolveTsConvention(Directory root) {
  final pkg = File('${root.path}/package.json');
  if (!pkg.existsSync()) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(pkg.readAsStringSync());
    // ignore: avoid_catching_errors
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final scripts = decoded['scripts'];
  if (scripts is! Map) return null;
  final test = scripts['test'];
  if (test is! String) return null;
  if (test.contains('vitest')) return const ['npx', 'vitest', 'run'];
  if (test.contains('jest')) return const ['npx', 'jest'];
  return null;
}

// ---------------------------------------------------------------------------
// The binding realizations (ADR 0035 §1/§2) — the perform fn + the pack
// registry the ts binding registers. The router reaches them ONLY through
// the registry (class-routed); nothing dispatches on a kind switch.
// ---------------------------------------------------------------------------

/// The ts pack registry: pack-declared executables the ts materializer
/// serves (v1: authored-body executables only — the dart op-chain
/// compiler emits Dart, so op-chain kinds are honestly unsupported for
/// this class until the v2 emitter lands, ADR 0035 §6). Hosts REPLACE
/// this to wire the pack-write consent gate (deny-by-default — same law
/// as the span editor's packConsent); the model never authors the body.
EditPackRegistry tsEditPacks = EditPackRegistry();

/// The ts binding's perform fn (the proven shape
/// `{action, anchor, body} → outcome.toJson()` over one request envelope —
/// zero-arg-delta, ADR 0035 §5).
Map<String, dynamic> tsMaterializerPerform(NodeEditRequest r) =>
    TsMaterializer(root: r.root, locks: r.locks, owner: r.owner)
        .perform(action: r.action, anchor: r.anchor, body: r.body)
        .toJson();

/// Mechanical bounce BEFORE any byte is touched: error + the exact repair
/// move + navigable hints (mechanism-first, ADR 0035 §5 — the repair
/// names the read-program move and the node's own props, never a format).
class TsEditBounce implements Exception {
  TsEditBounce(this.error, this.repair, this.failureClass,
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

/// The outcome of a ts edit. Failures are classified data — never dropped.
class TsEditOutcome {
  const TsEditOutcome({
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

  /// The jail's declared test convention (vitest/jest) — DATA on the
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

/// The ts materializer: plan (mechanical anchor re-resolution from a FRESH
/// scan — never stale tree offsets — + splice + byte fence, never touches
/// bytes) + apply (atomic write → `tsc --noEmit` → auto-revert on
/// failure, with failure attribution). Single-writer via the shared
/// [FileLockTable] (the same table md/keypath/span editors claim).
class TsMaterializer {
  TsMaterializer({
    required this.root,
    FileLockTable? locks,
    this.owner = 'ts_materializer',
    this.tscBin,
    this.packs,
  }) : locks = locks ?? FileLockTable();

  final FsToolsRoot root;
  final FileLockTable locks;
  final Object owner;

  /// Analyzer override (host-injected; null → jail `node_modules/.bin/tsc`
  /// then `PATH`).
  final String? tscBin;

  /// The pack registry (null → the package-level [tsEditPacks]).
  final EditPackRegistry? packs;

  /// The body budget (body-as-data, budgeted): a single move past this
  /// bound bounces with the split-it repair move.
  static const maxTsBodyChars = 20000;

  static const actions = <String>{
    'insert_member',
    'remove_member',
    'apply_executable',
  };

  TsEditOutcome perform({
    required String action,
    required String anchor,
    String? body,
  }) {
    try {
      return _perform(action: action, anchor: anchor, body: body);
    } on TsEditBounce catch (b) {
      return TsEditOutcome(
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
        convention: resolveTsConvention(Directory(root.rootPath)),
      );
    }
  }

  TsEditOutcome _perform({
    required String action,
    required String anchor,
    required String? body,
  }) {
    if (!actions.contains(action)) {
      // Mechanism-first (§5): legality is the BINDING's declared union —
      // this bounce names THIS node's legal actions AND points at the
      // node's own edit_actions prop. Zero per-class recipe prose; the
      // v1 limitation (bodies via packs only) is taught by the union.
      throw TsEditBounce(
        'action "$action" is not legal for this node',
        're-send with action as one of: ${actions.toList()..sort()} — the '
            "node's edit_actions prop carries the same list AND the anchor "
            'currency; member-body text is pack-fed (apply_executable), '
            'never model-composed',
        'unknown_action',
      );
    }
    if (body != null && body.length > maxTsBodyChars) {
      throw TsEditBounce(
        'body over budget: ${body.length} chars (max $maxTsBodyChars)',
        'split the edit into multiple member moves (one anchor per '
            'move) — the budget is per move, the file is not',
        'body_over_budget',
      );
    }
    if (anchor.isEmpty) {
      throw TsEditBounce(
        'missing anchor (the node id to edit)',
        'run the read program (locate, then zoom the target) — zoom rows '
            'stamp the id; re-send with the stamped node id as anchor',
        'anchor_not_found',
      );
    }
    final path = _fileOfAnchor(anchor);
    if (path == null) {
      throw TsEditBounce(
        'anchor "$anchor" does not name a scanned file',
        're-send with the stamped node id from the zoom cut '
            '(tsym_<file>_<symbol>) — zoom the file node for the outline',
        'anchor_not_found',
      );
    }
    final abs = root.resolve(path);
    final f = File(abs);
    if (!f.existsSync()) {
      throw TsEditBounce(
        'file not found: $path',
        'the file moved under the tree — refresh the tree (repo_etl '
            'scan) and re-zoom',
        'file_not_found',
      );
    }
    final content = f.readAsStringSync();
    final before = tsScanSymbols(content);
    final target = _resolveTail(anchor, before, path, content);
    final convention = resolveTsConvention(Directory(root.rootPath));

    // Dart 3 case scoping: each case's locals die with the case — the
    // plan is the switch EXPRESSION's value (one scope for the fence +
    // apply below).
    final plan = switch (action) {
      'insert_member' => _planInsert(target, before, content, body, path),
      'remove_member' => _planRemove(target, before, content, path),
      'apply_executable' => _planApplyExecutable(
          target, before, content, path, (body ?? '').trim()),
      _ => throw TsEditBounce(
          'unknown action: $action', 'host bug — report as data', 'unknown_action'),
    };
    final spliced = plan.content;
    final description = plan.description;

    // BYTE FENCE: everything outside the touched span must be
    // byte-identical (mechanically asserted — the emitter edits ONLY the
    // member span boundary).
    _assertByteFence(content, spliced, plan.touchedStart, plan.touchedEnd);

    // ORACLE AVAILABILITY — before any byte is touched: the named
    // analyzer must exist (jail bin, then PATH). Unavailable = a NAMED
    // bounce, never a silent pass.
    final oracle = _resolveAnalyzer();
    if (oracle == null) {
      throw TsEditBounce(
        'the named analyzer oracle (tsc_no_emit) is unavailable: no tsc '
            'binary in ${root.rootPath}/node_modules/.bin/ nor on PATH',
        'install typescript in the jail (npm i -D typescript) or wire the '
            'analyzer path — edits to this class never land unverified',
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
      oracle: oracle,
      convention: convention,
      exeId: action == 'apply_executable' ? (body ?? '').trim() : null,
    );
  }

  // -- anchor resolution (fresh scan; ids recomputed, never tree offsets) --

  /// The workspace-relative file an anchor belongs to: the id form is
  /// `tsym_<fileNodeId>_<idTail>` and the file node id is
  /// `f_<rel with / → _>`.
  String? _fileOfAnchor(String anchor) {
    if (!anchor.startsWith('tsym_')) return null;
    // The id form is `tsym_<fileNodeId>_<idTail>` and the file node id is
    // `f_<rel with / → _>` (fs_etl) — BOTH parts may contain underscores
    // (the rel itself is path-flattened), so the file/tail boundary is
    // resolved by matching against the files the jail actually scans
    // (longest file id wins; file ids are unique per file).
    final candidates = <String>[];
    final rootDir = Directory(root.rootPath);
    if (!rootDir.existsSync()) return null;
    final skipDirs = {'node_modules', '.git', 'build', '.dart_tool'};
    final stack = <Directory>[rootDir];
    while (stack.isNotEmpty) {
      final dir = stack.removeLast();
      for (final e in dir.listSync(followLinks: false)) {
        if (e is Directory) {
          if (!skipDirs.contains(e.uri.pathSegments.reversed.skip(1).first)) {
            stack.add(e);
          }
          continue;
        }
        if (e is! File) continue;
        final rel = e.path
            .substring(rootDir.path.length)
            .replaceAll('\\', '/')
            .replaceFirst(RegExp(r'^/'), '');
        if (rel.endsWith('.ts') || rel.endsWith('.tsx')) {
          candidates.add(rel);
        }
      }
    }
    candidates.sort((a, b) => b.length.compareTo(a.length));
    for (final rel in candidates) {
      final fileId = 'f_${rel.replaceAll('/', '_')}';
      if (anchor.startsWith('tsym_$fileId') &&
          anchor.length > 'tsym_'.length + fileId.length) {
        return rel;
      }
    }
    return null;
  }

  _ResolvedTarget _resolveTail(
    String anchor,
    List<TsSymbol> symbols,
    String path,
    String content,
  ) {
    // The file id is `f_<rel with / → _>` — the tail is the anchor's
    // remainder after `tsym_<fileId>_` (same boundary [_fileOfAnchor]
    // resolved; both parts may contain underscores, so the prefix comes
    // from the RESOLVED path, never a guess).
    final fileId = 'f_${path.replaceAll('/', '_')}';
    final prefix = 'tsym_$fileId';
    if (!anchor.startsWith('$prefix')) {
      throw TsEditBounce(
        'anchor "$anchor" does not name a node of $path',
        're-send with the stamped node id from the zoom cut '
            '(tsym_<file>_<symbol>) — zoom the file node for the outline',
        'anchor_not_found',
      );
    }
    final tail = anchor.substring(prefix.length + 1);
    // Recompute the SAME id tails over the fresh scan (deterministic) —
    // the anchor is the id, the span comes from CURRENT bytes.
    final usedTails = <String, int>{};
    final byTail = <String, TsSymbol>{
      for (final s in symbols) tsSymbolIdTail(s, usedTails): s,
    };
    final hit = byTail[tail];
    if (hit == null) {
      throw TsEditBounce(
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
      throw TsEditBounce(
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

  List<String> _outlineHints(List<TsSymbol> symbols) => [
        for (final s in symbols.take(12))
          'tsym ${s.kind} ${s.grammarType} ${s.name}'
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
    List<TsSymbol> before,
    String content,
    String? body,
    String path,
  ) {
    final s = target.symbol;
    const containers = {
      'class_declaration',
      'abstract_class_declaration',
      'interface_declaration',
    };
    if (!containers.contains(s.grammarType)) {
      throw TsEditBounce(
        '"${s.name}" is a ${s.grammarType} — insert_member targets a '
            'DECLARING body (a container node from the zoom cut)',
        'zoom the declaring parent (its sym node owns the body) and '
            're-send the move with that node id as anchor',
        'not_a_container',
      );
    }
    if (body == null || body.trim().isEmpty) {
      throw TsEditBounce(
        'missing body',
        're-send with body as the new member source (data — the '
            'tsc_no_emit oracle verifies it before it lands)',
        'invalid_body',
      );
    }
    if (body.contains(r'\\') && _unbalanced(body)) {
      throw TsEditBounce(
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
      throw TsEditBounce(
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
    // indent + 2.
    var memberIndent = 2;
    final openLineStart =
        content.lastIndexOf('\n', bodySpan.$1 - 1 < 0 ? 0 : bodySpan.$1 - 1) + 1;
    var containerIndent = 0;
    for (var i = openLineStart; i < content.length && content[i] == ' '; i++) {
      containerIndent++;
    }
    memberIndent = containerIndent + 2;
    for (final m in before) {
      if (m.parentName == s.name &&
          (m.grammarType == 'method_definition' ||
              m.grammarType == 'method_signature' ||
              m.grammarType == 'public_field_definition' ||
              m.grammarType == 'property_signature')) {
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
    List<TsSymbol> before,
    String content,
    String path,
  ) {
    final s = target.symbol;
    if (s.kind != 'member' && s.kind != 'sym') {
      throw TsEditBounce(
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
    if (lineEnd < 0) lineEnd = content.length; else lineEnd += 1;
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
    List<TsSymbol> before,
    String content,
    String path,
    String exeId,
  ) {
    if (exeId.isEmpty) {
      throw TsEditBounce(
        'missing executable id',
        're-send with body as the executable id from the pack (the '
            'body travels with the PACK — you supply ids only)',
        'invalid_body',
      );
    }
    final registry = packs ?? tsEditPacks;
    final wire = registry.executables[exeId];
    if (wire == null) {
      throw TsEditBounce(
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
      throw TsEditBounce(
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
      throw TsEditBounce(
        'executable "$exeId" carries no consented body',
        'fix the pack entry — the consent gate never passes an empty '
            'body',
        'unsupported_executable',
      );
    }
    final s = target.symbol;
    const bodyKinds = {
      'method_definition',
      'function_declaration',
      'generator_function_declaration',
    };
    if (!bodyKinds.contains(s.grammarType)) {
      throw TsEditBounce(
        '"${s.name}" is a ${s.grammarType} — authored bodies replace the '
            'bodies of brace-bodied members only',
        'target a brace-bodied member node from the zoom cut',
        'unsupported_shape',
      );
    }
    final cuToByte = _utf16ToUtf8Map(content);
    final startCu = _byteToCu(cuToByte, s.startByte);
    final endCu = _byteToCu(cuToByte, s.endByte);
    final openCu = _firstOpenBrace(content, startCu, endCu);
    if (openCu == null) {
      throw TsEditBounce(
        '"${s.name}" carries no brace body to replace',
        'the member must be brace-bodied — signatures and fields have no '
            'body span',
        'unsupported_shape',
      );
    }
    var closeCu = _matchingClose(content, openCu);
    if (closeCu == null) {
      throw TsEditBounce(
        '"${s.name}" body braces cannot be matched in the current bytes',
        'the body must be a plain brace body to splice into',
        'unsupported_shape',
      );
    }
    final memberIndent = _indentAt(content, startCu);
    final bodyIndent = ' ' * (memberIndent + 2);
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

  // -- apply: atomic write + tsc_no_emit + scan envelope + auto-revert -----

  TsEditOutcome _apply({
    required String path,
    required String original,
    required String spliced,
    required String description,
    required int touchedStart,
    required int touchedEnd,
    required List<TsSymbol> before,
    required String action,
    required String anchor,
    required TsSymbol targetSymbol,
    required ({String exe, List<String> baseArgs})? oracle,
    required List<String>? convention,
    String? exeId,
  }) {
    final rel = path;
    if (!locks.claim(rel, owner)) {
      final holder = locks.ownerOf(rel);
      return TsEditOutcome(
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
      final after = tsScanSymbols(spliced);
      final violation = _envelopeViolation(action, before, after, targetSymbol);
      if (violation != null) {
        return TsEditOutcome(
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
      // THE NAMED ORACLE — tsc --noEmit after EVERY apply.
      final check = _runTsc(oracle!, rel);
      if (!check.ok) {
        // AUTO-REVERT: a failing check never lands.
        f.writeAsStringSync(original, flush: true);
        return TsEditOutcome(
          ok: false,
          reverted: true,
          op: action,
          path: rel,
          anchor: anchor,
          detail: 'tsc_no_emit FAILED after $description — ALL bytes '
              'reverted (${_oneLine(check.output)})',
          failureClass: check.failureClass,
          hints: const [
            'fix the member source against the analyzer report and '
                're-send the move — the edit must satisfy 0 analyzer '
                'errors to land',
          ],
          convention: convention,
        );
      }
      return TsEditOutcome(
        ok: true,
        reverted: false,
        op: action,
        path: rel,
        anchor: anchor,
        detail: '$description — spliced byte-precise '
            '(${original.length} → ${spliced.length} bytes); tsc_no_emit '
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
    List<TsSymbol> before,
    List<TsSymbol> after,
    TsSymbol target,
  ) {
    String key(TsSymbol s) =>
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
        final targetKey = key(target);
        if (removed.isNotEmpty) {
          return 'symbols removed: $removed';
        }
        if (added.length != 1 || !added.single.contains('|${target.name}')) {
          return 'expected exactly 1 added member under "${target.name}", '
              'got: $added';
        }
        return null;
      case 'remove_member':
        final targetKey = key(target);
        if (added.isNotEmpty) {
          return 'symbols added: $added';
        }
        if (removed.length != 1 || removed.single != targetKey) {
          return 'expected exactly the target removed ($targetKey), got '
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

  /// Resolves the analyzer binary: jail `node_modules/.bin/tsc` first,
  /// then `PATH`. Null → unavailable (the named pre-apply bounce).
  ({String exe, List<String> baseArgs})? _resolveAnalyzer() {
    if (tscBin != null) {
      // Host-injected override — trust it verbatim (availability is
      // proven by the run itself).
      return (exe: tscBin!, baseArgs: const <String>[]);
    }
    final jailBin = File('${root.rootPath}/node_modules/.bin/tsc');
    if (jailBin.existsSync()) {
      return (exe: jailBin.path, baseArgs: const <String>[]);
    }
    try {
      final probe = Process.runSync('tsc', const ['--version']);
      if (probe.exitCode == 0) {
        return (exe: 'tsc', baseArgs: const <String>[]);
      }
      // ignore: avoid_catching_errors
    } on ProcessException {
      return null;
    }
    return null;
  }

  ({bool ok, String failureClass, String output}) _runTsc(
    ({String exe, List<String> baseArgs}) oracle,
    String rel,
  ) {
    final hasTsconfig = File('${root.rootPath}/tsconfig.json').existsSync();
    final args = [
      ...oracle.baseArgs,
      '--noEmit',
      if (!hasTsconfig) rel,
    ];
    final ProcessResult r;
    try {
      r = Process.runSync(oracle.exe, args, workingDirectory: root.rootPath);
    } on ProcessException catch (e) {
      return (ok: false, failureClass: 'oracle_unavailable', output: '$e');
    }
    if (r.exitCode != 0) {
      return (
        ok: false,
        failureClass: 'tsc_error',
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
    TsSymbol s,
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
      throw TsEditBounce(
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
      throw TsEditBounce(
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
  final TsSymbol symbol;
}

/// A validated plan (the splice result + the touched-span fence).
extension type _PlanResult(({String content, String description,
    int touchedStart, int touchedEnd}) _) implements Object {}

String _oneLine(Object e) =>
    '$e'.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ');

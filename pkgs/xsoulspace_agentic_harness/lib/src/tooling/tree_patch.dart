// ignore_for_file: lines_longer_than_80_chars

/// Tree-edit materializer (M3) — deterministic structural patching.
///
/// Same model-facing contract as `patch_file` (path + selector + body), but
/// the selector is a *symbol name* resolved through the Dart analyzer's
/// resolved-free AST, and the replacement is formatted with the canonical
/// printer. The file is only written when BOTH the original and the patched
/// sources parse cleanly — syntax errors can never reach disk.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:dart_style/dart_style.dart';
import 'package:dart_style/src/exceptions.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

/// A half-open [start, end) byte range and the text to splice in.
class _Span {
  const _Span(this.start, this.end, this.text);
  final int start;
  final int end;
  final String text;
}

AstNode? _findNamedDeclaration(CompilationUnit unit, String symbol) {
  for (final decl in unit.declarations) {
    final name = _declLexeme(decl);
    if (name == symbol) return decl;
  }
  // Fall back to a recursive scan for local/nested declarations.
  AstNode? hit;
  final visitor = _SymbolVisitor(symbol, (n) => hit ??= n);
  unit.accept(visitor);
  return hit;
}

class _SymbolVisitor extends RecursiveAstVisitor<void> {
  _SymbolVisitor(this.symbol, this.hit);
  final String symbol;
  final void Function(AstNode) hit;

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final l = _declLexeme(node);
    if (l == symbol) {
      hit(node);
    } else {
      super.visitClassDeclaration(node);
    }
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    if (_declLexeme(node) == symbol) {
      hit(node);
    } else {
      super.visitEnumDeclaration(node);
    }
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (_declLexeme(node) == symbol) {
      hit(node);
    } else {
      super.visitFunctionDeclaration(node);
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    if (_declLexeme(node) == symbol) {
      hit(node);
    } else {
      super.visitMethodDeclaration(node);
    }
  }

  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (final v in node.variables.variables) {
      if (_declLexeme(v) == symbol) {
        hit(v);
        return;
      }
    }
    super.visitTopLevelVariableDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (_declLexeme(node) == symbol) {
      hit(node);
    }
  }
}

/// Version-proof declaration-name extraction.
///
/// Analyzer versions differ on whether a declaration's name is exposed as a
/// `Token` (`.name`), a `SimpleIdentifier` (`.name2`), or neither. This reads
/// whichever is present without throwing — returning the lexeme or null.
String? _declLexeme(AstNode node) {
  Object? raw;
  try {
    raw = (node as dynamic).name;
  } on Object {
    raw = null;
  }
  String? fromToken(Object? r) => switch (r) {
        final Token t => t.lexeme,
        final SimpleIdentifier s => s.name,
        final String s => s,
        _ => null,
      };
  var lex = fromToken(raw);
  if (lex != null) return lex;
  try {
    raw = (node as dynamic).name2;
  } on Object {
    raw = null;
  }
  lex = fromToken(raw);
  if (lex != null) return lex;
  // Analyzer 14: ClassDeclaration / EnumDeclaration expose the name via the
  // `namePart` (ClassNamePart) whose `typeName` is the leading identifier
  // Token — e.g. class, enum, or type-parameterized names.
  try {
    final namePart = (node as dynamic).namePart;
    raw = namePart == null ? null : (namePart as dynamic).typeName;
  } on Object {
    raw = null;
  }
  return fromToken(raw);
}

Map<String, dynamic> treePatch({
  required String root,
  required String path,
  required String symbol,
  required String newBody,
}) {
  final filePath = '$root/$path';
  final file = File(filePath);
  if (!file.existsSync()) {
    return {'ok': false, 'code': 'file_missing', 'path': path};
  }
  final source = file.readAsStringSync();

  final original = parseString(content: source);
  if (original.errors.isNotEmpty) {
    return {
      'ok': false,
      'code': 'source_parse_error',
      'path': path,
      'hint': 'fix syntax before structural edits',
    };
  }
  final node = _findNamedDeclaration(original.unit, symbol);
  if (node == null) {
    return {
      'ok': false,
      'code': 'symbol_not_found',
      'path': path,
      'message': "no declaration named '$symbol'",
    };
  }

  String candidate;
  try {
    candidate = source.replaceRange(
      node.offset,
      node.end,
      '\n$newBody\n',
    );
    candidate = DartFormatter(languageVersion: Version(3, 8, 0)).format(candidate);
  } on FormatterException catch (e) {
    return {
      'ok': false,
      'code': 'replacement_parse_error',
      'path': path,
      'message': e.toString(),
      'hint': 'new_body must be complete, well-formed Dart',
    };
  }

  final reparsed = parseString(content: candidate);
  if (reparsed.errors.isNotEmpty) {
    return {
      'ok': false,
      'code': 'patched_source_invalid',
      'path': path,
      'hint': 'formatted result failed to parse; nothing written',
    };
  }

  file.writeAsStringSync(candidate);
  return {
    'ok': true,
    'path': path,
    'symbol': symbol,
    'replaced_span': node.length,
  };
}

/// In-file rename (M3a): rename a top-level or local declaration and every
/// identifier-use that resolves to it *within the same file*.
///
/// Unlike [treePatch] (which splices a whole new declaration body), this
/// rewrites the identifier name itself — including the declaration's own
/// name token — plus all matching `Simple` references, so a top-level
/// `const` and its usages all update atomically.
///
/// Candidate is formatted by `DartFormatter` and **re-parsed before
/// writing**: invalid Dart never reaches disk. Returns a structured result
/// with `renames`, `edited`, `conflicts`.
///
/// For the common multi-file case (a symbol imported elsewhere), prefer
/// [treePatchSymbolRenameMulti] so referencing files are rewritten too.
Map<String, dynamic> treePatchSymbolRename({
  required String root,
  required String path,
  required String symbol,
  required String newName,
}) =>
    _renameFile(root, path, symbol, newName);

/// Cross-file rename (M3b): rename [symbol] → [newName] in [path] (the
/// declaration file) **and** in every path listed in [extraFiles].
///
/// Each file is renamed atomically by the same mechanical logic as
/// [treePatchSymbolRename]; the declaration is verified to exist in [path]
/// (Stage 1) and referencing files are rewritten by the shared identifier
/// collector. Every file is independently re-parsed before write, so a
/// syntax error in any one file is reported and that file is left untouched
/// (other files already written are left consistent with the rename).
///
/// Returns aggregate `renames`/`edited` and per-file `details`. The model
/// discovers referencing files via `list_dir`; this tool does not yet walk
/// the package `AnalysisSession` element graph for automatic discovery —
/// that is a future Stage 2 that requires a resolved analysis context.
Map<String, dynamic> treePatchSymbolRenameMulti({
  required String root,
  required String path,
  required String symbol,
  required String newName,
  List<String> extraFiles = const [],
}) {
  final details = <Map<String, dynamic>>[];
  var totalRenames = 0;
  final edited = <String>[];

  final primary = _renameFile(root, path, symbol, newName);
  details.add(primary);
  if (primary['ok'] != true) {
    // Declaration missing / parse error in the origin file: abort, write
    // nothing, surface the reason.
    return {
      'ok': primary['ok'] as bool,
      'path': path,
      'symbol': symbol,
      'new_name': newName,
      'code': primary['code'],
      'renames': 0,
      'edited': <String>[],
      'details': details,
    };
  }
  totalRenames += (primary['renames'] as int? ?? 0);
  if (primary['edited'] case final List l when l.isNotEmpty) {
    edited.add(path);
  }

  for (final f in extraFiles) {
    final r = _renameFile(root, f, symbol, newName, allowMissing: true);
    details.add(r);
    if (r['ok'] == true) {
      totalRenames += (r['renames'] as int? ?? 0);
      if (r['edited'] case final List l when l.isNotEmpty) {
        edited.add(f);
      }
    }
  }

  return {
    'ok': true,
    'path': path,
    'symbol': symbol,
    'new_name': newName,
    'renames': totalRenames,
    'edited': edited,
    'details': details,
  };
}

/// Core single-file rename; returns the structured result. [allowMissing]
/// flips the "file must exist / declaration must be present" contract so
/// cross-file rewrites don't abort when a referencing file happens to not
/// use the symbol.
Map<String, dynamic> _renameFile(
  String root,
  String path,
  String symbol,
  String newName, {
  bool allowMissing = false,
}) {
  final filePath = '$root/$path';
  final file = File(filePath);
  if (!file.existsSync()) {
    return allowMissing
        ? {'ok': true, 'path': path, 'renames': 0, 'edited': <String>[]}
        : {'ok': false, 'code': 'file_missing', 'path': path};
  }
  if (newName.isEmpty) {
    return {'ok': false, 'code': 'bad_args', 'hint': 'newName must be non-empty'};
  }
  final source = file.readAsStringSync();

  final original = parseString(content: source);
  if (original.errors.isNotEmpty) {
    return {
      'ok': false,
      'code': 'source_parse_error',
      'path': path,
      'hint': 'fix syntax before structural edits',
    };
  }

  final decl = _findNamedDeclaration(original.unit, symbol);
  if (decl == null) {
    // No declaration in this file — but it may still REFERENCE the symbol
    // (a cross-file consumer). For allowMissing files we still rewrite any
    // matching identifier usages; otherwise it's a hard miss.
    if (!allowMissing) {
      return {
        'ok': false,
        'code': 'symbol_not_found',
        'path': path,
        'message': "no declaration named '$symbol'",
      };
    }
  }

  // Collect every identifier token (declaration name + all `Simple` uses)
  // matching [symbol]. The declaration's own name is matched by offset so it
  // is rewritten exactly once; references are matched as `SimpleIdentifier`s
  // whose `seen` set excludes that offset.
  final edits = <_Span>[];
  final conflicts = <String>[];
  final seen = <int>{};

  final declNameStart = decl == null ? null : _declNameOffset(decl, symbol);
  if (declNameStart != null) {
    edits.add(_Span(declNameStart, declNameStart + symbol.length, newName));
    seen.add(declNameStart);
  }

  final visitor = _ReferenceCollector(symbol, newName, edits, seen);
  original.unit.accept(visitor);

  // Sort high→low so offsets stay valid as we splice from the end.
  edits.sort((a, b) => b.start.compareTo(a.start));
  var candidate = source;
  for (final e in edits) {
    candidate = candidate.replaceRange(e.start, e.end, e.text);
  }

  String formatted;
  try {
    formatted = DartFormatter(languageVersion: Version(3, 8, 0)).format(candidate);
  } on FormatterException catch (ex) {
    return {
      'ok': false,
      'code': 'rename_format_error',
      'path': path,
      'message': ex.toString(),
      'renames': edits.length,
      'hint': 'formatted result failed to format; nothing written',
    };
  }

  final reparsed = parseString(content: formatted);
  if (reparsed.errors.isNotEmpty) {
    return {
      'ok': false,
      'code': 'renamed_source_invalid',
      'path': path,
      'renames': edits.length,
      'conflicts': conflicts,
      'hint': 'formatted result failed to parse; nothing written',
    };
  }

  final changed = formatted != source;
  if (changed) {
    file.writeAsStringSync(formatted);
  }
  return {
    'ok': true,
    'path': path,
    'symbol': symbol,
    'new_name': newName,
    'renames': edits.length,
    'edited': changed ? [path] : <String>[],
    'conflicts': conflicts,
  };
}

/// Offset of the declaration's own name token, so the rename rewrites the
/// name itself (not just its body via [treePatch]).
int? _declNameOffset(AstNode decl, String symbol) {
  String? lex;
  Object? raw;
  try {
    raw = (decl as dynamic).name;
  } on Object {
    raw = null;
  }
  lex = _lexemeOf(raw);
  if (lex == symbol) {
    return _tokenOffset(raw);
  }
  try {
    raw = (decl as dynamic).name2;
  } on Object {
    raw = null;
  }
  lex = _lexemeOf(raw);
  if (lex == symbol) {
    return _tokenOffset(raw);
  }
  // Analyzer 14: ClassDeclaration / EnumDeclaration carry the name on
  // `namePart.typeName` (a Token).
  try {
    final namePart = (decl as dynamic).namePart;
    if (namePart != null && (namePart as dynamic).typeName is Token) {
      final t = (namePart as dynamic).typeName as Token;
      if (t.lexeme == symbol && t.offset >= 0) return t.offset;
    }
  } on Object {
    // no namePart — fall through
  }
  return null;
}

String? _lexemeOf(Object? raw) => switch (raw) {
      final Token t => t.lexeme,
      final SimpleIdentifier s => s.name,
      final String s => s,
      _ => null,
    };

int? _tokenOffset(Object? raw) {
  if (raw is Token && raw.offset >= 0) return raw.offset;
  if (raw is SimpleIdentifier && raw.offset >= 0) return raw.offset;
  return null;
}

/// Collects identifier `Simple` nodes matching `symbol` whose offset is not
/// already claimed (avoids double-counting the declaration's own name token,
/// which lives inside the declaration's child tokens in some analyzer
/// versions). Only direct identifier references are collected — not field
/// accesses on a differently-declared member — which is the safe in-file
/// contract; cross-file resolution (Stage 2) is out of scope.
class _ReferenceCollector extends RecursiveAstVisitor<void> {
  _ReferenceCollector(this.symbol, this.newName, this.edits, this.seen);
  final String symbol;
  final String newName;
  final List<_Span> edits;
  final Set<int> seen;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final name = node.name;
    if (name != symbol) return;
    final off = node.offset;
    if (!seen.add(off)) return;
    edits.add(_Span(off, node.end, newName));
    super.visitSimpleIdentifier(node);
  }
}

/// Agent-facing tool over [treePatch]: same shape as `patch_file`, but the
/// selector is a declaration name and the payload is whole-member source.
/// selector is a declaration name and the payload is whole-member source.
ToolDef patchSymbolTool(String jailRoot) => ToolDef.encode(
      name: const ToolName('patch_symbol'),
      description:
          'Replace one named Dart declaration (class, method, function, '
          'enum, top-level variable) with [new_body] using the analyzer AST; '
          'result is canonically formatted and re-parsed before writing. '
          'Fails with structured diagnostics — never writes invalid Dart.',
      argsSchema: SchemaBundle(
        root: FM.object('patch_symbol', properties: () => [
          FM.prop('path', FM.string(), description: 'file to edit, jail-relative'),
          FM.prop('symbol', FM.string(), description: 'declaration name to replace'),
          FM.prop('new_body', FM.string(), description: 'complete replacement declaration source'),
        ]),
      ),
      execute: (args) async {
        final raw = args;
        final map = raw is Map
            ? raw.map((k, v) => MapEntry(k.toString(), v))
            : const <String, dynamic>{};
        final path = map['path'] as String?;
        final symbol = map['symbol'] as String?;
        final newBody = map['new_body'] as String?;
        if (path == null || symbol == null || newBody == null) {
          return {
            'ok': false,
            'code': 'bad_args',
            'hint': 'required: path, symbol, new_body',
          };
        }
        return treePatch(
          root: jailRoot,
          path: path,
          symbol: symbol,
          newBody: newBody,
        );
      },
    );

/// Agent-facing tool over [treePatchSymbolRename]: rename an in-file
/// symbol and all of its references within `path`.
ToolDef renameSymbolTool(String jailRoot) => ToolDef.encode(
      name: const ToolName('rename_symbol'),
      description:
          'Rename a Dart declaration (class, function, const, etc.) and all '
          'of its identifier references within the same file. The declaration '
          'name itself is rewritten, not replaced with a body. Result is '
          'canonically formatted and re-parsed before writing — never writes '
          'invalid Dart. Cross-file references (other files importing this '
          'symbol) are handled by rename_symbol_multi.',
      argsSchema: SchemaBundle(
        root: FM.object('rename_symbol', properties: () => [
          FM.prop('path', FM.string(), description: 'file containing the declaration'),
          FM.prop('symbol', FM.string(), description: 'declaration name to rename'),
          FM.prop('new_name', FM.string(), description: 'replacement identifier'),
        ]),
      ),
      execute: (args) async {
        final map = args is Map
            ? args.map((k, v) => MapEntry(k.toString(), v))
            : const <String, dynamic>{};
        final path = map['path'] as String?;
        final symbol = map['symbol'] as String?;
        final newName = map['new_name'] as String? ?? map['newName'] as String?;
        if (path == null || symbol == null || newName == null) {
          return {
            'ok': false,
            'code': 'bad_args',
            'hint': 'required: path, symbol, new_name',
          };
        }
        return treePatchSymbolRename(
          root: jailRoot,
          path: path,
          symbol: symbol,
          newName: newName,
        );
      },
    );

/// Agent-facing tool over [treePatchSymbolRenameMulti]: cross-file rename.
/// Pass `extra_files` to list referencing files the declaration's new name
/// must propagate to (e.g. after `list_dir` reveals imports).
ToolDef renameSymbolMultiTool(String jailRoot) => ToolDef.encode(
      name: const ToolName('rename_symbol_multi'),
      description:
          'Rename a Dart declaration and propagate the new name to referencing '
          'files. Requires `path` (the declaration file), `symbol`, `new_name`, '
          'and optionally `extra_files` (a list of files to rewrite in the same '
          'pass). Each file is formatted and re-parsed before write — never '
          'writes invalid Dart. The declaration must exist in `path`; '
          'referencing files are skipped if they do not use the symbol.',
      argsSchema: SchemaBundle(
        root: FM.object('rename_symbol_multi', properties: () => [
          FM.prop('path', FM.string(), description: 'file containing the declaration'),
          FM.prop('symbol', FM.string(), description: 'declaration name to rename'),
          FM.prop('new_name', FM.string(), description: 'replacement identifier'),
          FM.prop('extra_files', FM.array(FM.string()), description: 'referencing files to update', optional: true),
        ]),
      ),
      execute: (args) async {
        final map = args is Map
            ? args.map((k, v) => MapEntry(k.toString(), v))
            : const <String, dynamic>{};
        final path = map['path'] as String?;
        final symbol = map['symbol'] as String?;
        final newName =
            map['new_name'] as String? ?? map['newName'] as String?;
        if (path == null || symbol == null || newName == null) {
          return {
            'ok': false,
            'code': 'bad_args',
            'hint': 'required: path, symbol, new_name',
          };
        }
        final rawExtras = map['extra_files'] ?? map['extraFiles'];
        final extraFiles = switch (rawExtras) {
          List l => l.map((e) => e.toString()).toList(),
          String s when s.isNotEmpty => [s],
          _ => <String>[],
        };
        return treePatchSymbolRenameMulti(
          root: jailRoot,
          path: path,
          symbol: symbol,
          newName: newName,
          extraFiles: extraFiles,
        );
      },
    );

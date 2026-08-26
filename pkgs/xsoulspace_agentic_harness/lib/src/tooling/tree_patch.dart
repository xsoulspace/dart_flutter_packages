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

AstNode? _findNamedDeclaration(CompilationUnit unit, String symbol) {
  AstNode? hit;
  final visitor = _SymbolVisitor(symbol, (n) => hit ??= n);
  unit.visitChildren(visitor);
  return hit;
}

class _SymbolVisitor extends UnifyingAstVisitor<void> {
  _SymbolVisitor(this.symbol, this.hit);
  final String symbol;
  final void Function(AstNode) hit;

  @override
  void visitNode(AstNode node) {
    // Version-proof name match: declaration classes expose `name` as a
    // Token in some analyzer versions and different shapes in others.
    Object? raw;
    try {
      raw = (node as dynamic).name;
    } on Object {
      raw = null;
    }
    final lexeme = switch (raw) {
      final Token t => t.lexeme,
      final String s => s,
      _ => null,
    };
    if (lexeme == symbol &&
        (node is ClassDeclaration ||
            node is EnumDeclaration ||
            node is FunctionDeclaration ||
            node is MethodDeclaration)) {
      hit(node);
    }
    super.visitNode(node);
  }
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

/// Agent-facing tool over [treePatch]: same shape as `patch_file`, but the
/// selector is a declaration name and the payload is whole-member source.
ToolDef patchSymbolTool(String jailRoot) => ToolDef.encode(
      name: const ToolName('patch_symbol'),
      description:
          'Replace one named Dart declaration (class, method, function, '
          'enum) with [new_body] using the analyzer AST; result is '
          'canonically formatted and re-parsed before writing. Fails with '
          'structured diagnostics — never writes invalid Dart.',
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

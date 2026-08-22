// ignore_for_file: lines_longer_than_80_chars

/// Reusable, real tool definitions for the harness.
///
/// These are actual tool bodies (read/write/list files, clock, search) built
/// with structured [SchemaBundle] schemas — not string blobs — so they can be
/// shared across the scenario stress runner, the example host, and tests. If
/// you need a tool in more than one place, define it here and reuse it.
///
/// ## Platform
///
/// These tools use `dart:io` and only work on VM hosts (CLI, server,
/// desktop). They are NOT available on web or in restricted sandboxes.
///
/// ## Path jail
///
/// All paths are resolved against [FsToolsRoot.rootPath] and rejected if they
/// escape it. Always construct the suite with an explicit root — never expose
/// unrestricted filesystem access to a model.
library;

import 'dart:convert';
import 'dart:io';

import 'package:from_json_to_json/from_json_to_json.dart';

import '../structured_output/structured_output.dart';
import 'tool_registry.dart';

/// The path jail for [fsTools]: every tool path is resolved against this root
/// and must stay inside it.
class FsToolsRoot {
  FsToolsRoot(this.rootPath) {
    final dir = Directory(rootPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    rootPath = dir.resolveSymbolicLinksSync();
  }

  /// Absolute path of the jail root. Created if missing; symlinks resolved.
  String rootPath;

  /// Resolve [path] (absolute or relative) inside the jail.
  ///
  /// Throws [ArgumentError] when the resolved path escapes the root.
  String resolve(String path) {
    final p = File(path.startsWith('/') ? path : '$rootPath/$path');
    // Canonicalize the parent chain without requiring the target to exist.
    final resolved = _canonicalize(p.path);
    if (!resolved.startsWith(rootPath)) {
      throw ArgumentError('Path escapes the allowed root: $path');
    }
    return resolved;
  }

  /// Lexical canonicalization (resolves `.`/`..`) without touching disk.
  static String _canonicalize(String path) {
    final parts = <String>[];
    for (final part in path.split('/')) {
      switch (part) {
        case '' || '.':
          continue;
        case '..':
          if (parts.isNotEmpty && parts.last != '..') {
            parts.removeLast();
          } else {
            parts.add('..');
          }
        default:
          parts.add(part);
      }
    }
    return '/${parts.join('/')}';
  }
}

/// A file-system tool suite: `read`, `write`, `list_dir`.
///
/// Real tools (they touch the disk), jailed under [root]. Each is built with a
/// structured [SchemaBundle].
List<ToolDef> fsTools(FsToolsRoot root) => [
  readTool(root),
  writeTool(root),
  listDirTool(root),
];

/// Read a file's contents.
ToolDef readTool(FsToolsRoot root) => ToolDef(
  name: const ToolName('read'),
  description: 'Read a file',
  argsSchema: SchemaBundle(
    root: FM.object('read', properties: () => [FM.prop('path', FM.string())]),
  ),
  execute: (args) {
    final params = jsonDecodeMapAs(args);
    final path = root.resolve(jsonDecodeString(params['path']));
    return File(path).readAsString();
  },
);

/// Write content to a file.
ToolDef writeTool(FsToolsRoot root) => ToolDef(
  name: const ToolName('write'),
  description: 'Write a file',
  argsSchema: SchemaBundle(
    root: FM.object(
      'write',
      properties: () => [
        FM.prop('path', FM.string()),
        FM.prop('content', FM.string()),
      ],
    ),
  ),
  execute: (args) async {
    final params = jsonDecodeMapAs(args);
    final path = root.resolve(jsonDecodeString(params['path']));
    final content = jsonDecodeString(params['content']);
    // Create parent directories so nested paths (src/lib.dart) work in a
    // fresh workspace — the common case for a coding agent.
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString(content);
    return 'wrote $path';
  },
);

/// List the entries of a directory.
ToolDef listDirTool(FsToolsRoot root) => ToolDef(
  name: const ToolName('list_dir'),
  description: 'List a directory',
  argsSchema: SchemaBundle(
    root: FM.object(
      'list_dir',
      properties: () => [FM.prop('path', FM.string())],
    ),
  ),
  execute: (args) async {
    final params = jsonDecodeMapAs(args);
    final path = root.resolve(jsonDecodeString(params['path']));
    final entries = Directory(path).listSync().map((e) => e.path).toList();
    return jsonEncode(entries);
  },
);

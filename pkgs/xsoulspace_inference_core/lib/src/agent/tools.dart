// ignore_for_file: lines_longer_than_80_chars

/// Reusable, real tool definitions for the harness.
///
/// These are actual tool bodies (read/write/list files, clock, search) built
/// with structured [SchemaBundle] schemas — not string blobs — so they can be
/// shared across the scenario stress runner, the example host, and tests. If
/// you need a tool in more than one place, define it here and reuse it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:from_json_to_json/from_json_to_json.dart';

import 'structured_output/structured_output.dart';
import 'tool_call_parser.dart';

/// A file-system tool suite: `read`, `write`, `list_dir`.
///
/// These are real tools (they touch the disk) and are exactly the tools a
/// coding agent needs. Each is built with a structured [SchemaBundle].
List<ToolDef> fsTools() => [readTool(), writeTool(), listDirTool()];

/// Read a file's contents.
ToolDef readTool() => ToolDef.structured(
  name: const ToolName('read'),
  description: 'Read a file',
  parameters: SchemaBundle(
    root: FM.object('read', properties: () => [FM.prop('path', FM.string())]),
  ),
  execute: (args) async {
    final params = jsonDecodeMapAs(args);
    final path = jsonDecodeString(params['path']);
    return await File(path).readAsString();
  },
);

/// Write content to a file.
ToolDef writeTool() => ToolDef.structured(
  name: const ToolName('write'),
  description: 'Write a file',
  parameters: SchemaBundle(
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
    final path = jsonDecodeString(params['path']);
    final content = jsonDecodeString(params['content']);
    await File(path).writeAsString(content);
    return 'wrote $path';
  },
);

/// List the entries of a directory.
ToolDef listDirTool() => ToolDef.structured(
  name: const ToolName('list_dir'),
  description: 'List a directory',
  parameters: SchemaBundle(
    root: FM.object(
      'list_dir',
      properties: () => [FM.prop('path', FM.string())],
    ),
  ),
  execute: (args) async {
    final params = jsonDecodeMapAs(args);
    final path = jsonDecodeString(params['path']);
    final entries = Directory(path).listSync().map((e) => e.path).toList();
    return jsonEncode(entries);
  },
);

// ignore_for_file: lines_longer_than_80_chars

/// `patch_file` — the agent-facing single-op tool over TransformFlow
/// semantics: exact-match anchor, validated count==1 BEFORE writing,
/// structured diagnostics on failure. Payload = the replacement fragment
/// only, which is what cuts generated tokens on the edit path.
library;

import 'dart:io';

import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

import 'transform_flow.dart' show TransformContext;

/// Builds the tool rooted at [jailRoot] (the suite jail or workspace dir).
ToolDef patchFileTool(String jailRoot) => ToolDef.encode(
      name: const ToolName('patch_file'),
      description:
          'Replace exactly one occurrence of [anchor] in [path] with '
          '[new_text]. Fails with a structured diagnostic when the file is '
          'missing or the anchor matches more than once — nothing is written '
          'in that case. Cheaper and safer than rewriting whole files.',
      execute: (args) async {
        final raw = args;
        final map = raw is Map
            ? raw.map((k, v) => MapEntry(k.toString(), v))
            : const <String, dynamic>{};
        String? str(String key) => switch (map[key]) {
              final String s => s,
              final num n => n.toString(),
              _ => null,
            };
        final path = str('path');
        final anchor = str('anchor');
        final newText = str('new_text');
        if (path == null || anchor == null || newText == null) {
          return {
            'ok': false,
            'code': 'bad_args',
            'got': map.keys.toList(),
            'hint': 'required string args: path, anchor, new_text',
          };
        }
        try {
          final ctx = TransformContext(jailRoot);
          if (!ctx.exists(path)) {
            return {
              'ok': false,
              'code': 'file_missing',
              'path': path,
              'hint': 'use write to create it first',
            };
          }
          final matches = ctx.countMatches(path, anchor);
          if (matches != 1) {
            return {
              'ok': false,
              'code': 'anchor_not_unique',
              'path': path,
              'matches': matches,
              'hint': 'extend the anchor until it matches exactly once',
            };
          }
          final file = File('${ctx.root}/$path');
          file.writeAsStringSync(
            file.readAsStringSync().replaceFirst(anchor, newText),
          );
          return {
            'ok': true,
            'path': path,
            'replaced_chars': anchor.length,
            'generated_chars': newText.length,
          };
        } on Object catch (e) {
          // Never throw into the loop — teach instead.
          return {'ok': false, 'code': 'patch_failed', 'message': e.toString()};
        }
      },
    );

@TestOn('vm')
library;

import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';
import 'package:xsoulspace_tooling_runtime/src/owned_session_launch_embed.dart';

String _perlBodyFromFile(File plFile) {
  final pl = plFile.readAsStringSync();
  final lines = pl.split('\n');
  var start = 0;
  if (lines.first.startsWith('#!')) start = 1;
  while (start < lines.length &&
      (lines[start].trim().isEmpty || lines[start].trim().startsWith('#'))) {
    start++;
  }
  return lines
      .sublist(start)
      .where((line) {
        final trimmed = line.trim();
        return trimmed != 'use strict;' && trimmed != 'use warnings;';
      })
      .join('\n');
}

void main() {
  test('embedded owned leader matches tool/owned_session_p1_leader.pl', () async {
    final entry = Uri.parse(
      'package:xsoulspace_tooling_runtime/xsoulspace_tooling_runtime.dart',
    );
    final lib = await Isolate.resolvePackageUri(entry);
    final packageRoot = File.fromUri(lib!).parent.parent;
    final pl = File('${packageRoot.path}/tool/owned_session_p1_leader.pl');
    expect(pl.existsSync(), isTrue);
    expect(ownedSessionLaunchEmbed, _perlBodyFromFile(pl));
  });
}

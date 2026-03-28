import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

String resolvePackageRootFromPackageConfig({
  required final String currentPackageRoot,
  required final String packageName,
}) {
  final packageConfigPath = p.join(
    currentPackageRoot,
    '.dart_tool',
    'package_config.json',
  );
  final file = File(packageConfigPath);
  if (!file.existsSync()) {
    throw StateError(
      'Cannot resolve package `$packageName`: missing $packageConfigPath',
    );
  }

  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final packages = (decoded['packages']! as List<dynamic>)
      .cast<Map<String, Object?>>();
  final target = packages
      .where((final pkg) => pkg['name'] == packageName)
      .firstOrNull;
  if (target == null) {
    throw StateError(
      'Cannot resolve package `$packageName`: not found in package_config.json',
    );
  }

  final rootUriRaw = target['rootUri']! as String;
  final packageConfigDir = p.dirname(packageConfigPath);
  Uri rootUri;
  if (rootUriRaw.startsWith('file:')) {
    rootUri = Uri.parse(rootUriRaw);
  } else {
    rootUri = Uri.file(p.join(packageConfigDir, rootUriRaw));
  }

  return p.normalize(rootUri.toFilePath());
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

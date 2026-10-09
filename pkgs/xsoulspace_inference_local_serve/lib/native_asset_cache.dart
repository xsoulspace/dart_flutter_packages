/// Native build-hook cache destination; runtime resolution is separate.
library;

import 'dart:io';

/// An explicit root is supplied through cache-tracked hook user-defines.
/// This function selects a path only; callers own publication and validation.
Directory nativeAssetCacheDirectory({
  required String component,
  Object? configuredRoot,
  String? homeDirectory,
}) {
  if (!RegExp(r'^[a-z0-9_]+$').hasMatch(component)) {
    throw const FormatException('native_cache_component_invalid');
  }
  final String root;
  if (configuredRoot == null) {
    final home = homeDirectory ?? Platform.environment['HOME'] ?? '/tmp';
    root = '$home/.cache/xsoulspace';
  } else {
    if (configuredRoot is! String ||
        configuredRoot.isEmpty ||
        !Uri.directory(configuredRoot).hasAbsolutePath) {
      throw const FormatException('native_cache_root_must_be_absolute_path');
    }
    root = configuredRoot;
  }
  return Directory.fromUri(Uri.directory(root).resolve('$component/native/'));
}

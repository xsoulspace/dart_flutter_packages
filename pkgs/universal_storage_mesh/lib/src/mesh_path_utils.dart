import 'package:meta/meta.dart';

/// Normalizes storage paths the same way across replicas so identical
/// logical paths map to identical doc ids.
@internal
String normalizeMeshPath(final String raw) {
  var path = raw;
  while (path.startsWith('/')) {
    path = path.substring(1);
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path;
}

/// Encodes a normalized path into a filesystem-safe file name.
@internal
String encodeDocFileName(final String path) =>
    Uri.encodeComponent(path).replaceAll('/', '%2F');

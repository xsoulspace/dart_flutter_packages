import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:universal_storage_sync/universal_storage_sync.dart';

/// {@template hash_utils}
/// Lightweight hashing helpers for sync workflows.
/// Pure functions suitable for extraction into a shared utils package.
/// {@endtemplate}

/// Compute SHA-256 hash (hex) for a string.
String sha256Hex(final String input) =>
    crypto.sha256.convert(utf8.encode(input)).toString();

/// Normalize content by trimming trailing whitespace and collapsing CRLF.
String normalizeContent(final String input) =>
    input.replaceAll('\r\n', '\n').replaceAll(RegExp(r'[ \t]+\n'), '\n').trim();

/// Compute normalized SHA-256 (hex) for string content.
String normalizedSha256Hex(final String input) =>
    sha256Hex(normalizeContent(input));

/// Read a file via [storage] and return normalized SHA-256 hex.
/// Returns empty string if file doesn't exist.
Future<String> fileNormalizedSha256Hex(
  final StorageService storage,
  final String path,
) async {
  final content = await storage.readFile(path);
  if (content == null) return '';
  return normalizedSha256Hex(content);
}

import 'dart:io';

/// A security-scoped bookmark for a file or directory on macOS.
///
/// Docs:
/// https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox
/// https://developer.apple.com/documentation/security/app-sandbox#//apple_ref/doc/uid/TP40011183-CH3-SW16
extension type const MacOSBookmark(String value) {
  /// Creates a [MacOSBookmark] from a Base64 encoded string.
  factory MacOSBookmark.fromBase64(final String base64) =>
      MacOSBookmark(base64);

  /// Creates a [MacOSBookmark] from a [Directory] path.
  factory MacOSBookmark.fromDirectory(final Directory directory) =>
      MacOSBookmark(directory.path);

  /// Whether the bookmark is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether the bookmark is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// An empty bookmark.
  static const empty = MacOSBookmark('');
}

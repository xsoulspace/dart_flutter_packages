import 'package:path/path.dart' as path;

/// {@template file_extension}
/// Extension type that represents a file extension with type safety.
///
/// Provides compile-time safety for file extensions and ensures
/// consistent handling across the storage system.
/// {@endtemplate}
extension type const FileExtension(String value) {
  /// Creates a [FileExtension] from a file path.
  factory FileExtension.fromFilePath(final String filePath) {
    final extension = path.extension(filePath);
    return FileExtension.fromString(extension);
  }

  /// Creates a [FileExtension] from a string value.
  factory FileExtension.fromString(final String extension) {
    // Normalize extension (remove leading dot, lowercase)
    final normalized =
        (extension.startsWith('.') ? extension.substring(1) : extension)
            .toLowerCase();
    return FileExtension(normalized);
  }

  /// JSON file extension
  static const json = FileExtension('json');

  /// YAML file extension
  static const yaml = FileExtension('yaml');

  /// YML file extension (alternative YAML)
  static const yml = FileExtension('yml');

  /// Text file extension
  static const txt = FileExtension('txt');

  /// Markdown file extension
  static const md = FileExtension('md');

  /// Returns the extension with a leading dot
  String get withDot => '.$value';

  /// Returns the extension without a leading dot
  String get withoutDot => value;

  /// Checks if this is a JSON extension
  bool get isJson => value == 'json';

  /// Checks if this is a YAML extension
  bool get isYaml => value == 'yaml' || value == 'yml';

  /// Checks if this is a text-based extension
  bool get isTextBased => ['json', 'yaml', 'yml', 'txt', 'md'].contains(value);

  /// Returns the MIME type for this extension
  String get mimeType => switch (value) {
    'json' => 'application/json',
    'yaml' || 'yml' => 'text/yaml',
    'txt' => 'text/plain',
    'md' => 'text/markdown',
    _ => 'application/octet-stream',
  };
}

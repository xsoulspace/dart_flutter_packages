import 'dart:io';

/// Mutable host path policy. This is not an OS sandbox or write authority.
class WorkspacePathPolicy {
  WorkspacePathPolicy(this.rootPath, {this.pathAllowed}) {
    final dir = Directory(rootPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    rootPath = dir.resolveSymbolicLinksSync();
  }

  /// Absolute path of the jail root. Created if missing; symlinks resolved.
  String rootPath;

  /// Optional host policy over normalized absolute paths. Both the lexical
  /// request and its resolved symlink target must be allowed. Null preserves
  /// the ordinary workspace jail. This is a path policy, not an OS sandbox:
  /// hard-link aliases and concurrent filesystem replacement need host-level
  /// isolation when actors can create them.
  final bool Function(String canonicalPath)? pathAllowed;

  /// Resolve [path] (absolute or relative) inside the jail.
  ///
  /// Throws [ArgumentError] when the resolved path escapes the root. The
  /// error teaches the expected form: small models frequently hallucinate
  /// absolute workspace locations (`/tmp/config.dart`) — the rejection must
  /// say what to do instead, not just that it failed.
  String resolve(String path) {
    var raw = path.trim();
    // Strip one level of wrapping quotes some models add around arguments.
    if (raw.length >= 2 &&
        ((raw.startsWith('"') && raw.endsWith('"')) ||
            (raw.startsWith("'") && raw.endsWith("'")))) {
      raw = raw.substring(1, raw.length - 1);
      raw = raw.trim();
    }
    final candidate = _canonicalize(
      raw.startsWith('/') ? raw : '$rootPath/$raw',
    );
    _requireAllowed(candidate);
    // Resolve the nearest existing ancestor even when the requested file
    // does not yet exist. This handles an in-root symlink to an outside
    // directory and still permits writes under a new in-root directory.
    // It also accepts alternate spellings of the same root (/var ↔
    // /private/var on macOS).
    final real = _existingRealPath(candidate);
    if (real != null && _insideRoot(real)) {
      _requireAllowed(real);
      return real;
    }
    throw ArgumentError(
      'Path escapes the allowed root: "$path". '
      'Use paths RELATIVE to the workspace root — for example "config.dart" '
      'or "src/lib.dart" — never absolute filesystem paths like "/tmp/..." or '
      '"/Users/...". Call list_dir with path "." to see the workspace.',
    );
  }

  /// Whether a discovery child is accessible without opening its contents.
  /// Traversal skips denied children; explicitly requested paths still throw
  /// through [resolve].
  bool allows(String path) {
    try {
      resolve(path);
      return true;
      // resolve's existing public refusal contract is ArgumentError; discovery
      // must suppress only that refusal, not arbitrary policy failures.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return false;
    }
  }

  void _requireAllowed(String path) {
    if (!(pathAllowed?.call(path) ?? true)) {
      throw ArgumentError('Path is unavailable under host filesystem policy.');
    }
  }

  bool _insideRoot(String path) =>
      rootPath == '/' || path == rootPath || path.startsWith('$rootPath/');

  /// Real path of the nearest existing ancestor of [path] (symlinks
  /// resolved), with the non-existent remainder rejoined lexically. Null
  /// when nothing up to the filesystem root exists (never in practice).
  static String? _existingRealPath(String path) {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    for (var take = parts.length; take >= 1; take--) {
      final ancestor = '/${parts.take(take).join('/')}';
      final type = FileSystemEntity.typeSync(ancestor, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      try {
        final realAncestor = switch (type) {
          FileSystemEntityType.directory => Directory(
            ancestor,
          ).resolveSymbolicLinksSync(),
          FileSystemEntityType.file => File(
            ancestor,
          ).resolveSymbolicLinksSync(),
          FileSystemEntityType.link => Link(
            ancestor,
          ).resolveSymbolicLinksSync(),
          _ => null,
        };
        if (realAncestor == null) return null;
        final rest = parts.skip(take).toList();
        return _canonicalize(
          rest.isEmpty ? realAncestor : '$realAncestor/${rest.join('/')}',
        );
      } on FileSystemException {
        // An existing but unresolvable link (including a dangling one) must
        // not be treated as a plain missing child of its safe parent.
        return null;
      }
    }
    return null;
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

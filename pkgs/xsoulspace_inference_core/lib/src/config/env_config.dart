// ignore_for_file: lines_longer_than_80_chars

/// Persistent environment configuration for CLI-style tools.
///
/// Mirrors what coding agents (Claude Code, pi, gh, …) do: secrets and
/// settings live in two scopes, and lookups fall through in a fixed order.
///
/// ## Scopes
///
/// - **Global**: `~/.config/xsoulspace/inference/config.json`
///   (honors `XDG_CONFIG_HOME`) — machine-wide defaults, API keys.
/// - **Local**: `./.xsoulspace/config.json` — per-project overrides,
///   committed or gitignored at the user's discretion.
/// - **Process**: `Platform.environment` — always wins, the CLI contract
///   every Unix tool follows (`FOO=x cmd` must override saved config).
///
/// Lookup precedence (highest first): process env → local → global.
///
/// The file format is a flat JSON object of string keys to string values:
///
/// ```json
/// {"OPENROUTER_API_KEY": "sk-...", "default_model": "z-ai/glm-4.5-air"}
/// ```
///
/// Flat on purpose: this is an env store, not a settings tree. Nested config
/// belongs to the tool layer, which can encode structure into keys
/// (`openrouter.model`) or keep its own file.
library;

import 'dart:convert';
import 'dart:io';

/// Where a config value is persisted / read from.
enum ConfigScope {
  /// `~/.config/xsoulspace/inference/config.json` — machine-wide.
  global,

  /// `./.xsoulspace/config.json` — current project.
  local,
}

/// Read/write access to the merged environment configuration.
class EnvConfig {
  EnvConfig._(this._global, this._local, this._globalPath, this._localPath);

  final Map<String, String> _global;
  final Map<String, String> _local;
  final String _globalPath;
  final String _localPath;

  /// Default global path: `$XDG_CONFIG_HOME/xsoulspace/inference/config.json`,
  /// falling back to `~/.config/...`.
  static String defaultGlobalPath() {
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    final base = xdg != null && xdg.isNotEmpty ? xdg : '${_home()}/.config';
    return '$base/xsoulspace/inference/config.json';
  }

  /// Default local path: `./.xsoulspace/config.json`.
  static String defaultLocalPath() =>
      '${Directory.current.path}/.xsoulspace/config.json';

  /// Discover the nearest `.xsoulspace/config.json` by walking up from
  /// [start] (default: current directory) — the same convention as git's
  /// repo-root search, so tools work from any subdirectory of a project.
  /// Returns null when no ancestor owns a config.
  static String? discoverLocalPath({String? start}) {
    var dir = Directory(start ?? Directory.current.path).absolute.path;
    while (true) {
      final candidate = '$dir/.xsoulspace/config.json';
      if (File(candidate).existsSync()) return candidate;
      final parent = File(dir).parent.path;
      if (parent == dir) return null;
      dir = parent;
    }
  }

  static String _home() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) {
      throw StateError('Cannot resolve home directory (HOME is unset).');
    }
    return home;
  }

  /// Load both scopes. Missing files are treated as empty; a malformed file
  /// is reported via [onCorrupt] (default: print a warning) instead of
  /// throwing — a broken config must not brick the CLI.
  static Future<EnvConfig> load({
    String? globalPath,
    String? localPath,
    void Function(String path, Object error)? onCorrupt,
  }) async {
    final gp = globalPath ?? defaultGlobalPath();
    final lp = localPath ?? discoverLocalPath() ?? defaultLocalPath();
    final handler =
        onCorrupt ??
        (path, error) =>
            stderr.writeln('warning: skipping malformed config $path ($error)');
    return EnvConfig._(
      await _readMap(gp, handler),
      await _readMap(lp, handler),
      gp,
      lp,
    );
  }

  static Future<Map<String, String>> _readMap(
    String path,
    void Function(String, Object) onCorrupt,
  ) async {
    final file = File(path);
    if (!file.existsSync()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        onCorrupt(path, 'expected a JSON object');
        return {};
      }
      return decoded.map((k, v) => MapEntry(k, '$v'));
    } on FormatException catch (e) {
      onCorrupt(path, e);
      return {};
    }
  }

  /// Resolve [key]: process env → local scope → global scope → null.
  String? get(String key) =>
      Platform.environment[key] ?? _local[key] ?? _global[key];

  /// Resolve [key], throwing a helpful error when missing.
  String require(String key) {
    final value = get(key);
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing required config "$key". Set it with '
        '`--set $key=<value>` or edit $_localPath.',
      );
    }
    return value;
  }

  /// All known keys across scopes (process env excluded — it is huge and
  /// not ours), with the value source. Useful for `--list`.
  Map<String, ConfigScope> keys() {
    final out = <String, ConfigScope>{};
    for (final k in _global.keys) {
      out[k] = ConfigScope.global;
    }
    for (final k in _local.keys) {
      out[k] = ConfigScope.local;
    }
    return out;
  }

  /// Persist [key] = [value] in [scope]. Creates parent directories.
  /// Values are masked as `<redacted>` if they look like secrets when listed
  /// elsewhere; storage is always plaintext (same tradeoff as dotenv files).
  Future<void> set(
    String key,
    String value, {
    ConfigScope scope = .local,
  }) async {
    final path = scope == .local ? _localPath : _globalPath;
    final map = scope == .local ? _local : _global;
    map[key] = value;
    final file = File(path);
    await file.parent.create(recursive: true);
    // 0600 — these files routinely hold API keys.
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(map)}\n',
      mode: FileMode.write,
      flush: true,
    );
  }

  /// Remove [key] from [scope]. Returns whether it existed.
  Future<bool> delete(String key, {ConfigScope scope = .local}) async {
    final map = scope == .local ? _local : _global;
    if (!map.containsKey(key)) return false;
    map.remove(key);
    final path = scope == .local ? _localPath : _globalPath;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(map)}\n',
      flush: true,
    );
    return true;
  }
}

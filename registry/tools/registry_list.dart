import 'dart:convert';
import 'dart:io';

/// Lists package names (and optionally latest versions) from a local registry
/// build or from the live gateway.
Future<void> main(final List<String> args) async {
  final options = _ListOptions.parse(args);
  List<String> names;
  Map<String, String>? latestVersions;

  if (options.outputDirectory != null) {
    final dir = options.outputDirectory!;
    final namesFile = File('$dir/api/package-names.json');
    if (!namesFile.existsSync()) {
      stderr.writeln('Not found: ${namesFile.path}. Run registry-build-index first.');
      exit(1);
    }
    final payload = jsonDecode(await namesFile.readAsString()) as Map<String, Object?>;
    final raw = payload['packages'];
    if (raw is! List) {
      stderr.writeln('package-names.json has no "packages" list.');
      exit(1);
    }
    names = raw.whereType<String>().toList()..sort();

    if (options.showVersions) {
      latestVersions = {};
      for (final name in names) {
        final pkgFile = File('$dir/api/packages/$name.json');
        if (pkgFile.existsSync()) {
          final pkg = jsonDecode(await pkgFile.readAsString()) as Map<String, Object?>;
          final latest = pkg['latest'];
          if (latest is Map && latest['version'] is String) {
            latestVersions[name] = latest['version'] as String;
          }
        }
      }
    }
  } else {
    final baseUrl = options.gatewayUrl!.replaceFirst(RegExp(r'/+$'), '');
    final namesUrl = '$baseUrl/api/package-names';
    final body = await _httpGet(namesUrl);
    if (body == null) {
      stderr.writeln('GET $namesUrl failed.');
      exit(1);
    }
    final payload = jsonDecode(body) as Map<String, Object?>;
    final raw = payload['packages'];
    if (raw is! List) {
      stderr.writeln('Response has no "packages" list.');
      exit(1);
    }
    names = raw.whereType<String>().toList()..sort();

    if (options.showVersions) {
      latestVersions = {};
      for (final name in names) {
        final pkgUrl = '$baseUrl/api/packages/$name';
        final b = await _httpGet(pkgUrl);
        if (b != null) {
          final pkg = jsonDecode(b) as Map<String, Object?>;
          final latest = pkg['latest'];
          if (latest is Map && latest['version'] is String) {
            latestVersions[name] = latest['version'] as String;
          }
        }
      }
    }
  }

  if (latestVersions != null) {
    for (final name in names) {
      final v = latestVersions[name];
      stdout.writeln(v != null ? '$name $v' : name);
    }
  } else {
    for (final name in names) {
      stdout.writeln(name);
    }
  }
}

Future<String?> _httpGet(final String url) async {
  final uri = Uri.parse(url);
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != 200) return null;
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

class _ListOptions {
  const _ListOptions({
    this.outputDirectory,
    this.gatewayUrl,
    required this.showVersions,
  });

  final String? outputDirectory;
  final String? gatewayUrl;
  final bool showVersions;

  static _ListOptions parse(final List<String> args) {
    String? outputDirectory;
    String? gatewayUrl;
    var showVersions = false;

    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--output-dir':
          if (i + 1 < args.length) {
            outputDirectory = args[++i];
          }
          break;
        case '--gateway-url':
          if (i + 1 < args.length) {
            gatewayUrl = args[++i];
          }
          break;
        case '--versions':
        case '-v':
          showVersions = true;
          break;
      }
    }

    if (outputDirectory != null && gatewayUrl != null) {
      stderr.writeln('Use either --output-dir or --gateway-url, not both.');
      exit(64);
    }
    if (outputDirectory == null && gatewayUrl == null) {
      outputDirectory = '${Directory.current.path}/build/registry';
    }

    return _ListOptions(
      outputDirectory: outputDirectory,
      gatewayUrl: gatewayUrl,
      showVersions: showVersions,
    );
  }
}

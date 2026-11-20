import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'workspace_graph.dart';

/// One doctor finding; `severity` is `error` (blocks releases) or `warning`.
final class DoctorFinding {
  DoctorFinding({
    required this.code,
    required this.severity,
    required this.message,
  });

  final String code;
  final String severity;
  final String message;

  @override
  String toString() => '[$severity] $code: $message';
}

/// pub.dev presence for one package.
enum PubDevStatus { exists, newPackage, lookupFailed }

final class PubDevInfo {
  PubDevInfo({required this.status, this.latestVersion});

  final PubDevStatus status;
  final String? latestVersion;
}

/// Read-only client over the pub.dev package API; injectable for tests.
abstract class PubDevClient {
  Future<PubDevInfo> lookup(String package);

  /// All published version strings for [package]; empty for new packages.
  Future<List<String>> versions(String package);
}

final class HttpPubDevClient implements PubDevClient {
  HttpPubDevClient({this.baseUrl = 'https://pub.dev', this.timeoutMs = 15000});

  final String baseUrl;
  final int timeoutMs;

  @override
  Future<PubDevInfo> lookup(String package) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse('$baseUrl/api/packages/$package'))
          .timeout(Duration(milliseconds: timeoutMs));
      final response = await request.close();
      final body = await response.transform(const Utf8Decoder()).join();
      if (response.statusCode == 404) {
        return PubDevInfo(status: PubDevStatus.newPackage);
      }
      if (response.statusCode != 200) {
        return PubDevInfo(status: PubDevStatus.lookupFailed);
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final latest = json['latest'] as Map<String, dynamic>?;
      return PubDevInfo(
        status: PubDevStatus.exists,
        latestVersion: latest?['version']?.toString(),
      );
    } on Exception {
      return PubDevInfo(status: PubDevStatus.lookupFailed);
    } finally {
      client.close();
    }
  }

  @override
  Future<List<String>> versions(String package) async {
    final client = HttpClient();
    try {
      final request = await client
          .getUrl(Uri.parse('$baseUrl/api/packages/$package'))
          .timeout(Duration(milliseconds: timeoutMs));
      final response = await request.close();
      final body = await response.transform(const Utf8Decoder()).join();
      if (response.statusCode != 200) return const <String>[];
      final json = jsonDecode(body) as Map<String, dynamic>;
      final versions = json['versions'] as List<dynamic>? ?? const [];
      return <String>[
        for (final v in versions)
          ((v as Map<String, dynamic>)['version'] ?? '').toString(),
      ];
    } on Exception {
      return const <String>[];
    } finally {
      client.close();
    }
  }
}

/// Runs the release gates plus (optionally) the pub.dev presence census.
final class DoctorReport {
  DoctorReport({required this.findings, required this.census});

  final List<DoctorFinding> findings;

  /// package name → presence (empty when `--no-network`).
  final Map<String, PubDevInfo> census;

  bool get hasErrors => findings.any((f) => f.severity == 'error');

  int get errorCount => findings.where((f) => f.severity == 'error').length;
}

Future<DoctorReport> runDoctor({
  required WorkspaceGraph graph,
  required ChangesetsConfig config,
  required String changesetsDir,
  PubDevClient? pubDevClient,
  bool census = true,
}) async {
  final findings = <DoctorFinding>[];

  for (final pkg in graph.publishable) {
    // Gate 1: no path dependencies in publishable packages — `pub publish`
    // refuses them and they break hosted resolution.
    for (final entry in pkg.dependencies.entries) {
      if (entry.value.isPath) {
        findings.add(
          DoctorFinding(
            code: 'path_dep_in_publishable',
            severity: 'error',
            message: '${pkg.name} depends on ${entry.key} via path '
                '(${entry.value.path}); publishable packages must use '
                'hosted constraints.',
          ),
        );
      }
    }

    // Gate 2: publishable packages must not depend on private packages
    // (the dependency-driven conversion rule — convert the private package
    // first, or the release train cannot publish this package).
    for (final entry in pkg.dependencies.entries) {
      final dep = graph.packages[entry.key];
      if (dep == null) continue;
      if (!dep.publishable) {
        findings.add(
          DoctorFinding(
            code: 'depends_on_private',
            severity: 'error',
            message: '${pkg.name} depends on ${entry.key} which is '
                '`publish_to: none`. Remove publish_to from ${entry.key} '
                '(and convert its path dependencies) before releasing '
                '${pkg.name}.',
          ),
        );
      }
    }

    // Gate 3: publish-required files present.
    final dir = pkg.directory;
    for (final required in const <String>['CHANGELOG.md', 'README.md', 'LICENSE']) {
      if (!File('$dir${Platform.pathSeparator}$required').existsSync()) {
        findings.add(
          DoctorFinding(
            code: 'missing_file',
            severity: 'error',
            message: '${pkg.name} is missing $required (required to publish).',
          ),
        );
      }
    }

    // Warning: homepage/repository missing → pub publish prints a warning.
    final content = pkg.pubspecContent;
    if (!content.contains('homepage:') && !content.contains('repository:')) {
      findings.add(
        DoctorFinding(
          code: 'missing_repository_field',
          severity: 'warning',
          message: '${pkg.name} declares neither homepage: nor repository:.',
        ),
      );
    }
  }

  // Warning: mixed SDK floors across the publishable set.
  final sdkFloors = <String>{};
  for (final pkg in graph.publishable) {
    final sdk = pkg.sdkConstraint;
    if (sdk != null) sdkFloors.add(sdk);
  }
  if (sdkFloors.length > 1) {
    findings.add(
      DoctorFinding(
        code: 'mixed_sdk_floors',
        severity: 'warning',
        message: 'publishable packages declare mixed SDK constraints: '
            '${sdkFloors.toList()..sort()}',
      ),
    );
  }

  final censusResults = <String, PubDevInfo>{};
  if (census) {
    final client =
        pubDevClient ?? HttpPubDevClient();
    for (final pkg in graph.publishable) {
      censusResults[pkg.name] = await client.lookup(pkg.name);
    }
  }

  return DoctorReport(findings: findings, census: censusResults);
}

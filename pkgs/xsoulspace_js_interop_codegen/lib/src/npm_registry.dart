import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'hashes.dart';

final class NpmLockConfig {
  const NpmLockConfig({
    required this.packageName,
    required this.version,
    required this.integrity,
  });

  final String packageName;
  final String version;
  final String integrity;

  Map<String, Object?> toJson() => <String, Object?>{
    'package': packageName,
    'version': version,
    'integrity': integrity,
  };

  static NpmLockConfig fromJson(final Map<String, Object?> json) => NpmLockConfig(
      packageName: json['package']! as String,
      version: json['version']! as String,
      integrity: json['integrity']! as String,
    );
}

final class RegistryVersionInfo {
  const RegistryVersionInfo({
    required this.version,
    required this.tarball,
    required this.integrity,
  });

  final String version;
  final String tarball;
  final String integrity;

  static RegistryVersionInfo fromRegistryJson(final Map<String, Object?> json) {
    final dist = json['dist']! as Map<String, Object?>;
    return RegistryVersionInfo(
      version: json['version']! as String,
      tarball: dist['tarball']! as String,
      integrity: dist['integrity']! as String,
    );
  }
}

Future<RegistryVersionInfo> fetchRegistryVersionInfo(
  final String packageEncoded,
  final String version,
) async {
  final uri = Uri.parse('https://registry.npmjs.org/$packageEncoded/$version');
  final response = await http.get(uri);
  if (response.statusCode != 200) {
    throw StateError(
      'Failed to fetch npm metadata ($version): ${response.statusCode}',
    );
  }
  final decoded = jsonDecode(response.body) as Map<String, Object?>;
  return RegistryVersionInfo.fromRegistryJson(decoded);
}

Future<Uint8List> downloadTarball(final String tarballUrl) async {
  final response = await http.get(Uri.parse(tarballUrl));
  if (response.statusCode != 200) {
    throw StateError('Failed to download tarball: ${response.statusCode}');
  }
  return response.bodyBytes;
}

void verifyIntegrity(final String integrity, final Uint8List tarballBytes) {
  final parts = integrity.split('-');
  if (parts.length != 2 || parts.first != 'sha512') {
    throw StateError('Unsupported integrity format: $integrity');
  }

  final actual = sha512Base64(tarballBytes);
  if (actual != parts[1]) {
    throw StateError('Tarball integrity verification failed.');
  }
}

Future<String> extractTarGzFile({
  required final String tempDir,
  required final Uint8List tarballBytes,
  required final bool Function(String path) selector,
  required final String outputName,
  required final String missingError,
}) async {
  final decodedTar = const GZipDecoder().decodeBytes(tarballBytes);
  final archive = TarDecoder().decodeBytes(decodedTar);

  ArchiveFile? entry;
  for (final file in archive) {
    if (file.isFile && selector(file.name)) {
      entry = file;
      break;
    }
  }

  if (entry == null) {
    throw StateError(missingError);
  }

  final outPath = p.join(tempDir, outputName);
  final outFile = File(outPath);
  final content = entry.content as List<int>;
  await outFile.writeAsBytes(content, flush: true);
  return outPath;
}

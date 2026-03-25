import 'package:meta/meta.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';

/// Error categories returned by CloudKit bridge implementations.
enum CloudKitBridgeErrorCode {
  authentication,
  network,
  transient,
  conflict,
  notFound,
  payloadTooLarge,
  unsupported,
  unknown,
}

@immutable
class CloudKitBridgeException implements Exception {
  const CloudKitBridgeException({
    required this.code,
    required this.message,
    this.details = const <String, Object?>{},
  });

  final CloudKitBridgeErrorCode code;
  final String message;
  final Map<String, Object?> details;

  @override
  String toString() =>
      'CloudKitBridgeException(code: ${code.name}, message: $message)';
}

@immutable
class CloudKitBridgeConfig {
  const CloudKitBridgeConfig({
    required this.containerId,
    required this.environment,
    required this.databaseScope,
    required this.zoneName,
    required this.recordType,
    required this.maxInlineBytes,
    this.webApiToken,
  });

  factory CloudKitBridgeConfig.fromStorageConfig(final CloudKitConfig config) =>
      CloudKitBridgeConfig(
        containerId: config.containerId,
        environment: config.environment,
        databaseScope: config.databaseScope,
        zoneName: config.zoneName,
        recordType: config.recordType,
        maxInlineBytes: config.maxInlineBytes,
        webApiToken: config.webApiToken,
      );

  final String containerId;
  final CloudKitEnvironment environment;
  final CloudKitDatabaseScope databaseScope;
  final String zoneName;
  final String recordType;
  final int maxInlineBytes;
  final String? webApiToken;

  Map<String, Object?> toMap() => <String, Object?>{
    'containerId': containerId,
    'environment': environment.name,
    'databaseScope': databaseScope.name,
    'zoneName': zoneName,
    'recordType': recordType,
    'maxInlineBytes': maxInlineBytes,
    if (webApiToken != null) 'webApiToken': webApiToken,
  };
}

@immutable
class CloudKitRecord {
  const CloudKitRecord({
    required this.recordName,
    required this.path,
    required this.content,
    required this.checksum,
    required this.size,
    required this.updatedAt,
    this.changeTag,
  });

  factory CloudKitRecord.fromMap(final Map<String, Object?> map) =>
      CloudKitRecord(
        recordName: (map['recordName'] ?? '').toString(),
        path: (map['path'] ?? '').toString(),
        content: (map['content'] ?? '').toString(),
        checksum: (map['checksum'] ?? '').toString(),
        size: (map['size'] as num?)?.toInt() ?? 0,
        updatedAt:
            DateTime.tryParse((map['updatedAt'] ?? '').toString()) ??
            DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
        changeTag: map['changeTag']?.toString(),
      );

  final String recordName;
  final String path;
  final String content;
  final String checksum;
  final int size;
  final DateTime updatedAt;
  final String? changeTag;

  Map<String, Object?> toMap() => <String, Object?>{
    'recordName': recordName,
    'path': path,
    'content': content,
    'checksum': checksum,
    'size': size,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (changeTag != null) 'changeTag': changeTag,
  };
}

@immutable
class CloudKitDelta {
  const CloudKitDelta({
    this.updatedRecords = const <CloudKitRecord>[],
    this.deletedPaths = const <String>[],
    this.nextServerChangeToken,
  });

  factory CloudKitDelta.empty() => const CloudKitDelta();

  final List<CloudKitRecord> updatedRecords;
  final List<String> deletedPaths;
  final String? nextServerChangeToken;
}

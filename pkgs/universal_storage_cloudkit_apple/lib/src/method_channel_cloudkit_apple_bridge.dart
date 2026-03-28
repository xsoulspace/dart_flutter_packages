import 'package:flutter/services.dart';
import 'package:universal_storage_cloudkit_platform_interface/universal_storage_cloudkit_platform_interface.dart';

import 'cloudkit_apple_api.g.dart';
import 'cloudkit_apple_api_client.dart';

/// Registers the Apple CloudKit bridge as active platform bridge.
void registerCloudKitAppleBridge() {
  CloudKitBridgePlatform.instance = MethodChannelCloudKitAppleBridge(
    apiClient: PigeonCloudKitAppleApiClient(),
  );
}

/// Pigeon-backed CloudKit bridge for iOS/macOS.
class MethodChannelCloudKitAppleBridge implements CloudKitBridge {
  MethodChannelCloudKitAppleBridge({final CloudKitAppleApiClient? apiClient})
    : _apiClient = apiClient ?? PigeonCloudKitAppleApiClient();

  final CloudKitAppleApiClient _apiClient;

  @override
  Future<void> initialize(final CloudKitBridgeConfig config) async {
    await _invoke<void>(
      () => _apiClient.initialize(
        CloudKitAppleConfigData(
          containerId: config.containerId,
          environment: config.environment.name,
          databaseScope: config.databaseScope.name,
          zoneName: config.zoneName,
          recordType: config.recordType,
          maxInlineBytes: config.maxInlineBytes,
          webApiToken: config.webApiToken,
        ),
      ),
    );
  }

  @override
  Future<CloudKitRecord?> fetchRecordByPath(final String path) async =>
      _invoke<CloudKitRecord?>(() async {
        final response = await _apiClient.fetchRecordByPath(path);
        if (response == null) {
          return null;
        }

        return _toRecord(response);
      });

  @override
  Future<void> saveRecord(final CloudKitRecord record) async {
    await _invoke<void>(
      () => _apiClient.saveRecord(
        CloudKitAppleRecordData(
          recordName: record.recordName,
          path: record.path,
          content: record.content,
          checksum: record.checksum,
          size: record.size,
          updatedAtIso8601: record.updatedAt.toUtc().toIso8601String(),
          changeTag: record.changeTag,
        ),
      ),
    );
  }

  @override
  Future<void> deleteRecord(final String recordName) async {
    await _invoke<void>(() => _apiClient.deleteRecord(recordName));
  }

  @override
  Future<List<CloudKitRecord>> queryByPathPrefix(
    final String pathPrefix,
  ) async => _invoke<List<CloudKitRecord>>(() async {
    final response = await _apiClient.queryByPathPrefix(pathPrefix);
    return response.map(_toRecord).toList(growable: false);
  });

  @override
  Future<CloudKitDelta> fetchChanges({final String? serverChangeToken}) async =>
      _invoke<CloudKitDelta>(() async {
        final response = await _apiClient.fetchChanges(serverChangeToken);
        return CloudKitDelta(
          updatedRecords: response.updatedRecords
              .map(_toRecord)
              .toList(growable: false),
          deletedPaths: response.deletedPaths,
          nextServerChangeToken: response.nextServerChangeToken,
        );
      });

  @override
  Future<void> dispose() async {
    await _invoke<void>(_apiClient.dispose);
  }

  Future<T> _invoke<T>(final Future<T> Function() callback) async {
    try {
      return await callback();
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    }
  }

  CloudKitRecord _toRecord(final CloudKitAppleRecordData data) =>
      CloudKitRecord(
        recordName: data.recordName,
        path: data.path,
        content: data.content,
        checksum: data.checksum,
        size: data.size,
        updatedAt:
            DateTime.tryParse(data.updatedAtIso8601) ??
            DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
        changeTag: data.changeTag,
      );

  CloudKitBridgeException _mapPlatformException(final PlatformException error) {
    final code = switch (error.code) {
      'auth' => CloudKitBridgeErrorCode.authentication,
      'network' => CloudKitBridgeErrorCode.network,
      'transient' => CloudKitBridgeErrorCode.transient,
      'conflict' => CloudKitBridgeErrorCode.conflict,
      'notFound' => CloudKitBridgeErrorCode.notFound,
      'payloadTooLarge' => CloudKitBridgeErrorCode.payloadTooLarge,
      'unsupported' => CloudKitBridgeErrorCode.unsupported,
      _ => CloudKitBridgeErrorCode.unknown,
    };

    return CloudKitBridgeException(
      code: code,
      message: error.message ?? 'CloudKit platform channel call failed.',
      details: <String, Object?>{
        if (error.details != null) 'details': error.details,
      },
    );
  }
}

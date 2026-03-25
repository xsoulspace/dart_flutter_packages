import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/cloudkit_apple_api.g.dart',
    swiftOut: 'ios/Classes/CloudKitAppleApi.g.swift',
    swiftOptions: SwiftOptions(),
  ),
)
@HostApi()
abstract class CloudKitAppleHostApi {
  @async
  void initialize(final CloudKitAppleConfigData config);

  @async
  CloudKitAppleRecordData? fetchRecordByPath(final String path);

  @async
  void saveRecord(final CloudKitAppleRecordData record);

  @async
  void deleteRecord(final String recordName);

  @async
  List<CloudKitAppleRecordData> queryByPathPrefix(final String pathPrefix);

  @async
  CloudKitAppleDeltaData fetchChanges(final String? serverChangeToken);

  @async
  void dispose();
}

class CloudKitAppleConfigData {
  const CloudKitAppleConfigData({
    required this.containerId,
    required this.environment,
    required this.databaseScope,
    required this.zoneName,
    required this.recordType,
    required this.maxInlineBytes,
    this.webApiToken,
  });

  final String containerId;
  final String environment;
  final String databaseScope;
  final String zoneName;
  final String recordType;
  final int maxInlineBytes;
  final String? webApiToken;
}

class CloudKitAppleRecordData {
  const CloudKitAppleRecordData({
    required this.recordName,
    required this.path,
    required this.content,
    required this.checksum,
    required this.size,
    required this.updatedAtIso8601,
    this.changeTag,
  });

  final String recordName;
  final String path;
  final String content;
  final String checksum;
  final int size;
  final String updatedAtIso8601;
  final String? changeTag;
}

class CloudKitAppleDeltaData {
  const CloudKitAppleDeltaData({
    this.updatedRecords = const <CloudKitAppleRecordData>[],
    this.deletedPaths = const <String>[],
    this.nextServerChangeToken,
  });

  final List<CloudKitAppleRecordData> updatedRecords;
  final List<String> deletedPaths;
  final String? nextServerChangeToken;
}

import CloudKit
import Foundation

#if os(iOS)
import Flutter
import UIKit
#elseif os(macOS)
import Cocoa
import FlutterMacOS
#endif

public final class UniversalStorageCloudKitApplePlugin: NSObject, FlutterPlugin,
  CloudKitAppleHostApi
{
  private let stateQueue = DispatchQueue(
    label: "com.xsoulspace.universal_storage_cloudkit_apple.state"
  )

  private let dateFormatterWithFractionalSeconds: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private let dateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private var database: CKDatabase?
  private var zoneID: CKRecordZone.ID?
  private var recordType = "USFile"
  private var maxInlineBytes = 262_144

  // Persistent mapping is required to translate deleted record IDs back to paths.
  private var pathByRecordName: [String: String] = [:]
  private var cacheFileURL: URL?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = UniversalStorageCloudKitApplePlugin()
    #if os(iOS)
    CloudKitAppleHostApiSetup.setUp(
      binaryMessenger: registrar.messenger(),
      api: instance
    )
    #elseif os(macOS)
    CloudKitAppleHostApiSetup.setUp(
      binaryMessenger: registrar.messenger,
      api: instance
    )
    #endif
  }

  public func initialize(
    config: CloudKitAppleConfigData,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard config.databaseScope == "privateDb" else {
      completion(
        .failure(
          PigeonError(
            code: "unsupported",
            message: "Only private CloudKit database scope is supported.",
            details: nil
          )
        )
      )
      return
    }

    let container = CKContainer(identifier: config.containerId)
    let database = container.privateCloudDatabase
    let zoneID = CKRecordZone.ID(
      zoneName: config.zoneName,
      ownerName: CKCurrentUserDefaultName
    )

    let cacheURL = makeCacheFileURL(
      containerId: config.containerId,
      zoneName: config.zoneName,
      recordType: config.recordType
    )

    do {
      try ensureCacheDirectoryExists(for: cacheURL)
      let cachedMap = try loadPathCache(from: cacheURL)
      stateQueue.sync {
        self.database = database
        self.zoneID = zoneID
        self.recordType = config.recordType
        self.maxInlineBytes = Int(config.maxInlineBytes)
        self.cacheFileURL = cacheURL
        self.pathByRecordName = cachedMap
      }
    } catch {
      completion(.failure(mapError(error)))
      return
    }

    ensureZoneExists(database: database, zoneID: zoneID) { [weak self] result in
      guard let self else {
        completion(
          .failure(
            PigeonError(
              code: "unknown",
              message: "CloudKit bridge deallocated during initialization.",
              details: nil
            )
          )
        )
        return
      }

      switch result {
      case .success:
        completion(.success(()))
      case .failure(let error):
        completion(.failure(self.mapError(error)))
      }
    }
  }

  public func fetchRecordByPath(
    path: String,
    completion: @escaping (Result<CloudKitAppleRecordData?, Error>) -> Void
  ) {
    guard let state = currentState() else {
      completion(.failure(notInitializedError()))
      return
    }

    let predicate = NSPredicate(format: "path == %@", path)
    queryRecords(
      database: state.database,
      zoneID: state.zoneID,
      recordType: state.recordType,
      predicate: predicate
    ) { [weak self] result in
      guard let self else {
        completion(
          .failure(
            PigeonError(
              code: "unknown",
              message: "CloudKit bridge deallocated during fetch.",
              details: nil
            )
          )
        )
        return
      }

      switch result {
      case .success(let records):
        guard let record = records.first else {
          completion(.success(nil))
          return
        }

        do {
          let data = try self.toRecordData(record)
          self.cacheMapping(recordName: data.recordName, path: data.path)
          completion(.success(data))
        } catch {
          completion(.failure(self.mapError(error)))
        }
      case .failure(let error):
        completion(.failure(self.mapError(error)))
      }
    }
  }

  public func saveRecord(
    record: CloudKitAppleRecordData,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let state = currentState() else {
      completion(.failure(notInitializedError()))
      return
    }

    let contentSize = record.content.utf8.count
    if contentSize > state.maxInlineBytes {
      completion(
        .failure(
          PigeonError(
            code: "payloadTooLarge",
            message: "Payload exceeds maxInlineBytes for CloudKit inline content.",
            details: [
              "payloadBytes": "\(contentSize)",
              "maxInlineBytes": "\(state.maxInlineBytes)",
            ]
          )
        )
      )
      return
    }

    let recordID = CKRecord.ID(recordName: record.recordName, zoneID: state.zoneID)
    let ckRecord = CKRecord(recordType: state.recordType, recordID: recordID)
    ckRecord["path"] = record.path as CKRecordValue
    ckRecord["content"] = record.content as CKRecordValue
    ckRecord["checksum"] = record.checksum as CKRecordValue
    ckRecord["size"] = NSNumber(value: record.size) as CKRecordValue
    ckRecord["updatedAt"] = parseDate(from: record.updatedAtIso8601) as CKRecordValue

    if let changeTag = record.changeTag, !changeTag.isEmpty {
      ckRecord.recordChangeTag = changeTag
    }

    let operation = CKModifyRecordsOperation(recordsToSave: [ckRecord], recordIDsToDelete: nil)
    operation.isAtomic = true
    let shouldUseBlindOverwrite =
      (record.changeTag?.isEmpty ?? true)
    operation.savePolicy = shouldUseBlindOverwrite
      ? .allKeys
      : .ifServerRecordUnchanged
    operation.modifyRecordsCompletionBlock = { [weak self] savedRecords, _, error in
      guard let self else {
        completion(
          .failure(
            PigeonError(
              code: "unknown",
              message: "CloudKit bridge deallocated during save.",
              details: nil
            )
          )
        )
        return
      }

      if let error {
        completion(.failure(self.mapError(error)))
        return
      }

      let saved = savedRecords?.first ?? ckRecord
      if let savedPath = saved["path"] as? String {
        self.cacheMapping(recordName: saved.recordID.recordName, path: savedPath)
      }

      completion(.success(()))
    }

    state.database.add(operation)
  }

  public func deleteRecord(
    recordName: String,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let state = currentState() else {
      completion(.failure(notInitializedError()))
      return
    }

    let recordID = CKRecord.ID(recordName: recordName, zoneID: state.zoneID)
    state.database.delete(withRecordID: recordID) { [weak self] _, error in
      guard let self else {
        completion(
          .failure(
            PigeonError(
              code: "unknown",
              message: "CloudKit bridge deallocated during delete.",
              details: nil
            )
          )
        )
        return
      }

      if let error {
        completion(.failure(self.mapError(error)))
        return
      }

      self.removeCachedMapping(recordName: recordName)
      completion(.success(()))
    }
  }

  public func queryByPathPrefix(
    pathPrefix: String,
    completion: @escaping (Result<[CloudKitAppleRecordData], Error>) -> Void
  ) {
    guard let state = currentState() else {
      completion(.failure(notInitializedError()))
      return
    }

    let predicate = pathPrefix.isEmpty
      ? NSPredicate(value: true)
      : NSPredicate(format: "path BEGINSWITH %@", pathPrefix)

    queryRecords(
      database: state.database,
      zoneID: state.zoneID,
      recordType: state.recordType,
      predicate: predicate
    ) { [weak self] result in
      guard let self else {
        completion(
          .failure(
            PigeonError(
              code: "unknown",
              message: "CloudKit bridge deallocated during query.",
              details: nil
            )
          )
        )
        return
      }

      switch result {
      case .success(let records):
        let normalizedPrefix = pathPrefix.isEmpty || pathPrefix.hasSuffix("/")
          ? pathPrefix
          : "\(pathPrefix)/"

        var output: [CloudKitAppleRecordData] = []
        output.reserveCapacity(records.count)

        for record in records {
          guard let mapped = try? self.toRecordData(record) else {
            continue
          }

          if pathPrefix.isEmpty
            || mapped.path == pathPrefix
            || mapped.path.hasPrefix(normalizedPrefix)
          {
            output.append(mapped)
          }

          self.cacheMapping(recordName: mapped.recordName, path: mapped.path)
        }

        completion(.success(output))
      case .failure(let error):
        completion(.failure(self.mapError(error)))
      }
    }
  }

  public func fetchChanges(
    serverChangeToken: String?,
    completion: @escaping (Result<CloudKitAppleDeltaData, Error>) -> Void
  ) {
    guard let state = currentState() else {
      completion(.failure(notInitializedError()))
      return
    }

    let previousToken: CKServerChangeToken?
    do {
      previousToken = try decodeToken(serverChangeToken)
    } catch {
      completion(.failure(mapError(error)))
      return
    }

    let options = CKFetchRecordZoneChangesOperation.ZoneOptions()
    options.previousServerChangeToken = previousToken

    let operation = CKFetchRecordZoneChangesOperation(
      recordZoneIDs: [state.zoneID],
      optionsByRecordZoneID: [state.zoneID: options]
    )
    operation.fetchAllChanges = true

    let callbackQueue = DispatchQueue(
      label: "com.xsoulspace.universal_storage_cloudkit_apple.fetch_changes"
    )

    var updatedRecords: [CloudKitAppleRecordData] = []
    var deletedRecordNames: [String] = []
    var nextToken: CKServerChangeToken?
    var terminalError: Error?

    operation.recordChangedBlock = { [weak self] record in
      guard let self else { return }
      guard let mapped = try? self.toRecordData(record) else {
        return
      }

      callbackQueue.sync {
        updatedRecords.append(mapped)
      }
    }

    operation.recordWithIDWasDeletedBlock = { recordID, _ in
      callbackQueue.sync {
        deletedRecordNames.append(recordID.recordName)
      }
    }

    operation.recordZoneFetchCompletionBlock = { _, serverToken, _, _, error in
      callbackQueue.sync {
        if let serverToken {
          nextToken = serverToken
        }
        if let error {
          terminalError = error
        }
      }
    }

    operation.fetchRecordZoneChangesCompletionBlock = { [weak self] error in
      guard let self else {
        completion(
          .failure(
            PigeonError(
              code: "unknown",
              message: "CloudKit bridge deallocated during change fetch.",
              details: nil
            )
          )
        )
        return
      }

      callbackQueue.sync {
        if let error {
          terminalError = error
        }
      }

      if let terminalError {
        completion(.failure(self.mapError(terminalError)))
        return
      }

      let deletedPaths = deletedRecordNames.compactMap { self.cachedPath(for: $0) }
      deletedRecordNames.forEach { self.removeCachedMapping(recordName: $0) }
      updatedRecords.forEach {
        self.cacheMapping(recordName: $0.recordName, path: $0.path)
      }

      do {
        let encodedToken = try self.encodeToken(nextToken)
        completion(
          .success(
            CloudKitAppleDeltaData(
              updatedRecords: updatedRecords,
              deletedPaths: deletedPaths,
              nextServerChangeToken: encodedToken
            )
          )
        )
      } catch {
        completion(.failure(self.mapError(error)))
      }
    }

    state.database.add(operation)
  }

  public func dispose(completion: @escaping (Result<Void, Error>) -> Void) {
    stateQueue.sync {
      database = nil
      zoneID = nil
      recordType = "USFile"
      maxInlineBytes = 262_144
      pathByRecordName = [:]
      cacheFileURL = nil
    }

    completion(.success(()))
  }

  private typealias CloudKitState = (
    database: CKDatabase,
    zoneID: CKRecordZone.ID,
    recordType: String,
    maxInlineBytes: Int
  )

  private func currentState() -> CloudKitState? {
    stateQueue.sync {
      guard let database, let zoneID else {
        return nil
      }

      return (database, zoneID, recordType, maxInlineBytes)
    }
  }

  private func notInitializedError() -> Error {
    PigeonError(
      code: "unsupported",
      message: "CloudKit bridge is not initialized.",
      details: nil
    )
  }

  private func ensureZoneExists(
    database: CKDatabase,
    zoneID: CKRecordZone.ID,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    let zone = CKRecordZone(zoneID: zoneID)
    let operation = CKModifyRecordZonesOperation(
      recordZonesToSave: [zone],
      recordZoneIDsToDelete: nil
    )
    operation.modifyRecordZonesCompletionBlock = { _, _, error in
      if let error {
        completion(.failure(error))
        return
      }

      completion(.success(()))
    }

    database.add(operation)
  }

  private func queryRecords(
    database: CKDatabase,
    zoneID: CKRecordZone.ID,
    recordType: String,
    predicate: NSPredicate,
    completion: @escaping (Result<[CKRecord], Error>) -> Void
  ) {
    let query = CKQuery(recordType: recordType, predicate: predicate)
    let operation = CKQueryOperation(query: query)
    operation.zoneID = zoneID
    operation.desiredKeys = ["path", "content", "checksum", "size", "updatedAt"]

    executeQueryOperation(
      database: database,
      operation: operation,
      accumulated: [],
      completion: completion
    )
  }

  private func executeQueryOperation(
    database: CKDatabase,
    operation: CKQueryOperation,
    accumulated: [CKRecord],
    completion: @escaping (Result<[CKRecord], Error>) -> Void
  ) {
    var records = accumulated
    operation.recordFetchedBlock = { record in
      records.append(record)
    }

    operation.queryCompletionBlock = { [weak self] cursor, error in
      guard let self else {
        completion(
          .failure(
            PigeonError(
              code: "unknown",
              message: "CloudKit bridge deallocated during query pagination.",
              details: nil
            )
          )
        )
        return
      }

      if let error {
        completion(.failure(error))
        return
      }

      guard let cursor else {
        completion(.success(records))
        return
      }

      let nextOperation = CKQueryOperation(cursor: cursor)
      nextOperation.desiredKeys = operation.desiredKeys
      self.executeQueryOperation(
        database: database,
        operation: nextOperation,
        accumulated: records,
        completion: completion
      )
    }

    database.add(operation)
  }

  private func toRecordData(_ record: CKRecord) throws -> CloudKitAppleRecordData {
    guard let path = record["path"] as? String else {
      throw PigeonError(
        code: "unknown",
        message: "CloudKit record is missing required field `path`.",
        details: nil
      )
    }

    let content = (record["content"] as? String) ?? ""
    let checksum = (record["checksum"] as? String) ?? ""

    let size: Int64
    if let int64Value = record["size"] as? Int64 {
      size = int64Value
    } else if let intValue = record["size"] as? Int {
      size = Int64(intValue)
    } else if let numberValue = record["size"] as? NSNumber {
      size = numberValue.int64Value
    } else {
      size = Int64(content.utf8.count)
    }

    let updatedAtDate =
      (record["updatedAt"] as? Date)
      ?? record.modificationDate
      ?? Date(timeIntervalSince1970: 0)

    return CloudKitAppleRecordData(
      recordName: record.recordID.recordName,
      path: path,
      content: content,
      checksum: checksum,
      size: size,
      updatedAtIso8601: dateFormatterWithFractionalSeconds.string(from: updatedAtDate),
      changeTag: record.recordChangeTag
    )
  }

  private func parseDate(from iso8601: String) -> Date {
    if let parsed = dateFormatterWithFractionalSeconds.date(from: iso8601) {
      return parsed
    }

    if let parsed = dateFormatter.date(from: iso8601) {
      return parsed
    }

    return Date()
  }

  private func cacheMapping(recordName: String, path: String) {
    stateQueue.sync {
      pathByRecordName[recordName] = path
    }
    persistPathCache()
  }

  private func removeCachedMapping(recordName: String) {
    stateQueue.sync {
      pathByRecordName.removeValue(forKey: recordName)
    }
    persistPathCache()
  }

  private func cachedPath(for recordName: String) -> String? {
    stateQueue.sync {
      pathByRecordName[recordName]
    }
  }

  private func persistPathCache() {
    let snapshot: [String: String]
    let fileURL: URL?
    stateQueue.sync {
      snapshot = pathByRecordName
      fileURL = cacheFileURL
    }

    guard let fileURL else {
      return
    }

    do {
      let data = try JSONSerialization.data(
        withJSONObject: snapshot,
        options: [.sortedKeys]
      )
      try data.write(to: fileURL, options: [.atomic])
    } catch {
      // Cache persistence should not fail user operations.
    }
  }

  private func makeCacheFileURL(
    containerId: String,
    zoneName: String,
    recordType: String
  ) -> URL? {
    let baseDirectory = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first

    guard let baseDirectory else {
      return nil
    }

    let rootDirectory = baseDirectory.appendingPathComponent(
      "universal_storage_cloudkit_apple",
      isDirectory: true
    )

    let fileName = "\(sanitizeForFileName(containerId))_\(sanitizeForFileName(zoneName))_\(sanitizeForFileName(recordType))_path_cache_v1.json"
    return rootDirectory.appendingPathComponent(fileName, isDirectory: false)
  }

  private func sanitizeForFileName(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let scalars = value.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? Character(scalar) : "_"
    }
    return String(scalars)
  }

  private func ensureCacheDirectoryExists(for fileURL: URL?) throws {
    guard let fileURL else {
      return
    }

    let directoryURL = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true,
      attributes: nil
    )
  }

  private func loadPathCache(from fileURL: URL?) throws -> [String: String] {
    guard
      let fileURL,
      FileManager.default.fileExists(atPath: fileURL.path)
    else {
      return [:]
    }

    let data = try Data(contentsOf: fileURL)
    let decoded = try JSONSerialization.jsonObject(with: data)
    guard let map = decoded as? [String: String] else {
      return [:]
    }

    return map
  }

  private func encodeToken(_ token: CKServerChangeToken?) throws -> String? {
    guard let token else {
      return nil
    }

    let data = try NSKeyedArchiver.archivedData(
      withRootObject: token,
      requiringSecureCoding: true
    )
    return data.base64EncodedString()
  }

  private func decodeToken(_ encodedToken: String?) throws -> CKServerChangeToken? {
    guard let encodedToken, !encodedToken.isEmpty else {
      return nil
    }

    guard let data = Data(base64Encoded: encodedToken) else {
      throw PigeonError(
        code: "unknown",
        message: "Invalid CloudKit server change token encoding.",
        details: nil
      )
    }

    return try NSKeyedUnarchiver.unarchivedObject(
      ofClass: CKServerChangeToken.self,
      from: data
    )
  }

  private func mapError(_ error: Error) -> Error {
    if error is PigeonError {
      return error
    }

    guard let ckError = error as? CKError else {
      return PigeonError(
        code: "unknown",
        message: error.localizedDescription,
        details: nil
      )
    }

    if ckError.code == .partialFailure,
      let nestedErrors = ckError.partialErrorsByItemID,
      let firstNested = nestedErrors.values.first
    {
      return mapError(firstNested)
    }

    let code: String
    switch ckError.code {
    case .notAuthenticated:
      code = "auth"
    case .networkUnavailable, .networkFailure:
      code = "network"
    case .serviceUnavailable, .requestRateLimited, .zoneBusy:
      code = "transient"
    case .serverRecordChanged:
      code = "conflict"
    case .unknownItem, .zoneNotFound:
      code = "notFound"
    case .assetFileTooLarge, .limitExceeded, .quotaExceeded:
      code = "payloadTooLarge"
    case .missingEntitlement, .badContainer:
      code = "unsupported"
    default:
      code = "unknown"
    }

    return PigeonError(
      code: code,
      message: ckError.localizedDescription,
      details: ["ckCode": "\(ckError.code.rawValue)"]
    )
  }
}

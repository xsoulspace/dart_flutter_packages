import CloudKit
import Foundation

struct CloudKitAppleSupportError: Error, Equatable {
  let code: String
  let message: String
  let details: [String: String]?
}

enum CloudKitAppleTokenCodec {
  static func encode(_ token: CKServerChangeToken?) throws -> String? {
    try encodeSecureObject(token)
  }

  static func decode(_ encodedToken: String?) throws -> CKServerChangeToken? {
    try decodeSecureObject(encodedToken, as: CKServerChangeToken.self)
  }

  static func encodeSecureObject<T: NSObject & NSSecureCoding>(_ value: T?) throws -> String? {
    guard let value else {
      return nil
    }

    let data = try NSKeyedArchiver.archivedData(
      withRootObject: value,
      requiringSecureCoding: true
    )
    return data.base64EncodedString()
  }

  static func decodeSecureObject<T: NSObject & NSSecureCoding>(
    _ encodedToken: String?,
    as type: T.Type
  ) throws -> T? {
    guard let encodedToken, !encodedToken.isEmpty else {
      return nil
    }

    guard let data = Data(base64Encoded: encodedToken) else {
      throw CloudKitAppleSupportError(
        code: "unknown",
        message: "Invalid CloudKit server change token encoding.",
        details: nil
      )
    }

    return try NSKeyedUnarchiver.unarchivedObject(ofClass: type, from: data)
  }
}

enum CloudKitAppleErrorMapper {
  static func map(_ error: Error) -> CloudKitAppleSupportError {
    if let supportError = error as? CloudKitAppleSupportError {
      return supportError
    }

    guard let ckError = error as? CKError else {
      return CloudKitAppleSupportError(
        code: "unknown",
        message: error.localizedDescription,
        details: nil
      )
    }

    if ckError.code == .partialFailure,
      let nestedErrors = ckError.partialErrorsByItemID,
      let firstNested = nestedErrors.values.first
    {
      return map(firstNested)
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
    case .limitExceeded, .quotaExceeded:
      code = "payloadTooLarge"
    case .missingEntitlement, .badContainer:
      code = "unsupported"
    default:
      code = "unknown"
    }

    return CloudKitAppleSupportError(
      code: code,
      message: ckError.localizedDescription,
      details: ["ckCode": "\(ckError.code.rawValue)"]
    )
  }
}

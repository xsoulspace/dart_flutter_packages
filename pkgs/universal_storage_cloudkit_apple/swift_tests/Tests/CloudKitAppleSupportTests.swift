import CloudKit
@testable import CloudKitAppleSupport
import XCTest

final class CloudKitAppleSupportTests: XCTestCase {
  func testDecodeTokenReturnsNilForNilAndEmptyInput() throws {
    XCTAssertNil(try CloudKitAppleTokenCodec.decode(nil))
    XCTAssertNil(try CloudKitAppleTokenCodec.decode(""))
  }

  func testDecodeTokenThrowsForInvalidBase64Input() {
    XCTAssertThrowsError(try CloudKitAppleTokenCodec.decode("not-base64")) { error in
      guard let support = error as? CloudKitAppleSupportError else {
        XCTFail("Expected CloudKitAppleSupportError")
        return
      }
      XCTAssertEqual(support.code, "unknown")
      XCTAssertEqual(support.message, "Invalid CloudKit server change token encoding.")
      XCTAssertNil(support.details)
    }
  }

  func testEncodeDecodeSecureObjectRoundTrip() throws {
    let original = NSString(string: "change-token-placeholder")
    let encoded = try CloudKitAppleTokenCodec.encodeSecureObject(original)
    XCTAssertNotNil(encoded)

    let decoded = try CloudKitAppleTokenCodec.decodeSecureObject(
      encoded,
      as: NSString.self
    )
    XCTAssertEqual(decoded, original)
  }

  func testCloudKitErrorCodeMapping() {
    XCTAssertEqual(
      CloudKitAppleErrorMapper.map(CKError(.notAuthenticated)).code,
      "auth"
    )
    XCTAssertEqual(
      CloudKitAppleErrorMapper.map(CKError(.networkFailure)).code,
      "network"
    )
    XCTAssertEqual(
      CloudKitAppleErrorMapper.map(CKError(.serviceUnavailable)).code,
      "transient"
    )
    XCTAssertEqual(
      CloudKitAppleErrorMapper.map(CKError(.serverRecordChanged)).code,
      "conflict"
    )
    XCTAssertEqual(
      CloudKitAppleErrorMapper.map(CKError(.unknownItem)).code,
      "notFound"
    )
    XCTAssertEqual(
      CloudKitAppleErrorMapper.map(CKError(.limitExceeded)).code,
      "payloadTooLarge"
    )
    XCTAssertEqual(
      CloudKitAppleErrorMapper.map(CKError(.badContainer)).code,
      "unsupported"
    )
    XCTAssertEqual(
      CloudKitAppleErrorMapper.map(CKError(.internalError)).code,
      "unknown"
    )
  }

  func testPartialFailureUnwrapsNestedCloudKitError() {
    let nested = CKError(.serverRecordChanged)
    let recordID = CKRecord.ID(recordName: "record_1")
    let partial = CKError(
      .partialFailure,
      userInfo: [CKPartialErrorsByItemIDKey: [recordID: nested]]
    )

    let mapped = CloudKitAppleErrorMapper.map(partial)
    XCTAssertEqual(mapped.code, "conflict")
    XCTAssertEqual(mapped.details?["ckCode"], "\(CKError.Code.serverRecordChanged.rawValue)")
  }

  func testSupportErrorIsReturnedAsIs() {
    let original = CloudKitAppleSupportError(
      code: "unknown",
      message: "custom message",
      details: ["k": "v"]
    )
    let mapped = CloudKitAppleErrorMapper.map(original)
    XCTAssertEqual(mapped, original)
  }
}

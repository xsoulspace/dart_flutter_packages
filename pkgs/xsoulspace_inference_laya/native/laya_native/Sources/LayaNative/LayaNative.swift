import Darwin
import Foundation
import MLX

/// C ABI surface for dart:ffi. All calls are JSON-in/JSON-out with C strings;
/// returned strings are owned by the caller and released with
/// `laya_native_free`.
///
/// Request (forward):
/// ```json
/// {"batch":[{"ids":[..],"markers":[..],"qtype":0}]}
/// ```
/// Response:
/// ```json
/// {"logits":[[...]],"act":[[...]]}
/// ```
/// Errors return `{"error":"..."}`. The forward path is serialized behind a
/// lock; the harness server serves decisions one at a time.
private let registryLock = NSLock()
private var nextHandle: Int64 = 1
private var registry: [Int64: LayaWeights] = [:]
private let forwardLock = NSLock()

private func fail(_ message: String) -> UnsafeMutablePointer<CChar>? {
    strdup("{\"error\":\(jsonString(message))}")
}

private func jsonString(_ value: String) -> String {
    guard let data = try? JSONEncoder().encode([value]),
        let encoded = String(data: data, encoding: .utf8)
    else { return "\"\"" }
    // JSONEncoder encoded ["<value>"]; strip the surrounding brackets.
    let body = encoded.dropFirst().dropLast()
    return String(body)
}

@_cdecl("laya_native_load")
public func laya_native_load(_ modelDir: UnsafePointer<CChar>?) -> Int64 {
    guard let modelDir else { return -1 }
    pinMetallibColocated()
    registryLock.lock()
    defer { registryLock.unlock() }
    do {
        let model = try LayaWeights.load(modelDir: String(cString: modelDir))
        let handle = nextHandle
        nextHandle += 1
        registry[handle] = model
        return handle
    } catch {
        return -2
    }
}

/// Pins MLX's metallib override to the one colocated with THIS dylib.
///
/// mlx's automatic search checks `<current-binary-dir>/mlx.metallib`, where
/// "current binary" is the main executable — a bare dart process — so the
/// colocated file beside the loaded dylib is never found, and a bare dart
/// process has no SwiftPM bundle for the bundle fallback. Resolving this
/// dylib's own path with dladdr and setting the override before the first
/// GPU op closes both gaps.
private func pinMetallibColocated() {
    var info = dl_info()
    let symbol = unsafeBitCast(
        laya_native_load as @convention(c) (UnsafePointer<CChar>?) -> Int64,
        to: UnsafeRawPointer.self)
    guard dladdr(symbol, &info) != 0, let imagePath = info.dli_fname else {
        return
    }
    let dir = URL(fileURLWithPath: String(cString: imagePath))
        .deletingLastPathComponent()
    let metallib = dir.appendingPathComponent("mlx.metallib")
    if FileManager.default.fileExists(atPath: metallib.path) {
        GPU.metallib = metallib
    }
}

@_cdecl("laya_native_forward")
public func laya_native_forward(
    _ handle: Int64,
    _ requestJson: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    guard let requestJson else { return fail("missing request") }
    registryLock.lock()
    let model = registry[handle]
    registryLock.unlock()
    guard model != nil else { return fail("unknown handle") }
    guard
        let request = try? JSONSerialization.jsonObject(
            with: Data(bytes: requestJson, count: strlen(requestJson))
        ) as? [String: Any],
        let rawBatch = request["batch"] as? [[String: Any]]
    else { return fail("unreadable request JSON") }

    var ids: [[Int32]] = []
    var masks: [[Int32]] = []
    var markerPos: [[Int32]] = []
    var markerMask: [[Int32]] = []
    var qtypes: [Int32] = []
    for row in rawBatch {
        guard let rowIds = row["ids"] as? [Int],
            let rowMarkers = row["markers"] as? [Int],
            let rowQtype = row["qtype"] as? Int
        else { return fail("batch row missing ids/markers/qtype") }
        let count = max(2, rowMarkers.count)
        var rowMask = [Int32](repeating: 0, count: rowIds.count)
        for i in 0..<rowIds.count { rowMask[i] = 1 }
        var pos = [Int32](repeating: 0, count: count)
        var mMask = [Int32](repeating: 0, count: count)
        for (i, m) in rowMarkers.enumerated() where i < count {
            pos[i] = Int32(m)
            mMask[i] = 1
        }
        ids.append(rowIds.map { Int32($0) })
        masks.append(rowMask)
        markerPos.append(pos)
        markerMask.append(mMask)
        qtypes.append(Int32(rowQtype))
    }

    forwardLock.lock()
    defer { forwardLock.unlock() }
    do {
        let batch = LayaWeights.Batch(
            inputIds: padToRectangular(ids),
            attentionMask: padToRectangular(masks),
            markerPos: padToRectangular(markerPos),
            markerMask: padToRectangular(markerMask),
            qtype: MLXArray(qtypes))
        let (logits, act) = model!.forward(batch)
        eval(logits, act)
        // Materialize as float32 — astype(float64) is unsupported on the
        // GPU, so doubles are made host-side from floats.
        let kmax = batch.markerMask.dim(1)
        let logitsFlat = logits.asType(.float32).asArray(Float.self)
        let actFlat = act.asType(.float32).asArray(Float.self)
        let b = logits.dim(0)
        var logitsOut: [[Double]] = []
        var actOut: [[Double]] = []
        for r in 0..<b {
            logitsOut.append(
                (0..<kmax).map { Double(logitsFlat[r * kmax + $0]) })
            actOut.append((0..<2).map { Double(actFlat[r * 2 + $0]) })
        }
        var response: [String: Any] = [:]
        response["logits"] = logitsOut
        response["act"] = actOut
        let data = try JSONSerialization.data(withJSONObject: response)
        return strdup(String(data: data, encoding: .utf8) ?? "{\"error\":\"encode\"}")
    } catch {
        return fail("forward failed: \(error)")
    }
}

private func padToRectangular(_ rows: [[Int32]]) -> MLXArray {
    let width = rows.map { $0.count }.max() ?? 0
    var padded: [[Int32]] = []
    for row in rows {
        var copy = row
        if copy.count < width {
            copy.append(contentsOf: [Int32](repeating: 0, count: width - copy.count))
        }
        padded.append(copy)
    }
    return MLXArray(padded.flatMap { $0 }, [rows.count, width])
}

@_cdecl("laya_native_free")
public func laya_native_free(_ pointer: UnsafeMutablePointer<CChar>?) {
    free(pointer)
}

@_cdecl("laya_native_unload")
public func laya_native_unload(_ handle: Int64) {
    registryLock.lock()
    defer { registryLock.unlock() }
    registry.removeValue(forKey: handle)
}

/// NFC (canonical composed) normalization — the checkpoint tokenizer's
/// normalizer. Output requires up to 4 bytes per input UTF-8 byte.
/// Returns the number of bytes written, or -1 when out is too small.
@_cdecl("laya_native_normalize")
public func laya_native_normalize(
    _ src: UnsafePointer<CChar>?,
    _ out: UnsafeMutablePointer<CChar>?,
    _ outCap: Int32
) -> Int32 {
    guard let src, let out else { return -1 }
    let text = String(cString: src)
    let normalized = text.precomposedStringWithCanonicalMapping
    let bytes = normalized.utf8
    guard bytes.count + 1 <= Int(outCap) else { return -1 }
    var index = 0
    for byte in bytes {
        out.advanced(by: index).pointee = CChar(bitPattern: byte)
        index += 1
    }
    out.advanced(by: index).pointee = 0
    return Int32(index)
}

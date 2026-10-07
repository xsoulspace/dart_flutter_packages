import Foundation
import MLX

/// Minimal safetensors reader for the F16 Laya checkpoint.
///
/// The format is an 8-byte little-endian header length, a JSON header mapping
/// tensor name -> {dtype, shape, data_offsets}, then the raw buffer. We only
/// need F16 tensors, materialized as MLXArrays (one copy from the file into
/// managed memory; MLX moves them to the GPU on first evaluation).
enum Safetensors {
    struct TensorInfo {
        let dtype: String
        let shape: [Int]
        let start: Int
        let end: Int
    }

    static func loadFloat16(path: String, wanted: Set<String>) throws -> [String: MLXArray] {
        let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? file.close() }
        let headerLenData = try file.read(upToCount: 8) ?? Data()
        guard headerLenData.count == 8 else {
            throw NSError(
                domain: "laya.safetensors", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "truncated safetensors header"]
            )
        }
        let headerLen = headerLenData.withUnsafeBytes {
            $0.loadUnaligned(as: UInt64.self).littleEndian
        }
        let headerData = try file.read(upToCount: Int(headerLen)) ?? Data()
        guard let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
            throw NSError(
                domain: "laya.safetensors", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "unreadable safetensors header JSON"]
            )
        }
        // The data section starts right after the header (8 + headerLen).
        let dataStart = 8 + Int(headerLen)
        var result: [String: MLXArray] = [:]
        for (name, value) in header {
            guard name != "__metadata__", wanted.contains(name),
                  let entry = value as? [String: Any],
                  let dtype = entry["dtype"] as? String,
                  let shape = entry["shape"] as? [Int],
                  let offsets = entry["data_offsets"] as? [Int], offsets.count == 2
            else { continue }
            guard dtype == "F16" else {
                throw NSError(
                    domain: "laya.safetensors", code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "unsupported dtype \(dtype) for \(name); expected F16"
                    ]
                )
            }
            try file.seek(toOffset: UInt64(dataStart + offsets[0]))
            let count = offsets[1] - offsets[0]
            let raw = try file.read(upToCount: count) ?? Data()
            guard raw.count == count else {
                throw NSError(
                    domain: "laya.safetensors", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "short read for \(name)"]
                )
            }
            let scalars = raw.withUnsafeBytes { buf -> [Float16] in
                let base = buf.bindMemory(to: Float16.self)
                return Array(base)
            }
            result[name] = MLXArray(scalars, shape)
        }
        return result
    }
}

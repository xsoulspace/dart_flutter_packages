import Darwin
import Foundation
import MLX
import MLXLMCommon
import MLXLLM
import Tokenizers

/// C ABI surface for dart:ffi. JSON-in/JSON-out with C strings; returned
/// strings are owned by the caller and released with `mlx_text_free`.
///
/// The generation machinery is ml-explore/mlx-swift-lm's (model registry,
/// chat templates, KV cache, samplers); this shim adds only the ABI: a
/// tokenizer loader bridging swift-transformers (the 3.x decoupling — no
/// public loader ships), a handle registry, a single-flight generate lock
/// (the MLX wired-memory limit is per-process), and the JSON contract.
///
/// Request (generate):
/// ```json
/// {"system":"...","prompt":"...","max_tokens":128,"temperature":0.0,
///  "kv_bits":null,"prefill_step":null,"prefill_unchunked":false}
/// ```
/// (`kv_bits` opts into KV-cache quantization; `stop` strings are trimmed
/// post-hoc, the template's EOS is the real stop; `prefill_step` caps
/// tokens per prefill forward — nil is each model's default — and
/// `prefill_unchunked` runs the whole prompt in one forward.)
///
/// Response:
/// ```json
/// {"text":"...","prompt_tokens":741,"completion_tokens":41,
///  "prompt_time_ms":230,"generate_time_ms":880,"template_ms":12,
///  "stop_reason":"stop"}
/// ```
/// Errors return `{"error":"..."}`.
private let registryLock = NSLock()
private var nextHandle: Int64 = 1
private var registry: [Int64: ModelContainer] = [:]
private let generateLock = NSLock()

/// The cross-request prompt cache: the KV caches of the LAST generation
/// plus the exact prompt tokens they hold (generated tokens are trimmed
/// off after each generation, so the ledger stays exact). The next
/// request reuses the common prefix and prefills only its suffix — the
/// same primitive `mlx_lm.server`'s prompt cache provides; without it the
/// repeated-shape workloads (drafting lanes, benchmarks) pay full prefill
/// every call.
private var reusedCache: [KVCache]?
private var cachedPromptTokens: [Int] = []

/// Wall time of the last chat-template application (the diagnostics field
/// `template_ms`; the generate lock serializes writers).
private var lastTemplateMs: Double = 0



private func commonPrefixLength(_ a: [Int], _ b: [Int]) -> Int {
    var i = 0
    let limit = min(a.count, b.count)
    while i < limit && a[i] == b[i] { i += 1 }
    return i
}

/// Bridges swift-transformers' tokenizer to MLXLMCommon.Tokenizer — the
/// same shape the MLXHuggingFace macro expansion generates.
private struct TransformersFolderLoader: TokenizerLoader {
    init() {}

    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await Tokenizers.AutoTokenizer.from(
            modelFolder: directory)
        return TransformersBridge(upstream)
    }
}

private struct TransformersBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    // swift-transformers uses `decode(tokens:)` instead of `decode(tokenIds:)`.
    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages, tools: tools, additionalContext: additionalContext)
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

private func fail(_ message: String) -> UnsafeMutablePointer<CChar>? {
    strdup("{\"error\":\(jsonString(message))}")
}

private func jsonString(_ value: String) -> String {
    guard
        let data = try? JSONSerialization.data(withJSONObject: [value]),
        let encoded = String(data: data, encoding: .utf8)
    else { return "\"\"" }
    // JSONSerialization encoded ["<value>"]; strip the surrounding brackets.
    let body = encoded.dropFirst().dropLast()
    return String(body)
}

private func responseJson(_ fields: [String: Any]) -> UnsafeMutablePointer<CChar>? {
    guard let data = try? JSONSerialization.data(withJSONObject: fields),
        let text = String(data: data, encoding: .utf8)
    else { return fail("could not encode response") }
    return strdup(text)
}

/// Bridges the library's async load to the synchronous C ABI.
private func awaitAsync<T>(_ body: @escaping () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        Task {
            do {
                box.value = try await body()
            } catch {
                box.error = error
            }
            semaphore.signal()
        }
    }
    semaphore.wait()
    return try box.get()
}

private final class ResultBox<T>: @unchecked Sendable {
    var value: T?
    var error: (any Error)?

    func get() throws -> T {
        if let error { throw error }
        return value!
    }
}

@_cdecl("mlx_text_load")
public func mlx_text_load(_ modelDir: UnsafePointer<CChar>?) -> Int64 {
    guard let modelDir else { return -1 }
    registryLock.lock()
    defer { registryLock.unlock() }
    do {
        let container = try awaitAsync { [dir = String(cString: modelDir)] in
            try await LLMModelFactory.shared.loadContainer(
                from: URL(fileURLWithPath: dir),
                using: TransformersFolderLoader())
        }
        let handle = nextHandle
        nextHandle += 1
        registry[handle] = container
        return handle
    } catch {
        // -2 with the message on stderr: the load failure is an operator
        // fact (missing weights, bad snapshot), not a wire response.
        FileHandle.standardError.write(
            Data("[mlx_text_native] load failed: \(error)\n".utf8))
        return -2
    }
}

@_cdecl("mlx_text_generate")
public func mlx_text_generate(
    _ handle: Int64, _ requestJson: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    guard let requestJson else { return fail("missing request") }
    registryLock.lock()
    let container = registry[handle]
    registryLock.unlock()
    guard let container else { return fail("unknown handle \(handle)") }

    guard
        let raw = try? JSONSerialization.jsonObject(
            with: Data(bytes: requestJson, count: strlen(requestJson))),
        let request = raw as? [String: Any]
    else { return fail("request was not a JSON object") }

    var messages = [[String: any Sendable]]()
    if let system = request["system"] as? String, !system.isEmpty {
        messages.append(["role": "system", "content": system])
    }
    messages.append([
        "role": "user", "content": request["prompt"] as? String ?? "",
    ])

    let maxTokens = request["max_tokens"] as? Int ?? 320
    let temperature = Float(request["temperature"] as? Double ?? 0.0)
    let kvBits = request["kv_bits"] as? Int
    let stop = request["stop"] as? [String] ?? []
    // Prefill shaping: `prefill_step` caps tokens per prefill forward
    // (nil = each model's default, 512 on the generic path);
    // `prefill_unchunked` runs the whole prompt in one forward.
    let prefillStep = request["prefill_step"] as? Int
    let prefillUnchunked = request["prefill_unchunked"] as? Bool ?? false
    // Chat-template kwargs (e.g. Qwen3's enable_thinking:false), passed
    // through as the template's additional context. JSON booleans arrive
    // as NSNumber, and jinja's Value(any:) maps NSNumber to a NUMBER
    // before it would map to a boolean (`as Int` matches first) — so a
    // `false` kwarg would fail the template's `is false` test. Restore
    // real booleans from the CF type before handing the map over.
    let templateArgs = (request["template_args"] as? [String: Any])?.mapValues {
        (value: Any) -> any Sendable in
        if let number = value as? NSNumber,
            CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
        }
        return value
    }

    // One generation at a time: the KV cache and the wired-memory limit
    // are per-process, single-model resources.
    generateLock.lock()
    defer { generateLock.unlock() }

    do {
        // All async work (tokenizer access, template, stream) lives in the
        // bridged block; the C surface stays synchronous.
        let outcome = try awaitAsync { () -> (String, GenerateCompletionInfo?) in
            var parameters = GenerateParameters(
                maxTokens: maxTokens,
                kvBits: kvBits,
                temperature: temperature,
                topP: 1.0
            )
            parameters.prefill.stepSize = prefillStep
            if prefillUnchunked {
                parameters.prefill.chunking = .unchunked
            }
            return try await container.perform { context in
                // Direct context access only: re-entering
                // container.tokenizer here would nest a context read and
                // deadlock the actor.
                let tokenizer = context.tokenizer
                let templateStart = DispatchTime.now()
                let promptTokens = try tokenizer.applyChatTemplate(
                    messages: messages,
                    tools: nil,
                    additionalContext: templateArgs
                )
                lastTemplateMs = Double(
                    DispatchTime.now().uptimeNanoseconds
                        - templateStart.uptimeNanoseconds
                ) / 1_000_000_000

                // Reuse the common prefix of the previous request's KV
                // state; prefill only the suffix. The free generate()
                // re-enters the context actor, so the low-level
                // TokenIterator drives the loop INSIDE the single perform
                // (a nested read deadlocks).
                var inputTokens = promptTokens
                var caches = reusedCache
                if let cache = caches, !cache.isEmpty {
                    var common = commonPrefixLength(cachedPromptTokens, promptTokens)
                    // A full match would leave an empty suffix — keep at
                    // least one token to prefill (the pre-cache behavior).
                    if common >= promptTokens.count {
                        common = promptTokens.count - 1
                    }
                    var aligned = common >= 16 && common >= 1
                    if aligned {
                        // Trim and VERIFY alignment (ChatSession's rule):
                        // sliding-window layers can refuse a rewind; a
                        // misaligned cache silently corrupts generation.
                        for entry in cache {
                            let expected = entry.offset - common
                            let trimmed = entry.trim(expected)
                            if trimmed != expected || entry.offset != common {
                                aligned = false
                                break
                            }
                        }
                    }
                    if aligned {
                        inputTokens = Array(promptTokens[common...])
                    } else {
                        // Rebuild from scratch this request and drop the
                        // suspect cache entirely.
                        caches = nil
                        reusedCache = nil
                        cachedPromptTokens = []
                    }
                }
                if caches == nil {
                    caches = try context.model.newCache(parameters: parameters)
                }

                // The main model comes from THIS context (direct access);
                // the draft was boxed out before the perform.
                let mainModel = context.model

                // Measured around construction, not the first next(): the
                // TokenIterator init runs the whole prompt prefill
                // (prepare() -> model.prepare + chunked evaluate), and the
                // cache allocation in front of it is part of prompt
                // processing too. The loop below is decode only.
                let startedAt = DispatchTime.now()
                let input = LMInput(text: .init(tokens: MLXArray(inputTokens)))
                var iterator = try TokenIterator(
                    prompt: MLXArray(inputTokens),
                    model: mainModel,
                    cache: caches,
                    parameters: parameters
                )
                let promptTime = Double(
                    DispatchTime.now().uptimeNanoseconds
                        - startedAt.uptimeNanoseconds
                ) / 1_000_000_000
                // Any iterator stops only at maxTokens — the EOS check is
                // the caller's job (the generate() wrapper does it; a raw
                // loop must too, or every draft runs to the cap).
                let eosId = tokenizer.eosToken.flatMap {
                    tokenizer.convertTokenToId($0)
                }
                var generated: [Int] = []
                while let token = iterator.next() {
                    generated.append(token)
                    if token == eosId {
                        break
                    }
                }
                let totalTime = Double(
                    DispatchTime.now().uptimeNanoseconds
                        - startedAt.uptimeNanoseconds
                ) / 1_000_000_000
                let text = tokenizer.decode(
                    tokenIds: generated, skipSpecialTokens: true)

                // Keep the caches for the next request, trimmed back to the
                // exact prompt (drop generated KV so the ledger stays
                // honest).
                if let kept = caches {
                    for entry in kept {
                        _ = entry.trim(generated.count)
                    }
                    reusedCache = kept
                    cachedPromptTokens = promptTokens
                }
                let completion = GenerateCompletionInfo(
                    promptTokenCount: promptTokens.count,
                    generationTokenCount: generated.count,
                    promptTime: promptTime,
                    generationTime: max(0, totalTime - promptTime),
                    stopReason: .stop
                )
                return (text, completion)
            }
        }
        var (text, info) = outcome
        for token in stop {
            if let range = text.range(of: token) {
                text = String(text[..<range.lowerBound])
            }
        }

        let stopReason: String
        switch info?.stopReason {
        case .length: stopReason = "length"
        case .cancelled: stopReason = "cancelled"
        default: stopReason = "stop"
        }

        return responseJson([
            "text": text,
            "prompt_tokens": info?.promptTokenCount ?? 0,
            "completion_tokens": info?.generationTokenCount ?? 0,
            "prompt_time_ms": Int((info?.promptTime ?? 0) * 1000),
            "generate_time_ms": Int((info?.generateTime ?? 0) * 1000),
            "template_ms": Int(lastTemplateMs * 1000),
            "stop_reason": stopReason,
        ])
    } catch {
        return fail("generation failed: \(error)")
    }
}

@_cdecl("mlx_text_free")
public func mlx_text_free(_ pointer: UnsafeMutablePointer<CChar>?) {
    guard let pointer else { return }
    free(pointer)
}

@_cdecl("mlx_text_unload")
public func mlx_text_unload(_ handle: Int64) {
    registryLock.lock()
    defer { registryLock.unlock() }
    registry.removeValue(forKey: handle)
}

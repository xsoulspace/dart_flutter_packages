import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// C-ABI entrypoints. See bridge.h for the async contract.
///
/// Tool callbacks and the done callback are `NativeCallable.listener` native
/// function pointers from Dart. They are invoked on arbitrary threads; the
/// Dart VM posts them back to the owning isolate. Generation runs on a Swift
/// Task so the calling thread is never blocked — this is what lets Dart-side
/// tool handlers execute while a turn is in flight.

typealias XsFmToolCallback = @convention(c) (UnsafePointer<CChar>?) -> Void
typealias XsFmDoneCallback = @convention(c) (UnsafePointer<CChar>?) -> Void
typealias XsFmStreamCallback = @convention(c) (UnsafePointer<CChar>?) -> Void

// MARK: - Debug tracing

/// Debug tracing, controlled at runtime from Dart via `xs_fm_set_debug`.
/// Traces go to stderr (never stdout — stdout is the ACP/CLI protocol
/// channel). Enabled by default; disable for production runs.
enum XsFmDebug {
  static let queue = DispatchQueue(label: "xs.fm.debug")
  nonisolated(unsafe) static var enabled = true

  static func log(_ message: String) {
    guard enabled else { return }
    queue.sync {
      FileHandle.standardError.write(
        Data("[xs_fm] \(message)\n".utf8)
      )
    }
  }
}

@_cdecl("xs_fm_set_debug")
public func xs_fm_set_debug(_ enabled: Int32) {
  XsFmDebug.enabled = enabled != 0
  XsFmDebug.log("debug tracing \(enabled != 0 ? "enabled" : "disabled")")
}

// MARK: - Generation state + registry

/// Error resumed into pending tool continuations when a generation is
/// cancelled (timeout / Dart-side teardown).
struct XsFmGenerationCancelled: Error, LocalizedError {
  var errorDescription: String? { "generation cancelled" }
}

/// Per-generation state. Every callback path (done, tool payload, stream
/// delta) is gated through `queue`, so once `cancel()` has claimed the state
/// under the same lock, NO further callback invocation can start. This is the
/// contract that lets Dart cancel before tearing down its NativeCallable
/// listeners without a callback-after-delete VM crash.
final class GenerationState: @unchecked Sendable {
  let id: Int32
  let queue = DispatchQueue(label: "xs.fm.generation")
  let toolCallback: XsFmToolCallback?
  let doneCallback: XsFmDoneCallback
  var cancelled = false
  var finished = false
  var task: Task<Void, Never>?
  var pendingTools: [String: CheckedContinuation<String, Error>] = [:]

  init(
    id: Int32,
    toolCallback: XsFmToolCallback?,
    doneCallback: XsFmDoneCallback,
    streamCallback: XsFmStreamCallback? = nil
  ) {
    self.id = id
    self.toolCallback = toolCallback
    self.doneCallback = doneCallback
    self.streamCallback = streamCallback
  }

  /// Delivers the final done payload exactly once, unless cancelled first.
  func finish(_ responseJson: String) {
    // Lock order: registry queue BEFORE state queue (same as cancel).
    GenerationRegistry.shared.remove(id)
    var deliver = false
    queue.sync {
      if cancelled || finished { return }
      finished = true
      deliver = true
    }
    guard deliver else { return }
    // NativeCallable.listener delivers asynchronously on the Dart isolate,
    // so the buffer must outlive this call: heap-allocate and let Dart
    // free it via xs_fm_free_string.
    responseJson.withCString { cString in
      doneCallback(strdup(cString))
    }
  }

  /// Registers a tool continuation and posts the payload while still holding
  /// the state lock, so a concurrent cancel can never interleave between
  /// "continuation stored" and "payload posted". Returns the tool id on
  /// success, nil when the generation is dead — the continuation is resumed
  /// with an error and nothing is posted.
  func postToolCall(
    name: String,
    argumentsJSON: String,
    continuation: CheckedContinuation<String, Error>
  ) -> String? {
    var postedId: String? = nil
    var cancelledError = false
    queue.sync {
      if cancelled || finished {
        cancelledError = true
      } else {
        // Tool ids embed the generation id so xs_fm_tool_respond can route
        // without a second registry lookup (no toolOwners map, no lock-order
        // hazard between the registry and state queues).
        let toolId = "g\(id)_tool_\(UUID().uuidString)"
        pendingTools[toolId] = continuation
        let payload: [String: Any] = [
          "generation": Int(id),
          "id": toolId,
          "name": name,
          "arguments": argumentsJSON,
        ]
        if let callback = toolCallback,
          let data = try? JSONSerialization.data(withJSONObject: payload),
          let payloadString = String(data: data, encoding: .utf8)
        {
          payloadString.withCString { cString in
            callback(strdup(cString))
          }
          postedId = toolId
        }
      }
    }
    if cancelledError {
      continuation.resume(throwing: XsFmGenerationCancelled())
    }
    return postedId
  }

  /// Resumes one pending tool continuation (tool_respond path).
  func fulfillTool(id toolId: String, result: String) -> Bool {
    var resumed = false
    queue.sync {
      if let continuation = pendingTools.removeValue(forKey: toolId) {
        continuation.resume(returning: result)
        resumed = true
      }
    }
    return resumed
  }

  /// Cancels the generation: gates every future callback, resumes all pending
  /// tool continuations with a cancellation error, and cancels the Swift task.
  func cancel() {
    var toResume: [CheckedContinuation<String, Error>] = []
    queue.sync {
      cancelled = true
      toResume = Array(pendingTools.values)
      pendingTools.removeAll()
      task?.cancel()
    }
    for continuation in toResume {
      continuation.resume(throwing: XsFmGenerationCancelled())
    }
  }

  /// Emits a stream delta unless the generation is dead.
  func emitDelta(_ delta: String) {
    var send = false
    queue.sync {
      if !cancelled && !finished { send = true }
    }
    guard send, let streamCallback else { return }
    // Each snapshot is heap-allocated; Dart frees via xs_fm_free_string.
    // jsonEscaped produces a properly escaped JSON string literal (newlines
    // and quotes included) — never interpolate raw text into JSON.
    let payload = "{\"generation\":\(id),\"delta\":\(jsonEscaped(delta))}"
    payload.withCString { cString in
      streamCallback(strdup(cString))
    }
  }

  /// Stream callback, set at creation by the streaming entrypoint.
  var streamCallback: XsFmStreamCallback?
}

/// Registry of in-flight generations. Lock order with [GenerationState.queue]:
/// ALWAYS take the registry queue first, release, then the state queue.
final class GenerationRegistry: @unchecked Sendable {
  static let shared = GenerationRegistry()
  private let queue = DispatchQueue(label: "xs.fm.generations")
  private var byId: [Int32: GenerationState] = [:]
  private var counter: Int32 = 0

  func create(
    toolCallback: XsFmToolCallback?,
    doneCallback: XsFmDoneCallback,
    streamCallback: XsFmStreamCallback? = nil
  ) -> GenerationState {
    return queue.sync {
      counter += 1
      let state = GenerationState(
        id: counter,
        toolCallback: toolCallback,
        doneCallback: doneCallback,
        streamCallback: streamCallback
      )
      byId[state.id] = state
      return state
    }
  }

  func state(for id: Int32) -> GenerationState? {
    queue.sync { byId[id] }
  }

  func remove(_ id: Int32) {
    queue.sync { _ = byId.removeValue(forKey: id) }
  }

  func cancel(_ id: Int32) -> Int32 {
    let state: GenerationState? = queue.sync { byId.removeValue(forKey: id) }
    guard let state else { return 1 }
    state.cancel()
    return 0
  }

  /// Routes a tool response to its owning generation (tool ids embed the
  /// generation id: "g<gen>_tool_<uuid>").
  func fulfillTool(id toolId: String, result: String) -> Bool {
    guard toolId.hasPrefix("g") else { return false }
    let genPart = toolId.dropFirst().prefix(while: { $0.isNumber })
    guard let genId = Int32(genPart), let state = state(for: genId) else {
      return false
    }
    return state.fulfillTool(id: toolId, result: result)
  }
}

@_cdecl("xs_fm_is_available")
public func xs_fm_is_available() -> Int32 {
  #if canImport(FoundationModels)
    return SystemLanguageModel.default.isAvailable ? 1 : 0
  #else
    return 0
  #endif
}

@_cdecl("xs_fm_free_string")
public func xs_fm_free_string(_ s: UnsafeMutablePointer<CChar>?) {
  free(s)
}

@_cdecl("xs_fm_generate_async")
public func xs_fm_generate_async(
  _ request_json: UnsafePointer<CChar>?,
  _ tool_cb: UnsafeRawPointer?,
  _ done_cb: UnsafeRawPointer?
) -> Int32 {
  let toolCallback: XsFmToolCallback? =
    tool_cb.map { unsafeBitCast($0, to: XsFmToolCallback.self) }
  guard let doneRaw = done_cb else {
    return -1
  }
  let doneCallback = unsafeBitCast(doneRaw, to: XsFmDoneCallback.self)

  let state = GenerationRegistry.shared.create(
    toolCallback: toolCallback, doneCallback: doneCallback
  )

  /// Done payloads carry the generation id so Dart can drop stale callbacks
  /// from cancelled generations.
  func donePayload(_ body: String) -> String {
    "{\"generation\":\(state.id),\(body)}"
  }

  func finish(_ responseJson: String) {
    // Gated by the generation state: a no-op after cancel (the generation
    // was already removed from the registry and marked cancelled), so the
    // callback pointer is never invoked once Dart has cancelled + torn down.
    state.finish(responseJson)
  }

  func failNow(code: String, message: String) -> Int32 {
    finish(donePayload(jsonErrorBody(code: code, message: message)))
    return -1
  }

  guard let requestJson = request_json.map({ String(cString: $0) }) else {
    return failNow(code: "invalid_args", message: "request_json required")
  }
  guard let data = requestJson.data(using: .utf8),
    let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else {
    return failNow(code: "invalid_args", message: "request_json is not valid JSON")
  }
  guard let prompt = request["prompt"] as? String else {
    return failNow(code: "invalid_args", message: "prompt required")
  }

  let instructions = request["instructions"] as? String
  let schemaJson = request["schema"] as? [String: Any]
  let toolsJson = request["tools"] as? [[String: Any]] ?? []

  XsFmDebug.log(
    "generate: prompt=\(prompt.prefix(80)) schema=\(schemaJson != nil ? "present" : "absent") tools=[\(toolsJson.map { $0["name"] as? String ?? "?" }.joined(separator: ", "))] callback=\(toolCallback != nil ? "set" : "NULL")"
  )

  #if canImport(FoundationModels)
    do {
      let generationSchema = try materializeFromDartJSON(schemaJson ?? [:])
      XsFmDebug.log(
        "generate: schema materialized=\(generationSchema != nil ? "yes" : "no (nil)")"
      )
      let tools = try prepareNativeTools(from: toolsJson, callback: toolCallback, state: state)
      XsFmDebug.log(
        "generate: tools prepared=\(tools.count)/\(toolsJson.count) requested"
      )

      Task.detached {
        do {
          let model = SystemLanguageModel.default
          guard model.isAvailable else {
            finish(
              donePayload(
                jsonErrorBody(
                  code: "engine_unavailable",
                  message: "Apple Intelligence not available"
                )
              )
            )
            return
          }

          let session = LanguageModelSession(
            model: model,
            tools: tools,
            instructions: instructions
          )

          let content: String
          if let schema = generationSchema {
            let response = try await session.respond(to: prompt, schema: schema)
            content = response.content.jsonString
          } else {
            let response = try await session.respond(to: prompt)
            content = response.content
          }

          XsFmDebug.log("generate: ok, output=\(content.prefix(120))")
          finish(donePayload("\"ok\":true,\"output\":\(jsonEscaped(content))"))
        } catch {
          XsFmDebug.log("generate: error — \(error)")
          finish(
            donePayload(
              jsonErrorBody(
                code: "generation_error",
                message: error.localizedDescription
              )
            )
          )
        }
      }
      return state.id
    } catch {
      return failNow(code: "schema_error", message: error.localizedDescription)
    }
  #else
    return failNow(
      code: "engine_unavailable",
      message: "FoundationModels unavailable"
    )
  #endif
}

@_cdecl("xs_fm_tool_respond")
public func xs_fm_tool_respond(
  _ id: UnsafePointer<CChar>?,
  _ result_json: UnsafePointer<CChar>?
) -> Int32 {
  guard let idC = id, let resultC = result_json else { return 1 }
  let toolId = String(cString: idC)
  let result = String(cString: resultC)
  let resumed = GenerationRegistry.shared.fulfillTool(id: toolId, result: result)
  XsFmDebug.log(
    "tool respond: id=\(toolId) resumed=\(resumed) result=\(result.prefix(120))"
  )
  return resumed ? 0 : 1
}

@_cdecl("xs_fm_cancel")
public func xs_fm_cancel(_ generation_id: Int32) -> Int32 {
  let result = GenerationRegistry.shared.cancel(generation_id)
  XsFmDebug.log("cancel: generation=\(generation_id) result=\(result)")
  return result
}

// MARK: - Streaming generation

@_cdecl("xs_fm_generate_stream_async")
public func xs_fm_generate_stream_async(
  _ request_json: UnsafePointer<CChar>?,
  _ tool_cb: UnsafeRawPointer?,
  _ stream_cb: UnsafeRawPointer?,
  _ done_cb: UnsafeRawPointer?
) -> Int32 {
  let toolCallback: XsFmToolCallback? =
    tool_cb.map { unsafeBitCast($0, to: XsFmToolCallback.self) }
  guard let doneRaw = done_cb else {
    return -1
  }
  let doneCallback = unsafeBitCast(doneRaw, to: XsFmDoneCallback.self)
  guard let streamRaw = stream_cb else {
    return -1
  }
  let streamCallback = unsafeBitCast(streamRaw, to: XsFmStreamCallback.self)

  let state = GenerationRegistry.shared.create(
    toolCallback: toolCallback,
    doneCallback: doneCallback,
    streamCallback: streamCallback
  )

  func donePayload(_ body: String) -> String {
    "{\"generation\":\(state.id),\(body)}"
  }

  func finish(_ responseJson: String) {
    state.finish(responseJson)
  }

  func failNow(code: String, message: String) -> Int32 {
    finish(donePayload(jsonErrorBody(code: code, message: message)))
    return -1
  }

  guard let requestJson = request_json.map({ String(cString: $0) }) else {
    return failNow(code: "invalid_args", message: "request_json required")
  }
  guard let data = requestJson.data(using: .utf8),
    let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else {
    return failNow(code: "invalid_args", message: "request_json is not valid JSON")
  }
  guard let prompt = request["prompt"] as? String else {
    return failNow(code: "invalid_args", message: "prompt required")
  }

  let instructions = request["instructions"] as? String
  let schemaJson = request["schema"] as? [String: Any]
  let toolsJson = request["tools"] as? [[String: Any]] ?? []

  let schemaDesc = schemaJson != nil ? "present" : "absent"
  let toolNames = toolsJson.map { $0["name"] as? String ?? "?" }.joined(separator: ", ")
  XsFmDebug.log(
    "generate-stream: prompt=\(prompt.prefix(80)) schema=\(schemaDesc) tools=[\(toolNames)]"
  )

  #if canImport(FoundationModels)
    do {
      let generationSchema = try materializeFromDartJSON(schemaJson ?? [:])
      let tools = try prepareNativeTools(from: toolsJson, callback: toolCallback, state: state)

      Task.detached {
        do {
          let model = SystemLanguageModel.default
          guard model.isAvailable else {
            finish(
              donePayload(
                jsonErrorBody(
                  code: "engine_unavailable",
                  message: "Apple Intelligence not available"
                )
              )
            )
            return
          }

          let session = LanguageModelSession(
            model: model,
            tools: tools,
            instructions: instructions
          )

          // Streaming requires no generation schema (structured output is
          // delivered atomically by the framework). Fall back to the
          // non-streaming path when a schema is present.
          if generationSchema != nil {
            XsFmDebug.log("generate-stream: schema present — falling back to blocking respond")
            let response = try await session.respond(to: prompt, schema: generationSchema!)
            let content = response.content.jsonString
            finish(donePayload("\"ok\":true,\"output\":\(jsonEscaped(content))"))
            return
          }

          var lastEmittedLength = 0
          let stream = session.streamResponse(to: prompt)
          for try await snapshot in stream {
            // Snapshot.content is the full text so far; emit only the new
            // suffix as a delta so Dart can append incrementally.
            let full = snapshot.content
            if full.count > lastEmittedLength {
              let delta = String(full.suffix(full.count - lastEmittedLength))
              lastEmittedLength = full.count
              // Gated by the generation state — a no-op after cancel.
              state.emitDelta(delta)
            }
          }

          // The final content comes through done_cb via collect(); re-use the
          // accumulated stream to avoid a second model call.
          let finalText = try await stream.collect().content
          XsFmDebug.log("generate-stream: ok, output=\(finalText.prefix(120))")
          finish(donePayload("\"ok\":true,\"output\":\(jsonEscaped(finalText))"))
        } catch {
          XsFmDebug.log("generate-stream: error — \(error)")
          finish(
            donePayload(
              jsonErrorBody(
                code: "generation_error",
                message: error.localizedDescription
              )
            )
          )
        }
      }
      return state.id
    } catch {
      return failNow(code: "schema_error", message: error.localizedDescription)
    }
  #else
    return failNow(
      code: "engine_unavailable",
      message: "FoundationModels unavailable"
    )
  #endif
}

// MARK: - Native tool adapter

#if canImport(FoundationModels)
  /// A tool whose implementation lives on the Dart side, invoked through the
  /// C callback pointer. Mirrors `DartTool` from the Flutter plugin.
  ///
  /// `parameters` is NON-optional per the Tool protocol
  /// (`var parameters: GenerationSchema { get }`). Tools without an args
  /// schema get an explicit empty-object schema — a nil/optional here made
  /// LanguageModelSession fail with GenerationError -1/1020000.
  /// Wrapper so the framework hands us the RAW GeneratedContent.
  /// Using `GeneratedContent` directly as `Arguments` loses properties
  /// (decodes to an empty structure) for dynamically materialized schemas;
  /// a custom ConvertibleFromGeneratedContent receives them intact
  /// (regression: live E fails, live H passes).
  struct BridgeToolArguments: ConvertibleFromGeneratedContent {
    let content: GeneratedContent
    init(_ content: GeneratedContent) throws {
      self.content = content
    }
  }

  struct NativeDartTool: Tool {
    typealias Arguments = BridgeToolArguments
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let callback: XsFmToolCallback
    /// Generation state owning this tool's calls — gates the payload post so
    /// a cancelled generation can never post a callback after Dart tore down.
    weak var state: GenerationState?

    init(
      name: String,
      description: String,
      parameters: GenerationSchema?,
      callback: XsFmToolCallback,
      state: GenerationState?
    ) {
      self.name = name
      self.description = description
      self.state = state
      // Use the caller's schema when provided; only fall back to an
      // explicit empty-object schema for tools without arguments.
      // (This init previously DISCARDED `parameters` and always built an
      // empty schema — tools advertised no properties, so every tool call
      // arrived with empty arguments.)
      if let p = parameters {
        self.parameters = p
      } else {
        self.parameters =
          (try? GenerationSchema(
            root: DynamicGenerationSchema(name: name, properties: []),
            dependencies: []
          ))
          ?? (try! GenerationSchema(
            root: DynamicGenerationSchema(name: "empty", properties: []),
            dependencies: []
          ))
      }
      self.callback = callback
    }

    func call(arguments: BridgeToolArguments) async throws -> String {
      let argsJSON = try extractArgsJSON(from: arguments.content)
      XsFmDebug.log("tool call: name=\(name) args=\(argsJSON.prefix(120))")

      // Suspend until Dart calls xs_fm_tool_respond for our id. The payload
      // post happens under the generation state lock (see postToolCall), so
      // it is atomic with respect to cancel — after xs_fm_cancel returns, no
      // payload for this generation can be posted, and any continuation
      // registered before the cancel is resumed with an error.
      return try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<String, Error>) in
        guard let state = self.state,
          state.postToolCall(
            name: name,
            argumentsJSON: argsJSON,
            continuation: continuation
          ) != nil
        else {
          continuation.resume(throwing: NativeToolError(code: "generation_cancelled"))
          return
        }
      }
    }
  }

  struct NativeToolError: Error, LocalizedError {
    let code: String
    var errorDescription: String? { code }
  }

  func prepareNativeTools(
    from toolsJSON: [[String: Any]],
    callback: XsFmToolCallback?,
    state: GenerationState
  ) throws -> [any Tool] {
    guard let callback = callback else {
      XsFmDebug.log(
        "prepareTools: \(toolsJSON.count) tool(s) requested but callback is NULL — registering none"
      )
      return []
    }
    return try toolsJSON.map { json in
      guard let name = json["name"] as? String,
        let description = json["description"] as? String
      else {
        throw NativeToolError(code: "invalid_tool_json")
      }
      // Args schema is optional: an empty parameters object means the tool
      // takes no structured arguments. Registering without `parameters` is
      // valid; rejecting the tool here was the bridge-breaking bug.
      let schemaJSON = json["parameters"] as? [String: Any] ?? [:]
      let schema = try materializeFromDartJSON(schemaJSON)
      if schema == nil {
        XsFmDebug.log("prepareTools: \(name) has no args schema (optional args)")
      }
      return NativeDartTool(
        name: name,
        description: description,
        parameters: schema,
        callback: callback,
        state: state
      )
    }
  }
#endif

// MARK: - Tool argument extraction

/// `GeneratedContent.jsonString` loses properties for tools whose schema was
/// built from `DynamicGenerationSchema` (materialized from Dart JSON): it
/// returns "{}" even when the model supplied arguments. Extract explicitly
/// from the `.structure` kind instead.
func extractArgsJSON(from content: GeneratedContent) throws -> String {
  #if canImport(FoundationModels)
    if case .structure(let props, _) = content.kind {
      let dict = try props.mapValues { value -> Any in
        // Each property value is itself GeneratedContent; decode its
        // fragment JSON (scalars encode as bare literals).
        let s = try extractArgsJSON(from: value)
        return try JSONSerialization.jsonObject(
          with: Data(s.utf8), options: [.fragmentsAllowed])
      }
      let data = try JSONSerialization.data(withJSONObject: dict)
      return String(data: data, encoding: .utf8) ?? "{}"
    }
  #endif
  return try content.jsonString
}

// MARK: - JSON helpers

func jsonEscaped(_ s: String) -> String {
  // JSONEncoder escapes ALL control characters (newlines, quotes, backslashes)
  // correctly. JSONSerialization round-trips unescape them, so a naive
  // serialize→deserialize→interpolate helper emits raw newlines into the JSON
  // — which Dart's jsonDecode then rejects.
  guard #available(macOS 10.15, *) else { return "\"\"" }
  let data: Data
  if #available(macOS 13.0, *) {
    var encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    guard let d = try? encoder.encode([s]) else { return "\"\"" }
    data = d
  } else {
    guard let d = try? JSONEncoder().encode([s]) else { return "\"\"" }
    data = d
  }
  // data is a JSON array like ["line1\nline2"] — strip the brackets.
  guard let str = String(data: data, encoding: .utf8),
    str.hasPrefix("["), str.hasSuffix("]"), str.count >= 2
  else { return "\"\"" }
  return String(str.dropFirst().dropLast())
}

func jsonEscapedError(code: String, message: String) -> String {
  "{" + jsonErrorBody(code: code, message: message) + "}"
}

/// Error body WITHOUT the outer braces — embeddable inside a payload that
/// carries additional top-level fields (e.g. the generation id).
func jsonErrorBody(code: String, message: String) -> String {
  let payload: [String: Any] = [
    "ok": false,
    "error": ["code": code, "message": message],
  ]
  guard let data = try? JSONSerialization.data(withJSONObject: payload),
    let s = String(data: data, encoding: .utf8),
    s.hasPrefix("{"), s.hasSuffix("}"), s.count >= 2
  else {
    return "\"ok\":false,\"error\":{\"code\":\"\(code)\",\"message\":\"\"}"
  }
  return String(s.dropFirst().dropLast())
}

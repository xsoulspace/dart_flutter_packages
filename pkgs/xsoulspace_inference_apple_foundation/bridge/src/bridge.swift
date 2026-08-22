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

// MARK: - Pending tool registry

/// Tracks in-flight tool calls so `xs_fm_tool_respond` can resume the right
/// continuation. Access is serialized on a private queue.
final class PendingToolRegistry: @unchecked Sendable {
  static let shared = PendingToolRegistry()
  private let queue = DispatchQueue(label: "xs.fm.pendingTools")
  private var pending: [String: CheckedContinuation<String, Error>] = [:]
  private var counter = 0

  func register(_ continuation: CheckedContinuation<String, Error>) -> String {
    let id = "tool_\(UUID().uuidString)"
    queue.sync {
      counter += 1
      pending[id] = continuation
    }
    return id
  }

  func fulfill(id: String, result: String) -> Bool {
    var resumed = false
    queue.sync {
      if let continuation = pending.removeValue(forKey: id) {
        continuation.resume(returning: result)
        resumed = true
      }
    }
    XsFmDebug.log(
      "tool respond: id=\(id) resumed=\(resumed) result=\(result.prefix(120))"
    )
    return resumed
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
    return 1
  }
  let doneCallback = unsafeBitCast(doneRaw, to: XsFmDoneCallback.self)

  func finish(_ responseJson: String) {
    // NativeCallable.listener delivers asynchronously on the Dart isolate,
    // so the buffer must outlive this call: heap-allocate and let Dart
    // free it via xs_fm_free_string.
    responseJson.withCString { cString in
      doneCallback(strdup(cString))
    }
  }

  func failNow(code: String, message: String) -> Int32 {
    finish(jsonEscapedError(code: code, message: message))
    return 1
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
      let tools = try prepareNativeTools(from: toolsJson, callback: toolCallback)
      XsFmDebug.log(
        "generate: tools prepared=\(tools.count)/\(toolsJson.count) requested"
      )

      Task.detached {
        do {
          let model = SystemLanguageModel.default
          guard model.isAvailable else {
            finish(
              jsonEscapedError(
                code: "engine_unavailable",
                message: "Apple Intelligence not available"
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
          finish("{\"ok\":true,\"output\":\(jsonEscaped(content))}")
        } catch {
          XsFmDebug.log("generate: error — \(error)")
          finish(
            jsonEscapedError(
              code: "generation_error",
              message: error.localizedDescription
            )
          )
        }
      }
      return 0
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
  return PendingToolRegistry.shared.fulfill(id: toolId, result: result) ? 0 : 1
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
    return 1
  }
  let doneCallback = unsafeBitCast(doneRaw, to: XsFmDoneCallback.self)
  guard let streamRaw = stream_cb else {
    return 1
  }
  let streamCallback = unsafeBitCast(streamRaw, to: XsFmStreamCallback.self)

  func finish(_ responseJson: String) {
    responseJson.withCString { cString in
      doneCallback(strdup(cString))
    }
  }

  func emitDelta(_ delta: String) {
    // Each snapshot is heap-allocated; Dart frees via xs_fm_free_string.
    // jsonEscaped produces a properly escaped JSON string literal (newlines
    // and quotes included) — never interpolate raw text into JSON.
    let payload = "{\"delta\":\(jsonEscaped(delta))}"
    payload.withCString { cString in
      streamCallback(strdup(cString))
    }
  }

  func failNow(code: String, message: String) -> Int32 {
    finish(jsonEscapedError(code: code, message: message))
    return 1
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
      let tools = try prepareNativeTools(from: toolsJson, callback: toolCallback)

      Task.detached {
        do {
          let model = SystemLanguageModel.default
          guard model.isAvailable else {
            finish(
              jsonEscapedError(
                code: "engine_unavailable",
                message: "Apple Intelligence not available"
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
            finish("{\"ok\":true,\"output\":\(jsonEscaped(content))}")
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
              emitDelta(delta)
            }
          }

          // The final content comes through done_cb via collect(); re-use the
          // accumulated stream to avoid a second model call.
          let finalText = try await stream.collect().content
          XsFmDebug.log("generate-stream: ok, output=\(finalText.prefix(120))")
          finish("{\"ok\":true,\"output\":\(jsonEscaped(finalText))}")
        } catch {
          XsFmDebug.log("generate-stream: error — \(error)")
          finish(
            jsonEscapedError(
              code: "generation_error",
              message: error.localizedDescription
            )
          )
        }
      }
      return 0
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
  struct NativeDartTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = String

    let name: String
    let description: String
    let parameters: GenerationSchema
    let callback: XsFmToolCallback

    init(
      name: String,
      description: String,
      parameters: GenerationSchema?,
      callback: XsFmToolCallback
    ) {
      self.name = name
      self.description = description
      self.parameters =
        (try? GenerationSchema(
          root: DynamicGenerationSchema(name: name, properties: []),
          dependencies: []
        ))
        ?? (try! GenerationSchema(
          root: DynamicGenerationSchema(name: "empty", properties: []),
          dependencies: []
        ))
      self.callback = callback
    }

    func call(arguments: GeneratedContent) async throws -> String {
      let argsJSON = try arguments.jsonString
      XsFmDebug.log("tool call: name=\(name) args=\(argsJSON.prefix(120))")

      // Suspend until Dart calls xs_fm_tool_respond for our id.
      return try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<String, Error>) in
        let id = PendingToolRegistry.shared.register(continuation)
        let payload: [String: Any] = [
          "id": id,
          "name": name,
          "arguments": argsJSON,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let payloadString = String(data: data, encoding: .utf8) ?? "{}"
        payloadString.withCString { cString in
          callback(strdup(cString))
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
    callback: XsFmToolCallback?
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
        callback: callback
      )
    }
  }
#endif

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
  let payload: [String: Any] = [
    "ok": false,
    "error": ["code": code, "message": message],
  ]
  guard let data = try? JSONSerialization.data(withJSONObject: payload),
    let s = String(data: data, encoding: .utf8)
  else {
    return "{\"ok\":false,\"error\":{\"code\":\"\(code)\",\"message\":\"\"}}"
  }
  return s
}

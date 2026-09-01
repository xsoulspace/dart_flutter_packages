// AFM bridge regression tests — plain Swift executable, no XCTest infra.
//
// Run:  sh tool/check_bridge_swift.sh          (unit + live sessions)
//       LIVE=0 sh tool/check_bridge_swift.sh   (unit only, no AFM calls)
//
// Exits non-zero on any failure. Each test prints PASS/FAIL with a reason.

import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

// The bridge sources are compiled together with this file (see
// check_bridge_swift.sh), so internal symbols like materializeFromDartJSON
// and NativeDartTool are visible here.

var failures = 0
var passed = 0

func check(_ name: String, _ condition: Bool, _ detail: String = "") {
  if condition {
    passed += 1
    print("PASS \(name)")
  } else {
    failures += 1
    print("FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
  }
}

// MARK: - Unit: jsonEscaped round-trip

func testJsonEscaped() {
  // Control characters must survive as escapes (the newline bug).
  let withNewline = jsonEscaped("line1\nline2")
  check(
    "jsonEscaped newline stays escaped",
    !withNewline.contains("\n"),
    "got raw newline in \(withNewline)"
  )

  // Round-trip through JSONSerialization must recover the original string.
  let original = "quote\"back\\slash\ttab\nnew é😀"
  let encoded = jsonEscaped(original)
  let wrapped = "{\"v\":\(encoded)}"
  guard let data = wrapped.data(using: .utf8),
    let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
    let decoded = obj["v"]
  else {
    check("jsonEscaped round-trip", false, "unparseable: \(wrapped)")
    return
  }
  check("jsonEscaped round-trip", decoded == original, "\(decoded)")

  // Empty string.
  check("jsonEscaped empty", jsonEscaped("") == "\"\"")
}

// MARK: - Unit: schema materialization

func testSchemaMaterialization() {
  // Object with primitive property (the weather shape from the field trace).
  let weather: [String: Any] =
    [
      "root": [
        "kind": "object",
        "name": "weather",
        "representNilExplicitly": false,
        "properties": [
          [
            "name": "condition",
            "schema": ["kind": "primitive", "primitiveType": "Double"],
            "isOptional": false,
          ]
        ],
      ],
      "dependencies": [],
    ] as [String: Any]

  do {
    let schema = try materializeFromDartJSON(weather)
    check("materialize weather object schema", schema != nil)
  } catch {
    check("materialize weather object schema", false, "\(error)")
  }

  // Empty dict → nil schema (no structured output).
  do {
    let schema = try materializeFromDartJSON([:])
    check("materialize empty → nil", schema == nil)
  } catch {
    check("materialize empty → nil", false, "\(error)")
  }

  // Array of strings.
  let listOfStrings: [String: Any] =
    [
      "root": [
        "kind": "array",
        "item": ["kind": "primitive", "primitiveType": "String"],
        "minItems": 1,
      ],
      "dependencies": [],
    ] as [String: Any]
  do {
    let schema = try materializeFromDartJSON(listOfStrings)
    check("materialize array schema", schema != nil)
  } catch {
    check("materialize array schema", false, "\(error)")
  }
}

#if canImport(FoundationModels)
  // MARK: - Live: tool conformance bisection
  //
  // These are THE regression for GenerationError -1/1020000: any framework
  // update that breaks NativeDartTool conformance or dynamic tool schemas
  // fails here before it reaches Dart.

  @available(macOS 26.0, *)
  func makeClockTool(parameters: GenerationSchema?) -> NativeDartTool {
    // The callback receives {id, name, arguments} and must resolve the
    // pending continuation via PendingToolRegistry — same contract as the
    // Dart side's xs_fm_tool_respond. Returning a string from the closure
    // alone would leave the continuation hanging forever.
    NativeDartTool(
      name: "clock",
      description: "Returns the current time in ISO-8601.",
      parameters: parameters,
      callback: { payload in
        guard let payload = payload else { return }
        let payloadStr = String(cString: payload)
        guard let data = payloadStr.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
          let id = obj["id"] as? String
        else { return }
        PendingToolRegistry.shared.fulfill(
          id: id,
          result: "2026-01-01T00:00:00Z"
        )
      },
      state: nil
    )
  }

  func liveSessionTest(
    _ name: String,
    tools: [any Tool],
    prompt: String,
    timeoutSeconds: UInt64 = 90
  ) async -> Bool {
    do {
      let model = SystemLanguageModel.default
      guard model.isAvailable else {
        print("SKIP \(name) — Apple Intelligence unavailable")
        return true
      }
      // Race the session against a timeout so a hung tool round-trip fails
      // loudly instead of blocking the suite forever.
      return try await withThrowingTaskGroup(of: Bool.self) { group in
        group.addTask {
          let session = LanguageModelSession(model: model, tools: tools)
          let response = try await session.respond(to: prompt)
          return !response.content.isEmpty
        }
        group.addTask {
          try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
          throw TimeoutError(name: name, seconds: timeoutSeconds)
        }
        let first = try await group.next()!
        group.cancelAll()
        return first
      }
    } catch let err as TimeoutError {
      print("     TIMEOUT: \(err)")
      return false
    } catch {
      print("     error: \(error)")
      return false
    }
  }

  struct TimeoutError: Error, CustomStringConvertible {
    let name: String
    let seconds: UInt64
    var description: String { "\(name) exceeded \(seconds)s" }
  }

  func runLiveTests() async {
    let model = SystemLanguageModel.default
    guard model.isAvailable else {
      print("SKIP live session tests — Apple Intelligence unavailable")
      return
    }

    // A: plain session, no tools (control).
    let a = await liveSessionTest(
      "live A: plain session",
      tools: [],
      prompt: "Reply with exactly one word: ok"
    )
    check("live A: plain session responds", a)

    // B: one tool WITHOUT parameters schema (nil) — isolates tool conformance.
    let clockNoSchema = makeClockTool(parameters: nil)
    let b = await liveSessionTest(
      "live B: nil-schema tool",
      tools: [clockNoSchema],
      prompt: "Use the clock tool and tell me the hour."
    )
    check("live B: nil-schema tool session", b)

    // C: one tool WITH a materialized args schema — isolates schema
    // materialization inside tool registration.
    let clockSchemaJSON: [String: Any] =
      [
        "root": [
          "kind": "object",
          "name": "clock_args",
          "representNilExplicitly": false,
          "properties": [
            [
              "name": "timezone",
              "schema": ["kind": "primitive", "primitiveType": "String"],
              "isOptional": true,
            ]
          ],
        ],
        "dependencies": [],
      ] as [String: Any]
    let materialized = try? materializeFromDartJSON(clockSchemaJSON)
    check("live C: tool schema materialized", materialized != nil)
    if let params = materialized {
      let clockWithSchema = makeClockTool(parameters: params)
      let c = await liveSessionTest(
        "live C: schema'd tool",
        tools: [clockWithSchema],
        prompt: "Use the clock tool for timezone UTC and tell me the hour."
      )
      check("live C: schema'd tool session", c)
    }

    // E: THE empty-args regression — a schema'd tool must receive the
    // model's arguments (path/content), not an empty structure.
    let writeSchemaJSON: [String: Any] =
      [
        "root": [
          "kind": "object",
          "name": "write_args",
          "representNilExplicitly": false,
          "properties": [
            [
              "name": "path",
              "schema": ["kind": "primitive", "primitiveType": "String"],
              "isOptional": false,
            ],
            [
              "name": "content",
              "schema": ["kind": "primitive", "primitiveType": "String"],
              "isOptional": false,
            ],
          ],
        ],
        "dependencies": [],
      ] as [String: Any]
    if let writeParams = try? materializeFromDartJSON(writeSchemaJSON) {
      final class ArgsCapture: @unchecked Sendable {
        static let shared = ArgsCapture()
        var lastArgsJSON = "{}"
      }
      let writeTool = NativeDartTool(
        name: "write",
        description: "Writes text content to a file at the given path.",
        parameters: writeParams,
        callback: { payload in
          guard let payload = payload else { return }
          let payloadStr = String(cString: payload)
          if let data = payloadStr.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data)
              as? [String: Any],
            let id = obj["id"] as? String
          {
            ArgsCapture.shared.lastArgsJSON =
              (obj["arguments"] as? String) ?? "(missing)"
            PendingToolRegistry.shared.fulfill(id: id, result: "ok")
          }
        },
        state: nil)
      let e = await liveSessionTest(
        "live E: schema'd tool receives args",
        tools: [writeTool],
        prompt:
          "Use the write tool to create a file named notes.txt containing the text hello world."
      )
      let captured = ArgsCapture.shared.lastArgsJSON
      let argsPopulated =
        captured.contains("notes.txt") || captured.contains("hello")
      check(
        "live E: schema'd tool receives args",
        e && argsPopulated,
        "captured args=\(captured.prefix(200))")
    } else {
      check("live E: schema'd tool receives args", false, "schema materialize failed")
    }

    // F: CONTROL — native @Generable macro args type. If this receives
    // populated args while E fails, the dynamic-schema decode path is the
    // culprit; if F also fails, the framework/tool protocol is.
    if #available(macOS 26.0, *) {
      final class MacroCapture: @unchecked Sendable {
        static let shared = MacroCapture()
        var lastArgs: WriteArgs?
      }
      struct MacroWriteTool: Tool {
        typealias Output = String
        var name = "write"
        var description = "Writes text content to a file at the given path."
        func call(arguments: WriteArgs) async throws -> String {
          MacroCapture.shared.lastArgs = arguments
          return "ok"
        }
      }
      let f = await liveSessionTest(
        "live F: macro tool receives args",
        tools: [MacroWriteTool()],
        prompt:
          "Use the write tool to create a file named notes.txt containing the text hello world."
      )
      let a = MacroCapture.shared.lastArgs
      check(
        "live F: macro tool receives args",
        f && a != nil && !a!.path.isEmpty,
        "got: \(a.map(\.path) ?? "nil")")
    }

    // G: NativeDartTool (GeneratedContent args) but schema from
    // WriteArgs.generationSchema. Isolates whether the
    // GeneratedContent tool surface decodes when the schema is macro-derived.
    if #available(macOS 26.0, *) {
      final class GCapture: @unchecked Sendable {
        static let shared = GCapture()
        var lastArgsJSON = "{}"
      }
      let reflectedParams = try? WriteArgs.generationSchema
      if let rp = reflectedParams {
        let gTool = NativeDartTool(
          name: "write",
          description: "Writes text content to a file at the given path.",
          parameters: rp,
          callback: { payload in
            guard let payload = payload else { return }
            let payloadStr = String(cString: payload)
            if let data = payloadStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let id = obj["id"] as? String
            {
              GCapture.shared.lastArgsJSON =
                (obj["arguments"] as? String) ?? "(missing)"
              PendingToolRegistry.shared.fulfill(id: id, result: "ok")
            }
          },
          state: nil)
        let g = await liveSessionTest(
          "live G: reflected-schema tool receives args",
          tools: [gTool],
          prompt:
            "Use the write tool to create a file named notes.txt containing the text hello world."
        )
        let capturedG = GCapture.shared.lastArgsJSON
        check(
          "live G: reflected-schema tool receives args",
          g && capturedG.contains("notes.txt"),
          "captured args=\(capturedG.prefix(200))")
      } else {
        check("live G: reflected-schema tool receives args", false, "reflect failed")
      }
    }

    // H: custom ConvertibleFromGeneratedContent wrapper capturing raw
    // content, with the dynamic (Dart-materialized) schema.
    final class RawCapture: @unchecked Sendable {
      static let shared = RawCapture()
      var lastDebug = "none"
    }
    struct RawArgs: ConvertibleFromGeneratedContent {
      let content: GeneratedContent
      init(_ content: GeneratedContent) throws {
        self.content = content
        RawCapture.shared.lastDebug = String(describing: content)
      }
    }
    struct RawTool: Tool {
      typealias Output = String
      typealias Arguments = RawArgs
      var name = "write"
      var description = "Writes text content to a file at the given path."
      var parameters: GenerationSchema
      func call(arguments: RawArgs) async throws -> String { "ok" }
    }
    if #available(macOS 26.0, *), let wp = try? materializeFromDartJSON(writeSchemaJSON) {
      let h = await liveSessionTest(
        "live H: raw-capture tool receives args",
        tools: [RawTool(parameters: wp)],
        prompt:
          "Use the write tool to create a file named notes.txt containing the text hello world."
      )
      let dbg = RawCapture.shared.lastDebug
      check(
        "live H: raw-capture tool receives args",
        h && dbg.contains("notes.txt"),
        "captured: \(dbg.prefix(200))")
    } else {
      check("live H: raw-capture tool receives args", false, "materialize failed")
    }

    // D: multiple DISTINCT tools — matches production shape
    // (read/write/list_dir). Duplicate names would be an invalid session.
    let timeTool = makeClockTool(parameters: nil)
    let echoTool = NativeDartTool(
      name: "echo",
      description: "Echoes back the given text.",
      parameters: nil,
      callback: { payload in
        guard let payload = payload else { return }
        let payloadStr = String(cString: payload)
        guard let data = payloadStr.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any],
          let id = obj["id"] as? String
        else { return }
        PendingToolRegistry.shared.fulfill(id: id, result: "echo-ok")
      },
      state: nil
    )
    let d = await liveSessionTest(
      "live D: multi-tool session",
      tools: [timeTool, echoTool],
      prompt: "Say ok."
    )
    check("live D: multi-tool session", d)
  }
#endif

// MARK: - Unit: tool argument extraction

func testExtractArgsJSON() {
  #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      // Structure with scalar leaves — the shape that jsonString loses.
      let content = GeneratedContent(
        kind: .structure(
          properties: [
            "path": GeneratedContent(kind: .string("x.txt")),
            "content": GeneratedContent(kind: .string("hi")),
          ],
          orderedKeys: ["path", "content"]
        ))
      do {
        let json = try extractArgsJSON(from: content)
        guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
          check("extractArgsJSON structure", false, "unparseable: \(json)")
          return
        }
        check(
          "extractArgsJSON structure",
          obj["path"] == "x.txt" && obj["content"] == "hi",
          "got: \(json)")
      } catch {
        check("extractArgsJSON structure", false, "threw: \(error)")
      }

      // Nested structure must round-trip too (recursion path).
      let nested = GeneratedContent(
        kind: .structure(
          properties: [
            "inner": GeneratedContent(kind: .structure(
              properties: ["v": GeneratedContent(kind: .number(3.0))],
              orderedKeys: ["v"])),
            "flag": GeneratedContent(kind: .bool(true)),
          ],
          orderedKeys: ["inner", "flag"]))
      do {
        let json = try extractArgsJSON(from: nested)
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let inner = obj?["inner"] as? [String: Any]
        check(
          "extractArgsJSON nested",
          (inner?["v"] as? Double) == 3.0 && (obj?["flag"] as? Bool) == true,
          "got: \(json)")
      } catch {
        check("extractArgsJSON nested", false, "threw: \(error)")
      }
    }
  #endif
}

// MARK: - Unit: generation cancel gate (P1 bridge crash fix)

// C-convention closures cannot capture; record deliveries in globals.
var gateDoneDeliveries: [String] = []
var gateToolPayloads: [String] = []

let gateDoneCb: @convention(c) (UnsafePointer<CChar>?) -> Void = { p in
  if let p { gateDoneDeliveries.append(String(cString: p)) }
}
let gateToolCb: @convention(c) (UnsafePointer<CChar>?) -> Void = { p in
  if let p { gateToolPayloads.append(String(cString: p)) }
}

func makeGateState() -> GenerationState {
  gateDoneDeliveries = []
  gateToolPayloads = []
  return GenerationRegistry.shared.create(
    toolCallback: gateToolCb,
    doneCallback: gateDoneCb
  )
}

func testGenerationCancelGate() async throws {
  // finish delivers exactly once.
  let state = makeGateState()
  state.finish("{\"generation\":\(state.id),\"ok\":true}")
  state.finish("{\"generation\":\(state.id),\"ok\":true}")
  check(
    "finish delivers exactly once",
    gateDoneDeliveries.count == 1 && gateDoneDeliveries[0].contains("\"ok\":true"),
    "got \(gateDoneDeliveries)")
  // finish removes the state from the registry → cancel returns 1.
  check(
    "cancel after finish returns 1",
    GenerationRegistry.shared.cancel(state.id) == 1,
    "expected unknown-id result")

  // postToolCall on a LIVE state posts the payload and the continuation is
  // resumable through xs_fm_tool_respond routing (generation-embedded ids).
  let liveState = makeGateState()
  let toolResult: String = try await withCheckedThrowingContinuation {
    (continuation: CheckedContinuation<String, Error>) in
    if let toolId = liveState.postToolCall(
      name: "t", argumentsJSON: "{}", continuation: continuation)
    {
      check("tool payload posted with generation id", true)
      DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
        _ = GenerationRegistry.shared.fulfillTool(id: toolId, result: "resp")
      }
    } else {
      check("tool payload posted with generation id", false, "post refused")
      continuation.resume(returning: "")
    }
  }
  check("tool respond routes to the owning generation", toolResult == "resp", "got \(String(describing: toolResult))")

  // After cancel: no done delivery, postToolCall refuses and resumes the
  // continuation with a cancellation error, cancel of a dead id returns 1.
  let cancelledState = makeGateState()
  check(
    "cancel live id returns 0",
    GenerationRegistry.shared.cancel(cancelledState.id) == 0,
    "expected cancelled")
  check(
    "cancel dead id returns 1",
    GenerationRegistry.shared.cancel(cancelledState.id) == 1,
    "expected unknown-id result")
  cancelledState.finish("{\"generation\":\(cancelledState.id),\"ok\":true}")
  check(
    "no done delivery after cancel",
    gateDoneDeliveries.isEmpty,
    "got \(gateDoneDeliveries)")
  do {
    _ = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<String, Error>) in
      let posted = cancelledState.postToolCall(
        name: "t", argumentsJSON: "{}", continuation: continuation)
      if posted != nil {
        check("postToolCall refuses after cancel", false, "posted after cancel")
      }
    }
    check("postToolCall after cancel throws", false, "returned normally")
  } catch {
    check("postToolCall after cancel throws", true)
  }
  check(
    "no tool payload posted after cancel",
    gateToolPayloads.isEmpty,
    "got \(gateToolPayloads)")
}

#if canImport(FoundationModels)
  @available(macOS 26.0, *)
  @Generable struct WriteArgs {
    @Guide(description: "Relative file path")
    var path: String
    @Guide(description: "Text content to write")
    var content: String
  }
#endif

// MARK: - Entry

@main
struct TestMain {
  static func main() async {
    print("── AFM bridge regression tests ──")

    testJsonEscaped()
    testSchemaMaterialization()
    testExtractArgsJSON()
    do {
      try await testGenerationCancelGate()
    } catch {
      check("generation cancel gate", false, "threw: \(error)")
    }

    #if canImport(FoundationModels)
      let live = ProcessInfo.processInfo.environment["LIVE"] ?? "1"
      if live == "1" {
        if #available(macOS 26.0, *) {
          await runLiveTests()
        } else {
          print("SKIP live tests — macOS < 26")
        }
      } else {
        print("LIVE=0 — skipping live session tests")
      }
    #endif

    print("── \(passed) passed, \(failures) failed ──")
    exit(failures == 0 ? 0 : 1)
  }
}

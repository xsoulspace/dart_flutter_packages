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
      }
    )
  }

  func liveSessionTest(
    _ name: String,
    tools: [NativeDartTool],
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
      }
    )
    let d = await liveSessionTest(
      "live D: multi-tool session",
      tools: [timeTool, echoTool],
      prompt: "Say ok."
    )
    check("live D: multi-tool session", d)
  }
#endif

// MARK: - Entry

@main
struct TestMain {
  static func main() async {
    print("── AFM bridge regression tests ──")

    testJsonEscaped()
    testSchemaMaterialization()

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

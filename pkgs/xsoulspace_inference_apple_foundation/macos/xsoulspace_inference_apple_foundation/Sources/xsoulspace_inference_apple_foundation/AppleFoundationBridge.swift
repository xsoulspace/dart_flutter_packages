import FlutterMacOS
import Foundation

/// Bridge to Apple Foundation Models using SystemLanguageModel.
enum AppleFoundationBridge {
    static func isAvailable() -> Bool {
        #if canImport(FoundationModels)
            return FoundationModelsBridge.isAvailable()
        #else
            return false
        #endif
    }

    static func generate(
        prompt: String,
        transcript: String?,
        instructions: String?,
        generationSchema: GenerationSchema?,
        toolsJSON: [[String: Any]],
        toolInvoker: FlutterToolInvoker,
        completion: @escaping (String?, String?, String?) -> Void
    ) {
        //        #if canImport(FoundationModels)

        let tools =
            (try? FoundationModelsBridge.prepareTools(
                from: toolsJSON,
                toolInvoker: toolInvoker
            )) ?? []
        FoundationModelsBridge.generate(
            prompt: prompt,
            transcript: transcript != nil
                ? Transcript(entries: [
                    Transcript.Entry.prompt(
                        Transcript.Prompt(
                            segments: [
                                Transcript.Segment.text(
                                    Transcript.TextSegment(
                                        content: transcript!
                                    )
                                )
                            ]
                        )
                    )
                ]) : nil,
            instructions: instructions,
            completion: completion,
            generationSchema: generationSchema,
            tools: tools
        )
        //        #else
        //            completion(
        //                nil,
        //                "engine_unavailable",
        //                "Foundation Models not available"
        //            )
        //        #endif
    }
}

#if canImport(FoundationModels)
    import FoundationModels

    enum FoundationModelsBridge {
        static func isAvailable() -> Bool {
            SystemLanguageModel.default.isAvailable
        }

        static func generate(
            prompt: String,
            transcript: Transcript?,
            instructions: String?,
            completion: @escaping (String?, String?, String?) -> Void,
            generationSchema: GenerationSchema?,
            tools: [any Tool]
        ) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                completion(
                    nil,
                    "engine_unavailable",
                    "Apple Intelligence not available"
                )
                return
            }

            Task {
                do {
                    let session: LanguageModelSession
                    if let transcript, !transcript.isEmpty {
                        session = LanguageModelSession(
                            model: model,
                            tools: tools,
                            transcript: transcript,
                        )
                    } else {
                        session = LanguageModelSession(
                            model: model,
                            tools: tools,
                            instructions: instructions,
                        )
                    }
                    let response = try await {
                        if let schema = generationSchema {
                            return try await session.respond(
                                to: prompt,
                                schema: schema
                            )
                        } else {
                            return try await session.respond(
                                to: prompt
                            )
                        }
                    }()
                    print(response.content.jsonString)
                    let content = response.content
                    let contentString = String(describing: content)
                    await MainActor.run {
                        completion(contentString, nil, nil)
                    }
                } catch {
                    print("Other generation error: \(error)")

                    await MainActor.run {
                        completion(
                            nil,
                            "generation_error",
                            error.localizedDescription
                        )
                    }
                }
            }
        }

        static func prepareTools(
            from toolsJSON: [[String: Any]],
            toolInvoker: FlutterToolInvoker
        )
            throws
            -> [any Tool]
        {
            do {
                return try toolsJSON.map {
                    try self.makeDartTool(from: $0, toolInvoker: toolInvoker)
                }
            } catch {
                print(
                    FlutterError(
                        code: "create_failed",
                        message: error.localizedDescription,
                        details: nil
                    )
                )
                return []
            }

        }
        static func makeDartTool(
            from json: [String: Any],
            toolInvoker: FlutterToolInvoker
        ) throws
            -> DartTool
        {
            let name = json["name"] as! String
            let description = json["description"] as! String
            let schemaJSON = json["parameters"] as! [String: Any]

            let schema = try materializeFromDartJSON(schemaJSON)
            guard let schema = schema else {
                throw FlutterToolError(code: "no scheme found for tool \(name)")
            }

            return DartTool(
                name: name,
                description: description,
                parameters: schema,
                invoker: toolInvoker
            )
        }
    }
#endif

/// A tool whose implementation lives on the Dart side.
struct DartTool: Tool {
    let name: String
    let description: String
    let parameters: GenerationSchema

    // Channel / callback that talks to Dart
    private let invoker: ToolInvoker

    init(
        name: String,
        description: String,
        parameters: GenerationSchema,
        invoker: ToolInvoker
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.invoker = invoker
    }

    func call(arguments: GeneratedContent) async throws -> String {
        // 1. Turn GeneratedContent into something JSON-serializable
        let argsJSON = try arguments.jsonString  // or your own encoder

        // 2. Call Dart and wait for the result
        let result = try await invoker.invoke(
            toolName: name,
            arguments: argsJSON
        )

        return result
    }
}

protocol ToolInvoker: Sendable {
    func invoke(toolName: String, arguments: Any) async throws -> String
}
/// Concrete implementation using Flutter MethodChannel / FFI / etc.
final class FlutterToolInvoker: ToolInvoker {
    private let channel: FlutterMethodChannel

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    func invoke(toolName: String, arguments: Any) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            // This calls INTO Dart
            DispatchQueue.main.async {
                self.channel.invokeMethod(
                    "onToolCall",  // ← method name Dart will listen to
                    arguments: [
                        "name": toolName,
                        "arguments": arguments,
                    ]
                ) { result in
                    if let error = result as? FlutterError {
                        continuation.resume(
                            throwing: FlutterToolError(code: error.message)
                        )
                    } else if let value = result as? String {
                        continuation.resume(returning: value)
                    } else if let value = result as? [String: Any],
                        let text = value["result"] as? String
                    {
                        continuation.resume(returning: text)
                    } else {
                        continuation.resume(
                            throwing: FlutterToolError(
                                code: "ToolBridgeError.invalidResponse"
                            )
                        )
                    }
                }
            }
        }
    }

}

struct FlutterToolError: Error {
    public let code: String?
}

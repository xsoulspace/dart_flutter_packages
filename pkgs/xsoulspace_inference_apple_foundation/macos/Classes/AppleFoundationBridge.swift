import Foundation

/// Bridge to Apple Foundation Models. Uses SystemLanguageModel when available (macOS 26+, Apple Intelligence).
/// Compiles on older SDKs by stubbing; at runtime returns unavailable when framework is missing.
enum AppleFoundationBridge {
    static func isAvailable() -> Bool {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                return FoundationModelsBridge.isAvailable()
            }
        #endif
        return false
    }

    static func generate(
        prompt: String,
        transcript: String?,
        instructions: String?,
        completion: @escaping (String?, String?, String?) -> Void
    ) {
        #if canImport(FoundationModels)
            if #available(macOS 26.0, *) {
                FoundationModelsBridge.generate(
                    prompt: prompt,
                    transcript: transcript != nil
                        ? Transcript(entries: [
                            Transcript.Entry.prompt(
                                Transcript.Prompt.init(
                                    segments: [
                                        Transcript.Segment.text(
                                            Transcript.TextSegment.init(
                                                content: transcript!
                                            )
                                        )
                                    ]
                                )
                            )
                        ]) : nil,
                    instructions: instructions,
                    completion: completion
                )
                return
            }
        #endif
        completion(
            nil,
            "engine_unavailable",
            "Foundation Models not available on this OS"
        )
    }
}

#if canImport(FoundationModels)
    import FoundationModels

    @available(macOS 26.0, *)
    enum FoundationModelsBridge {
        static func isAvailable() -> Bool {
            let model = SystemLanguageModel.default
            return model.isAvailable
        }

        static func generate(
            prompt: String,
            transcript: Transcript?,
            instructions: String?,
            completion: @escaping (String?, String?, String?) -> Void
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
                    // 1. Directly assign the constant using an if-else expression
                    let session =
                    if let transcript = transcript, !transcript.isEmpty {
                        LanguageModelSession(model: model, transcript: transcript)
                    } else {
                        LanguageModelSession(model: model, instructions: instructions)
                    }
                    let response = try await session.respond(to: prompt)
                    //        DispatchQueue.main.async {
                    //          completion(response.content, nil, nil)
                    //        }

                    // 2. Safe main-thread UI updates using modern Swift concurrency
                    await MainActor.run {
                        completion(response.content, nil, nil)
                    }
                } catch {
                    //        DispatchQueue.main.async {
                    //          completion(nil, "engine_unavailable", error.localizedDescription)
                    //        }
                    // 3. Always handle errors in a do-catch block
                    await MainActor.run {
                        completion(
                            nil,
                            "engine_unavailable",
                            error.localizedDescription
                        )
                    }
                }
            }
        }
    }
#endif

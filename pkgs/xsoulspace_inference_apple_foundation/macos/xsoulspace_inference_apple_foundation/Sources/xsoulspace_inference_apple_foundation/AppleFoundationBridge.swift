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
        completion: @escaping (String?, String?, String?) -> Void,
        generationSchema: GenerationSchema?
    ) {
        #if canImport(FoundationModels)
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
                generationSchema: generationSchema
            )
        #else
            completion(
                nil,
                "engine_unavailable",
                "Foundation Models not available"
            )
        #endif
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
            generationSchema: GenerationSchema?
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
                            transcript: transcript
                        )
                    } else {
                        session = LanguageModelSession(
                            model: model,
                            instructions: instructions
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
                    let content = response.content
                    let contentString = String(describing: content)
                    await MainActor.run {
                        completion(contentString, nil, nil)
                    }
                } catch {
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




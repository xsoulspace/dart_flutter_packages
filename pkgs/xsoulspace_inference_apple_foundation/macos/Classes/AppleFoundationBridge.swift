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
    workingDirectory: String,
    completion: @escaping (String?, String?, String?) -> Void
  ) {
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      FoundationModelsBridge.generate(prompt: prompt, workingDirectory: workingDirectory, completion: completion)
      return
    }
    #endif
    completion(nil, "engine_unavailable", "Foundation Models not available on this OS")
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
    workingDirectory: String,
    completion: @escaping (String?, String?, String?) -> Void
  ) {
    let model = SystemLanguageModel.default
    guard model.isAvailable else {
      completion(nil, "engine_unavailable", "Apple Intelligence not available")
      return
    }
    Task {
      do {
        let session = LanguageModelSession(model: model)
        let response = try await session.respond(to: prompt)
        DispatchQueue.main.async {
          completion(response.content, nil, nil)
        }
      } catch {
        DispatchQueue.main.async {
          completion(nil, "engine_unavailable", error.localizedDescription)
        }
      }
    }
  }
}
#endif

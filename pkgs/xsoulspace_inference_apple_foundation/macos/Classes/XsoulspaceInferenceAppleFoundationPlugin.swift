#if os(macOS)
import FlutterMacOS
#else
import Flutter
#endif
import Foundation

/// macOS plugin: method channel for Apple Foundation Models availability and generation.
/// When FoundationModels is available (macOS 26+, Apple Intelligence enabled),
/// uses SystemLanguageModel for inference; otherwise returns engine_unavailable.
public class XsoulspaceInferenceAppleFoundationPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "xsoulspace_inference_apple_foundation",
      binaryMessenger: registrar.messenger
    )
    let instance = XsoulspaceInferenceAppleFoundationPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      handleIsAvailable(result: result)
    case "generate":
      guard let args = call.arguments as? [String: Any],
            let prompt = args["prompt"] as? String else {
        result(FlutterError(code: "invalid_args", message: "prompt required", details: nil))
        return
      }
      let workingDirectory = args["workingDirectory"] as? String ?? ""
      handleGenerate(prompt: prompt, workingDirectory: workingDirectory, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleIsAvailable(result: @escaping FlutterResult) {
    let available = AppleFoundationBridge.isAvailable()
    result(available)
  }

  private func handleGenerate(prompt: String, workingDirectory: String, result: @escaping FlutterResult) {
    AppleFoundationBridge.generate(prompt: prompt, workingDirectory: workingDirectory) { output, errorCode, message in
      if let code = errorCode {
        result(FlutterError(code: code, message: message ?? "Inference failed", details: nil))
        return
      }
      result(output ?? "")
    }
  }
}

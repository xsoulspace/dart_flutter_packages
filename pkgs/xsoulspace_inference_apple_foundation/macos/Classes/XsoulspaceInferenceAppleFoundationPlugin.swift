import Foundation

#if os(macOS)
    import FlutterMacOS
#else
    import Flutter
#endif

/// macOS plugin: method channel for Apple Foundation Models availability and generation.
/// Works only when FoundationModels is available (macOS 26+, Apple Intelligence enabled),
/// uses SystemLanguageModel for inference; otherwise returns engine_unavailable.
@available(macOS 26.0, *)
public class XsoulspaceInferenceAppleFoundationPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "xsoulspace_inference_apple_foundation",
            binaryMessenger: registrar.messenger
        )
        let instance = XsoulspaceInferenceAppleFoundationPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        switch call.method {
        case "isAvailable":
            handleIsAvailable(result: result)
        case "generate":
            // 1. Ensure args is a dictionary, and prompt is a valid, required String
            guard let args = call.arguments as? [String: Any],
                let prompt = args["prompt"] as? String
            else {
                result(
                    FlutterError(
                        code: "invalid_args",
                        message: "prompt required",
                        details: nil
                    )
                )
                return
            }

            // 2. Safely cast optional properties without failing the entire guard statement if they are nil
            let transcript = args["transcript"] as? String
            let instructions = args["instructions"] as? String

            // 3. Pass values to your handler function cleanly
            handleGenerate(
                prompt: prompt,
                transcript: transcript,
                instructions: instructions,
                result: result
            )
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleIsAvailable(result: @escaping FlutterResult) {
        let available = FoundationModelsBridge.isAvailable()
        result(available)
    }

    private func handleGenerate(
        prompt: String,
        transcript: String?,
        instructions: String?,
        result: @escaping FlutterResult
    ) {
        AppleFoundationBridge.generate(
            prompt: prompt,
            transcript: transcript,
            instructions: instructions,
        ) {
            output,
            errorCode,
            message in
            if let code = errorCode {
                result(
                    FlutterError(
                        code: code,
                        message: message ?? "Inference failed",
                        details: nil
                    )
                )
                return
            }
            result(output ?? "")
        }
    }
}

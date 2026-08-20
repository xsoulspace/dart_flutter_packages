import FlutterMacOS
import Foundation

/// macOS plugin for Apple Foundation Models.
public class XsoulspaceInferenceAppleFoundationPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel!
    private var toolInvoker: FlutterToolInvoker!
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "xsoulspace_inference_apple_foundation",
            binaryMessenger: registrar.messenger
        )
        let instance = XsoulspaceInferenceAppleFoundationPlugin()
        instance.channel = channel
        instance.toolInvoker = FlutterToolInvoker(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {

        switch call.method {
        case "isAvailable":
            result(AppleFoundationBridge.isAvailable())
        case "generate":
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

            let schemaJson = args["schema"] as? [String: Any] ?? [:]
            let dartRoot = schemaJson["root"] as? String
            let dartDependencies = schemaJson["dependencies"] as? String
            let toolsJSON = args["tools"] as? [[String: Any]] ?? []
            let requestId = args["requestId"] as? String ?? ""

            do {
                let generationSchema = try materializeFromDartJSON(
                    schemaJson
                )
                AppleFoundationBridge.generate(
                    prompt: prompt,
                    transcript: args["transcript"] as? String,
                    instructions: args["instructions"] as? String,
                    generationSchema: generationSchema,
                    toolsJSON: toolsJSON,
                    requestId: requestId,
                    toolInvoker: toolInvoker,
                ) { output, errorCode, message in
                    if let errorCode {
                        result(
                            FlutterError(
                                code: errorCode,
                                message: message ?? "Inference failed",
                                details: nil
                            )
                        )
                    } else {
                        result(output ?? "")
                    }
                }
            } catch {
                result(
                    FlutterError(
                        code: error.localizedDescription,
                        message: "Inference failed",
                        details: error
                    )
                )
            }

        default:
            result(FlutterMethodNotImplemented)
        }
    }

}

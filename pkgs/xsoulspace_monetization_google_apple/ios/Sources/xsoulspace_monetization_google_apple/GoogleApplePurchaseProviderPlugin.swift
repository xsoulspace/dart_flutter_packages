import Flutter
import StoreKit
import UIKit

// code from https://github.com/flutter/flutter/issues/86096#issuecomment-1110433644
public class GoogleApplePurchaseProviderPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.xsoulspace.monetization/cancelSubscription", binaryMessenger: registrar.messenger()
    )
    let instance = GoogleApplePurchaseProviderPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "showCancelSubscriptionSheet" else {
      result(FlutterMethodNotImplemented)
      return
    }

    if #available(iOS 15.0, *) {
      Task {
        let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene
        if let scene = windowScene {
          await self.showCancelSubSheet(scene: scene)
        }
      }
    }
    result(true)
  }

  @available(iOS 15.0, *)
  func showCancelSubSheet(scene: UIWindowScene) async {
    do {
      try await AppStore.showManageSubscriptions(in: scene)
    } catch {
      // TODO(arenukvern): Handle or log the error
    }
  }
}

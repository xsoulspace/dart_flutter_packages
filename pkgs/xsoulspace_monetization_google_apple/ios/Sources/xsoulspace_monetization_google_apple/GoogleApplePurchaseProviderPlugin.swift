import Flutter
import StoreKit
import UIKit

// code from https://github.com/flutter/flutter/issues/86096#issuecomment-1110433644
public class GoogleApplePurchaseProviderPlugin: NSObject, FlutterPlugin {
  private let storeKitService = StoreKitService()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.xsoulspace.monetization/purchases", binaryMessenger: registrar.messenger()
    )
    let instance = GoogleApplePurchaseProviderPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    channel.setMethodCallHandler(instance.handle)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "showCancelSubscriptionSheet":
      if #available(iOS 15.0, *) {
        Task {
          let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene
          if let scene = windowScene {
            await self.showCancelSubSheet(scene: scene)
          }
        }
      }
      result(true)

    case "fetchProducts":
      guard let productIdentifiers = call.arguments as? [String] else {
        // TODO: Create a custom error here
        result(nil)
        return
      }
      storeKitService.fetchProducts(productIdentifiers: productIdentifiers) { products, error in
        if let error = error {
          result(
            FlutterError(
              code: "FETCH_PRODUCTS_FAILED", message: error.localizedDescription, details: nil))
          return
        }
        result(products)
      }

    case "purchaseProduct":
      guard let productIdentifier = call.arguments as? String else {
        // TODO: Create a custom error here
        result(nil)
        return
      }
      storeKitService.purchaseProduct(productIdentifier: productIdentifier) { productID, error in
        if let error = error {
          result(
            FlutterError(
              code: "PURCHASE_PRODUCT_FAILED", message: error.localizedDescription, details: nil))
          return
        }
        result(productID)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
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

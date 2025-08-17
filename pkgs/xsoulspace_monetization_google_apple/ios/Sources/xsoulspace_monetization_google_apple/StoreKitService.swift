import StoreKit

// https://medium.com/@aisultanios/implement-inn-app-subscriptions-using-swift-and-storekit2-serverless-and-share-active-purchases-7d50f9ecdc09

@objc public class StoreKitService: NSObject {
  private var products: [Product] = []
  /// The `productID` is a unique string identifier for an in-app product or subscription
  /// as defined in App Store Connect. It is used to fetch, purchase, and manage products
  /// via StoreKit.
  private var purchasedProductIDs: Set<String> = []

  @objc public func fetchProducts(
    productIdentifiers: Set<String>, completion: @escaping ([String]?, Error?) -> Void
  ) {
    Task {
      do {
        let products = try await Product.products(for: productIdentifiers)
        self.products = products

        let jsonStrings = products.map { $0.jsonRepresentation }
        completion(jsonStrings, nil)
      } catch {
        completion(nil, error)
      }
    }
  }

  @objc public func purchaseProduct(
    productIdentifier: String, completion: @escaping (String?, Error?) -> Void
  ) {
    guard let product = products.first(where: { $0.id == productIdentifier }) else {
      // TODO: Create a custom error here
      completion(nil, nil)
      return
    }

    Task {
      do {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
          let transaction = try self.checkVerified(verification)
          self.purchasedProductIDs.insert(transaction.productID)
          await transaction.finish()
          completion(transaction.productID, nil)
        case .userCancelled, .pending:
          completion(nil, nil)
        default:
          completion(nil, nil)
        }
      } catch {
        completion(nil, error)
      }
    }
  }

  private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .unverified:
      // Successful purchase but transaction/receipt can't be verified
      // Could be a jailbroken phone
      // TODO: Create a custom error here
      throw URLError(.cancelled)
    case .verified(let safe):
      return safe
    }
  }
}

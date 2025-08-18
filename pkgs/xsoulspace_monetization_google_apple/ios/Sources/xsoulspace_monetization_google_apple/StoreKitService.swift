import StoreKit
import UIKit

// https://medium.com/@aisultanios/implement-inn-app-subscriptions-using-swift-and-storekit2-serverless-and-share-active-purchases-7d50f9ecdc09

@objc public class StoreKitService: NSObject {
  private var products: [Product] = []
  /// The `productID` is a unique string identifier for an in-app product or subscription
  /// as defined in App Store Connect. It is used to fetch, purchase, and manage products
  /// via StoreKit.
  private var purchasedProductIDs: Set<String> = []

  @objc public func fetchProducts(
    productIdentifiers: [String], completion: @escaping ([String]?, Error?) -> Void
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
      let error = NSError(
        domain: "StoreKitService", code: 404,
        userInfo: [
          NSLocalizedDescriptionKey: "Product not found: \(productIdentifier)"
        ])
      completion(nil, error)
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
          completion("\(transaction.id)", nil)
        case .userCancelled:
          let error = NSError(
            domain: "StoreKitService", code: 1001,
            userInfo: [
              NSLocalizedDescriptionKey: "Purchase was cancelled by user"
            ])
          completion(nil, error)
        case .pending:
          let error = NSError(
            domain: "StoreKitService", code: 1002,
            userInfo: [
              NSLocalizedDescriptionKey: "Purchase is pending approval"
            ])
          completion(nil, error)
        default:
          let error = NSError(
            domain: "StoreKitService", code: 1003,
            userInfo: [
              NSLocalizedDescriptionKey: "Purchase failed with unknown status"
            ])
          completion(nil, error)
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
      throw NSError(
        domain: "StoreKitService", code: 2001,
        userInfo: [
          NSLocalizedDescriptionKey: "Transaction verification failed"
        ])
    case .verified(let safe):
      return safe
    }
  }

  private func enrichTransaction(_ transaction: Transaction) async -> String? {
    guard let product: Product = products.first(where: { $0.id == transaction.productID }) else {
      return transaction.jsonRepresentation
    }

    // Create a new dictionary like Dart Map
    var enrichedDict: [String: Any] = [:]

    // Spread transaction data (equivalent to Dart's ... operator)
    if let transactionData = transaction.jsonRepresentation as? [String: Any] {
      enrichedDict.merge(transactionData) { _, new in new }
    }

    // Add product with key "product"
    enrichedDict["product"] = product.jsonRepresentation

    do {
      let jsonData = try JSONSerialization.data(
        withJSONObject: enrichedDict, options: .prettyPrinted)
      return String(data: jsonData, encoding: .utf8)
    } catch {
      return transaction.jsonRepresentation
    }
  }

  @objc public func getLatestTransaction(
    productIdentifier: String, completion: @escaping (String?, Error?) -> Void
  ) {
    Task {
      guard let result = await Transaction.latest(for: productIdentifier) else {
        let error = NSError(
          domain: "StoreKitService", code: 3001,
          userInfo: [
            NSLocalizedDescriptionKey: "No transaction found for product: \(productIdentifier)"
          ])
        completion(nil, error)
        return
      }

      do {
        let transaction = try self.checkVerified(result)
        let enrichedTransaction = await self.enrichTransaction(transaction)
        completion(enrichedTransaction, nil)
      } catch {
        completion(nil, error)
      }
    }
  }

  @objc public func getTransaction(
    for purchaseId: String, completion: @escaping (String?, Error?) -> Void
  ) {
    Task {
      var allTransactions: [Transaction] = []
      for await result in Transaction.all {
        do {
          let transaction = try self.checkVerified(result)
          allTransactions.append(transaction)
        } catch {
          // Ignore unverified transactions
        }
      }

      let transaction = allTransactions.first { "\($0.id)" == purchaseId }
      if let transaction = transaction {
        let enrichedTransaction = await self.enrichTransaction(transaction)
        completion(enrichedTransaction, nil)
      } else {
        let error = NSError(
          domain: "StoreKitService", code: 4001,
          userInfo: [
            NSLocalizedDescriptionKey: "Transaction not found for purchase ID: \(purchaseId)"
          ])
        completion(nil, error)
      }
    }
  }

  @objc public func showManageSubscriptions(completion: @escaping (Error?) -> Void) {
    Task {
      do {
        guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene
        else {
          let error = NSError(
            domain: "StoreKitService", code: 5001,
            userInfo: [
              NSLocalizedDescriptionKey: "No window scene available for showing subscriptions"
            ])
          completion(error)
          return
        }
        try await AppStore.showManageSubscriptions(in: windowScene)
        completion(nil)
      } catch {
        completion(error)
      }
    }
  }
}

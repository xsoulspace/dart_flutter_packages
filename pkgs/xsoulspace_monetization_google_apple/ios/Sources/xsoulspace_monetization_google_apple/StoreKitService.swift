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
          completion("\(transaction.id)", nil)
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

  private func enrichTransaction(_ transaction: Transaction) async -> String? {
    guard let product = products.first(where: { $0.id == transaction.productID }) else {
      return transaction.jsonRepresentation
    }

    var transactionDict = transaction.dictionaryRepresentation
    transactionDict["product"] = product.dictionaryRepresentation

    do {
      let jsonData = try JSONSerialization.data(
        withJSONObject: transactionDict, options: .prettyPrinted)
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
        completion(nil, nil)
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
        completion(nil, nil)
      }
    }
  }

  @objc public func showManageSubscriptions(completion: @escaping (Error?) -> Void) {
    Task {
      do {
        guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene
        else {
          // TODO: Create a custom error here
          completion(nil)
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

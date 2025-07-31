import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rustore_billing_api/rustore_billing_api.dart';

/// {@template rustore_billing_example}
/// Example demonstrating RuStore billing API usage
/// {@endtemplate}
class RustoreBillingExample extends StatefulWidget {
  /// {@macro rustore_billing_example}
  const RustoreBillingExample({super.key});

  @override
  State<RustoreBillingExample> createState() => _RustoreBillingExampleState();
}

class _RustoreBillingExampleState extends State<RustoreBillingExample> {
  final _client = RustoreBillingClient.instance;
  var _isInitialized = false;
  var _isRustoreUserAuthorized = false;
  var _purchasesAvailable = false;
  List<RustoreProduct> _products = [];
  List<RustorePurchase> _purchases = [];
  var _status = 'Not initialized';

  @override
  void initState() {
    super.initState();
    unawaited(_setupBilling());
  }

  @override
  void dispose() {
    unawaited(_client.dispose());
    super.dispose();
  }

  /// Initialize the billing client
  Future<void> _setupBilling() async {
    try {
      setState(() => _status = 'Initializing...');

      // Initialize with configuration
      await _client.initialize(
        RustoreBillingConfig(
          consoleApplicationId: 'your_app_id_here',
          deeplinkScheme: 'yourappscheme',
          debugLogs: true,
          enableLogging: true,
        ),
      );

      setState(() => _isInitialized = true);
      setState(() => _status = 'Initialized successfully');

      // Check RuStore installation
      await _checkRuStoreInstallation();

      // Check purchase availability
      await _checkPurchaseAvailability();

      // Listen to purchase results
      _client.updatesStream.listen(
        (final e) => switch (e.type) {
          RustoreBillingResultType.payment => _handlePurchaseResult(
            e.paymentResult!,
          ),
          RustoreBillingResultType.error => _handleError(e.error!),
        },
      );
    } catch (e) {
      setState(() => _status = 'Initialization failed: $e');
    }
  }

  /// Check if RuStore is installed
  Future<void> _checkRuStoreInstallation() async {
    try {
      final isInstalled = await _client.isRustoreUserAuthorized();
      setState(() => _isRustoreUserAuthorized = isInstalled);
    } catch (e) {
      setState(() => _status = 'Failed to check RuStore installation: $e');
    }
  }

  /// Check if purchases are available
  Future<void> _checkPurchaseAvailability() async {
    try {
      final result = await _client.checkPurchasesAvailability();
      setState(() {
        _purchasesAvailable =
            result.resultType == RustorePurchaseAvailabilityType.available;
        if (result.resultType == RustorePurchaseAvailabilityType.unavailable) {
          _status = 'Purchases unavailable: ${result.cause?.message}';
        }
      });
    } catch (e) {
      setState(() => _status = 'Failed to check purchase availability: $e');
    }
  }

  /// Load products
  Future<void> _loadProducts() async {
    try {
      setState(() => _status = 'Loading products...');

      final products = await _client.getProducts([
        'product_id_1',
        'product_id_2',
        'subscription_id_1',
      ]);

      setState(() {
        _products = products;
        _status = 'Loaded ${products.length} products';
      });
    } catch (e) {
      setState(() => _status = 'Failed to load products: $e');
    }
  }

  /// Load purchases
  Future<void> _loadPurchases() async {
    try {
      setState(() => _status = 'Loading purchases...');

      final purchases = await _client.getPurchases();

      setState(() {
        _purchases = purchases;
        _status = 'Loaded ${purchases.length} purchases';
      });
    } catch (e) {
      setState(() => _status = 'Failed to load purchases: $e');
    }
  }

  /// Purchase a product
  Future<void> _purchaseProduct(final String productId) async {
    try {
      setState(() => _status = 'Starting purchase...');

      final result = await _client.purchaseProduct(
        productId,
        developerPayload:
            'custom_payload_${DateTime.now().millisecondsSinceEpoch}',
      );

      _handlePurchaseResult(result);
    } catch (e) {
      setState(() => _status = 'Purchase failed: $e');
    }
  }

  /// Handle purchase result
  void _handlePurchaseResult(final RustorePaymentResult result) {
    setState(() {
      switch (result.resultType) {
        case RustorePaymentResultType.success:
          _status = 'Purchase successful: ${result.purchaseId}';
          // Confirm the purchase
          if (result.purchaseId.isNotEmpty) {
            unawaited(_confirmPurchase(result.purchaseId));
          }
        case RustorePaymentResultType.cancelled:
          _status = 'Purchase cancelled';
        case RustorePaymentResultType.failure:
          _status = 'Purchase failed: ${result.errorMessage}';
        case RustorePaymentResultType.invalidPaymentState:
          _status = 'Invalid payment state: ${result.errorMessage}';
      }
    });
  }

  /// Confirm a purchase
  Future<void> _confirmPurchase(final String purchaseId) async {
    try {
      await _client.confirmPurchase(purchaseId);
      setState(() => _status = 'Purchase confirmed: $purchaseId');
      // Reload purchases after confirmation
      await _loadPurchases();
    } catch (e) {
      setState(() => _status = 'Failed to confirm purchase: $e');
    }
  }

  /// Handle errors
  void _handleError(final RustoreError error) {
    setState(() => _status = 'Error: ${error.message} (${error.code})');
  }

  RustoreBillingTheme _theme = RustoreBillingTheme.light;

  /// Toggle theme
  Future<void> _toggleTheme() async {
    try {
      _theme = _theme == RustoreBillingTheme.light
          ? RustoreBillingTheme.dark
          : RustoreBillingTheme.light;

      await _client.setTheme(_theme);
      setState(() => _status = 'Theme changed to ${_theme.name}');
    } catch (e) {
      setState(() => _status = 'Failed to change theme: $e');
    }
  }

  @override
  Widget build(final BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('RuStore Billing Example'),
      actions: [
        IconButton(
          icon: const Icon(Icons.palette),
          onPressed: _isInitialized ? _toggleTheme : null,
          tooltip: 'Toggle theme',
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Status: $_status',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text('Initialized: $_isInitialized'),
                  Text('RuStore User Authorized: $_isRustoreUserAuthorized'),
                  Text('Purchases Available: $_purchasesAvailable'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Action buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: _isInitialized ? _loadProducts : null,
                child: const Text('Load Products'),
              ),
              ElevatedButton(
                onPressed: _isInitialized ? _loadPurchases : null,
                child: const Text('Load Purchases'),
              ),
              ElevatedButton(
                onPressed: _isInitialized ? _checkRuStoreInstallation : null,
                child: const Text('Check RuStore'),
              ),
              ElevatedButton(
                onPressed: _isInitialized ? _checkPurchaseAvailability : null,
                child: const Text('Check Availability'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Products section
          if (_products.isNotEmpty) ...[
            Text(
              'Products (${_products.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _products.length,
                itemBuilder: (final context, final index) {
                  final product = _products[index];
                  return Card(
                    child: ListTile(
                      title: Text(product.title ?? product.productId),
                      subtitle: Text(product.description ?? ''),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (product.priceLabel != null)
                            Text(product.priceLabel!),
                          if (product.price != null)
                            Text('${product.price} ${product.currency ?? ''}'),
                        ],
                      ),
                      onTap: _purchasesAvailable
                          ? () => _purchaseProduct(product.productId)
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],

          // Purchases section
          if (_purchases.isNotEmpty) ...[
            Text(
              'Purchases (${_purchases.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _purchases.length,
                itemBuilder: (final context, final index) {
                  final purchase = _purchases[index];
                  return Card(
                    child: ListTile(
                      title: Text(purchase.productId ?? 'Unknown Product'),
                      subtitle: Text(
                        purchase.purchaseState?.name ?? 'Unknown State',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (purchase.amountLabel != null)
                            Text(purchase.amountLabel!),
                          if (purchase.amount != null)
                            Text(
                              '${purchase.amount} ${purchase.currency ?? ''}',
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

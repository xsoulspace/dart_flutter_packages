import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rustore_billing_api/rustore_billing_api.dart';

void main() {
  runApp(const MaterialApp(home: RustoreBillingExample()));
}

class RustoreBillingExample extends StatefulWidget {
  const RustoreBillingExample({super.key});

  @override
  State<RustoreBillingExample> createState() => _RustoreBillingExampleState();
}

class _RustoreBillingExampleState extends State<RustoreBillingExample> {
  final RustoreBillingClient _client = RustoreBillingClient.instance;

  bool _initialized = false;
  bool _authorized = false;
  RustorePurchaseAvailabilityResult? _availability;
  List<RustoreProduct> _products = const <RustoreProduct>[];
  List<RustorePurchase> _purchases = const <RustorePurchase>[];
  String _status = 'Not initialized';
  StreamSubscription<RustoreBillingResult>? _updatesSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void dispose() {
    unawaited(_updatesSubscription?.cancel());
    unawaited(_client.dispose());
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _status = 'Initializing...');
    try {
      await _client.initialize(
        RustoreBillingConfig(
          consoleApplicationId: 'your_app_id_here',
          deeplinkScheme: 'yourappscheme',
          debugLogs: true,
        ),
      );
      _updatesSubscription = _client.updatesStream.listen(_handleUpdate);
      setState(() {
        _initialized = true;
        _status = 'Initialized';
      });
      await _refreshStoreStatus();
    } catch (e) {
      setState(() => _status = 'Initialization failed: $e');
    }
  }

  Future<void> _refreshStoreStatus() async {
    try {
      final auth = await _client.getUserAuthorizationStatus();
      final availability = await _client.getPurchaseAvailability();
      setState(() {
        _authorized = auth;
        _availability = availability;
      });
    } catch (e) {
      setState(() => _status = 'Status check failed: $e');
    }
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _client.getProducts(const <String>[
        'product_id_1',
        'subscription_id_1',
      ]);
      setState(() {
        _products = products;
        _status = 'Loaded ${products.length} products';
      });
    } catch (e) {
      setState(() => _status = 'Load products failed: $e');
    }
  }

  Future<void> _loadPurchases() async {
    try {
      final purchases = await _client.getPurchases();
      setState(() {
        _purchases = purchases;
        _status = 'Loaded ${purchases.length} purchases';
      });
    } catch (e) {
      setState(() => _status = 'Load purchases failed: $e');
    }
  }

  Future<void> _purchaseOneStep(final String productId) async {
    try {
      final result = await _client.purchase(
        RustoreProductPurchaseParams(
          productId: productId,
          quantity: 1,
          developerPayload: 'example_one_step',
        ),
        preferredPurchaseType: RustorePreferredPurchaseType.oneStep,
      );
      _handlePurchaseResult(result, prefix: 'One-step');
    } catch (e) {
      setState(() => _status = 'One-step purchase failed: $e');
    }
  }

  Future<void> _purchaseTwoStep(final String productId) async {
    try {
      final result = await _client.purchaseTwoStep(
        RustoreProductPurchaseParams(
          productId: productId,
          quantity: 1,
          developerPayload: 'example_two_step',
        ),
      );
      _handlePurchaseResult(result, prefix: 'Two-step');
      final purchaseId = result.purchase?.purchaseId;
      if (purchaseId != null && purchaseId.isNotEmpty) {
        await _client.confirmTwoStepPurchase(
          purchaseId,
          developerPayload: 'confirmed_in_example',
        );
        setState(() => _status = 'Two-step purchase confirmed: $purchaseId');
      }
    } catch (e) {
      setState(() => _status = 'Two-step purchase failed: $e');
    }
  }

  void _handleUpdate(final RustoreBillingResult event) {
    final purchaseResult = event.purchaseResult;
    if (purchaseResult != null) {
      _handlePurchaseResult(purchaseResult, prefix: 'Stream');
      return;
    }
    final error = event.error;
    if (error != null) {
      setState(
        () => _status = 'Stream error: ${error.message} (${error.code})',
      );
    }
  }

  void _handlePurchaseResult(
    final RustoreProductPurchaseResult result, {
    required final String prefix,
  }) {
    final purchaseId = result.purchase?.purchaseId ?? '-';
    switch (result.resultType) {
      case RustoreProductPurchaseResultType.success:
        setState(() => _status = '$prefix purchase success: $purchaseId');
      case RustoreProductPurchaseResultType.cancelled:
        setState(() => _status = '$prefix purchase cancelled');
      case RustoreProductPurchaseResultType.failure:
        setState(
          () => _status =
              '$prefix purchase failed: ${result.error?.message ?? 'Unknown'}',
        );
      case RustoreProductPurchaseResultType.unknown:
        setState(() => _status = '$prefix purchase returned unknown state');
    }
  }

  @override
  Widget build(final BuildContext context) {
    final availabilityStatus = _availability?.status.name ?? 'unknown';
    return Scaffold(
      appBar: AppBar(title: const Text('RuStore Billing 10.1 Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Status: $_status'),
            Text('Initialized: $_initialized'),
            Text('Authorized: $_authorized'),
            Text('Purchase availability: $availabilityStatus'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ElevatedButton(
                  onPressed: _initialized ? _refreshStoreStatus : null,
                  child: const Text('Refresh status'),
                ),
                ElevatedButton(
                  onPressed: _initialized ? _loadProducts : null,
                  child: const Text('Load products'),
                ),
                ElevatedButton(
                  onPressed: _initialized ? _loadPurchases : null,
                  child: const Text('Load purchases'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_products.isNotEmpty) ...<Widget>[
              Text('Products: ${_products.length}'),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _products.length,
                  itemBuilder: (final context, final index) {
                    final RustoreProduct product = _products[index];
                    return Card(
                      child: ListTile(
                        title: Text(product.title ?? product.productId),
                        subtitle: Text(
                          product.priceLabel ?? product.productType.name,
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: <Widget>[
                            TextButton(
                              onPressed: () =>
                                  _purchaseOneStep(product.productId),
                              child: const Text('One-step'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _purchaseTwoStep(product.productId),
                              child: const Text('Two-step'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (_purchases.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text('Purchases: ${_purchases.length}'),
            ],
          ],
        ),
      ),
    );
  }
}

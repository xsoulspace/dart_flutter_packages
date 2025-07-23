import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rustore_billing_api/rustore_billing_api.dart';

void main() {
  runApp(const RustoreBillingExampleApp());
}

class RustoreBillingExampleApp extends StatelessWidget {
  const RustoreBillingExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RuStore Billing Example',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      useMaterial3: true,
    ),
    home: const BillingExamplePage(),
  );
}

class BillingExamplePage extends StatefulWidget {
  const BillingExamplePage({super.key});

  @override
  State<BillingExamplePage> createState() => _BillingExamplePageState();
}

class _BillingExamplePageState extends State<BillingExamplePage> {
  final RustoreBillingClient _billingClient = RustoreBillingClient.instance;

  bool _initialized = false;
  bool _loading = false;
  String _status = 'Not initialized';

  List<RustoreProduct> _products = [];
  List<RustorePurchase> _purchases = [];

  StreamSubscription<RustorePaymentResult>? _purchaseSubscription;
  StreamSubscription<RustoreError>? _errorSubscription;

  // Example product IDs - replace with your actual product IDs
  final List<String> _productIds = ['productId1', 'productId2', 'productId3'];

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    _errorSubscription?.cancel();
    super.dispose();
  }

  void _setupListeners() {
    _purchaseSubscription = _billingClient.purchaseResults.listen((result) {
      setState(() {
        _status = 'Purchase result: ${result.resultType}';
      });

      if (result.resultType == RustorePaymentResultType.success) {
        _confirmPurchase(result.purchaseId!);
      }
    });

    _errorSubscription = _billingClient.errors.listen((error) {
      setState(() {
        _status = 'Error: ${error.message}';
      });
      _showErrorDialog(error);
    });
  }

  Future<void> _initializeBilling() async {
    setState(() {
      _loading = true;
      _status = 'Initializing...';
    });

    try {
      await _billingClient.initialize(
        RustoreBillingConfig(
          consoleApplicationId: '123456789', // Replace with your app ID
          deeplinkScheme: 'rustoresdkexamplescheme', // Replace with your scheme
          debugLogs: true,
        ),
      );

      setState(() {
        _initialized = true;
        _status = 'Initialized successfully';
      });

      // Load products and purchases after initialization
      await _loadProducts();
      await _loadPurchases();
    } catch (e) {
      setState(() {
        _status = 'Initialization failed: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadProducts() async {
    if (!_initialized) return;

    setState(() {
      _loading = true;
      _status = 'Loading products...';
    });

    try {
      final products = await _billingClient.getProducts(_productIds);
      setState(() {
        _products = products;
        _status = 'Loaded ${products.length} products';
      });
    } catch (e) {
      setState(() {
        _status = 'Failed to load products: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _loadPurchases() async {
    if (!_initialized) return;

    setState(() {
      _loading = true;
      _status = 'Loading purchases...';
    });

    try {
      final purchases = await _billingClient.getPurchases();
      setState(() {
        _purchases = purchases;
        _status = 'Loaded ${purchases.length} purchases';
      });

      // Process unfinished purchases
      await _processUnfinishedPurchases(purchases);
    } catch (e) {
      setState(() {
        _status = 'Failed to load purchases: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _processUnfinishedPurchases(
    List<RustorePurchase> purchases,
  ) async {
    for (final purchase in purchases) {
      if (purchase.purchaseState == RustorePurchaseState.paid &&
          purchase.purchaseId != null) {
        // Auto-confirm paid purchases
        await _confirmPurchase(purchase.purchaseId!);
      }
    }
  }

  Future<void> _purchaseProduct(RustoreProduct product) async {
    setState(() {
      _loading = true;
      _status = 'Purchasing ${product.title ?? product.productId}...';
    });

    try {
      final result = await _billingClient.purchaseProduct(
        product.productId,
        developerPayload:
            'example_payload_${DateTime.now().millisecondsSinceEpoch}',
      );

      setState(() {
        _status = 'Purchase initiated: ${result.resultType}';
      });
    } catch (e) {
      setState(() {
        _status = 'Purchase failed: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _confirmPurchase(String purchaseId) async {
    setState(() {
      _loading = true;
      _status = 'Confirming purchase...';
    });

    try {
      await _billingClient.confirmPurchase(purchaseId);
      setState(() {
        _status = 'Purchase confirmed successfully';
      });

      // Reload purchases to reflect changes
      await _loadPurchases();
    } catch (e) {
      setState(() {
        _status = 'Failed to confirm purchase: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  void _showErrorDialog(RustoreError error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Billing Error'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Code: ${error.code}'),
            const SizedBox(height: 8),
            Text('Message: ${error.message}'),
            if (error.description != null) ...[
              const SizedBox(height: 8),
              Text('Description: ${error.description}'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('RuStore Billing Example'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_status),
                    if (_loading) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Action buttons
            if (!_initialized) ...[
              ElevatedButton(
                onPressed: _loading ? null : _initializeBilling,
                child: const Text('Initialize Billing'),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _loadProducts,
                      child: const Text('Load Products'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _loadPurchases,
                      child: const Text('Load Purchases'),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Products section
            Expanded(
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    const TabBar(
                      tabs: [
                        Tab(text: 'Products'),
                        Tab(text: 'Purchases'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [_buildProductsList(), _buildPurchasesList()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsList() {
    if (_products.isEmpty) {
      return const Center(
        child: Text(
          'No products loaded. Tap "Load Products" to fetch products.',
        ),
      );
    }

    return ListView.builder(
      itemCount: _products.length,
      itemBuilder: (context, index) {
        final product = _products[index];
        return Card(
          child: ListTile(
            title: Text(product.title ?? product.productId),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (product.description != null) Text(product.description!),
                if (product.priceLabel != null)
                  Text('Price: ${product.priceLabel}'),
                Text('Type: ${product.productType}'),
              ],
            ),
            trailing: ElevatedButton(
              onPressed: _loading ? null : () => _purchaseProduct(product),
              child: const Text('Buy'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPurchasesList() {
    if (_purchases.isEmpty) {
      return const Center(
        child: Text('No purchases found. Make a purchase to see it here.'),
      );
    }

    return ListView.builder(
      itemCount: _purchases.length,
      itemBuilder: (context, index) {
        final purchase = _purchases[index];
        return Card(
          child: ListTile(
            title: Text(purchase.productId ?? 'Unknown Product'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('State: ${purchase.purchaseState}'),
                if (purchase.purchaseId != null)
                  Text('ID: ${purchase.purchaseId}'),
                if (purchase.amountLabel != null)
                  Text('Amount: ${purchase.amountLabel}'),
                if (purchase.purchaseTime != null)
                  Text('Time: ${purchase.purchaseTime}'),
              ],
            ),
            trailing:
                purchase.purchaseState == RustorePurchaseState.paid &&
                    purchase.purchaseId != null
                ? ElevatedButton(
                    onPressed: _loading
                        ? null
                        : () => _confirmPurchase(purchase.purchaseId!),
                    child: const Text('Confirm'),
                  )
                : null,
          ),
        );
      },
    );
  }
}

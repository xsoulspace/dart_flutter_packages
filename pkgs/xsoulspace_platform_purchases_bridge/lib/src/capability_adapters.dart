import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

import 'capabilities.dart';
import 'noop_purchase_provider.dart';

/// Wraps an existing [PurchaseProvider] as a platform capability.
final class PurchasesCapabilityAdapter implements PurchasesCapability {
  const PurchasesCapabilityAdapter(this.purchaseProvider);

  @override
  final PurchaseProvider purchaseProvider;

  @override
  String get capabilityName => 'monetization.purchases';
}

/// No-op purchases capability implementation.
final class NoopPurchasesCapability extends PurchasesCapabilityAdapter {
  NoopPurchasesCapability() : super(NoopPurchaseProvider());
}

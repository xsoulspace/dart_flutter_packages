import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';

abstract interface class PurchasesCapability implements PlatformCapability {
  PurchaseProvider get purchaseProvider;
}

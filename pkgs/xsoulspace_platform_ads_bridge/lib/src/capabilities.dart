import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';

abstract interface class AdsCapability implements PlatformCapability {
  AdProvider get adProvider;
}

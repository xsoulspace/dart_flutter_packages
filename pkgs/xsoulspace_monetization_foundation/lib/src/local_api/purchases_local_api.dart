import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';
import 'package:xsoulspace_monetization_interface/xsoulspace_monetization_interface.dart';

/// {@template purchases_local_api}
/// A class that provides a local API for purchases.
/// {@endtemplate}
class PurchasesLocalApi {
  /// {@macro purchases_local_api}
  PurchasesLocalApi({required this.localDb});
  final LocalDbI localDb;

  static const activeSubscriptionKey =
      'XSP_MonetizationFoundation.active_subscription';

  /// {@template save_active_subscription}
  /// Saves the active subscription to the local database.
  /// {@endtemplate}
  Future<void> saveActiveSubscription(
    final PurchaseDetailsModel purchase,
  ) async {
    await localDb.setItem(
      key: activeSubscriptionKey,
      value: purchase,
      toJson: (final value) => value.toJson(),
    );
  }

  /// {@template get_active_subscription}
  /// Gets the active subscription from the local database.
  /// Will return an empty purchase if no active subscription is found.
  /// {@endtemplate}
  Future<PurchaseDetailsModel> getActiveSubscription() =>
      localDb.getItem<PurchaseDetailsModel>(
        key: activeSubscriptionKey,
        fromJson: PurchaseDetailsModel.fromJson,
        defaultValue: PurchaseDetailsModel.empty,
      );

  /// {@template clear_active_subscription}
  /// Clears the active subscription from the local database.
  /// {@endtemplate}
  Future<void> clearActiveSubscription() => localDb.setItem(
    key: activeSubscriptionKey,
    value: PurchaseDetailsModel.empty,
    toJson: (final value) => value.toJson(),
  );
}

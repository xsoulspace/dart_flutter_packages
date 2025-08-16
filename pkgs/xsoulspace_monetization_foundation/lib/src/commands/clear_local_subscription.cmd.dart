import '../local_api/local_api.dart';

/// {@template clean_local_subscription_command}
/// Command to clean local subscription.
/// {@endtemplate}
class ClearLocalSubscriptionCommand {
  /// {@macro clean_local_subscription_command}
  ClearLocalSubscriptionCommand({required this.purchasesLocalApi});

  /// {@macro clean_local_subscription_command}
  final PurchasesLocalApi purchasesLocalApi;

  /// {@macro clean_local_subscription_command}
  Future<void> execute() async {
    await purchasesLocalApi.clearActiveSubscription();
  }
}

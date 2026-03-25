import 'dart:async';

import 'android/rustore_billing_android.dart';
import 'models/rustore_billing_result.dart';
import 'rustore_api.g.dart';
import 'rustore_billing_platform.dart';

class RustoreBillingClient {
  RustoreBillingClient._();

  static RustoreBillingClient? _instance;
  // ignore: prefer_constructors_over_static_methods
  static RustoreBillingClient get instance =>
      _instance ??= RustoreBillingClient._();

  RustoreBillingPlatform get _platform => RustoreBillingPlatform.instance;

  Stream<RustoreBillingResult> get updatesStream {
    if (_platform is RustoreBillingAndroid) {
      return (_platform as RustoreBillingAndroid).updatesStream;
    }
    return const Stream.empty();
  }

  Future<void> initialize(final RustoreBillingConfig config) async {
    try {
      await _platform.initialize(config);
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        code: 'initialize_failed',
        message: 'Failed to initialize billing client: $e',
        details: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<RustorePurchaseAvailabilityResult> getPurchaseAvailability() async {
    try {
      return await _platform.getPurchaseAvailability();
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        code: 'availability_failed',
        message: 'Failed to get purchase availability: $e',
        details: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> getUserAuthorizationStatus() async {
    try {
      return await _platform.getUserAuthorizationStatus();
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        code: 'authorization_failed',
        message: 'Failed to check user authorization status: $e',
        details: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<List<RustoreProduct>> getProducts(
    final List<String> productIds,
  ) async {
    try {
      return await _platform.getProducts(productIds);
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        code: 'products_failed',
        message: 'Failed to get products: $e',
        details: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<List<RustorePurchase>> getPurchases({
    final RustorePurchaseFilter? filter,
  }) async {
    try {
      return await _platform.getPurchases(filter);
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        code: 'purchases_failed',
        message: 'Failed to get purchases: $e',
        details: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<RustorePurchase?> getPurchase(final String purchaseId) async {
    try {
      return await _platform.getPurchase(purchaseId);
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        code: 'purchase_failed',
        message: 'Failed to get purchase by id: $e',
        details: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<RustoreProductPurchaseResult> purchase(
    final RustoreProductPurchaseParams params, {
    final RustorePreferredPurchaseType preferredPurchaseType =
        RustorePreferredPurchaseType.unknown,
    final RustoreBillingTheme sdkTheme = RustoreBillingTheme.system,
  }) async {
    try {
      return await _platform.purchase(
        params,
        preferredPurchaseType: preferredPurchaseType,
        sdkTheme: sdkTheme,
      );
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        code: 'purchase_failed',
        message: 'Failed to purchase product: $e',
        details: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<RustoreProductPurchaseResult> purchaseTwoStep(
    final RustoreProductPurchaseParams params, {
    final RustoreBillingTheme sdkTheme = RustoreBillingTheme.system,
  }) async {
    try {
      return await _platform.purchaseTwoStep(params, sdkTheme: sdkTheme);
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        code: 'purchase_two_step_failed',
        message: 'Failed to start two-step purchase: $e',
        details: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> confirmTwoStepPurchase(
    final String purchaseId, {
    final String? developerPayload,
  }) async {
    try {
      await _platform.confirmTwoStepPurchase(
        purchaseId,
        developerPayload: developerPayload,
      );
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        code: 'confirm_two_step_failed',
        message: 'Failed to confirm two-step purchase: $e',
        details: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> cancelTwoStepPurchase(final String purchaseId) async {
    try {
      await _platform.cancelTwoStepPurchase(purchaseId);
    } catch (e, stackTrace) {
      throw RustoreBillingException(
        code: 'cancel_two_step_failed',
        message: 'Failed to cancel two-step purchase: $e',
        details: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> dispose() async {
    if (_platform is RustoreBillingAndroid) {
      await (_platform as RustoreBillingAndroid).dispose();
    }
  }
}

class RustoreBillingException implements Exception {
  const RustoreBillingException({
    required this.code,
    required this.message,
    required this.stackTrace,
    this.details,
  });

  final String code;
  final String message;
  final Object? details;
  final StackTrace stackTrace;

  @override
  String toString() => 'RustoreBillingException($code): $message';
}

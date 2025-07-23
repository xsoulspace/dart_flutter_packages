import 'android/rustore_billing_android.dart';

/// Registers the Android implementation of RuStore billing
///
/// This should be called during app initialization on Android platforms.
/// The implementation will automatically register itself as the default
/// platform implementation.
void registerWith() {
  RustoreBillingAndroid.registerWith();
}

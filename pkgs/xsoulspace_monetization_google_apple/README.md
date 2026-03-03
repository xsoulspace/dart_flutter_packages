# xsoulspace_monetization_google_apple

A Flutter package for integrating Google Play and Apple App Store in-app purchases.

## Features

- In-app purchases for Android (Google Play) and iOS (App Store)
- Unified API via [xsoulspace_monetization_interface](https://pub.dev/packages/xsoulspace_monetization_interface)

## Production readiness

- Supported platforms: Android (Google Play Billing), iOS (App Store / StoreKit).
- Known limitations:
  - Product type and subscription period inference may depend on product naming conventions when store metadata is partial.
  - Store-side account state (signed out, unavailable billing backend) is surfaced as provider errors and must be handled by app UI.
- Required configuration:
  - Create product IDs in App Store Connect / Google Play Console.
  - Ensure app signing, billing permissions, and store listing setup are complete for release builds.
  - Provide the same product IDs to the provider that are configured in store consoles.
- Rollback guidance:
  - Pin the previously known-good package version in `pubspec.yaml`.
  - Temporarily disable purchase entry points in UI if store errors increase during rollout.
  - Re-run purchase verification tests before re-enabling traffic.

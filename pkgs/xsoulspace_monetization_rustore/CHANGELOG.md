# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.1-dev.1] - 2026-04-29

- fix: subscription / non-consumable purchases reported by RuStore as
  `RustorePurchaseState.paid` are now mapped to `PurchaseStatus.purchased`
  instead of `pendingVerification`. Previously, a successful subscription
  purchase left users stuck on the paywall: the foundation's
  `confirmPurchaseCommand` ran, but its `isPurchased` check failed because
  RuStore's `paid` was treated as unverified, so subscription state never
  transitioned to `subscribed`. `paid` for consumable purchases is unchanged
  (still mapped to `pendingVerification` so the foundation drives the
  `confirmPurchase` call).
- changed: `purchaseStatusFromRustoreState` now takes a required `productType`
  argument and is exported with `@visibleForTesting`.

## 0.8.0

- chore: updated dependencies
- chore: updated README
- chore: updated CHANGELOG
- chore: updated LICENSE

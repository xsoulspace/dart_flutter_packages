# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.10.0

BREAKING:

- feat!: remove material-based screens (PurchaseScreen, SubscriptionScreen,
  PurchaseGuardScreen, PricingScreen, AdFreeScreen, FamilyPlanScreen) — the
  widgets folder no longer contains any Material UI
- feat!: add material-free slot-based views: PurchaseListView,
  SubscriptionListView, PurchaseGate and the sealed PurchaseProductsState.
  State flows in through properties, actions flow out through callbacks, and
  every visual (loading, error, items, locked prompt) is a caller-supplied
  builder — the access/product fetch lifecycle moves to the caller

## 0.9.0

BREAKING:

- chore: sdk: ^3.12.0
- chore: is_dart_empty_or_not: ^0.4.0
- chore: xsoulspace_monetization_interface: ^0.9.0

## [0.11.0]

### Added

- `MonetizationStoreBinding` — the monetization extension of `oka_store`'s
  open `StoreBinding`: names the store openly (no enum) and constructs the
  purchase provider compiled for it (`purchaseProviderFactory`, null =
  store-neutral build). Hand-typed binding files import exactly one backend
  package; per-store app entrypoints import exactly one binding, so only
  that backend ships in the AOT kernel.
- `NoopMonetizationStoreBinding` — the store-neutral posture (dev/website/
  snap): no key, null provider.
- **Dependency direction law** (oka ADR-0055): monetization → oka, never the
  reverse. Requires `oka_store` ^0.12.0 (publishes from the oka repo train).

## [0.8.2] - 2026-02-08

- chore: update is_dart_empty_or_not dependency to 0.4.0
- chore: update xsoulspace_monetization_interface dependency to 0.8.2

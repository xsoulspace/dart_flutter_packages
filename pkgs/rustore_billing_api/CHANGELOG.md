# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.0

BREAKING:

- chore: sdk: ">=3.11.0 <4.0.0"
- chore: from_json_to_json: ^0.5.0
- chore: pigeon: ^26.3.4

## 1.0.0

- breaking: migrated Android bridge to RuStore Billing/Pay SDK `10.1.0` API
  surface (interactors + new purchase flow contracts).
- breaking: replaced old methods with new APIs:
  `getPurchaseAvailability`, `getUserAuthorizationStatus`, `purchase`,
  `purchaseTwoStep`, `confirmTwoStepPurchase`, `cancelTwoStepPurchase`,
  `getPurchases(filter)`, `getPurchase(id)`.
- breaking: removed legacy `onNewIntent`, `purchaseProduct`, `confirmPurchase`,
  `deletePurchase`, and standalone `setTheme`.
- added: new request/response models for purchase params, purchase filters,
  purchase result/error, and status enums with `unknown` fallback values.
- added: automatic deep-link forwarding on Android via activity intent listener.
- changed: package version bumped to `1.0.0`.

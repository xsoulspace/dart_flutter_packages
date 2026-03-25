# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-03-02

- breaking: migrated to `rustore_billing_api: ^1.0.0`.
- breaking: switched purchase flow integration to new RuStore 10.1-style APIs:
  `purchase`, `purchaseTwoStep`, `confirmTwoStepPurchase`,
  `cancelTwoStepPurchase`, and filtered purchase retrieval.
- changed: complete/cancel operations are now explicitly tied to two-step
  purchases only.

## [0.8.2] - 2026-02-08

- chore: update xsoulspace_monetization_interface dependency to 0.8.2

## 0.8.0

- chore: updated dependencies
- chore: updated README
- chore: updated CHANGELOG
- chore: updated LICENSE

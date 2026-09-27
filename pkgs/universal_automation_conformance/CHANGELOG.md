# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Added
- change: navigation conformance now accepts a loud typed refusal,
  so tree-only OS drivers (AT-SPI, UIA) can adopt the suite.

- feat: `automationDriverConformanceTests` — capability honesty,
  snapshot validity, action, screenshot, idempotent close.
- feat: `frameSourceConformanceTests` — monotonic sequences, metadata
  sanity, nothing-after-stop, idempotent stop.
- feat: `frameSinkConformanceTests` — accept/close, use-after-close
  throws, idempotent close with error surfacing.

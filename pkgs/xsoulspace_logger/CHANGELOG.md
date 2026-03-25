# Changelog

All notable changes to this package will be documented in this file.

## 1.0.0-beta.0

- BREAKING: redesigned `xsoulspace_logger` into a pure Dart core package.
- Added sink abstraction (`LogSink`) with explicit composition in `Logger`.
- Added immutable `LogRecord` model with monotonic `sequence` and trace support.
- Added `TraceContext` and scoped logger context APIs (`child`, `withTrace`).
- Added query/inspection APIs: `query`, `watch`, and `trace`.
- Added backpressure handling with low-priority drop strategy and synthetic warnings.
- Added safe-by-default redaction and depth/size guards.
- Added lazy logging methods `traceLazy` and `debugLazy`.
- Added deterministic testing utilities (`FakeClock`, `InMemoryLogSink`).
- Removed old built-in file writer and singleton reset flow.

# Changelog

All notable changes to this package will be documented in this file.

## 1.0.0-beta.0

- Initial beta release.
- Added `IoLogSink` durable NDJSON segment sink for `xsoulspace_logger`.
- Added startup recovery for truncated/corrupt segment tails.
- Added retention eviction by age and total size.
- Added segment rotation with sequence continuity.
- Added integration tests for recovery, retention, and ordering.

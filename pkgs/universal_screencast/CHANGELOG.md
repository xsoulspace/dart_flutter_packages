# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Added

- feat: `Frame`, `FrameSource`, `FrameSink` contracts with declared
  capabilities.
- feat: `ScreencastComposition` fail-closed validation (capability
  matrix, pacing floors per audience) and `ScreencastPipeline` with
  per-sink isolation and structured events.
- feat: `CdpScreencastFrameSource` and `PollingFrameSource`.
- feat: `WebSocketFrameServer`, `MjpegHttpSink`, `FileRecorderSink`.

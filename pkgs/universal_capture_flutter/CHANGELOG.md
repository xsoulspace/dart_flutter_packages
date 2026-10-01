# Changelog

## 0.1.1

- interface/conformance constraint bump only; no code changes.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Added

- feat: `ToolkitFrameSource` — paced PNG frames from a running Flutter
  app's `ext.mcp.toolkit.view_screenshots` extension, stamped with the
  `toolkit-flutter` source id and conformant with the family frame-source
  contract suite.
- feat: `VmScreenshotGrabber` — VM-service connection owning toolkit
  isolate discovery and PNG grabs, including `normalizeWsUri` for
  `flutter run`-style `http://…/#authToken=…` announcements.

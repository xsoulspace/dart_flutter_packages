# Changelog

## 0.1.1

- interface constraint bump only; no code changes.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Fixed

- fix: `CaptureStream.stop` drains the SCStream delivery queue (250 ms)
  before closing the frame callback — closing immediately raced an
  in-flight delegate call and crashed the VM intermittently; the frame
  sink also guards against adds after close.

### Added
- feat: ScreenCaptureKit streaming — `CaptureStream` (continuous
  JPEG frames at a capped fps via `NativeCallable.listener`) and
  `CaptureKitFrameSource`, a screencast `FrameSource` for the
  macOS-native tier. Verified live (permission-gated).

- feat: native-assets build hook compiling the Swift capture bridge
  (CoreGraphics + ApplicationServices) into a code asset.
- feat: `CaptureBridge` — version, AX trust probe, screen-recording
  preflight/request, display enumeration, single-frame PNG capture with
  typed permission errors.

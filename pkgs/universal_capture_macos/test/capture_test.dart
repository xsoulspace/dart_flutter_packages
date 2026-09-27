import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_capture_macos/universal_capture_macos.dart';
import 'package:universal_screencast/universal_screencast.dart';

void main() {
  test('refuses to load off macOS', () {
    if (Platform.isMacOS) {
      return; // The interesting case is covered below.
    }
    expect(CaptureBridge.ensureLoaded, throwsA(isA<Object>()));
  });

  test('bridge loads and reports trust state without prompting', () {
    if (!Platform.isMacOS) return;
    CaptureBridge.ensureLoaded();
    expect(CaptureBridge.version(), contains('xs-capture-bridge'));
    // Both probes are passive: they never trigger consent prompts.
    expect(CaptureBridge.axTrusted, isA<bool>());
    expect(CaptureBridge.screenPermissionPreflight, isA<bool>());
  }, skip: Platform.isMacOS ? false : 'macOS only (native-assets bridge)');

  test('captures a PNG frame when permission is already granted', () {
    if (!Platform.isMacOS) return;
    CaptureBridge.ensureLoaded();
    if (!CaptureBridge.screenPermissionPreflight) {
      // Permission-gated: an unattended environment has no consent.
      return;
    }
    final png = CaptureBridge.screenshotPng();
    expect(png.length, greaterThan(8));
    // PNG magic bytes.
    expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  }, skip: Platform.isMacOS ? false : 'macOS only (native-assets bridge)');

  test('lists displays when permission is already granted', () {
    if (!Platform.isMacOS) return;
    CaptureBridge.ensureLoaded();
    if (!CaptureBridge.screenPermissionPreflight) return;
    expect(CaptureBridge.listDisplays(), isNotEmpty);
  }, skip: Platform.isMacOS ? false : 'macOS only (native-assets bridge)');
}

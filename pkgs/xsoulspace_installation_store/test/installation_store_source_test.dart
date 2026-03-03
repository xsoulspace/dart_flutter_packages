import 'package:test/test.dart';
import 'package:xsoulspace_installation_store/xsoulspace_installation_store.dart';

void main() {
  group('InstallationStoreSource classifiers', () {
    test('maps major platform families', () {
      expect(InstallationStoreSource.androidGooglePlay.isAndroid, isTrue);
      expect(InstallationStoreSource.appleMacOSAppStore.isApple, isTrue);
      expect(InstallationStoreSource.windowsStore.isWindows, isTrue);
      expect(InstallationStoreSource.linuxSnap.isLinux, isTrue);
      expect(InstallationStoreSource.webSelfhost.isWeb, isTrue);
    });

    test('distinguishes apple iOS and macOS channels', () {
      expect(InstallationStoreSource.appleIOSAppStore.isAppleIos, isTrue);
      expect(InstallationStoreSource.appleIOSAppStore.isAppleMacos, isFalse);

      expect(InstallationStoreSource.appleMacOSDmg.isAppleMacos, isTrue);
      expect(InstallationStoreSource.appleMacOSDmg.isAppleIos, isFalse);
    });
  });

  group('InstallationTargetStore metadata', () {
    test('exposes stable human-readable names', () {
      expect(InstallationTargetStore.mobileGooglePlay.name, 'Google Play');
      expect(InstallationTargetStore.rustore.name, 'RuStore');
    });
  });
}

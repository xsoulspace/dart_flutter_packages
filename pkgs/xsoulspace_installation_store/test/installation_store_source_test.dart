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

  group('InstallationTargetStore (open key)', () {
    test('well-known keys carry stable identity and labels', () {
      expect(installationTargetGooglePlay.name, 'google-play');
      expect(installationTargetGooglePlay.label, 'Google Play');
      expect(installationTargetRuStore.name, 'rustore');
      expect(installationTargetRuStore.label, 'RuStore');
    });

    test('the set stays open: a novel key needs no PR here', () {
      const mine = InstallationTargetStore('my-market');
      expect(InstallationTargetStore.isValidName(mine.name), isTrue);
      expect(mine.label, 'my-market'); // fallback = raw name
    });
  });
}

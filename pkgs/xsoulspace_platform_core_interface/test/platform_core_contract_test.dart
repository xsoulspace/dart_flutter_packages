import 'package:test/test.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';

void main() {
  group('PlatformInitOptions', () {
    test('reads typed context values safely', () {
      final options = PlatformInitOptions(
        context: const <String, Object?>{'retries': 3, 'title': 'runtime'},
      );

      expect(options.read<int>('retries'), 3);
      expect(options.read<String>('title'), 'runtime');
      expect(options.read<bool>('title'), isNull);
    });
  });

  group('PlatformInitResult', () {
    test('exposes status helpers', () {
      expect(PlatformInitResult.success().isSuccess, isTrue);
      expect(PlatformInitResult.notAvailable().isNotAvailable, isTrue);
      expect(PlatformInitResult.failure().isFailure, isTrue);
    });
  });

  group('MissingPlatformCapabilityException', () {
    test('includes capability, platform and behavior in message', () {
      final exception = MissingPlatformCapabilityException(
        capabilityType: _AuthCapability,
        supportedCapabilities: const <Type>{_StatsCapability},
        behavior: MissingCapabilityBehavior.strict,
        platformId: PlatformId.discord,
      );

      expect(exception.code, PlatformExceptionCode.missingCapability);
      expect(exception.toString(), contains('_AuthCapability'));
      expect(exception.toString(), contains('discord'));
      expect(exception.toString(), contains('strict'));
    });
  });
}

final class _AuthCapability {}

final class _StatsCapability {}

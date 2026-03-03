import 'dart:async';

import 'package:test/test.dart';
import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';
import 'package:xsoulspace_platform_foundation/xsoulspace_platform_foundation.dart';

void main() {
  test('selects first available adapter by priority', () async {
    final notAvailableFactory = _FakeFactory(
      platformId: PlatformId.steam,
      priority: 0,
      supported: true,
      client: _FakeClient(
        platformId: PlatformId.steam,
        initResult: PlatformInitResult.notAvailable(
          message: 'no steam runtime',
        ),
      ),
    );

    final yandexFactory = _FakeFactory(
      platformId: PlatformId.yandexGames,
      priority: 1,
      supported: true,
      client: _FakeClient(
        platformId: PlatformId.yandexGames,
        initResult: PlatformInitResult.success(),
      ),
    );

    final runtime = PlatformRuntime(
      factories: <PlatformAdapterFactory>[yandexFactory, notAvailableFactory],
    );

    final result = await runtime.start();
    expect(result.activePlatform, PlatformId.yandexGames);
    expect(runtime.activePlatform, PlatformId.yandexGames);
  });

  test('strict mode fails startup when required capability missing', () async {
    final runtime = PlatformRuntime(
      factories: <PlatformAdapterFactory>[
        _FakeFactory(
          platformId: PlatformId.steam,
          priority: 0,
          supported: true,
          client: _FakeClient(
            platformId: PlatformId.steam,
            initResult: PlatformInitResult.success(),
          ),
        ),
      ],
      initOptions: const PlatformInitOptions(
        missingCapabilityBehavior: MissingCapabilityBehavior.strict,
        requiredCapabilities: <Type>{_FakeCapability},
      ),
    );

    expect(runtime.start(), throwsA(isA<MissingPlatformCapabilityException>()));
  });

  test('permissive mode starts with reduced capability set', () async {
    final runtime = PlatformRuntime(
      factories: <PlatformAdapterFactory>[
        _FakeFactory(
          platformId: PlatformId.steam,
          priority: 0,
          supported: true,
          client: _FakeClient(
            platformId: PlatformId.steam,
            initResult: PlatformInitResult.success(),
          ),
        ),
      ],
      initOptions: const PlatformInitOptions(
        missingCapabilityBehavior: MissingCapabilityBehavior.permissive,
      ),
    );

    final result = await runtime.start();
    expect(result.activePlatform, PlatformId.steam);
    expect(runtime.maybe<_FakeCapability>(), isNull);
  });

  test('require throws deterministic missing capability exception', () async {
    final runtime = PlatformRuntime(
      factories: <PlatformAdapterFactory>[
        _FakeFactory(
          platformId: PlatformId.steam,
          priority: 0,
          supported: true,
          client: _FakeClient(
            platformId: PlatformId.steam,
            initResult: PlatformInitResult.success(),
          ),
        ),
      ],
    );

    await runtime.start();

    expect(
      () => runtime.require<_FakeCapability>(),
      throwsA(
        isA<MissingPlatformCapabilityException>().having(
          (final e) => e.message,
          'message',
          contains('_FakeCapability'),
        ),
      ),
    );
  });

  test('maybe returns null for unsupported capability', () async {
    final runtime = PlatformRuntime(
      factories: <PlatformAdapterFactory>[
        _FakeFactory(
          platformId: PlatformId.steam,
          priority: 0,
          supported: true,
          client: _FakeClient(
            platformId: PlatformId.steam,
            initResult: PlatformInitResult.success(),
          ),
        ),
      ],
    );

    await runtime.start();
    expect(runtime.maybe<_FakeCapability>(), isNull);
  });
}

final class _FakeCapability implements PlatformCapability {
  @override
  String get capabilityName => 'fake';
}

final class _FakeFactory implements PlatformAdapterFactory {
  _FakeFactory({
    required this.platformId,
    required this.priority,
    required this.supported,
    required this.client,
  });

  @override
  final PlatformId platformId;

  @override
  final int priority;

  final bool supported;
  final PlatformClient client;

  @override
  Future<PlatformClient> createClient() async => client;

  @override
  Future<bool> isSupportedEnvironment() async => supported;
}

final class _FakeClient implements PlatformClient {
  _FakeClient({
    required this.platformId,
    required this.initResult,
    final Iterable<PlatformCapability> capabilities =
        const <PlatformCapability>[],
  }) {
    for (final capability in capabilities) {
      _capabilities[capability.runtimeType] = capability;
    }
  }

  @override
  final PlatformId platformId;

  final PlatformInitResult initResult;
  final Map<Type, PlatformCapability> _capabilities =
      <Type, PlatformCapability>{};

  @override
  Set<Type> get capabilityTypes => _capabilities.keys.toSet();

  @override
  Stream<PlatformEvent> get events => const Stream<PlatformEvent>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<PlatformInitResult> init(final PlatformInitOptions options) async =>
      initResult;

  @override
  T? maybe<T extends PlatformCapability>() => _capabilities[T] as T?;

  @override
  T require<T extends PlatformCapability>() {
    final capability = maybe<T>();
    if (capability == null) {
      throw MissingPlatformCapabilityException(
        capabilityType: T,
        supportedCapabilities: capabilityTypes,
        behavior: MissingCapabilityBehavior.strict,
      );
    }
    return capability;
  }

  @override
  bool supports<T extends PlatformCapability>() => _capabilities.containsKey(T);
}

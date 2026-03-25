import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xsoulspace_steamworks/xsoulspace_steamworks.dart';

import 'src/fake/fake_native_api.dart';

final class SteamExampleKeys {
  static const statusText = Key('status_text');
  static const eventText = Key('event_text');

  static const initializeButton = Key('btn_initialize');
  static const pumpButton = Key('btn_pump_once');
  static const requestStatsButton = Key('btn_request_stats');
  static const setAchievementButton = Key('btn_set_achievement');
  static const clearAchievementButton = Key('btn_clear_achievement');
  static const shutdownButton = Key('btn_shutdown');
}

class SteamworksExampleApp extends StatelessWidget {
  const SteamworksExampleApp({
    super.key,
    this.useFakeBackend = false,
    this.client,
  });

  final bool useFakeBackend;
  final SteamClient? client;

  @override
  Widget build(final BuildContext context) {
    final resolvedClient =
        client ??
        (useFakeBackend
            ? SteamClient(
                nativeApiFactory: const ExampleFakeSteamNativeApiFactory(),
              )
            : SteamClient());

    return MaterialApp(
      title: 'Steamworks Desktop Example',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: SteamworksHomePage(client: resolvedClient),
    );
  }
}

class SteamworksHomePage extends StatefulWidget {
  const SteamworksHomePage({super.key, required this.client});

  final SteamClient client;

  @override
  State<SteamworksHomePage> createState() => _SteamworksHomePageState();
}

class _SteamworksHomePageState extends State<SteamworksHomePage> {
  StreamSubscription<SteamEvent>? _eventSubscription;

  String _status = 'Idle';
  String _lastEvent = 'None';

  SteamClient get _client => widget.client;

  @override
  void initState() {
    super.initState();
    _eventSubscription = _client.events.listen((final event) {
      setState(() {
        _lastEvent = event.runtimeType.toString();
      });
    });
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    unawaited(_client.shutdown());
    super.dispose();
  }

  Future<void> _initialize() async {
    setState(() => _status = 'Initializing...');

    final result = await _client.initialize(
      const SteamInitConfig(
        appId: 480,
        autoPumpCallbacks: true,
        callbackInterval: Duration(milliseconds: 16),
      ),
    );

    setState(() {
      if (result.success) {
        _status = 'Initialized';
      } else {
        _status =
            'Init failed: ${result.errorCode} '
            '${result.message == null || result.message!.isEmpty ? '' : result.message}';
      }
    });
  }

  Future<void> _requestStats() async {
    if (!_client.isInitialized) {
      setState(() => _status = 'Initialize first.');
      return;
    }

    final ok = await _client.stats.requestCurrentStats();
    setState(() => _status = 'requestCurrentStats: $ok');
  }

  Future<void> _setAchievement() async {
    if (!_client.isInitialized) {
      setState(() => _status = 'Initialize first.');
      return;
    }

    final ok = _client.achievements.setAchievement('ACH_WIN_ONE_GAME');
    final stored = await _client.stats.storeStats();
    setState(() => _status = 'setAchievement=$ok storeStats=$stored');
  }

  Future<void> _clearAchievement() async {
    if (!_client.isInitialized) {
      setState(() => _status = 'Initialize first.');
      return;
    }

    final ok = _client.achievements.clearAchievement('ACH_WIN_ONE_GAME');
    final stored = await _client.stats.storeStats();
    setState(() => _status = 'clearAchievement=$ok storeStats=$stored');
  }

  @override
  Widget build(final BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Steamworks Desktop Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Status: $_status', key: SteamExampleKeys.statusText),
            const SizedBox(height: 8),
            Text('Last event: $_lastEvent', key: SteamExampleKeys.eventText),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ElevatedButton(
                  key: SteamExampleKeys.initializeButton,
                  onPressed: _initialize,
                  child: const Text('Initialize'),
                ),
                ElevatedButton(
                  key: SteamExampleKeys.pumpButton,
                  onPressed: _client.runCallbacksOnce,
                  child: const Text('Pump once'),
                ),
                ElevatedButton(
                  key: SteamExampleKeys.requestStatsButton,
                  onPressed: _requestStats,
                  child: const Text('Request stats'),
                ),
                ElevatedButton(
                  key: SteamExampleKeys.setAchievementButton,
                  onPressed: _setAchievement,
                  child: const Text('Set achievement'),
                ),
                ElevatedButton(
                  key: SteamExampleKeys.clearAchievementButton,
                  onPressed: _clearAchievement,
                  child: const Text('Clear achievement'),
                ),
                ElevatedButton(
                  key: SteamExampleKeys.shutdownButton,
                  onPressed: () async {
                    await _client.shutdown();
                    setState(() => _status = 'Shutdown complete');
                  },
                  child: const Text('Shutdown'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xsoulspace_steamworks/xsoulspace_steamworks.dart';

void main() {
  runApp(const SteamworksExampleApp());
}

class SteamworksExampleApp extends StatelessWidget {
  const SteamworksExampleApp({super.key});

  @override
  Widget build(final BuildContext context) {
    return MaterialApp(
      title: 'Steamworks Desktop Example',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const SteamworksHomePage(),
    );
  }
}

class SteamworksHomePage extends StatefulWidget {
  const SteamworksHomePage({super.key});

  @override
  State<SteamworksHomePage> createState() => _SteamworksHomePageState();
}

class _SteamworksHomePageState extends State<SteamworksHomePage> {
  final SteamClient _client = SteamClient();

  StreamSubscription<SteamEvent>? _eventSubscription;

  String _status = 'Idle';
  String _lastEvent = 'None';

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
            Text('Status: $_status'),
            const SizedBox(height: 8),
            Text('Last event: $_lastEvent'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ElevatedButton(
                  onPressed: _initialize,
                  child: const Text('Initialize'),
                ),
                ElevatedButton(
                  onPressed: _client.runCallbacksOnce,
                  child: const Text('Pump once'),
                ),
                ElevatedButton(
                  onPressed: _requestStats,
                  child: const Text('Request stats'),
                ),
                ElevatedButton(
                  onPressed: _setAchievement,
                  child: const Text('Set achievement'),
                ),
                ElevatedButton(
                  onPressed: _clearAchievement,
                  child: const Text('Clear achievement'),
                ),
                ElevatedButton(
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

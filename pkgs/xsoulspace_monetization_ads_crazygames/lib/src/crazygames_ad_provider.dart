import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:xsoulspace_crazygames_js/xsoulspace_crazygames_js.dart';
import 'package:xsoulspace_monetization_ads_interface/xsoulspace_monetization_ads_interface.dart';

/// Banner size helper for [CrazyGamesAdProvider].
final class CrazyGamesBannerSize {
  const CrazyGamesBannerSize({required this.width, required this.height});

  final int width;
  final int height;
}

/// Ad provider backed by CrazyGames HTML5 SDK.
class CrazyGamesAdProvider implements AdProvider {
  CrazyGamesAdProvider({
    final Future<CrazyGamesClient> Function({String expectedGlobal})?
    initClient,
    this.expectedGlobal = 'CrazyGames',
  }) : _initClient = initClient ?? CrazyGames.init;

  final Future<CrazyGamesClient> Function({String expectedGlobal}) _initClient;
  final String expectedGlobal;
  CrazyGamesClient? _client;

  @override
  Future<void> init() async {
    _client = await _initClient(expectedGlobal: expectedGlobal);
  }

  @override
  Future<void> showRewardedAd({required final String adUnitId}) async {
    final client = await _ensureClient();
    await client.ad.requestAd(AdType.rewarded);
  }

  @override
  Future<void> showInterstitialAd({required final String adUnitId}) async {
    final client = await _ensureClient();
    await client.ad.requestAd(AdType.midgame);
  }

  @override
  Widget buildBannerAd({
    required final String adUnitId,
    required final Object adSize,
  }) {
    final resolved = switch (adSize) {
      CrazyGamesBannerSize value => value,
      _ => const CrazyGamesBannerSize(width: 320, height: 50),
    };

    return _CrazyGamesBannerWidget(
      provider: this,
      adUnitId: adUnitId,
      size: resolved,
    );
  }

  Future<CrazyGamesClient> _ensureClient() async {
    final existing = _client;
    if (existing != null) {
      return existing;
    }

    await init();
    final initialized = _client;
    if (initialized == null) {
      throw StateError('CrazyGamesAdProvider.init() did not create a client.');
    }
    return initialized;
  }
}

final class _CrazyGamesBannerWidget extends StatefulWidget {
  const _CrazyGamesBannerWidget({
    required this.provider,
    required this.adUnitId,
    required this.size,
  });

  final CrazyGamesAdProvider provider;
  final String adUnitId;
  final CrazyGamesBannerSize size;

  @override
  State<_CrazyGamesBannerWidget> createState() =>
      _CrazyGamesBannerWidgetState();
}

final class _CrazyGamesBannerWidgetState
    extends State<_CrazyGamesBannerWidget> {
  @override
  void initState() {
    super.initState();
    unawaited(_requestBanner());
  }

  Future<void> _requestBanner() async {
    final client = await widget.provider._ensureClient();
    await client.banner.requestBanner(
      BannerRequest(
        id: widget.adUnitId,
        width: widget.size.width,
        height: widget.size.height,
      ),
    );
  }

  @override
  Widget build(final BuildContext context) {
    return SizedBox(
      width: widget.size.width.toDouble(),
      height: widget.size.height.toDouble(),
    );
  }
}

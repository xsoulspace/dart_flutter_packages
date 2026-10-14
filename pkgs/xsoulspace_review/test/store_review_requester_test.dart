import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';
import 'package:xsoulspace_review/xsoulspace_review.dart';

void main() {
  group('StoreReviewRequester', () {
    test('keeps requester unavailable when reviewer cannot load', () async {
      final localDb = _MemoryLocalDb();
      final reviewer = _FakeStoreReviewer(available: false);
      final requester = StoreReviewRequester(
        localDb: localDb,
        storeReviewer: reviewer,
        firstReviewPeriod: Duration.zero,
        reviewPeriod: Duration.zero,
      );

      await requester.onLoad();

      expect(requester.isAvailable, isFalse);
      expect(reviewer.onLoadCalls, 1);
      requester.dispose();
    });

    testWidgets('manual request updates counters and forwards to reviewer', (
      tester,
    ) async {
      final localDb = _MemoryLocalDb();
      final reviewer = _FakeStoreReviewer(available: true);
      final requester = StoreReviewRequester(
        localDb: localDb,
        storeReviewer: reviewer,
        firstReviewPeriod: const Duration(days: 30),
        reviewPeriod: const Duration(days: 30),
      );

      BuildContext? context;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (buildContext) {
              context = buildContext;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await requester.onLoad();
      await requester.requestReview(
        context: context,
        locale: const Locale('en'),
      );

      expect(reviewer.requestCalls, 1);
      expect(await localDb.getInt(key: 'review_count'), 1);
      requester.dispose();
    });
  });
}

final class _FakeStoreReviewer extends StoreReviewer {
  _FakeStoreReviewer({required this.available});

  final bool available;
  int onLoadCalls = 0;
  int requestCalls = 0;

  @override
  Future<bool> onLoad() async {
    onLoadCalls += 1;
    return available;
  }

  @override
  Future<void> requestReview(
    BuildContext context, {
    Locale? locale,
    bool force = false,
  }) async {
    requestCalls += 1;
  }
}

final class _MemoryLocalDb implements LocalDbI {
  final Map<String, dynamic> _store = <String, dynamic>{};

  @override
  Future<void> init() async {}

  @override
  Future<void> clear() async => _store.clear();

  @override
  Future<void> clearKey({required String key}) async {
    _store.remove(key);
  }

  @override
  Future<void> setMap({
    required String key,
    required Map<String, dynamic> value,
  }) async {
    _store[key] = value;
  }

  @override
  Future<Map<String, dynamic>> getMap(String key) async =>
      (_store[key] as Map<String, dynamic>?) ?? <String, dynamic>{};

  @override
  Future<void> setString({
    required String key,
    required String value,
  }) async {
    _store[key] = value;
  }

  @override
  Future<String> getString({
    required String key,
    String defaultValue = '',
  }) async => (_store[key] as String?) ?? defaultValue;

  @override
  Future<void> setBool({
    required String key,
    required bool value,
  }) async {
    _store[key] = value;
  }

  @override
  Future<bool> getBool({
    required String key,
    bool defaultValue = false,
  }) async => (_store[key] as bool?) ?? defaultValue;

  @override
  Future<void> setInt({required String key, int value = 0}) async {
    _store[key] = value;
  }

  @override
  Future<int> getInt({
    required String key,
    int defaultValue = 0,
  }) async => (_store[key] as int?) ?? defaultValue;

  @override
  Future<void> setItem<T>({
    required String key,
    required T value,
    required Map<String, dynamic> Function(T) toJson,
  }) async {
    _store[key] = toJson(value);
  }

  @override
  Future<T> getItem<T>({
    required String key,
    required T? Function(Map<String, dynamic>) fromJson,
    required T defaultValue,
  }) async {
    final raw = _store[key];
    if (raw is Map<String, dynamic>) {
      return fromJson(raw) ?? defaultValue;
    }
    return defaultValue;
  }

  @override
  Future<void> setItemsList<T>({
    required String key,
    required List<T> value,
    required Map<String, dynamic> Function(T) toJson,
  }) async {
    _store[key] = value.map(toJson).toList();
  }

  @override
  Future<Iterable<T>> getItemsIterable<T>({
    required String key,
    required T Function(Map<String, dynamic>) fromJson,
    List<T> defaultValue = const [],
  }) async {
    final raw = _store[key];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().map(fromJson);
    }
    return defaultValue;
  }

  @override
  Future<void> setMapList({
    required String key,
    required List<Map<String, dynamic>> value,
  }) async {
    _store[key] = value;
  }

  @override
  Future<Iterable<Map<String, dynamic>>> getMapIterable({
    required String key,
    List<Map<String, dynamic>> defaultValue =
        const <Map<String, dynamic>>[],
  }) async {
    final raw = _store[key];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>();
    }
    return defaultValue;
  }

  @override
  Future<void> setStringList({
    required String key,
    required List<String> value,
  }) async {
    _store[key] = value;
  }

  @override
  Future<Iterable<String>> getStringsIterable({
    required String key,
    List<String> defaultValue = const <String>[],
  }) async {
    final raw = _store[key];
    if (raw is List) {
      return raw.whereType<String>();
    }
    return defaultValue;
  }
}

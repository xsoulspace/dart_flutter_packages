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
      final tester,
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
            builder: (final buildContext) {
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
    final BuildContext context, {
    final Locale? locale,
    final bool force = false,
  }) async {
    requestCalls += 1;
  }
}

final class _MemoryLocalDb implements LocalDbI {
  final Map<String, dynamic> _store = <String, dynamic>{};

  @override
  Future<void> init() async {}

  Future<void> clear() async => _store.clear();

  Future<void> clearKey({required final String key}) async {
    _store.remove(key);
  }

  @override
  Future<void> setMap({
    required final String key,
    required final Map<String, dynamic> value,
  }) async {
    _store[key] = value;
  }

  @override
  Future<Map<String, dynamic>> getMap(final String key) async {
    return (_store[key] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }

  @override
  Future<void> setString({
    required final String key,
    required final String value,
  }) async {
    _store[key] = value;
  }

  @override
  Future<String> getString({
    required final String key,
    final String defaultValue = '',
  }) async {
    return (_store[key] as String?) ?? defaultValue;
  }

  @override
  Future<void> setBool({
    required final String key,
    required final bool value,
  }) async {
    _store[key] = value;
  }

  @override
  Future<bool> getBool({
    required final String key,
    final bool defaultValue = false,
  }) async {
    return (_store[key] as bool?) ?? defaultValue;
  }

  @override
  Future<void> setInt({required final String key, final int value = 0}) async {
    _store[key] = value;
  }

  @override
  Future<int> getInt({
    required final String key,
    final int defaultValue = 0,
  }) async {
    return (_store[key] as int?) ?? defaultValue;
  }

  @override
  Future<void> setItem<T>({
    required final String key,
    required final T value,
    required final Map<String, dynamic> Function(T) toJson,
  }) async {
    _store[key] = toJson(value);
  }

  @override
  Future<T> getItem<T>({
    required final String key,
    required final T? Function(Map<String, dynamic>) fromJson,
    required final T defaultValue,
  }) async {
    final raw = _store[key];
    if (raw is Map<String, dynamic>) {
      return fromJson(raw) ?? defaultValue;
    }
    return defaultValue;
  }

  @override
  Future<void> setItemsList<T>({
    required final String key,
    required final List<T> value,
    required final Map<String, dynamic> Function(T) toJson,
  }) async {
    _store[key] = value.map(toJson).toList();
  }

  @override
  Future<Iterable<T>> getItemsIterable<T>({
    required final String key,
    required final T Function(Map<String, dynamic>) fromJson,
    final List<T> defaultValue = const [],
  }) async {
    final raw = _store[key];
    if (raw is List) {
      return raw.whereType<Map<String, dynamic>>().map(fromJson);
    }
    return defaultValue;
  }

  @override
  Future<void> setMapList({
    required final String key,
    required final List<Map<String, dynamic>> value,
  }) async {
    _store[key] = value;
  }

  @override
  Future<Iterable<Map<String, dynamic>>> getMapIterable({
    required final String key,
    final List<Map<String, dynamic>> defaultValue =
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
    required final String key,
    required final List<String> value,
  }) async {
    _store[key] = value;
  }

  @override
  Future<Iterable<String>> getStringsIterable({
    required final String key,
    final List<String> defaultValue = const <String>[],
  }) async {
    final raw = _store[key];
    if (raw is List) {
      return raw.whereType<String>();
    }
    return defaultValue;
  }
}

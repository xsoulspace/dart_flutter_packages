import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_ui_foundation/xsoulspace_ui_foundation.dart';

void main() {
  group('PagingControllerPageModel', () {
    test('supports json roundtrip and copyWith', () {
      const original = PagingControllerPageModel<int>(
        values: <int>[1, 2, 3],
        currentPage: 2,
        pagesCount: 4,
      );

      final json = original.toJson(
        (final value) => <String, dynamic>{'v': value},
      );
      final decoded = PagingControllerPageModel<int>.fromJson(
        json,
        (final raw) => (raw as Map<String, dynamic>)['v'] as int,
      );

      expect(decoded.values, <int>[1, 2, 3]);
      expect(decoded.currentPage, 2);
      expect(decoded.pagesCount, 4);

      final copied = decoded.copyWith(currentPage: 3);
      expect(copied.currentPage, 3);
      expect(copied.values, <int>[1, 2, 3]);
    });
  });

  group('Widget extension', () {
    test('toSliver wraps widget in SliverToBoxAdapter', () {
      const child = SizedBox(width: 10, height: 10);

      final sliver = child.toSliver();

      expect(sliver, isA<SliverToBoxAdapter>());
      expect((sliver as SliverToBoxAdapter).child, child);
    });
  });
}

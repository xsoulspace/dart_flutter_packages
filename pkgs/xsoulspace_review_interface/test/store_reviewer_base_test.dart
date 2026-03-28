import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_review_interface/xsoulspace_review_interface.dart';

void main() {
  testWidgets('base StoreReviewer provides no-op defaults', (
    final tester,
  ) async {
    const reviewer = StoreReviewer(packageName: 'dev.xsoulspace.app');

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

    expect(await reviewer.onLoad(), isFalse);
    await reviewer.requestReview(context!);
  });
}

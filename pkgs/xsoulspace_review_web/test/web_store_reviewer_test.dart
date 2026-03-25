import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_review_web/xsoulspace_review_web.dart';

void main() {
  testWidgets('requestReview is a safe no-op on web fallback reviewer', (
    final tester,
  ) async {
    const reviewer = WebStoreReviewer();

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

    await reviewer.requestReview(context!, locale: const Locale('en'));
  });
}

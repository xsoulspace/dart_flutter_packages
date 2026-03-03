import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_review_huawei/xsoulspace_review_huawei.dart';

void main() {
  testWidgets('requestReview is a safe no-op fallback', (final tester) async {
    const reviewer = HuaweiStoreReviewer();

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

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_review_google_apple/xsoulspace_review_google_apple.dart';

void main() {
  testWidgets('requests review only when native API is available', (
    final tester,
  ) async {
    var requestCalls = 0;
    var available = false;

    final reviewer = GoogleAppleStoreReviewer(
      isAvailable: () async => available,
      requestNativeReview: () async {
        requestCalls += 1;
      },
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

    expect(await reviewer.onLoad(), isFalse);
    await reviewer.requestReview(context!);
    expect(requestCalls, 0);

    available = true;
    expect(await reviewer.onLoad(), isTrue);
    await reviewer.requestReview(context!);
    expect(requestCalls, 1);
  });
}

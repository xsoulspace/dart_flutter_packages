import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_review_rustore/xsoulspace_review_rustore.dart';

void main() {
  testWidgets('handles request limit without forcing fallback', (
    final tester,
  ) async {
    var consentCalls = 0;
    var launchCalls = 0;

    final reviewer = RuStoreReviewer(
      packageName: 'dev.xsoulspace.app',
      consentBuilder: (final context, final locale) async {
        consentCalls += 1;
        return true;
      },
      requestReviewFlow: () async {
        throw PlatformException(
          code: 'request_limit_reached',
          message: 'RuStoreRequestLimitReached',
        );
      },
      launchNativeReviewFlow: () async {},
      launchSchemeAction: (final scheme) async {
        launchCalls += 1;
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

    await reviewer.requestReview(context!);

    expect(consentCalls, 0);
    expect(launchCalls, 0);
  });

  testWidgets('opens store fallback when forced and consent is granted', (
    final tester,
  ) async {
    var launchScheme = '';

    final reviewer = RuStoreReviewer(
      packageName: 'dev.xsoulspace.app',
      consentBuilder: (final context, final locale) async => true,
      requestReviewFlow: () async {
        throw PlatformException(
          code: 'request_limit_reached',
          message: 'RuStoreRequestLimitReached',
        );
      },
      launchNativeReviewFlow: () async {},
      launchSchemeAction: (final scheme) async {
        launchScheme = scheme;
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

    await reviewer.requestReview(context!, force: true);

    expect(
      launchScheme,
      'https://www.rustore.ru/catalog/app/dev.xsoulspace.app',
    );
  });
}

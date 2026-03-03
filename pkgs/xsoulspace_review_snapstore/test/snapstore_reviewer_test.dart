import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_review_snapstore/xsoulspace_review_snapstore.dart';

void main() {
  testWidgets('does not launch store when consent is denied', (final tester) async {
    var launchCalls = 0;
    final reviewer = SnapStoreReviewer(
      packageName: 'xs-app',
      consentBuilder: (final context, final locale) async => false,
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

    expect(launchCalls, 0);
  });

  testWidgets('launches snap review scheme when consent is granted', (
    final tester,
  ) async {
    var launchedScheme = '';
    final reviewer = SnapStoreReviewer(
      packageName: 'xs-app',
      consentBuilder: (final context, final locale) async => true,
      launchSchemeAction: (final scheme) async {
        launchedScheme = scheme;
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

    expect(launchedScheme, 'snap://review/xs-app');
  });
}

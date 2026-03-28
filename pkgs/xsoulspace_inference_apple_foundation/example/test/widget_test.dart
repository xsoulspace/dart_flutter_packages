import 'package:flutter_test/flutter_test.dart';
import 'package:apple_foundation_example/main.dart';

void main() {
  testWidgets('Example app shows availability and inference actions', (
    tester,
  ) async {
    await tester.pumpWidget(const AppleFoundationExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('Check availability'), findsOneWidget);
    expect(find.text('Run inference'), findsOneWidget);
  });
}

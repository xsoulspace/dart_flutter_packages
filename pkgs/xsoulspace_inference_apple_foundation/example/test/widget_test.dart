import 'package:apple_foundation_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Example app shows availability and inference actions', (
    final tester,
  ) async {
    await tester.pumpWidget(const AppleFoundationExampleApp());
    await tester.pumpAndSettle();
    expect(find.text('Check availability'), findsOneWidget);
    expect(find.text('Run inference'), findsOneWidget);
  });
}

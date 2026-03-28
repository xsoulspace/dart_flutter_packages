import 'package:flutter_test/flutter_test.dart';
import 'package:gemma_example/main.dart';

void main() {
  testWidgets(
    'Example app shows availability, install, and inference actions',
    (tester) async {
      await tester.pumpWidget(const GemmaExampleApp());
      await tester.pumpAndSettle();
      expect(find.text('Check availability'), findsOneWidget);
      expect(find.text('Install model'), findsOneWidget);
      expect(find.text('Run inference'), findsOneWidget);
    },
  );
}

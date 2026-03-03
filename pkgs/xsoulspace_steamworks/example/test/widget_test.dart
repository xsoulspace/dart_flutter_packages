import 'package:flutter_test/flutter_test.dart';
import 'package:xsoulspace_steamworks_example/app.dart';

void main() {
  testWidgets('renders example home', (final tester) async {
    await tester.pumpWidget(const SteamworksExampleApp(useFakeBackend: true));

    expect(find.text('Steamworks Desktop Example'), findsOneWidget);
    expect(find.byKey(SteamExampleKeys.initializeButton), findsOneWidget);
  });
}

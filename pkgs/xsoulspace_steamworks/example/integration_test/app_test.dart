import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xsoulspace_steamworks_example/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('smoke flow works with fake backend', (final tester) async {
    await tester.pumpWidget(const SteamworksExampleApp(useFakeBackend: true));
    await tester.pumpAndSettle();

    expect(find.byKey(SteamExampleKeys.statusText), findsOneWidget);
    expect(find.textContaining('Status: Idle'), findsOneWidget);

    await tester.tap(find.byKey(SteamExampleKeys.initializeButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Status: Initialized'), findsOneWidget);

    await tester.tap(find.byKey(SteamExampleKeys.requestStatsButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('requestCurrentStats: true'), findsOneWidget);

    await tester.tap(find.byKey(SteamExampleKeys.setAchievementButton));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('setAchievement=true storeStats=true'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(SteamExampleKeys.clearAchievementButton));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('clearAchievement=true storeStats=true'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(SteamExampleKeys.pumpButton));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SteamExampleKeys.shutdownButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Status: Shutdown complete'), findsOneWidget);
  });
}

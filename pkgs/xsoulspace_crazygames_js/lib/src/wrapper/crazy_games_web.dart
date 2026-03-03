import 'crazygames_client.dart';
import 'converters.dart';
import '../raw/crazygames_raw.g.dart' as raw;

export 'crazygames_client.dart';
export 'models.dart';
export 'enums.dart';

/// Wrapper entrypoint for CrazyGames HTML5 SDK.
abstract final class CrazyGames {
  static Future<CrazyGamesClient> init() async {
    await jsCallPromise(raw.crazyGamesSdk, 'init');
    return CrazyGamesClient(raw.crazyGamesSdk);
  }
}

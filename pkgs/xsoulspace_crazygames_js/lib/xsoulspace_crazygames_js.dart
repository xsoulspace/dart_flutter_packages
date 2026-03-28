/// Wrapper API for CrazyGames HTML5 SDK.
library;

export 'src/wrapper/crazy_games_stub.dart'
    if (dart.library.js_interop) 'src/wrapper/crazy_games_web.dart';
export 'src/wrapper/enums.dart';
export 'src/wrapper/models.dart';

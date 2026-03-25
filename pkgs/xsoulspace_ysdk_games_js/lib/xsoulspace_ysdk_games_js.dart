/// Wrapper API for Yandex Games SDK.
library;

export 'src/wrapper/enums.dart';
export 'src/wrapper/models.dart';
export 'src/wrapper/yandex_games_stub.dart'
    if (dart.library.js_interop) 'src/wrapper/yandex_games_web.dart';

/// Wrapper API for Discord Embedded App SDK.
library;

export 'src/wrapper/models.dart';
export 'src/wrapper/discord_stub.dart'
    if (dart.library.js_interop) 'src/wrapper/discord_web.dart';

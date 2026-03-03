/// Wrapper API for VK Play iframe API.
library;

export 'src/wrapper/models.dart';
export 'src/wrapper/vkplay_stub.dart'
    if (dart.library.js_interop) 'src/wrapper/vkplay_web.dart';

import 'dart:ffi';

/// C-ABI bindings for the Apple Foundation native bridge.
///
/// Two resolution paths:
/// 1. **Code assets (preferred):** `native_bindings.dart` declares the same
///    symbols via `@Native(assetId:)`; the Dart runtime resolves them from
///    the asset registered by `hook/build.dart`. No manual loading needed.
/// 2. **Fallback:** this file resolves symbols from a [DynamicLibrary] opened
///    by `library_loader.dart` — used when code assets can't be loaded
///    (e.g. Flutter under Dart 3.13, or a dylib built outside the hook).
///
/// Callbacks are registered as `NativeCallable.listener` so Swift can invoke
/// them from arbitrary threads; the VM posts the call back to this isolate.

/// void xs_fm_tool_cb(const char* payload_json)
typedef ToolCbNative = Void Function(Pointer<Char>);
typedef ToolCbDart = void Function(Pointer<Char>);

/// void xs_fm_done_cb(const char* response_json)
typedef DoneCbNative = Void Function(Pointer<Char>);
typedef DoneCbDart = void Function(Pointer<Char>);

/// void xs_fm_stream_cb(const char* snapshot_json)
typedef StreamCbNative = Void Function(Pointer<Char>);
typedef StreamCbDart = void Function(Pointer<Char>);

/// int32_t xs_fm_is_available(void)
typedef IsAvailableNative = Int32 Function();
typedef IsAvailableDart = int Function();

/// int32_t xs_fm_generate_async(const char*, void*, void*)
typedef GenerateAsyncNative =
    Int32 Function(
      Pointer<Char>,
      Pointer<NativeFunction<ToolCbNative>>,
      Pointer<NativeFunction<DoneCbNative>>,
    );
typedef GenerateAsyncDart =
    int Function(
      Pointer<Char>,
      Pointer<NativeFunction<ToolCbNative>>,
      Pointer<NativeFunction<DoneCbNative>>,
    );

/// int32_t xs_fm_generate_stream_async(const char*, void*, void*, void*)
typedef GenerateStreamAsyncNative =
    Int32 Function(
      Pointer<Char>,
      Pointer<NativeFunction<ToolCbNative>>,
      Pointer<NativeFunction<StreamCbNative>>,
      Pointer<NativeFunction<DoneCbNative>>,
    );
typedef GenerateStreamAsyncDart =
    int Function(
      Pointer<Char>,
      Pointer<NativeFunction<ToolCbNative>>,
      Pointer<NativeFunction<StreamCbNative>>,
      Pointer<NativeFunction<DoneCbNative>>,
    );

/// int32_t xs_fm_tool_respond(const char*, const char*)
typedef ToolRespondNative = Int32 Function(Pointer<Char>, Pointer<Char>);
typedef ToolRespondDart = int Function(Pointer<Char>, Pointer<Char>);

/// void xs_fm_free_string(char*)
typedef FreeStringNative = Void Function(Pointer<Char>);
typedef FreeStringDart = void Function(Pointer<Char>);

/// void xs_fm_set_debug(int32_t)
typedef SetDebugNative = Void Function(Int32);
typedef SetDebugDart = void Function(int);

/// Interface over the bridge symbols, shared by both resolution paths:
/// the code-asset path (`@Native` in `native_bindings.dart`) and the
/// fallback loader path ([XsFmBindings.fromLibrary]).
abstract interface class XsFmBindings {
  int isAvailable();
  int generateAsync(
    Pointer<Char> requestJson,
    Pointer<NativeFunction<ToolCbNative>> toolCb,
    Pointer<NativeFunction<DoneCbNative>> doneCb,
  );
  int generateStreamAsync(
    Pointer<Char> requestJson,
    Pointer<NativeFunction<ToolCbNative>> toolCb,
    Pointer<NativeFunction<StreamCbNative>> streamCb,
    Pointer<NativeFunction<DoneCbNative>> doneCb,
  );
  int toolRespond(Pointer<Char> id, Pointer<Char> resultJson);
  void freeString(Pointer<Char> s);
  void setDebug(int enabled);
}

/// Typed view over the bridge symbols resolved from a loaded library.
final class LibraryXsFmBindings implements XsFmBindings {
  LibraryXsFmBindings.fromLibrary(DynamicLibrary library)
    : isAvailableFn = library
          .lookup<NativeFunction<IsAvailableNative>>('xs_fm_is_available')
          .asFunction(),
      generateAsyncFn = library
          .lookup<NativeFunction<GenerateAsyncNative>>('xs_fm_generate_async')
          .asFunction(),
      generateStreamAsyncFn = library
          .lookup<NativeFunction<GenerateStreamAsyncNative>>(
            'xs_fm_generate_stream_async',
          )
          .asFunction(),
      toolRespondFn = library
          .lookup<NativeFunction<ToolRespondNative>>('xs_fm_tool_respond')
          .asFunction(),
      freeStringFn = library
          .lookup<NativeFunction<FreeStringNative>>('xs_fm_free_string')
          .asFunction(),
      setDebugFn = library
          .lookup<NativeFunction<SetDebugNative>>('xs_fm_set_debug')
          .asFunction();

  final IsAvailableDart isAvailableFn;
  final GenerateAsyncDart generateAsyncFn;
  final GenerateStreamAsyncDart generateStreamAsyncFn;
  final ToolRespondDart toolRespondFn;
  final FreeStringDart freeStringFn;
  final SetDebugDart setDebugFn;

  @override
  int isAvailable() => isAvailableFn();

  @override
  int generateAsync(
    Pointer<Char> requestJson,
    Pointer<NativeFunction<ToolCbNative>> toolCb,
    Pointer<NativeFunction<DoneCbNative>> doneCb,
  ) => generateAsyncFn(requestJson, toolCb, doneCb);

  @override
  int generateStreamAsync(
    Pointer<Char> requestJson,
    Pointer<NativeFunction<ToolCbNative>> toolCb,
    Pointer<NativeFunction<StreamCbNative>> streamCb,
    Pointer<NativeFunction<DoneCbNative>> doneCb,
  ) => generateStreamAsyncFn(requestJson, toolCb, streamCb, doneCb);

  @override
  int toolRespond(Pointer<Char> id, Pointer<Char> resultJson) =>
      toolRespondFn(id, resultJson);

  @override
  void freeString(Pointer<Char> s) => freeStringFn(s);

  @override
  void setDebug(int enabled) => setDebugFn(enabled);
}

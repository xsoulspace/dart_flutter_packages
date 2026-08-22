import 'dart:ffi';

/// C-ABI bindings for the Apple Foundation native bridge.
///
/// Callbacks are registered as [NativeCallable.listener] so Swift can invoke
/// them from arbitrary threads; the VM posts the call back to this isolate.

/// void xs_fm_tool_cb(const char* payload_json)
typedef ToolCbNative = Void Function(Pointer<Char>);
typedef ToolCbDart = void Function(Pointer<Char>);

/// void xs_fm_done_cb(const char* response_json)
typedef DoneCbNative = Void Function(Pointer<Char>);
typedef DoneCbDart = void Function(Pointer<Char>);

/// int32_t xs_fm_is_available(void)
typedef _IsAvailableNative = Int32 Function();
typedef IsAvailableDart = int Function();

/// int32_t xs_fm_generate_async(const char*, void*, void*)
typedef _GenerateAsyncNative =
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

/// int32_t xs_fm_tool_respond(const char*, const char*)
typedef _ToolRespondNative = Int32 Function(Pointer<Char>, Pointer<Char>);
typedef ToolRespondDart = int Function(Pointer<Char>, Pointer<Char>);

/// void xs_fm_free_string(char*)
typedef _FreeStringNative = Void Function(Pointer<Char>);
typedef FreeStringDart = void Function(Pointer<Char>);

/// Typed view over the bridge symbols resolved from a loaded library.
final class XsFmBindings {
  XsFmBindings.fromLibrary(DynamicLibrary library)
    : isAvailable = library
          .lookup<NativeFunction<_IsAvailableNative>>('xs_fm_is_available')
          .asFunction(),
      generateAsync = library
          .lookup<NativeFunction<_GenerateAsyncNative>>('xs_fm_generate_async')
          .asFunction(),
      toolRespond = library
          .lookup<NativeFunction<_ToolRespondNative>>('xs_fm_tool_respond')
          .asFunction(),
      freeString = library
          .lookup<NativeFunction<_FreeStringNative>>('xs_fm_free_string')
          .asFunction();

  final IsAvailableDart isAvailable;
  final GenerateAsyncDart generateAsync;
  final ToolRespondDart toolRespond;
  final FreeStringDart freeString;
}

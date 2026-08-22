// C-ABI surface for the Apple Foundation native bridge (async contract).
//
// Contract rules:
// - All strings are UTF-8, NUL-terminated C strings.
// - Strings passed TO the bridge are borrowed (bridge copies if needed).
// - Strings passed FROM the bridge via callbacks are owned by the bridge and
//   remain valid only during the callback; Dart must copy before returning.
// - Callback pointers are `NativeCallable.listener` native function pointers;
//   they are invoked on arbitrary threads and post back to the Dart isolate.
//
// Generation flow:
//   1. Dart calls xs_fm_generate_async(request_json, tool_cb, done_cb).
//   2. If the model requests a tool, bridge invokes tool_cb exactly once per
//      call with {"id","name","arguments"} JSON. Dart executes the handler
//      and calls xs_fm_tool_respond(id, result_json).
//   3. Bridge invokes done_cb once with {"ok":true,"output":"..."} or
//      {"ok":false,"error":{"code","message"}}.
#ifndef XS_FM_BRIDGE_H
#define XS_FM_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 1 when SystemLanguageModel.default.isAvailable, else 0.
int32_t xs_fm_is_available(void);

/// Starts an asynchronous generation turn. Returns 0 on accept, 1 on
/// immediate failure (done_cb is still invoked with the error).
///
/// request_json shape:
/// {
///   "prompt": "...",
///   "instructions": "..." | null,
///   "schema": { ...SchemaBundle JSON... } | null,
///   "tools": [ {"name","description","parameters"} ] | null
/// }
typedef void (*xs_fm_tool_cb)(const char *payload_json);
typedef void (*xs_fm_done_cb)(const char *response_json);

int32_t xs_fm_generate_async(const char *request_json, void *tool_cb,
                             void *done_cb);

/// Delivers a tool result for a pending tool_cb payload id.
/// Returns 0 if the id was pending, 1 otherwise.
int32_t xs_fm_tool_respond(const char *id, const char *result_json);

#ifdef __cplusplus
}
#endif

#endif /* XS_FM_BRIDGE_H */

//! C ABI surface for dart:ffi — identical to the historical Swift contract
//! (ADR 0051): JSON-in/JSON-out with C strings; returned strings are owned
//! by the caller and released with `mlx_native_free`.
//!
//! Request (forward):
//! ```json
//! {"batch":[{"ids":[..],"markers":[..],"qtype":0}]}
//! ```
//! Response:
//! ```json
//! {"logits":[[...]],"act":[[...]]}
//! ```
//! Errors return `{"error":"..."}`. The forward path is serialized behind a
//! lock; the harness server serves decisions one at a time.

pub mod mlx;
pub mod model;
pub mod plan;
pub mod bindings;
pub mod lfm2;
pub mod qwen;
pub mod bpe;

#[cfg(test)]
pub fn gelu_ref(x: &mlx::Array, s: mlx::Stream) -> mlx::MlxResult<mlx::Array> {
    model::gelu_pub(x, s)
}
pub mod safetensors;

use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::fs::File;
use std::os::raw::c_int;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use mlx::{gpu, set_metallib_path, Array};
use model::{Batch, LayaModel};
use unicode_normalization::UnicodeNormalization;

/// LAYA_DEBUG_DUMP support (ADR 0051 debugging): raw stage dumps (f32 host
/// copies) land in the env dir under the plan nodes' historical stage names
/// for diffing against the reference runtime.
pub struct DebugDump {
    dir: Option<PathBuf>,
}

static FORWARD_IDX: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
thread_local! {
    static CURRENT_FW: std::cell::Cell<usize> = const { std::cell::Cell::new(0) };
}

impl DebugDump {
    pub fn from_env() -> DebugDump {
        DebugDump {
            dir: std::env::var_os("LAYA_DEBUG_DUMP")
                .filter(|value| !value.is_empty())
                .map(PathBuf::from),
        }
    }

    pub fn disabled() -> DebugDump {
        DebugDump { dir: None }
    }

    /// One forward began — advance the dump-file index.
    pub fn begin_forward() {
        CURRENT_FW.with(|c| c.set(FORWARD_IDX.fetch_add(1, Ordering::SeqCst)));
    }

    pub fn active(&self) -> bool {
        self.dir.is_some()
    }

    /// Diagnostic activations may contain actor-private evidence. Never
    /// materialize or persist them without an explicit diagnostic destination.
    pub fn stage(&self, name: &str, arr: &Array, s: mlx::Stream) {
        let Some(dir) = &self.dir else { return };
        let _ = std::fs::create_dir_all(dir);
        let name = format!("fw{:02}_{name}", CURRENT_FW.with(|c| c.get()));
        let dumped = arr.astype(mlx::Dtype::Float32, s).and_then(|a| a.to_f32_vec(s));
        let vals = match dumped {
            Ok(v) => v,
            Err(e) => {
                let _ = std::fs::write(dir.join(format!("DUMP_ERROR_{name}.txt")), format!("{e:?}"));
                return;
            }
        };
        let shape: Vec<usize> = (0..arr.ndim()).map(|d| arr.dim(d as i32)).collect();
        let _ = std::fs::write(
            dir.join(format!("{name}.json")),
            serde_json::json!({ "shape": shape, "file": format!("{name}.bin") }).to_string(),
        );
        let bytes: Vec<u8> = vals.iter().flat_map(|v| v.to_le_bytes()).collect();
        let _ = std::fs::write(dir.join(format!("{name}.bin")), bytes);
    }
}

#[derive(serde::Deserialize)]
struct ForwardRequest {
    #[serde(default)]
    batch: Vec<BatchRow>,
}

#[derive(serde::Deserialize)]
struct BatchRow {
    ids: Vec<i64>,
    markers: Vec<i64>,
    qtype: i32,
}

struct Engine {
    model: Arc<LayaModel>,
    /// The compiled forward (LAYA_COMPILE, ADR 0054 R1) is built lazily on
    /// first use and lives as long as the engine handle.
    compiled: Arc<OnceLock<model::CompiledForward>>,
}

static REGISTRY: OnceLock<Mutex<HashMap<i64, Engine>>> = OnceLock::new();
static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);
static FORWARD_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

fn registry() -> &'static Mutex<HashMap<i64, Engine>> {
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn forward_lock() -> &'static Mutex<()> {
    FORWARD_LOCK.get_or_init(|| Mutex::new(()))
}

fn fail(message: &str) -> *mut c_char {
    let payload = serde_json::json!({ "error": message }).to_string();
    match CString::new(payload) {
        Ok(c) => c.into_raw(),
        Err(_) => CString::new("{\"error\":\"encode\"}").unwrap().into_raw(),
    }
}

fn ok_json(value: &serde_json::Value) -> *mut c_char {
    match CString::new(value.to_string()) {
        Ok(c) => c.into_raw(),
        Err(_) => fail("encode"),
    }
}

/// Pins MLX's metallib before the first GPU op, mirroring the historical
/// Swift pin: beside THIS dylib, then `LAYA_METALLIB`, then the fleet cache.
/// MLX's own colocated search looks beside the binary containing the mlx
/// code — which is now this cdylib — so the first candidate is usually the
/// same file the search would find; the explicit pin keeps the fallbacks.
///
/// The fleet shares one load-dir filename (`mlx.metallib`) across engine
/// packages, and more than one hook refreshes it — so the first existing
/// candidate can be a DIFFERENT engine's kernel library (measured
/// 2026-10-10: the Swift text lane's 2.4 MB lib under this engine's dylib
/// → "Unable to load kernel arangeint32" at first generate). Each
/// candidate is therefore probed for a kernel MLX itself demands before
/// it is pinned; a miss falls through to the next candidate, and only a
/// set with no probed match degrades to the first existing file.
fn pin_metallib_colocated() {
    static PINNED: std::sync::OnceLock<()> = std::sync::OnceLock::new();
    if PINNED.get().is_some() {
        return;
    }
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Some(dir) = current_dylib_dir() {
        candidates.push(dir.join("mlx.metallib"));
    }
    if let Ok(env) = std::env::var("LAYA_METALLIB") {
        candidates.push(PathBuf::from(env));
    }
    if let Ok(home) = std::env::var("HOME") {
        candidates.push(PathBuf::from(home).join(".cache/xsoulspace/laya/native/mlx.metallib"));
    }
    let mut pin = |candidate: &PathBuf| {
        if candidate.is_file() {
            let _ = set_metallib_path(candidate);
            PINNED.set(()).ok();
            true
        } else {
            false
        }
    };
    for candidate in &candidates {
        if looks_like_mlx_metallib(candidate) && pin(candidate) {
            return;
        }
    }
    for candidate in &candidates {
        if pin(candidate) {
            return;
        }
    }
}

/// Whether the file carries MLX's kernel library: the metallib embeds its
/// kernel names, and `arangeint32` is one MLX demands on ordinary decode
/// paths. A cheap chunked byte scan (the full lib is ~140 MB; impostors
/// are megabytes and lack the name).
fn looks_like_mlx_metallib(path: &Path) -> bool {
    use std::io::Read;
    const NEEDLE: &[u8] = b"arangeint32";
    const CHUNK: usize = 4 << 20;
    let Ok(mut file) = File::open(path) else {
        return false;
    };
    let mut tail: Vec<u8> = Vec::new();
    let mut chunk = vec![0u8; CHUNK];
    loop {
        let read = match file.read(&mut chunk) {
            Ok(0) => return false,
            Ok(n) => n,
            Err(_) => return false,
        };
        let mut window = std::mem::take(&mut tail);
        window.extend_from_slice(&chunk[..read]);
        if window.windows(NEEDLE.len()).any(|w| w == NEEDLE) {
            return true;
        }
        tail = window
            [window.len().saturating_sub(NEEDLE.len() - 1)..]
            .to_vec();
    }
}

#[repr(C)]
struct DlInfo {
    dli_fname: *const c_char,
    dli_fbase: *mut core::ffi::c_void,
    dli_sname: *const c_char,
    dli_saddr: *mut core::ffi::c_void,
}

extern "C" {
    fn dladdr(symbol: *mut core::ffi::c_void, info: *mut DlInfo) -> c_int;
}

fn current_dylib_dir() -> Option<PathBuf> {
    extern "C" fn anchor() {}
    let mut info: DlInfo = unsafe { std::mem::zeroed() };
    let anchor_ptr = anchor as extern "C" fn() as *mut core::ffi::c_void;
    if unsafe { dladdr(anchor_ptr, &mut info) } == 0 || info.dli_fname.is_null() {
        return None;
    }
    let path = unsafe { CStr::from_ptr(info.dli_fname) };
    PathBuf::from(path.to_string_lossy().to_string())
        .parent()
        .map(|p| p.to_path_buf())
}

/// Loads the model from `model_dir`. Returns a positive handle, or negative
/// codes matching the historical contract: -1 null arg, -2 load failure.
#[no_mangle]
pub extern "C" fn mlx_native_load(model_dir: *const c_char) -> i64 {
    if model_dir.is_null() {
        return -1;
    }
    pin_metallib_colocated();
    let dir = PathBuf::from(unsafe { CStr::from_ptr(model_dir) }.to_string_lossy().to_string());
    let stream = match gpu() {
        Ok(s) => s,
        Err(_) => return -2,
    };
    match LayaModel::load(&dir, stream) {
        Ok(model) => {
            // R3 calibration path: LAYA_Q8=1 quantizes every linear to
            // 8-bit at load (ADR 0054 — gated by the calibration test).
            let model = if std::env::var_os("LAYA_Q8").is_some_and(|v| !v.is_empty()) {
                let qs = match gpu() {
                    Ok(s2) => s2,
                    Err(_) => return -2,
                };
                match model.into_q8(qs) {
                    Ok(m) => m,
                    Err(_) => return -2,
                }
            } else {
                model
            };
            let handle = NEXT_HANDLE.fetch_add(1, Ordering::SeqCst);
            registry().lock().unwrap().insert(
                handle,
                Engine {
                    model: Arc::new(model),
                    compiled: Arc::new(OnceLock::new()),
                },
            );
            handle
        }
        Err(_) => -2,
    }
}

#[no_mangle]
pub extern "C" fn mlx_native_forward(handle: i64, request_json: *const c_char) -> *mut c_char {
    if request_json.is_null() {
        return fail("missing request");
    }
    let engine = registry().lock().unwrap().get(&handle).map(|e| (Arc::clone(&e.model), Arc::clone(&e.compiled)));
    let Some((model, compiled_slot)) = engine else {
        return fail("unknown handle");
    };
    let raw = unsafe { CStr::from_ptr(request_json) }.to_bytes();
    let request: ForwardRequest = match serde_json::from_slice(raw) {
        Ok(r) => r,
        Err(_) => return fail("unreadable request JSON"),
    };
    let _guard = forward_lock().lock().unwrap();
    // MLX streams are registered per OS thread. Dart isolates can migrate
    // threads, so never reuse the loader thread's stream on this FFI call.
    // Weights are eager host arrays (safetensors::take); this request graph
    // is created and materialized entirely on the current thread's stream.
    let stream = match gpu() {
        Ok(stream) => stream,
        Err(e) => return fail(&format!("stream initialization failed: mlx status {}", e.0)),
    };
    let batch = match build_batch(&request) {
        Ok(b) => b,
        Err(message) => return fail(&message),
    };

    // R1 (ADR 0054): LAYA_COMPILE routes the plan through mlx.compile. A
    // compile failure is loud, never a silent eager fallback.
    let output = if std::env::var_os("LAYA_COMPILE").is_some_and(|v| !v.is_empty()) {
        let compiled = match compiled_slot.get() {
            Some(c) => c,
            None => match model::CompiledForward::new(Arc::clone(&model)) {
                Ok(c) => {
                    let _ = compiled_slot.set(c);
                    compiled_slot.get().expect("compiled forward just inserted")
                }
                Err(e) => return fail(&format!("compile init failed: mlx status {}", e.0)),
            },
        };
        compiled.forward(&batch, stream)
    } else {
        model.forward(&batch, stream)
    };
    let output = match output {
        Ok(o) => o,
        Err(e) => return fail(&format!("forward failed: mlx status {}", e.0)),
    };
    let response = serde_json::json!({
        "logits": output.logits,
        "act": output.act,
    });
    match CString::new(response.to_string()) {
        Ok(c) => c.into_raw(),
        Err(_) => fail("encode"),
    }
}

/// Rectangularizes exactly like the Swift port: ids padded with 0 (mask 1
/// for real ids), markers padded to max(2, count) with pos 0 / mask 0.
fn build_batch(request: &ForwardRequest) -> Result<Batch, String> {
    if request.batch.is_empty() {
        return Err("empty batch".into());
    }
    for row in &request.batch {
        if row.ids.is_empty() {
            return Err("batch row missing ids/markers/qtype".into());
        }
    }
    let b = request.batch.len();
    let width_ids = request.batch.iter().map(|r| r.ids.len()).max().unwrap_or(0);
    let width_k = request
        .batch
        .iter()
        .map(|r| (r.markers.len() as i32).max(2) as usize)
        .max()
        .unwrap_or(0);

    let mut ids = Vec::with_capacity(b * width_ids);
    let mut mask = Vec::with_capacity(b * width_ids);
    let mut pos = Vec::with_capacity(b * width_k);
    let mut mmask = Vec::with_capacity(b * width_k);
    let mut qtypes = Vec::with_capacity(b);
    for row in &request.batch {
        ids.extend(row.ids.iter().map(|v| *v as i32));
        mask.extend(std::iter::repeat(1i32).take(row.ids.len()));
        mask.extend(std::iter::repeat(0i32).take(width_ids - row.ids.len()));
        let count = (row.markers.len() as i32).max(2) as usize;
        let mut p = vec![0i32; width_k];
        let mut m = vec![0u8; width_k];
        for (i, marker) in row.markers.iter().enumerate().take(count) {
            p[i] = *marker as i32;
            m[i] = 1;
        }
        pos.extend(p);
        mmask.extend(m);
        qtypes.push(row.qtype);
    }
    Ok(Batch {
        input_ids: Array::from_data_i32(&ids, &[b, width_ids]).map_err(|e| e.to_string())?,
        attention_mask: Array::from_data_i32(&mask, &[b, width_ids]).map_err(|e| e.to_string())?,
        marker_pos: Array::from_data_i32(&pos, &[b, width_k]).map_err(|e| e.to_string())?,
        marker_mask: Array::from_data_bool(&mmask, &[b, width_k]).map_err(|e| e.to_string())?,
        qtype: Array::from_data_i32(&qtypes, &[b]).map_err(|e| e.to_string())?,
    })
}

#[no_mangle]
pub extern "C" fn mlx_native_free(pointer: *mut c_char) {
    if !pointer.is_null() {
        unsafe { drop(CString::from_raw(pointer)) };
    }
}

#[no_mangle]
pub extern "C" fn mlx_native_unload(handle: i64) {
    registry().lock().unwrap().remove(&handle);
}

// ---- qwen text engine (ADR 0054 R2) — same handle/JSON conventions ----

struct QwenEngine {
    model: Arc<crate::qwen::Qwen3>,
    tokenizer: crate::bpe::ByteLevelBpe,
}

static QWEN_REGISTRY: OnceLock<Mutex<HashMap<i64, Arc<QwenEngine>>>> = OnceLock::new();
static QWEN_NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);

fn qwen_registry() -> &'static Mutex<HashMap<i64, Arc<QwenEngine>>> {
    QWEN_REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

#[derive(serde::Deserialize)]
struct QwenGenerateRequest {
    /// Raw text (tokenized by the checkpoint BPE) or explicit prompt ids.
    #[serde(default)]
    prompt: Option<String>,
    #[serde(default)]
    prompt_ids: Option<Vec<i32>>,
    #[serde(default = "default_max_tokens")]
    max_tokens: usize,
    /// Opt-in EOS stop (ADR 0055): when true, generation breaks right after
    /// emitting any token in `eos_ids` (the eos token itself is kept — HF
    /// convention). Default OFF: the parity fixtures pin full greedy streams
    /// that run THROUGH `<|endoftext|>`, and must stay byte-identical.
    #[serde(default)]
    stop_on_eos: bool,
    #[serde(default)]
    eos_ids: Vec<i32>,
}

fn default_max_tokens() -> usize {
    64
}

#[no_mangle]
pub extern "C" fn mlx_native_qwen_load(model_dir: *const c_char) -> i64 {
    if model_dir.is_null() {
        return -1;
    }
    pin_metallib_colocated();
    let dir = PathBuf::from(unsafe { CStr::from_ptr(model_dir) }.to_string_lossy().to_string());
    let model = match crate::qwen::Qwen3::load(&dir) {
        Ok(m) => m,
        Err(_) => return -2,
    };
    let tokenizer = match crate::bpe::ByteLevelBpe::load(&dir) {
        Ok(t) => t,
        Err(_) => return -2,
    };
    let handle = QWEN_NEXT_HANDLE.fetch_add(1, Ordering::SeqCst);
    qwen_registry().lock().unwrap().insert(
        handle,
        Arc::new(QwenEngine { model: Arc::new(model), tokenizer }),
    );
    handle
}

/// Greedy text generation. Request: `{"prompt": "…", "max_tokens": 64}` (or
/// `prompt_ids`), optional `stop_on_eos` + `eos_ids` (default OFF — see
/// `QwenGenerateRequest`). Response:
/// `{"ids": [...], "text": "…", "prompt_ids": [...]}` or `{"error": "…"}`.
#[no_mangle]
pub extern "C" fn mlx_native_qwen_generate(handle: i64, request_json: *const c_char) -> *mut c_char {
    if request_json.is_null() {
        return fail("missing request");
    }
    let engine = qwen_registry().lock().unwrap().get(&handle).map(Arc::clone);
    let Some(engine) = engine else {
        return fail("unknown handle");
    };
    let request: QwenGenerateRequest = match serde_json::from_slice(unsafe {
        CStr::from_ptr(request_json)
    }
    .to_bytes())
    {
        Ok(r) => r,
        Err(_) => return fail("unreadable request JSON"),
    };
    let _guard = forward_lock().lock().unwrap();
    let stream = match gpu() {
        Ok(stream) => stream,
        Err(e) => return fail(&format!("stream initialization failed: mlx status {}", e.0)),
    };
    let prompt_ids = if let Some(ids) = request.prompt_ids {
        ids
    } else {
        match &request.prompt {
            Some(text) => match engine.tokenizer.encode(text) {
                Ok(ids) => ids.into_iter().map(|i| i as i32).collect(),
                Err(e) => return fail(&format!("tokenize failed: {e}")),
            },
            None => return fail("request needs prompt or prompt_ids"),
        }
    };
    let stop: Option<&[i32]> = if request.stop_on_eos {
        Some(&request.eos_ids)
    } else {
        None
    };
    match engine
        .model
        .generate_greedy(&prompt_ids, request.max_tokens, stop, stream)
    {
        Ok(ids) => {
            let text = engine
                .tokenizer
                .decode(&ids[prompt_ids.len()..].iter().map(|&i| i as u32).collect::<Vec<_>>())
                .unwrap_or_default();
            let payload = serde_json::json!({
                "prompt_ids": prompt_ids,
                "ids": ids,
                "text": text,
            })
            .to_string();
            match CString::new(payload) {
                Ok(c) => c.into_raw(),
                Err(_) => fail("encode"),
            }
        }
        Err(e) => fail(&format!("generate failed: mlx status {}", e.0)),
    }
}

#[no_mangle]
pub extern "C" fn mlx_native_qwen_unload(handle: i64) {
    qwen_registry().lock().unwrap().remove(&handle);
}

// ---- lfm2 text engine (ADR 0055 LFM2 rung) — same handle/JSON conventions ----

struct Lfm2Engine {
    model: Arc<crate::lfm2::Lfm2>,
    tokenizer: crate::bpe::ByteLevelBpe,
    /// LFM2.5 prepends <|startoftext|> to raw text (the parity fixture's
    /// pinned prompt_ids start with it); qwen has no BOS. The id is the
    /// checkpoint's `bos_token_id` (1 low-id-special, 124894 on the 2.6B
    /// 128k vocab) — read from config, never guessed.
    bos: u32,
}

static LFM2_REGISTRY: OnceLock<Mutex<HashMap<i64, Arc<Lfm2Engine>>>> = OnceLock::new();
static LFM2_NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);

fn lfm2_registry() -> &'static Mutex<HashMap<i64, Arc<Lfm2Engine>>> {
    LFM2_REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

static LFM2_LOAD_ERROR: Mutex<Option<String>> = Mutex::new(None);

fn lfm2_load_error_set<E: std::fmt::Debug>(error: &E) {
    *LFM2_LOAD_ERROR.lock().unwrap() = Some(format!("{error:?}"));
}

/// The last `mlx_native_lfm2_load` failure's error payload (a Debug print
/// of the MlxError) — surfaced so a rejected checkpoint is diagnosable
/// from Dart instead of a bare `-2`.
#[no_mangle]
pub extern "C" fn mlx_native_lfm2_last_load_error() -> *mut c_char {
    let held = LFM2_LOAD_ERROR.lock().unwrap().clone();
    match held {
        Some(text) => ok_json(&serde_json::json!({ "error": text })),
        None => ok_json(&serde_json::json!({ "error": null })),
    }
}

#[no_mangle]
pub extern "C" fn mlx_native_lfm2_load(model_dir: *const c_char) -> i64 {
    if model_dir.is_null() {
        return -1;
    }
    pin_metallib_colocated();
    let dir = PathBuf::from(unsafe { CStr::from_ptr(model_dir) }.to_string_lossy().to_string());
    let model = match crate::lfm2::Lfm2::load(&dir) {
        Ok(m) => m,
        Err(e) => {
            lfm2_load_error_set(&e);
            return -2;
        }
    };
    let tokenizer = match crate::bpe::ByteLevelBpe::load_tokenizer_json(&dir) {
        Ok(t) => t,
        Err(_) => return -3,
    };
    let handle = LFM2_NEXT_HANDLE.fetch_add(1, Ordering::SeqCst);
    let bos = model.cfg.bos_token_id as u32;
    lfm2_registry().lock().unwrap().insert(
        handle,
        Arc::new(Lfm2Engine {
            model: Arc::new(model),
            tokenizer,
            bos,
        }),
    );
    handle
}

/// The checkpoint's special-token ids, resolved from its own tokenizer
/// (never guessed): `{"bos": N, "im_end": N, "endoftext": N}` — the chat
/// EOS stop passes `im_end`/`endoftext` (id 7/2 on the low-id-special
/// checkpoints, 124900/… on the 2.6B's 128k vocab). `{"error": …}` when a
/// token is absent — callers must not fall back to another checkpoint's
/// ids.
#[no_mangle]
pub extern "C" fn mlx_native_lfm2_special_ids(handle: i64) -> *mut c_char {
    let registry = lfm2_registry();
    let guard = registry.lock().unwrap();
    let engine = match guard.get(&handle) {
        Some(e) => e,
        None => return fail("unknown lfm2 handle"),
    };
    let im_end = match engine.tokenizer.added_id("<|im_end|>") {
        Some(id) => id,
        None => return fail("checkpoint tokenizer has no <|im_end|>"),
    };
    let endoftext = match engine.tokenizer.added_id("<|endoftext|>") {
        Some(id) => id,
        None => return fail("checkpoint tokenizer has no <|endoftext|>"),
    };
    let (bos, im_end, endoftext) = (engine.bos, im_end, endoftext);
    drop(guard);
    ok_json(&serde_json::json!({
        "bos": bos,
        "im_end": im_end,
        "endoftext": endoftext,
    }))
}

/// Greedy text generation. Request: `{"prompt": "…", "max_tokens": 64}` (or
/// `prompt_ids`, used verbatim — no BOS added; optional `stop_on_eos` +
/// `eos_ids`, default OFF — see `QwenGenerateRequest`). Response:
/// `{"ids": [...], "text": "…", "prompt_ids": [...]}` or `{"error": "…"}`.
#[no_mangle]
pub extern "C" fn mlx_native_lfm2_generate(handle: i64, request_json: *const c_char) -> *mut c_char {
    if request_json.is_null() {
        return fail("missing request");
    }
    let engine = lfm2_registry().lock().unwrap().get(&handle).map(Arc::clone);
    let Some(engine) = engine else {
        return fail("unknown handle");
    };
    let request: QwenGenerateRequest = match serde_json::from_slice(unsafe {
        CStr::from_ptr(request_json)
    }
    .to_bytes())
    {
        Ok(r) => r,
        Err(_) => return fail("unreadable request JSON"),
    };
    let _guard = forward_lock().lock().unwrap();
    let stream = match gpu() {
        Ok(stream) => stream,
        Err(e) => return fail(&format!("stream initialization failed: mlx status {}", e.0)),
    };
    let had_explicit_ids = request.prompt_ids.is_some();
    let mut prompt_ids = if let Some(ids) = request.prompt_ids {
        ids
    } else {
        match &request.prompt {
            Some(text) => match engine.tokenizer.encode(text) {
                Ok(ids) => ids.into_iter().map(|i| i as i32).collect(),
                Err(e) => return fail(&format!("tokenize failed: {e}")),
            },
            None => return fail("request needs prompt or prompt_ids"),
        }
    };
    if !had_explicit_ids {
        prompt_ids.insert(0, engine.bos as i32);
    }
    let stop: Option<&[i32]> = if request.stop_on_eos {
        Some(&request.eos_ids)
    } else {
        None
    };
    match engine
        .model
        .generate_greedy(&prompt_ids, request.max_tokens, stop, stream)
    {
        Ok(ids) => {
            let text = engine
                .tokenizer
                .decode(&ids[prompt_ids.len()..].iter().map(|&i| i as u32).collect::<Vec<_>>())
                .unwrap_or_default();
            let payload = serde_json::json!({
                "prompt_ids": prompt_ids,
                "ids": ids,
                "text": text,
            })
            .to_string();
            match CString::new(payload) {
                Ok(c) => c.into_raw(),
                Err(_) => fail("encode"),
            }
        }
        Err(e) => fail(&format!("generate failed: mlx status {}", e.0)),
    }
}

#[no_mangle]
pub extern "C" fn mlx_native_lfm2_unload(handle: i64) {
    lfm2_registry().lock().unwrap().remove(&handle);
}

/// NFC (canonical composed) normalization — the checkpoint tokenizer's
/// normalizer. Output requires up to 4 bytes per input UTF-8 byte.
/// Returns the number of bytes written, or -1 when out is too small.
#[no_mangle]
pub extern "C" fn mlx_native_normalize(
    src: *const c_char,
    out: *mut c_char,
    out_cap: c_int,
) -> c_int {
    if src.is_null() || out.is_null() {
        return -1;
    }
    let text = unsafe { CStr::from_ptr(src) }.to_string_lossy();
    let normalized: String = text.nfc().collect();
    let bytes = normalized.as_bytes();
    if bytes.len() + 1 > out_cap as usize {
        return -1;
    }
    unsafe {
        std::ptr::copy_nonoverlapping(bytes.as_ptr() as *const c_char, out, bytes.len());
        *out.add(bytes.len()) = 0;
    }
    bytes.len() as c_int
}

#[cfg(test)]
mod tests {
    use super::mlx::*;
    use std::ffi::{CStr, CString};
    use std::path::PathBuf;

    /// L0 spike (ADR 0051): the mlx-c path runs real GPU ops from Rust and
    /// per-op dispatch overhead is noise against the decision budget.
    #[test]
    fn l0_ops_run_and_are_dispatch_cheap() {
        // Test binaries don't sit beside a metallib; pin the cmake-built one.
        let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("build/mlx-install/lib/mlx.metallib");
        if metallib.is_file() {
            set_metallib_path(&metallib).unwrap();
        }
        let s = gpu().expect("metal available");
        let rows = 256usize;
        let k = 1024usize;
        let fp16_pattern = |len: usize, modulus: u16| -> Vec<u8> {
            let mut v = vec![0u8; len];
            for (i, chunk) in v.chunks_exact_mut(2).enumerate() {
                let bits = (0x3800u16.wrapping_add((i % modulus as usize) as u16)).to_le_bytes();
                chunk[0] = bits[0];
                chunk[1] = bits[1];
            }
            v
        };
        let a = Array::from_data_f16(&fp16_pattern(rows * k * 2, 512), &[rows, k]).unwrap();
        let b = Array::from_data_f16(&fp16_pattern(k * k * 2, 251), &[k, k]).unwrap();

        // Big matmul: GPU-compute-bound throughput (informational).
        for _ in 0..5 {
            a.matmul(&b, s).unwrap().eval().unwrap();
        }
        let iters = 100;
        let start = std::time::Instant::now();
        for _ in 0..iters {
            a.matmul(&b, s).unwrap().eval().unwrap();
        }
        let per_big_us = start.elapsed().as_micros() as f64 / iters as f64;
        let tflops = (2.0 * rows as f64 * k as f64 * k as f64) / (per_big_us * 1e-6) / 1e12;

        // Small matmul [16,64]x[64,64] with eval per op: the true per-op
        // dispatch+commit overhead a decision path pays per kernel.
        let sa = Array::from_data_f16(&fp16_pattern(16 * 64 * 2, 97), &[16, 64]).unwrap();
        let sb = Array::from_data_f16(&fp16_pattern(64 * 64 * 2, 61), &[64, 64]).unwrap();
        for _ in 0..5 {
            sa.matmul(&sb, s).unwrap().eval().unwrap();
        }
        let start = std::time::Instant::now();
        for _ in 0..iters {
            sa.matmul(&sb, s).unwrap().eval().unwrap();
        }
        let per_small_us = start.elapsed().as_micros() as f64 / iters as f64;
        // This is the sync round-trip (commit + wait + signal) per op — the
        // worst case. The forward path syncs once at the end, so the gate
        // that matters is the amortized submission cost below.
        assert!(per_small_us < 400.0, "small-matmul eval+sync {per_small_us}us");

        // Amortized submission: 100 ops enqueued without per-op eval, one
        // sync — measures pure graph/dispatch cost.
        let start = std::time::Instant::now();
        for _ in 0..iters {
            sa.matmul(&sb, s).unwrap();
        }
        let last = sa.matmul(&sb, s).unwrap();
        last.eval().unwrap();
        let per_submitted_us =
            start.elapsed().as_micros() as f64 / (iters as f64 + 1.0);
        assert!(per_submitted_us < 50.0, "submitted-op cost {per_submitted_us}us");

        // Attention path: rope + sdp on [1,H,L,D].
        let heads = 8usize;
        let seq = 128usize;
        let dim = 64usize;
        let q = Array::from_data_f16(&fp16_pattern(heads * seq * dim * 2, 97), &[1, heads, seq, dim])
            .unwrap();
        let mask = Array::full(1.0, &[1, 1, seq, seq], Dtype::Bool, s).unwrap();
        let start = std::time::Instant::now();
        for _ in 0..50 {
            let qr = q.rope(dim as i32, 160000.0, 0, s).unwrap();
            Array::sdp_attention(&qr, &qr, &qr, 0.125, &mask, s)
                .unwrap()
                .eval()
                .unwrap();
        }
        let per_attn_us = start.elapsed().as_micros() as f64 / 50.0;
        // Worst-case sync probe on a real flash-attention kernel; the
        // forward syncs once for all 28 layers, so the golden p50 is the
        // binding gate — this only guards against pathological regressions.
        assert!(per_attn_us < 4000.0, "rope+sdp eval+sync {per_attn_us}us");

        // Observed numbers go into ADR 0051's evidence table.
        println!(
            "L0 spike: big matmul {per_big_us:.1}us ({tflops:.2} TFLOPS), \
             small matmul+eval {per_small_us:.1}us, submitted {per_submitted_us:.1}us, \
             rope+sdp {per_attn_us:.1}us per op"
        );
    }

    #[test]
    fn nfc_normalization_composes() {
        let src = CString::new("e\u{301}").unwrap(); // 'e' + combining acute
        let mut buf = [0i8; 16];
        let n = super::mlx_native_normalize(src.as_ptr(), buf.as_mut_ptr(), 16);
        assert!(n > 0);
        let out = unsafe { CStr::from_ptr(buf.as_ptr()) };
        assert_eq!(out.to_str().unwrap(), "\u{00e9}");
    }
}

#[cfg(test)]
mod perf_tests {
    use super::model::{Batch, LayaModel};
    use super::mlx::{gpu, Array};
    use std::path::PathBuf;

    /// Engine forward cost in-process (no dart): gates the ADR 0051 p50.
    /// Depends on a prior LAYA_DEBUG_DUMP run having populated /tmp/laya-dump
    /// (the fw13 batch inputs); skips honestly when that artifact is absent.
    #[test]
    fn engine_forward_latency() {
        if !PathBuf::from("/tmp/laya-dump/fw13_in_ids.json").is_file() {
            eprintln!(
                "skipping: /tmp/laya-dump/fw13_*.json absent — run a \
                 LAYA_DEBUG_DUMP=/tmp/laya-dump golden pass first"
            );
            return;
        }
        let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("build/mlx-install/lib/mlx.metallib");
        if metallib.is_file() {
            super::set_metallib_path_pub(&metallib);
        }
        let s = gpu().unwrap();
        let model_dir = std::env::var("HOME").unwrap()
            + "/.cache/xsoulspace/laya-mlx";
        let t0 = std::time::Instant::now();
        let model = LayaModel::load(std::path::Path::new(&model_dir), s).unwrap();
        eprintln!("load: {:?}", t0.elapsed());

        // fw13 batch: B=20, L=93
        let dir = PathBuf::from("/tmp/laya-dump");
        let read = |name: &str| -> Vec<f32> {
            let meta: serde_json::Value = serde_json::from_str(
                &std::fs::read_to_string(dir.join(format!("fw13_{name}.json"))).unwrap(),
            )
            .unwrap();
            let bytes = std::fs::read(dir.join(meta["file"].as_str().unwrap())).unwrap();
            bytes
                .chunks_exact(4)
                .map(|c| f32::from_le_bytes(c.try_into().unwrap()))
                .collect()
        };
        let ids = read("in_ids");
        let mask = read("in_mask");
        let pos = read("in_marker_pos");
        let mmask = read("in_marker_mask");
        let qt = read("in_qtype");
        let (b, l) = (20usize, 93usize);
        let k = 4usize;
        let to_i32 = |v: &[f32]| v.iter().map(|f| *f as i32).collect::<Vec<i32>>();
        let to_b = |v: &[f32]| v.iter().map(|f| *f as u8).collect::<Vec<u8>>();
        let batch = Batch {
            input_ids: Array::from_data_i32(&to_i32(&ids), &[b, l]).unwrap(),
            attention_mask: Array::from_data_i32(&to_i32(&mask), &[b, l]).unwrap(),
            marker_pos: Array::from_data_i32(&to_i32(&pos), &[b, k]).unwrap(),
            marker_mask: Array::from_data_bool(&to_b(&mmask), &[b, k]).unwrap(),
            qtype: Array::from_data_i32(&to_i32(&qt), &[b]).unwrap(),
        };
        // warmup
        let out = model.forward(&batch, s).unwrap();
        eprintln!("first forward: {:?}", t0.elapsed());
        let t1 = std::time::Instant::now();
        for _ in 0..10 {
            model.forward(&batch, s).unwrap();
        }
        eprintln!(
            "steady forward: {:?}/iter",
            t1.elapsed() / 10
        );
        assert_eq!(out.logits.len(), b);
    }

    /// R0 (ADR 0054): laya decision p50/p99 sweep B=1..20 over the fw13
    /// shape (L=93, K=4), in-process eager. Inputs come from the fw13 dump
    /// when present, else a synthetic vocab-bounded batch (say so when
    /// reading the numbers). Run: cargo test --release -- --ignored --nocapture
    #[test]
    #[ignore]
    fn r0_forward_sweep_b1_b20() {
        let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("build/mlx-install/lib/mlx.metallib");
        if metallib.is_file() {
            super::set_metallib_path_pub(&metallib);
        }
        let s = crate::mlx::gpu().unwrap();
        let model_dir = std::env::var("HOME").unwrap() + "/.cache/xsoulspace/laya-mlx";
        let model = crate::model::LayaModel::load(std::path::Path::new(&model_dir), s).unwrap();

        let (l, k, vocab) = (93usize, 4usize, 30522usize);
        let synthetic = |b: usize| -> crate::model::Batch {
            // Deterministic pseudo-batch in the fw13 shape: real ids when the
            // dump exists (row 0 of it), else arange ids mod vocab.
            let dump = PathBuf::from("/tmp/laya-dump/fw13_in_ids.json");
            let mut ids: Vec<i32> = (0..b * l).map(|i| (i * 7 + 13) as i32 % vocab as i32).collect();
            if dump.is_file() {
                let meta: serde_json::Value =
                    serde_json::from_str(&std::fs::read_to_string(&dump).unwrap()).unwrap();
                let bytes = std::fs::read(PathBuf::from("/tmp/laya-dump").join(meta["file"].as_str().unwrap())).unwrap();
                let real: Vec<f32> = bytes
                    .chunks_exact(4)
                    .map(|c| f32::from_le_bytes(c.try_into().unwrap()))
                    .collect();
                for r in 0..b {
                    for i in 0..l {
                        ids[r * l + i] = real[i] as i32;
                    }
                }
            }
            let mask = vec![1i32; b * l];
            let pos: Vec<i32> = (0..b * k).map(|i| ((i * 11 + 17) % (l - 5)) as i32).collect();
            let mmask: Vec<u8> = (0..b * k).map(|i| (i % k != k - 1) as u8).collect();
            let qt: Vec<i32> = (0..b).map(|i| (i % 3) as i32).collect();
            crate::model::Batch {
                input_ids: Array::from_data_i32(&ids, &[b, l]).unwrap(),
                attention_mask: Array::from_data_i32(&mask, &[b, l]).unwrap(),
                marker_pos: Array::from_data_i32(&pos, &[b, k]).unwrap(),
                marker_mask: Array::from_data_bool(&mmask, &[b, k]).unwrap(),
                qtype: Array::from_data_i32(&qt, &[b]).unwrap(),
            }
        };

        eprintln!("R0 sweep (fw13 shape L={l} K={k}):");
        for b in [1usize, 2, 3, 5, 8, 12, 16, 20] {
            let batch = synthetic(b);
            // Plan stats: nodes submitted per forward (the dispatch pressure).
            let (plan, _) = model.build_plan([
                &batch.input_ids,
                &batch.attention_mask,
                &batch.marker_pos,
                &batch.marker_mask,
                &batch.qtype,
            ]);
            let nodes = plan.nodes.len();
            // warmup
            for _ in 0..3 {
                model.forward(&batch, s).unwrap();
            }
            let iters = 10;
            let mut samples = Vec::with_capacity(iters);
            for _ in 0..iters {
                let t = std::time::Instant::now();
                model.forward(&batch, s).unwrap();
                samples.push(t.elapsed().as_micros() as f64);
            }
            samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
            let p50 = samples[(iters - 1) / 2] / 1000.0;
            let p99 = samples[iters - 1] / 1000.0;
            eprintln!("  B={b:2}: p50={p50:8.2}ms p99={p99:8.2}ms plan_nodes={nodes}");
        }
    }

    /// R0 (ADR 0054 §5): per-op profile DERIVED from the plan — every node
    /// auto-derives a µbench from its plan slot. Prints the per-group table
    /// sorted by total time. Run: cargo test --release -- --ignored --nocapture
    #[test]
    #[ignore]
    fn r0_plan_derived_microbench() {
        let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("build/mlx-install/lib/mlx.metallib");
        if metallib.is_file() {
            super::set_metallib_path_pub(&metallib);
        }
        let s = crate::mlx::gpu().unwrap();
        let model_dir = std::env::var("HOME").unwrap() + "/.cache/xsoulspace/laya-mlx";
        let model = crate::model::LayaModel::load(std::path::Path::new(&model_dir), s).unwrap();
        let (b, l, k) = (20usize, 93usize, 4usize);
        let batch = crate::model::Batch {
            input_ids: Array::from_data_i32(&vec![13i32; b * l], &[b, l]).unwrap(),
            attention_mask: Array::from_data_i32(&vec![1i32; b * l], &[b, l]).unwrap(),
            marker_pos: Array::from_data_i32(&vec![7i32; b * k], &[b, k]).unwrap(),
            marker_mask: Array::from_data_bool(&vec![1u8; b * k], &[b, k]).unwrap(),
            qtype: Array::from_data_i32(&vec![0i32; b], &[b]).unwrap(),
        };
        let (plan, pool) = model.build_plan([
            &batch.input_ids,
            &batch.attention_mask,
            &batch.marker_pos,
            &batch.marker_mask,
            &batch.qtype,
        ]);
        let table = crate::bindings::BindingTable::baseline();
        let contracts = crate::plan::record_contracts(&plan, &pool, &table, s).unwrap();
        eprintln!(
            "R0 plan µbench: {} executable nodes, ctx {} arrays; per-op (µs, eval-per-run):",
            contracts.len(),
            plan.ctx.len()
        );
        let mut rows: Vec<(std::time::Duration, String, String, &'static str)> = Vec::new();
        for c in &contracts {
            let d = crate::plan::bench_node(c, 20, &table, s).unwrap();
            rows.push((d, c.group.clone(), c.name.clone(), c.op.kind()));
        }
        rows.sort_by(|a, b| b.0.cmp(&a.0));
        let total: std::time::Duration = rows.iter().map(|r| r.0).sum();
        for (d, group, name, kind) in rows.iter().take(30) {
            eprintln!("  {:>8.1}us {:>10} {:28} {}", d.as_nanos() as f64 / 1000.0, group, name, kind);
        }
        eprintln!("  sum-of-op-times (upper bound incl. per-op sync): {total:?}");
    }

    /// R1 (ADR 0054): eager vs compiled A/B, interleaved in one process so
    /// slow thermal/power drift hits both modes equally. STATE THE POWER
    /// STATE when recording numbers (battery throttles 4–10x, ADR 0051).
    /// Run: cargo test --release r1_compile_ab -- --ignored --nocapture
    fn qwen_snapshot_dir() -> Option<std::path::PathBuf> {
        let home = std::env::var("HOME").ok()?;
        let hub = std::path::PathBuf::from(home).join(".cache/huggingface/hub");
        for e in std::fs::read_dir(&hub).ok()?.flatten() {
            if e.file_name().to_string_lossy().contains("Qwen3-0.6B-4bit") {
                for s in std::fs::read_dir(e.path().join("snapshots")).ok()?.flatten() {
                    if s.path().join("config.json").is_file() {
                        return Some(s.path());
                    }
                }
            }
        }
        None
    }

    /// R2 decode/perf shape (ADR 0054): chunked-prefill TTFT and greedy
    /// decode rate for the fixture prompt and a ~2k-token prompt. BATTERY
    /// RUNS ARE NON-CLAIMS (ADR 0051: battery throttles 4-10x) — the ADR
    /// only records AC-power numbers as evidence.
    #[test]
    #[ignore]
    fn r2_qwen_greedy_bench() {
        let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("build/mlx-install/lib/mlx.metallib");
        if metallib.is_file() {
            super::set_metallib_path_pub(&metallib);
        }
        let Some(snap) = super::qwen_snapshot_dir_pub() else {
            eprintln!("skipping: Qwen3-0.6B-4bit snapshot absent");
            return;
        };
        let s = crate::mlx::gpu().unwrap();
        let tok = crate::bpe::ByteLevelBpe::load(&snap).unwrap();
        let model = crate::qwen::Qwen3::load(&snap).unwrap();

        let fx: serde_json::Value = serde_json::from_str(
            &std::fs::read_to_string(
                PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("testdata/qwen3_06b_parity.json"),
            )
            .unwrap(),
        )
        .unwrap();
        let prompt: String = fx["prompt"].as_str().unwrap().to_string();
        let prompt_ids: Vec<i32> = tok
            .encode(&prompt)
            .unwrap()
            .into_iter()
            .map(|i| i as i32)
            .collect();

        // ~2k-token prompt: fixture prompt repeated (BPE-stable repetition).
        let mut long_ids = prompt_ids.clone();
        while long_ids.len() < 2048 {
            long_ids.extend_from_slice(&prompt_ids);
        }
        long_ids.truncate(2048);

        for (tag, ids) in [("short", prompt_ids), ("2k", long_ids)] {
            let mut cache = crate::qwen::KvCache::new(model.cfg.layers);
            // Warmup.
            let _ = model.generate_greedy(&ids, 4, None, s).unwrap();

            // Prefill TTFT: chunked prefill + first decode step, 5 rounds.
            let mut ttfts = Vec::new();
            for _ in 0..5 {
                let t0 = std::time::Instant::now();
                let _ = model.generate_greedy(&ids, 1, None, s).unwrap();
                ttfts.push(t0.elapsed().as_secs_f64() * 1e3);
            }
            ttfts.sort_by(|a, b| a.total_cmp(b));

            // Decode: 32 tokens, per-step wall clock.
            let t0 = std::time::Instant::now();
            model.generate_greedy(&ids, 32, None, s).unwrap();
            let decode_ms = t0.elapsed().as_secs_f64() * 1e3;
            let per_tok = decode_ms / 32.0;
            println!(
                "r2 {tag}: prompt={} ttft_p50={:.1}ms decode={:.2}ms/tok ({:.1} tok/s) [power state not verified — see ADR 0051]",
                ids.len(),
                ttfts[2],
                per_tok,
                1000.0 / per_tok,
            );
        }
    }

    #[test]
    #[ignore]
    fn r1_compile_ab_probe() {
        let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("build/mlx-install/lib/mlx.metallib");
        if metallib.is_file() {
            super::set_metallib_path_pub(&metallib);
        }
        let s = crate::mlx::gpu().unwrap();
        let model_dir = std::env::var("HOME").unwrap() + "/.cache/xsoulspace/laya-mlx";
        let model = std::sync::Arc::new(
            crate::model::LayaModel::load(std::path::Path::new(&model_dir), s).unwrap(),
        );
        let compiled = crate::model::CompiledForward::new(std::sync::Arc::clone(&model)).unwrap();

        let (b, l, k) = (1usize, 93usize, 4usize);
        let batch = crate::model::Batch {
            input_ids: Array::from_data_i32(&vec![13i32; b * l], &[b, l]).unwrap(),
            attention_mask: Array::from_data_i32(&vec![1i32; b * l], &[b, l]).unwrap(),
            marker_pos: Array::from_data_i32(&vec![7i32; b * k], &[b, k]).unwrap(),
            marker_mask: Array::from_data_bool(&vec![1u8; b * k], &[b, k]).unwrap(),
            qtype: Array::from_data_i32(&vec![0i32; b], &[b]).unwrap(),
        };
        // Warmup both paths (compile traces + specializes per shape here).
        model.forward(&batch, s).unwrap();
        compiled.forward(&batch, s).unwrap();
        compiled.forward(&batch, s).unwrap();

        let mut eager = Vec::new();
        let mut fused = Vec::new();
        for _ in 0..7 {
            for _ in 0..3 {
                let t = std::time::Instant::now();
                model.forward(&batch, s).unwrap();
                eager.push(t.elapsed().as_micros() as f64);
            }
            for _ in 0..3 {
                let t = std::time::Instant::now();
                compiled.forward(&batch, s).unwrap();
                fused.push(t.elapsed().as_micros() as f64);
            }
        }
        let med = |v: &mut Vec<f64>| -> f64 {
            v.sort_by(|a, b| a.partial_cmp(b).unwrap());
            v[v.len() / 2] / 1000.0
        };
        let (eager_p50, fused_p50) = (med(&mut eager), med(&mut fused));
        eprintln!(
            "R1 A/B (B={b} L={l}, interleaved, 21 samples each): eager p50={eager_p50:.2}ms compiled p50={fused_p50:.2}ms ratio={:.2}x — STATE POWER STATE",
            eager_p50 / fused_p50
        );
    }
}

#[cfg(test)]
pub fn qwen_snapshot_dir_pub() -> Option<std::path::PathBuf> {
    let home = std::env::var("HOME").ok()?;
    let hub = std::path::PathBuf::from(home).join(".cache/huggingface/hub");
    for e in std::fs::read_dir(&hub).ok()?.flatten() {
        if e.file_name().to_string_lossy().contains("Qwen3-0.6B-4bit") {
            for s in std::fs::read_dir(e.path().join("snapshots")).ok()?.flatten() {
                if s.path().join("config.json").is_file() {
                    return Some(s.path());
                }
            }
        }
    }
    None
}

pub fn set_metallib_path_pub(p: &std::path::Path) {
    let _ = mlx::set_metallib_path(p);
}

#[cfg(test)]
mod op_profiles {
    use super::mlx::*;
    use std::path::PathBuf;

    fn timed(name: &str, iters: usize, f: impl Fn() -> Array, _s: Stream) {
        let _ = f().eval();
        let t = std::time::Instant::now();
        for _ in 0..iters {
            let out = f();
            out.eval().unwrap();
        }
        eprintln!("{name}: {:?}", t.elapsed() / iters as u32);
    }

    #[test]
    fn profile_engine_shapes() {
        let metallib = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("build/mlx-install/lib/mlx.metallib");
        if metallib.is_file() {
            super::set_metallib_path_pub(&metallib);
        }
        let s = gpu().unwrap();
        let (b, l, h, inter) = (20usize, 93usize, 1024usize, 2624usize);
        let hd = 64usize;
        let heads = 16usize;
        let fp16 = |n: usize| vec![0x38u8; n * 2];
        let x = Array::from_data_f16(&fp16(b * l * h), &[b, l, h]).unwrap();
        let wq = Array::from_data_f16(&fp16(3 * h * h), &[3 * h, h]).unwrap();
        let wo = Array::from_data_f16(&fp16(h * h), &[h, h]).unwrap();
        let wi = Array::from_data_f16(&fp16(2 * inter * h), &[2 * inter, h]).unwrap();
        let w2 = Array::from_data_f16(&fp16(h * inter), &[h, inter]).unwrap();
        let ones = || Array::full(1.0, &[b, 1, l, l], Dtype::Bool, s).unwrap();

        timed("Wqkv gemm [20,93,1024]x[1024,3072]", 20, || {
            x.matmul(&wq.transpose_axes(&[1, 0], s).unwrap(), s).unwrap()
        }, s);
        let qkv = x.matmul(&wq.transpose_axes(&[1, 0], s).unwrap(), s).unwrap();
        timed("split+squeeze+transpose qkv", 20, || {
            let q3 = qkv.reshape(&[b, l, 3, heads, hd], s).unwrap();
            let parts = q3.split_n(3, 2, s).unwrap();
            parts[0].identity(s).unwrap().squeeze_axes(&[2], s).unwrap().transpose_axes(&[0, 2, 1, 3], s).unwrap()
        }, s);
        let q = qkv.reshape(&[b, l, 3, heads, hd], s).unwrap().split_n(3, 2, s).unwrap()[0]
            .identity(s).unwrap().squeeze_axes(&[2], s).unwrap().transpose_axes(&[0, 2, 1, 3], s).unwrap();
        timed("rope [20,16,93,64]", 20, || q.rope(hd as i32, 160000.0, 0, s).unwrap(), s);
        let qr = q.rope(hd as i32, 160000.0, 0, s).unwrap();
        timed("sdp [20,16,93,64] bool mask", 20, || {
            Array::sdp_attention(&qr, &qr, &qr, 0.125, &ones(), s).unwrap()
        }, s);
        let att = Array::sdp_attention(&qr, &qr, &qr, 0.125, &ones(), s).unwrap();
        timed("wo gemm", 20, || {
            att.transpose_axes(&[0, 2, 1, 3], s).unwrap().reshape(&[b, l, h], s).unwrap()
                .matmul(&wo.transpose_axes(&[1, 0], s).unwrap(), s).unwrap()
        }, s);
        let normed = x.identity(s).unwrap();
        timed("Wi gemm [20,93,1024]x[1024,5248]", 20, || {
            normed.matmul(&wi.transpose_axes(&[1, 0], s).unwrap(), s).unwrap()
        }, s);
        let wide = normed.matmul(&wi.transpose_axes(&[1, 0], s).unwrap(), s).unwrap();
        timed("split2 + gelu + gate-mul", 20, || {
            let (v, g) = wide.split2(-1, s).unwrap();
            super::gelu_ref(&v, s).unwrap().mul(&g, s).unwrap()
        }, s);
        timed("Wo-mlp gemm [20,93,2624]x[2624,1024]", 20, || {
            wide.split2(-1, s).unwrap().0.matmul(&w2.transpose_axes(&[1, 0], s).unwrap(), s).unwrap()
        }, s);
        timed("layernorm fp32 accum", 20, || {
            let xf = x.astype(Dtype::Float32, s).unwrap();
            let mu = xf.mean_axes(&[-1], true, s).unwrap();
            let c = xf.sub(&mu, s).unwrap();
            let v = c.mul(&c, s).unwrap().mean_axes(&[-1], true, s).unwrap();
            c.div(&v.add(&Array::scalar_f32(1e-5), s).unwrap().sqrt(s).unwrap(), s).unwrap()
                .mul(&x.astype(Dtype::Float32, s).unwrap(), s).unwrap()
        }, s);
    }
}

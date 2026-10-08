//! C ABI surface for dart:ffi — identical to the historical Swift contract
//! (ADR 0051): JSON-in/JSON-out with C strings; returned strings are owned
//! by the caller and released with `laya_native_free`.
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

#[cfg(test)]
pub fn gelu_ref(x: &mlx::Array, s: mlx::Stream) -> mlx::MlxResult<mlx::Array> {
    model::gelu_pub(x, s)
}
pub mod safetensors;

use std::collections::HashMap;
use std::ffi::{c_char, CStr, CString};
use std::os::raw::c_int;
use std::path::PathBuf;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use mlx::{gpu, set_metallib_path, Array};
use model::{Batch, LayaModel};
use unicode_normalization::UnicodeNormalization;

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

/// Pins MLX's metallib before the first GPU op, mirroring the historical
/// Swift pin: beside THIS dylib, then `LAYA_METALLIB`, then the fleet cache.
/// MLX's own colocated search looks beside the binary containing the mlx
/// code — which is now this cdylib — so the first candidate is usually the
/// same file the search would find; the explicit pin keeps the fallbacks.
fn pin_metallib_colocated() {
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
    for candidate in candidates {
        if candidate.is_file() {
            let _ = set_metallib_path(&candidate);
            return;
        }
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
pub extern "C" fn laya_native_load(model_dir: *const c_char) -> i64 {
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
            let handle = NEXT_HANDLE.fetch_add(1, Ordering::SeqCst);
            registry().lock().unwrap().insert(
                handle,
                Engine {
                    model: Arc::new(model),
                },
            );
            handle
        }
        Err(_) => -2,
    }
}

#[no_mangle]
pub extern "C" fn laya_native_forward(handle: i64, request_json: *const c_char) -> *mut c_char {
    if request_json.is_null() {
        return fail("missing request");
    }
    let engine = registry().lock().unwrap().get(&handle).map(|e| Arc::clone(&e.model));
    let Some(model) = engine else {
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

    let output = match model.forward(&batch, stream) {
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
pub extern "C" fn laya_native_free(pointer: *mut c_char) {
    if !pointer.is_null() {
        unsafe { drop(CString::from_raw(pointer)) };
    }
}

#[no_mangle]
pub extern "C" fn laya_native_unload(handle: i64) {
    registry().lock().unwrap().remove(&handle);
}

/// NFC (canonical composed) normalization — the checkpoint tokenizer's
/// normalizer. Output requires up to 4 bytes per input UTF-8 byte.
/// Returns the number of bytes written, or -1 when out is too small.
#[no_mangle]
pub extern "C" fn laya_native_normalize(
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
        let n = super::laya_native_normalize(src.as_ptr(), buf.as_mut_ptr(), 16);
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
    #[test]
    fn engine_forward_latency() {
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
}

#[cfg(test)]
pub fn set_metallib_path_pub(p: &std::path::Path) {
    let _ = mlx::set_metallib_path(p);
}

#[cfg(test)]
mod op_profiles {
    use super::mlx::*;
    use std::path::PathBuf;

    fn timed(name: &str, iters: usize, f: impl Fn() -> Array, s: Stream) {
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

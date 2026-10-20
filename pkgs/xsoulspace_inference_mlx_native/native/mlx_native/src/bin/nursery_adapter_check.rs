//! End-to-end proof that the LoRA surface reaches the nursery runtime.
//!
//! Loads the same store twice — once plain, once with a synthetic adapter
//! merged at load — and generates the same prompt on both. A different
//! output proves the adapter reached the weights; an identical output would
//! mean the merge silently did nothing, which is the failure this surface
//! exists to prevent.
//!
//! Usage:
//!   cargo run --bin nursery_adapter_check -- <store_dir> <adapter.safetensors>

use std::ffi::{CStr, CString};

use mlx_native::{
    mlx_native_nursery_model_generate, mlx_native_nursery_model_last_error,
    mlx_native_nursery_model_load, mlx_native_nursery_model_load_with_adapter,
};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: nursery_adapter_check <store_dir> <adapter.safetensors>");
        std::process::exit(2);
    }
    let store = CString::new(args[1].clone()).unwrap();
    let adapter = CString::new(args[2].clone()).unwrap();

    let base = mlx_native_nursery_model_load(store.as_ptr());
    if base <= 0 {
        eprintln!("base load failed: {}", last_error());
        std::process::exit(1);
    }
    let tuned = mlx_native_nursery_model_load_with_adapter(store.as_ptr(), adapter.as_ptr(), 1.0);
    if tuned <= 0 {
        eprintln!("adapter load failed: {}", last_error());
        std::process::exit(1);
    }

    let req =
        CString::new(r#"{"bytes":[79,112,116,77,101,109,32,119,105,114,101,100],"max_new":24}"#)
            .unwrap();
    let a = generate(base, req.as_ptr());
    let b = generate(tuned, req.as_ptr());

    let same = a == b;
    println!("base:    {a}");
    println!("adapter: {b}");
    println!("identical: {same}");
    if same {
        eprintln!("FAIL: adapter produced no change — the merge did not reach the weights");
        std::process::exit(1);
    }
    println!("PASS: adapter changed generation");
}

fn generate(handle: i64, req: *const std::ffi::c_char) -> String {
    let out = mlx_native_nursery_model_generate(handle, req);
    if out.is_null() {
        return format!("<null: {}>", last_error());
    }
    unsafe { CStr::from_ptr(out).to_string_lossy().to_string() }
}

fn last_error() -> String {
    let out = mlx_native_nursery_model_last_error();
    if out.is_null() {
        return "<no error>".to_string();
    }
    unsafe { CStr::from_ptr(out).to_string_lossy().to_string() }
}

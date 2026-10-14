//! Opt-in native ABI regression. Supply QWEN_CACHE_SNAPSHOT; no downloads.
use std::ffi::{CStr, CString};
use mlx_native::{mlx_native_qwen_load, mlx_native_qwen_generate,
    mlx_native_qwen_clear_cache, mlx_native_qwen_unload, mlx_native_free};
use serde_json::{json, Value};
#[test]
fn scoped_cache_matches_fresh_and_revokes() {
    let Ok(path) = std::env::var("QWEN_CACHE_SNAPSHOT") else {
        eprintln!("SKIP: QWEN_CACHE_SNAPSHOT absent"); return;
    };
    let h = mlx_native_qwen_load(CString::new(path).unwrap().as_ptr());
    assert!(h > 0);
    let max_tokens = std::cell::Cell::new(8);
    let run = |text: &str, actor: Option<&str>, epoch: &str| -> Value {
        let mut r = json!({"prompt": text, "max_tokens": max_tokens.get()});
        if let Some(a) = actor { r["cache_scope"] = json!({"actor": a, "epoch": epoch}); }
        let raw = CString::new(r.to_string()).unwrap();
        let p = mlx_native_qwen_generate(h, raw.as_ptr());
        let v = serde_json::from_slice(unsafe { CStr::from_ptr(p).to_bytes() }).unwrap();
        mlx_native_free(p); v
    };
    let prompt = "<|im_start|>user\nSay READY.<|im_end|>\n<|im_start|>assistant\n<think>\n";
    let fresh = run(prompt, None, "1");
    let cold = run(prompt, Some("realm/alpha"), "1");
    let warm = run(prompt, Some("realm/alpha"), "1");
    assert_eq!(fresh["ids"], cold["ids"]);
    assert_eq!(fresh["ids"], warm["ids"]);
    assert!(warm["cache_reused_tokens"].as_u64().unwrap() > 0);
    assert_eq!(run(prompt, Some("realm/beta"), "1")["cache_reused_tokens"], 0);
    assert_eq!(run(prompt, Some("realm/alpha"), "2")["cache_reused_tokens"], 0);
    let actor = CString::new("realm/alpha").unwrap();
    assert_eq!(mlx_native_qwen_clear_cache(h, actor.as_ptr()), 0);
    assert_eq!(run(prompt, Some("realm/alpha"), "2")["cache_reused_tokens"], 0);
    let changed = prompt.replace("READY", "DONE");
    assert_eq!(run(&changed, Some("realm/alpha"), "2")["ids"], run(&changed, None, "1")["ids"]);
    max_tokens.set(16);
    let grown = run(&changed, Some("realm/alpha"), "2");
    assert_eq!(grown["cache_reused_tokens"], 0);
    assert_eq!(grown["ids"], run(&changed, None, "1")["ids"]);
    mlx_native_qwen_unload(h);
}

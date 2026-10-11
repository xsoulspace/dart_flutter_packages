//! ADR 0061 consumer 3: the energy probe — joules per decision, sampled
//! from IOReport's "Energy Model" channels around N laya decisions.
//!
//! IOReport is a PRIVATE framework (absent from every SDK tbd), so the
//! symbols are dlopen/dlsym'd at runtime and EVERY step degrades honestly:
//! any missing symbol or unreadable channel prints `energy: NON-CLAIM on
//! this host` and exits 0 — a refused measurement is a first-class
//! result, never a fake number. Values are the channels' own deltas over
//! exactly N forwards (mJ as observed by the OS's own energy accounting);
//! the sum names the unit it read. Print-only bench: it gates nothing.
//! Power state rides every output line (the ADR 0061 law).

use std::ffi::{c_char, c_void, CString};
use std::os::raw::{c_double, c_long};

#[cfg(target_os = "macos")]
mod ioreport {
    use super::*;
    use std::ffi::c_ulong;

    pub type CfAllocatorRef = *const c_void;
    pub type CfStringRef = *const c_void;
    pub type CfDictionaryRef = *const c_void;
    pub type CfMutableDictionaryRef = *mut c_void;
    pub type CfTypeRef = *const c_void;

    pub const K_CF_ENCODING_UTF8: u32 = 0x0800_0100;

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        pub fn CFStringCreateWithCString(
            alloc: CfAllocatorRef,
            c_str: *const c_char,
            encoding: u32,
        ) -> CfStringRef;
        pub fn CFStringGetCString(
            s: CfStringRef,
            buffer: *mut c_char,
            buffer_size: c_long,
            encoding: u32,
        ) -> u8;
        pub fn CFStringGetTypeID() -> c_ulong;
        pub fn CFDictionaryGetCount(the_dict: CfDictionaryRef) -> c_long;
        pub fn CFDictionaryGetKeysAndValues(
            the_dict: CfDictionaryRef,
            keys: *mut *const c_void,
            values: *mut *const c_void,
        );
        pub fn CFGetTypeID(cf: CfTypeRef) -> c_ulong;
        pub fn CFNumberGetValue(
            number: *const c_void,
            the_type: c_long,
            value_ptr: *mut c_void,
        ) -> u8;
        pub fn CFNumberGetTypeID() -> c_ulong;
        pub fn CFRelease(cf: *const c_void);
    }

    /// The IOReport surface, resolved at runtime (private framework).
    pub struct IoReport {
        pub create_subscription:
            unsafe extern "C" fn(*const c_void, CfMutableDictionaryRef, *mut CfDictionaryRef, u64, CfDictionaryRef) -> *const c_void,
        pub copy_channels_in_group:
            unsafe extern "C" fn(CfStringRef, CfDictionaryRef, u64) -> CfMutableDictionaryRef,
        pub sample: unsafe extern "C" fn(*const c_void) -> CfDictionaryRef,
    }

    impl IoReport {
        /// dlopen + dlsym the three calls; `None` = the honest degrade.
        /// Two routes, in order: the private framework (where it still
        /// exists), then the process's default symbol scope (hosts whose
        /// shared cache exports IOReport to linked images). darwin 27
        /// exposes NEITHER to an unentitled process — the recorded
        /// capability gap — and the probe prints its non-claim and exits 0.
        pub fn open() -> Option<IoReport> {
            const PATH: &[u8] =
                b"/System/Library/PrivateFrameworks/IOReport.framework/IOReport\0";
            unsafe {
                let mut handle = dlopen(PATH.as_ptr().cast(), RTLD_LAZY);
                if handle.is_null() {
                    // The symbols may still be in the default scope.
                    handle = RTLD_DEFAULT;
                }
                let create = dlsym(handle, b"IOReportCreateSubscription\0".as_ptr().cast());
                let copy = dlsym(handle, b"IOReportCopyChannelsInGroup\0".as_ptr().cast());
                let sample = dlsym(handle, b"IOReportSample\0".as_ptr().cast());
                if create.is_null() || copy.is_null() || sample.is_null() {
                    return None;
                }
                Some(IoReport {
                    create_subscription: std::mem::transmute(create),
                    copy_channels_in_group: std::mem::transmute(copy),
                    sample: std::mem::transmute(sample),
                })
            }
        }
    }

    const RTLD_LAZY: i32 = 1;
    const RTLD_DEFAULT: *mut c_void = -2isize as *mut c_void;

    extern "C" {
        #[link_name = "dlopen"]
        fn dlopen(path: *const c_char, mode: i32) -> *mut c_void;
        #[link_name = "dlsym"]
        fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    }

    /// Reads a CFString's UTF-8 content (empty on anything else).
    pub fn cf_string_value(s: *const c_void) -> String {
        if s.is_null() || unsafe { CFGetTypeID(s) } != unsafe { CFStringGetTypeID() } {
            return String::new();
        }
        let mut buf = [0u8; 512];
        let ok = unsafe {
            CFStringGetCString(
                s,
                buf.as_mut_ptr().cast(),
                buf.len() as c_long,
                K_CF_ENCODING_UTF8,
            )
        };
        if ok == 0 {
            return String::new();
        }
        let end = buf.iter().position(|&b| b == 0).unwrap_or(0);
        String::from_utf8_lossy(&buf[..end]).into_owned()
    }

    /// Reads a CFNumber as f64 (None on anything else).
    pub fn cf_number_value(v: *const c_void) -> Option<f64> {
        if v.is_null() || unsafe { CFGetTypeID(v) } != unsafe { CFNumberGetTypeID() } {
            return None;
        }
        // kCFNumberFloat64Type = 6.
        let mut out: c_double = 0.0;
        let out_ptr: *mut c_void = &mut out as *mut c_double as *mut c_void;
        let ok = unsafe { CFNumberGetValue(v, 6, out_ptr) };
        (ok != 0).then_some(out)
    }
}

#[cfg(target_os = "macos")]
use ioreport::*;

fn cfstr(s: &str) -> *const c_void {
    let c = CString::new(s).unwrap();
    unsafe { CFStringCreateWithCString(std::ptr::null(), c.as_ptr(), K_CF_ENCODING_UTF8) }
}

/// Deltas of every "Energy Model" channel between two samples, keyed by
/// "group/name". Channels present in both samples with numeric values only.
#[cfg(target_os = "macos")]
fn energy_deltas(
    report: &IoReport,
    before: *const c_void,
    after: *const c_void,
) -> Vec<(String, f64)> {
    let mut deltas = Vec::new();
    unsafe {
        let (n_before, n_after) = (CFDictionaryGetCount(before), CFDictionaryGetCount(after));
        if n_before == 0 || n_after == 0 {
            return deltas;
        }
        // Walk the AFTER sample; look up the same channel key in BEFORE.
        let mut keys: Vec<*const c_void> = vec![std::ptr::null(); n_after as usize];
        let mut vals: Vec<*const c_void> = vec![std::ptr::null(); n_after as usize];
        CFDictionaryGetKeysAndValues(after, keys.as_mut_ptr(), vals.as_mut_ptr());
        let mut b_keys: Vec<*const c_void> = vec![std::ptr::null(); n_before as usize];
        let mut b_vals: Vec<*const c_void> = vec![std::ptr::null(); n_before as usize];
        CFDictionaryGetKeysAndValues(before, b_keys.as_mut_ptr(), b_vals.as_mut_ptr());

        for (k, v) in keys.iter().zip(vals.iter()) {
            let name = cf_string_value(*k);
            let Some(after_val) = cf_number_value(*v) else {
                continue;
            };
            let before_val = b_keys
                .iter()
                .zip(b_vals.iter())
                .find(|(bk, _)| cf_string_value(**bk) == name)
                .and_then(|(_, bv)| cf_number_value(*bv));
            let Some(before_val) = before_val else { continue };
            if name.is_empty() {
                continue;
            }
            deltas.push((name, after_val - before_val));
        }
    }
    deltas
}

fn main() {
    // The power state rides every output (ADR 0061 law).
    let facts = mlx_native::power::facts();
    println!("power: {}", facts.describe());

    #[cfg(not(target_os = "macos"))]
    {
        println!("energy: NON-CLAIM on this host (IOReport is macOS-only)");
        return;
    }
    #[cfg(target_os = "macos")]
    {
        let Some(report) = IoReport::open() else {
            println!("energy: NON-CLAIM on this host (IOReport framework unreadable)");
            return;
        };
        // Channels: the whole Energy Model group.
        let group = cfstr("Energy Model");
        let channels = unsafe { (report.copy_channels_in_group)(group, std::ptr::null(), 0) };
        if channels.is_null() {
            println!("energy: NON-CLAIM on this host (Energy Model group unreadable)");
            return;
        }
        let mut subscribed: *const c_void = std::ptr::null();
        let sub = unsafe {
            (report.create_subscription)(
                std::ptr::null(),
                channels,
                &mut subscribed,
                0,
                std::ptr::null(),
            )
        };
        if sub.is_null() {
            println!("energy: NON-CLAIM on this host (subscription refused)");
            return;
        }

        // The measured section: N laya decisions, exactly like the R0 sweep
        // runs them (fw13 shape).
        let s = match mlx_native::mlx::gpu() {
            Ok(s) => s,
            Err(e) => {
                println!("energy: NON-CLAIM on this host (no Metal: status {})", e.0);
                return;
            }
        };
        let model_dir = std::env::var("HOME").unwrap() + "/.cache/xsoulspace/laya-mlx";
        let Ok(model) =
            mlx_native::model::LayaModel::load(std::path::Path::new(&model_dir), s)
        else {
            println!("energy: NON-CLAIM on this host (laya model absent at {model_dir})");
            return;
        };
        let (b, l, k) = (1usize, 93usize, 4usize);
        let batch = mlx_native::model::Batch {
            input_ids: mlx_native::mlx::Array::from_data_i32(&vec![13i32; b * l], &[b, l]).unwrap(),
            attention_mask: mlx_native::mlx::Array::from_data_i32(&vec![1i32; b * l], &[b, l])
                .unwrap(),
            marker_pos: mlx_native::mlx::Array::from_data_i32(&vec![7i32; b * k], &[b, k]).unwrap(),
            marker_mask: mlx_native::mlx::Array::from_data_bool(&vec![1u8; b * k], &[b, k]).unwrap(),
            qtype: mlx_native::mlx::Array::from_data_i32(&vec![0i32; b], &[b]).unwrap(),
        };
        const N: usize = 20;
        // Warmup (compile-free eager; the probe measures the shipping path).
        model.forward(&batch, s).unwrap();
        let before = unsafe { (report.sample)(sub) };
        if before.is_null() {
            println!("energy: NON-CLAIM on this host (first sample empty)");
            return;
        }
        let t0 = std::time::Instant::now();
        for _ in 0..N {
            model.forward(&batch, s).unwrap();
        }
        let wall = t0.elapsed();
        let after = unsafe { (report.sample)(sub) };
        if after.is_null() {
            println!("energy: NON-CLAIM on this host (second sample empty)");
            return;
        }

        let deltas = energy_deltas(&report, before, after);
        if deltas.is_empty() {
            println!("energy: NON-CLAIM on this host (no numeric Energy Model deltas)");
            return;
        }
        let mut rows: Vec<(String, f64)> = deltas;
        rows.sort_by(|a, b| b.1.abs().partial_cmp(&a.1.abs()).unwrap());
        let mut total_mj = 0.0;
        println!(
            "energy over {N} decisions (wall {:.1}ms, {:.1}ms/dec) [power: {}]:",
            wall.as_secs_f64() * 1e3,
            wall.as_secs_f64() * 1e3 / N as f64,
            facts.describe()
        );
        for (name, d) in rows.iter().take(12) {
            println!("  {name}: {d:.1} (unit as the OS reports it)");
        }
        for (_, d) in &rows {
            total_mj += d;
        }
        println!(
            "sum of all Energy Model channel deltas: {total_mj:.1} over {N} decisions = {:.3}/decision \
             (per-channel units may differ; named above — treat the SUM as a convention, the TABLE as the fact)",
            total_mj / N as f64
        );
        if facts.source != mlx_native::power::PowerSource::Ac {
            println!("POWER-CONTAMINATED — non-baseline (ADR 0061): energy on battery is the INTERESTING number, but not comparable to AC rows");
        }
    }
}

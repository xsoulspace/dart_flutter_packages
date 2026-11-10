//! Sidecar-delta specs merged IN MEMORY at load (PREREG-SPEED.md L4,
//! FROZEN 2026-11-10). The weightmap program's edit unit is a column-
//! restricted low-rank delta spec (the frozen apply_delta.py semantics):
//!
//! ```text
//! {"tensor": "<name>", "columns": [int, ...], "direction": [f32 x rows],
//!  "scale": f32}
//! ```
//!
//! Semantics verbatim from the frozen tool's docstring: "the delta for
//! `tensor` (rows x cols) is zero except at the chosen columns; each chosen
//! column j receives `scale * direction`" — i.e.
//! `merged[r][j] = base[r][j] + scale * direction[r]` for every chosen
//! column j (the SIGN lives in the spec's direction values; the python
//! reference is `tool/runs/delta_merge.py` in xsoulspace_inference_weightmap).
//!
//! Why merge-at-load: mirrors are banned in stage-3+ arms (L4) — one
//! materialized 3.2 GB store per sample filled a volume and bought nothing
//! (the decode loop is memory-bound, so a merged weight costs nothing per
//! token; this doc comment's reasoning mirrors lora.rs's). The PARITY GATE:
//! the first live run receipts a merged-tensor f32 digest
//! python == rust (the qwen35_parity pattern; delta_merge.f32_parity_digest
//! is the python anchor) before this path feeds any certification cell.
//! Until that receipt exists this module stays screening-only.
//!
//! Contract pins (mirror lora.rs): base checkpoint digest, tokenizer
//! digest, quantization (a merged spec is f32; merging into a quantized
//! base requires dequantize→merge→requantize and is REFUSED, not
//! approximated), scale. KV/prefix invalidation is the caller's job — a
//! merged weight set is a different model.

use std::collections::HashMap;
use std::path::Path;

use serde::Deserialize;

use crate::mlx::{Array, Stream};

/// One parsed sidecar spec (`apply_delta.py` REQUIRED_KEYS, `tensor` named
/// `target` here because that is what it targets).
#[derive(Debug, Clone, Deserialize)]
pub struct SidecarSpec {
    #[serde(rename = "tensor")]
    pub target: String,
    pub columns: Vec<usize>,
    pub direction: Vec<f32>,
    pub scale: f32,
}

impl SidecarSpec {
    /// Parse a frozen spec file (the shape apply_delta.py consumes).
    pub fn load(path: &Path) -> Result<Self, String> {
        let bytes = std::fs::read(path)
            .map_err(|e| format!("spec read {}: {}", path.display(), e))?;
        serde_json::from_slice::<SidecarSpec>(&bytes)
            .map_err(|e| format!("spec parse {}: {}", path.display(), e))
    }

    /// Validate against the target tensor's shape BEFORE touching params:
    /// direction must cover every row, every column in range, duplicates
    /// harmless but pointless (refused — a duplicated column is a spec
    /// authoring error, the same class A1's audit refuses).
    pub fn validate(&self, rows: usize, cols: usize) -> Result<(), String> {
        if self.direction.len() != rows {
            return Err(format!(
                "ROWS_MISMATCH: direction {} != tensor rows {}",
                self.direction.len(),
                rows
            ));
        }
        for &c in &self.columns {
            if c >= cols {
                return Err(format!(
                    "COLUMN_OUT_OF_RANGE: {} (cols {})",
                    c, cols
                ));
            }
        }
        let mut seen = std::collections::HashSet::new();
        for &c in &self.columns {
            if !seen.insert(c) {
                return Err(format!("DUPLICATE_COLUMN: {}", c));
            }
        }
        Ok(())
    }

    /// CPU-exact merged tensor: `merged[r][j] = base[r][j] + scale *
    /// direction[r]` on chosen columns, everything else copied. The
    /// arithmetic is elementwise f32 in the SAME order as the python
    /// reference (base element, then one fused multiply, then one add —
    /// a single `b + scale * d` expression each side), so the f32 parity
    /// digest compares byte-for-byte.
    pub fn merged_f32(&self, base: &[f32], rows: usize, cols: usize)
        -> Result<Vec<f32>, String> {
        self.validate(rows, cols)?;
        if base.len() != rows * cols {
            return Err(format!(
                "BASE_LEN_MISMATCH: {} != {}x{}",
                base.len(),
                rows,
                cols
            ));
        }
        let mut out = base.to_vec();
        for r in 0..rows {
            let d = self.direction[r];
            for &c in &self.columns {
                out[r * cols + c] = base[r * cols + c] + self.scale * d;
            }
        }
        Ok(out)
    }
}

/// Merge one spec into `params` in place (the lora.rs `apply_to` pattern:
/// read target, compute merged, eval, insert).
pub fn apply_spec_to(
    params: &mut HashMap<String, Array>,
    spec: &SidecarSpec,
    s: Stream,
) -> Result<(), String> {
    let base = params
        .get(&spec.target)
        .ok_or_else(|| format!("missing {}", spec.target))?;
    if base.ndim() != 2 {
        return Err(format!("{}_NOT_2D: ndim {}", spec.target, base.ndim()));
    }
    let (rows, cols) = (base.dim(0), base.dim(1));
    let flat = base.to_f32_vec(s).map_err(|e| format!("read {}: {:?}", spec.target, e))?;
    let merged = spec.merged_f32(&flat, rows, cols)?;
    let merged_arr =
        Array::from_data_f32(&merged, &[rows, cols]).map_err(|e| format!("build {}: {:?}", spec.target, e))?;
    merged_arr
        .eval()
        .map_err(|e| format!("eval {}: {:?}", spec.target, e))?;
    params.insert(spec.target.clone(), merged_arr);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gpu_stream() -> Option<Stream> {
        // Same guard pattern as lora.rs tests: skip quietly without Metal.
        crate::mlx::gpu().ok()
    }

    #[test]
    fn merged_f32_matches_python_reference_fixture() {
        // The delta_merge.py test fixture, hand-derived THIRD time:
        // base [[1,2,3,4],[5,6,7,8]], cols [0,2], dir [10,-10], scale 0.5.
        let spec = SidecarSpec {
            target: "t".into(),
            columns: vec![0, 2],
            direction: vec![10.0, -10.0],
            scale: 0.5,
        };
        let base = vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0];
        let out = spec.merged_f32(&base, 2, 4).unwrap();
        assert_eq!(out, vec![6.0, 2.0, 8.0, 4.0, 0.0, 6.0, 2.0, 8.0]);
    }

    #[test]
    fn zero_scale_is_identity() {
        let spec = SidecarSpec {
            target: "t".into(),
            columns: vec![0, 1, 2, 3],
            direction: vec![9.0, 9.0], // one per ROW (validate refuses len 4)
            scale: 0.0,
        };
        let base = vec![1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0];
        assert_eq!(spec.merged_f32(&base, 2, 4).unwrap(), base);
    }

    #[test]
    fn validation_refusal_names_are_stable() {
        let spec = SidecarSpec {
            target: "t".into(),
            columns: vec![4],
            direction: vec![1.0, 1.0],
            scale: 1.0,
        };
        let err = spec.merged_f32(&vec![0.0; 8], 2, 4).unwrap_err();
        assert!(err.starts_with("COLUMN_OUT_OF_RANGE"), "{err}");
        let spec = SidecarSpec {
            target: "t".into(),
            columns: vec![0],
            direction: vec![1.0],
            scale: 1.0,
        };
        let err = spec.merged_f32(&vec![0.0; 8], 2, 4).unwrap_err();
        assert!(err.starts_with("ROWS_MISMATCH"), "{err}");
        let spec = SidecarSpec {
            target: "t".into(),
            columns: vec![0, 0],
            direction: vec![1.0, 1.0],
            scale: 1.0,
        };
        let err = spec.merged_f32(&vec![0.0; 8], 2, 4).unwrap_err();
        assert!(err.starts_with("DUPLICATE_COLUMN"), "{err}");
    }

    #[test]
    fn apply_spec_to_merges_and_replaces_params() {
        let Some(s) = gpu_stream() else {
            return;
        };
        let spec = SidecarSpec {
            target: "w".into(),
            columns: vec![1],
            direction: vec![2.0, -2.0],
            scale: 1.0,
        };
        let mut params = HashMap::new();
        params.insert(
            "w".to_string(),
            Array::from_data_f32(&[1.0, 2.0, 3.0, 4.0], &[2, 2]).unwrap(),
        );
        apply_spec_to(&mut params, &spec, s).unwrap();
        let vals = params["w"].to_f32_vec(s).unwrap();
        assert_eq!(vals, vec![1.0, 4.0, 3.0, 2.0]); // col1 += dir
    }

    #[test]
    fn missing_target_is_named() {
        let Some(s) = gpu_stream() else {
            return;
        };
        let spec = SidecarSpec {
            target: "absent".into(),
            columns: vec![0],
            direction: vec![1.0, 1.0],
            scale: 1.0,
        };
        let mut params = HashMap::new();
        let err = apply_spec_to(&mut params, &spec, s).unwrap_err();
        assert!(err.starts_with("missing absent"), "{err}");
    }
}

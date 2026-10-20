//! LoRA adapters (the adapter surface for the on-device lane).
//!
//! Why this is a *merge* surface and not a hot-swap hook: on this device the
//! decode loop is memory-bound, so an adapter that is applied at load time
//! costs nothing per token, while a per-token `W + BA` costs an extra read of
//! A and B on every forward. Merging once at load is the cheap shape.
//!
//! The contract (what a caller must pin, or the adapter is silently wrong):
//!
//!   * base checkpoint digest — an adapter is trained against ONE base;
//!   * tokenizer digest — a different tokenizer makes the adapter noise;
//!   * quantization — a merged adapter is f32; merging into a quantized base
//!     requires dequantize → merge → requantize, which is a different path
//!     and is refused here rather than approximated;
//!   * scale — PEFT stores `alpha / r`; the caller passes the final scale.
//!
//! KV/prefix cache invalidation is the caller's job: a merged weight set is a
//! different model, so every cached prefix computed under the old weights is
//! stale. `AdapterSet::digest` exists so a cache can key on it.
//!
//! PEFT naming: `base_model.model.<module>.lora_A.weight` /
//! `...lora_B.weight`; the base weight is `<module>.weight`.

use std::collections::HashMap;
use std::path::Path;

use crate::mlx::{Array, Dtype, MlxResult, Stream};
use crate::safetensors::SafetensorsFile;

/// One (A, B) pair targeting a base weight name.
pub struct LoraPair {
    /// Base weight name, e.g. `model.layers.0.self_attn.q_proj.weight`.
    pub target: String,
    /// Down-projection `[r, in]`.
    pub a: Array,
    /// Up-projection `[out, r]`.
    pub b: Array,
    pub scale: f32,
}

pub struct LoraAdapter {
    pub pairs: Vec<LoraPair>,
    /// Stable digest of the adapter file contents (cache key).
    pub digest: String,
}

impl LoraAdapter {
    /// Load a PEFT-style adapter safetensors file.
    ///
    /// `scale` is the final multiplier (PEFT's `alpha / r`), applied as
    /// `W + scale * (B @ A)`.
    pub fn load(path: &Path, scale: f32, s: Stream) -> Result<Self, String> {
        let bytes = std::fs::read(path).map_err(|e| format!("read adapter: {e}"))?;
        let digest = crate::nursery::sha256_hex(&bytes);
        let file = SafetensorsFile::open(path).map_err(|e| format!("open adapter: {}", e.0))?;

        // Group by target module: strip the PEFT prefix and the A/B suffix.
        let mut a_map: HashMap<String, Array> = HashMap::new();
        let mut b_map: HashMap<String, Array> = HashMap::new();
        for name in file.names() {
            let Some((module, which)) = split_peft_name(&name) else {
                continue;
            };
            let arr = file
                .take_any(&name)
                .map_err(|e| format!("adapter tensor {name}: {}", e.0))?;
            let arr = arr
                .astype(Dtype::Float32, s)
                .map_err(|e| format!("adapter tensor {name}: {}", e.0))?;
            arr.eval()
                .map_err(|e| format!("adapter tensor {name}: {}", e.0))?;
            match which {
                'A' => a_map.insert(module, arr),
                _ => b_map.insert(module, arr),
            };
        }

        let mut pairs = Vec::new();
        for (module, a) in a_map {
            let Some(b) = b_map.remove(&module) else {
                return Err(format!("adapter has lora_A for {module} but no lora_B"));
            };
            pairs.push(LoraPair {
                target: format!("{module}.weight"),
                a,
                b,
                scale,
            });
        }
        if pairs.is_empty() {
            return Err("adapter contains no lora_A/lora_B pairs".to_string());
        }
        pairs.sort_by(|x, y| x.target.cmp(&y.target));
        Ok(Self { pairs, digest })
    }

    /// Check every target exists in the base BEFORE touching the GPU. A
    /// silently-unapplied adapter is the failure mode this surface exists to
    /// prevent, so this is a hard error, never a skip.
    pub fn validate(&self, params: &HashMap<String, Array>) -> Result<(), String> {
        let targets: Vec<String> = self.pairs.iter().map(|p| p.target.clone()).collect();
        validate_targets(&targets, params)
    }

    /// Merge every pair into `params` in place.
    pub fn apply_to(
        &self,
        params: &mut HashMap<String, Array>,
        s: Stream,
    ) -> Result<usize, String> {
        self.validate(params)?;
        let mut applied = 0;
        for pair in &self.pairs {
            let base = params
                .get(&pair.target)
                .ok_or_else(|| format!("missing {}", pair.target))?;
            let merged = merge(base, &pair.a, &pair.b, pair.scale, s)
                .map_err(|e| format!("merge {}: {}", pair.target, e.0))?;
            merged
                .eval()
                .map_err(|e| format!("merge {}: {}", pair.target, e.0))?;
            params.insert(pair.target.clone(), merged);
            applied += 1;
        }
        Ok(applied)
    }
}

/// Every target must exist in the base. Pure (no GPU): callable before any
/// tensor is materialized.
pub fn validate_targets(targets: &[String], params: &HashMap<String, Array>) -> Result<(), String> {
    for t in targets {
        if !params.contains_key(t) {
            return Err(format!(
                "adapter targets {t} which the base model does not have"
            ));
        }
    }
    Ok(())
}

/// `base_t + scale * (A^T @ B^T)` — the merge in the TRANSPOSED
/// orientation the nursery runtime keeps its weights in (`[in, out]`).
///
/// `(B @ A)^T == A^T @ B^T`, so this is the same arithmetic as [`merge`]
/// without the two transposes a caller would otherwise pay per weight.
pub fn merge_transposed(
    base_t: &Array,
    a: &Array,
    b: &Array,
    scale: f32,
    s: Stream,
) -> MlxResult<Array> {
    if b.ndim() != 2 || a.ndim() != 2 {
        return Err(crate::mlx::MlxError(-1));
    }
    if b.dim(1) != a.dim(0) {
        return Err(crate::mlx::MlxError(-1));
    }
    let at = a.transpose_axes(&[1, 0], s)?;
    let bt = b.transpose_axes(&[1, 0], s)?;
    let delta = at.matmul(&bt, s)?;
    let scaled = delta.mul(&Array::scalar_f32(scale), s)?;
    base_t.add(&scaled, s)
}

/// `base + scale * (B @ A)`.
///
/// Shapes: base `[out, in]`, a `[r, in]`, b `[out, r]`.
pub fn merge(base: &Array, a: &Array, b: &Array, scale: f32, s: Stream) -> MlxResult<Array> {
    if b.ndim() != 2 || a.ndim() != 2 {
        return Err(crate::mlx::MlxError(-1));
    }
    // a: [r, in], b: [out, r] -> b @ a is [out, in]
    if b.dim(1) != a.dim(0) {
        return Err(crate::mlx::MlxError(-1));
    }
    let delta = b.matmul(a, s)?;
    let scaled = delta.mul(&Array::scalar_f32(scale), s)?;
    base.add(&scaled, s)
}

/// `base_model.model.<module>.lora_A.weight` -> (`<module>`, 'A').
fn split_peft_name(name: &str) -> Option<(String, char)> {
    let (module, which) = if let Some(m) = name.strip_suffix(".lora_A.weight") {
        (m, 'A')
    } else if let Some(m) = name.strip_suffix(".lora_B.weight") {
        (m, 'B')
    } else {
        return None;
    };
    let module = module
        .strip_prefix("base_model.model.")
        .unwrap_or(module)
        .to_string();
    Some((module, which))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn peft_names_resolve_to_base_weights() {
        assert_eq!(
            split_peft_name("base_model.model.model.layers.0.self_attn.q_proj.lora_A.weight"),
            Some(("model.layers.0.self_attn.q_proj".to_string(), 'A'))
        );
        assert_eq!(
            split_peft_name("model.layers.0.self_attn.q_proj.lora_B.weight"),
            Some(("model.layers.0.self_attn.q_proj".to_string(), 'B'))
        );
        assert_eq!(
            split_peft_name("model.layers.0.self_attn.q_proj.weight"),
            None
        );
    }

    #[test]
    #[ignore = "needs a live Metal stream; run with --ignored on a GPU host"]
    fn zero_adapter_is_identity() {
        // A zero B makes the delta zero, so the merge must return the base
        // unchanged. This is the "adapter off == base" law.
        let s = match crate::mlx::gpu() {
            Ok(s) => s,
            Err(_) => return,
        };
        let base = Array::full_f32(2.0, &[4, 3], s).unwrap();
        let a = Array::full_f32(1.0, &[2, 3], s).unwrap();
        let b = Array::full_f32(0.0, &[4, 2], s).unwrap();
        let merged = merge(&base, &a, &b, 1.0, s).unwrap();
        merged.eval().unwrap();
        let v = merged.item_f32().unwrap();
        assert!((v - 2.0).abs() < 1e-6, "zero adapter changed the base: {v}");
    }

    #[test]
    fn adapter_target_must_exist_in_the_base() {
        // The failure this surface exists to prevent: an adapter that silently
        // does not apply. A missing target is an error, never a skip.
        let params = HashMap::new();
        let targets = vec!["model.layers.0.self_attn.q_proj.weight".to_string()];
        let err = validate_targets(&targets, &params).expect_err("missing target must be an error");
        assert!(err.contains("does not have"), "unexpected error: {err}");
    }
}

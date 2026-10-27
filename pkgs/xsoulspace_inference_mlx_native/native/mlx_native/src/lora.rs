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
//!
//! The MLX-LM naming is ALSO accepted (`<module>.lora_a` / `<module>.lora_b`),
//! because the adapter this lane actually trains comes from the Python
//! mlx-lm tuner, and the two formats are not interchangeable on disk:
//!
//!   format   | a / lora_a        | b / lora_b       | delta
//!   ---------+-------------------+------------------+-------------------
//!   PEFT     | [r, in]           | [out, r]         | `scale * (B @ A)`
//!   mlx-lm   | [in, r]           | [r, out]         | `scale * (B^T @ A^T)`
//!
//! Both compute the same `W + scale * B @ A` in the `[out, in]` orientation;
//! only the on-disk transposition differs. The loader below TRANSPOSES the
//! mlx-lm pair into the PEFT orientation once, at load, so every downstream
//! consumer (merge, the adapter set, the cache key) sees one shape.
//!
//! Why this matters (a measured gap, not a hypothetical): the 2026-10-21
//! adapter capability arm trained its adapters with the mlx-lm tuner, which
//! writes the mlx-lm format. Before this loader, the Rust surface could not
//! read that artifact at all — so the measured capability was a PYTHON-path
//! number with no native consumer.

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

    /// Load an adapter in the MLX-LM on-disk format.
    ///
    /// The mlx-lm tuner writes `<module>.lora_a` `[in, r]` and
    /// `<module>.lora_b` `[r, out]`; the PEFT orientation this crate uses is
    /// `a [r, in]` / `b [out, r]`. The pair is transposed ONCE here, at
    /// load, so every downstream consumer sees the PEFT shape.
    ///
    /// The module name is used verbatim as the base-weight prefix, so the
    /// adapter targets `model.layers.20.mlp.down_proj.weight` — the same
    /// name the base model uses (see `validate`, which hard-errors when a
    /// target is absent rather than skipping it).
    pub fn load_mlx_lm(path: &Path, scale: f32, s: Stream) -> Result<Self, String> {
        let bytes = std::fs::read(path).map_err(|e| format!("read adapter: {e}"))?;
        let digest = crate::nursery::sha256_hex(&bytes);
        let file = SafetensorsFile::open(path).map_err(|e| format!("open adapter: {}", e.0))?;

        let mut a_map: HashMap<String, Array> = HashMap::new();
        let mut b_map: HashMap<String, Array> = HashMap::new();
        for name in file.names() {
            let Some((module, which)) = split_mlx_lm_name(&name) else {
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
                return Err(format!("adapter has lora_a for {module} but no lora_b"));
            };
            // mlx-lm: a [in, r], b [r, out]  ->  PEFT: a [r, in], b [out, r]
            let a_t = a
                .transpose_axes(&[1, 0], s)
                .map_err(|e| format!("transpose lora_a {module}: {}", e.0))?;
            let b_t = b
                .transpose_axes(&[1, 0], s)
                .map_err(|e| format!("transpose lora_b {module}: {}", e.0))?;
            pairs.push(LoraPair {
                target: format!("{module}.weight"),
                a: a_t,
                b: b_t,
                scale,
            });
        }
        if pairs.is_empty() {
            return Err("adapter contains no lora_a/lora_b pairs".to_string());
        }
        pairs.sort_by(|x, y| x.target.cmp(&y.target));
        Ok(Self { pairs, digest })
    }

    /// Load an adapter, DETECTING its on-disk format from the tensor names.
    ///
    /// The two formats are not interchangeable on disk (see the module docs),
    /// and the adapter this lane actually trains comes from the Python mlx-lm
    /// tuner. A loader that understood only one of them would fail LOUDLY on
    /// the other, which is acceptable — but a loader that guessed the wrong
    /// orientation, or that read a file and produced zero pairs, would be a
    /// wrong answer rather than an error. So the format is DETECTED, never
    /// assumed, and an unrecognised file is REFUSED with the names it found.
    ///
    /// A refusal is a valid outcome here: "I will not guess" is the contract.
    /// What is NOT valid is silently reading a PEFT file as mlx-lm (or the
    /// reverse) and merging a transposed delta into the base.
    pub fn load_auto(path: &Path, scale: f32, s: Stream) -> Result<Self, String> {
        let file = SafetensorsFile::open(path).map_err(|e| format!("open adapter: {}", e.0))?;
        let names = file.names();
        match detect_format_from_names(names.iter().map(|n| n.as_str()))? {
            AdapterFormat::MlxLm => Self::load_mlx_lm(path, scale, s),
            AdapterFormat::Peft => Self::load(path, scale, s),
        }
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

/// The RUNTIME application surface: adapter pairs kept UNMERGED and applied
/// at every forward, as `y = x·Wᵀ + scale·((x·a_t)·b_t)`.
///
/// WHY A SECOND SURFACE. The merge surface ([`LoraAdapter::apply_to`]) is the
/// cheap shape on this device — but it requires a PLAIN base (merging into a
/// quantized base means dequantize → merge → requantize, and the requant
/// error is the same order as the adapter's own delta, which K-G4 refuses to
/// approximate). The lane's real adapter is trained on the 4-BIT base and
/// evaluated on the python mlx-lm path, which applies the adapter at runtime
/// for exactly this reason. This struct is the native mirror of that path, so
/// the capability measured on python can be measured on the shipping surface
/// WITHOUT a base confound.
///
/// The arrays are kept in the orientation the runtime math needs —
/// `a_t: [in, r]`, `b_t: [r, out]` — with the scale UNFOLDED, so the forward
/// computes exactly what the reference computes: `y + scale·((x·a_t)·b_t)`,
/// cast to the model's activation dtype once, at attach (the reference casts
/// per call; casting once is the same values, cheaper).
pub struct RuntimeLora {
    /// Pair per target, keyed by the BASE weight name (`<module>.weight`).
    pub by_target: HashMap<String, (Array, Array)>,
    /// The one scale multiplier (mlx-lm's `lora_parameters.scale`).
    pub scale: f32,
    /// The adapter file digest (identity folding, cache keys).
    pub digest: String,
}

impl RuntimeLora {
    /// Build the runtime pair set from a loaded adapter.
    ///
    /// The loader's pairs are in the PEFT orientation (`a [r, in]`,
    /// `b [out, r]`, both Float32); the runtime math wants the transposes,
    /// and `merge_transposed` documents why: `(B @ A)ᵀ == Aᵀ @ Bᵀ`.
    pub fn from_adapter(adapter: &LoraAdapter, dtype: Dtype, s: Stream) -> Result<Self, String> {
        let mut by_target: HashMap<String, (Array, Array)> = HashMap::new();
        for pair in &adapter.pairs {
            let a_t = pair
                .a
                .transpose_axes(&[1, 0], s)
                .map_err(|e| format!("lora a_t {}: {}", pair.target, e.0))?
                .astype(dtype, s)
                .map_err(|e| format!("lora a_t {}: {}", pair.target, e.0))?;
            let b_t = pair
                .b
                .transpose_axes(&[1, 0], s)
                .map_err(|e| format!("lora b_t {}: {}", pair.target, e.0))?
                .astype(dtype, s)
                .map_err(|e| format!("lora b_t {}: {}", pair.target, e.0))?;
            a_t.eval()
                .map_err(|e| format!("lora a_t {}: {}", pair.target, e.0))?;
            b_t.eval()
                .map_err(|e| format!("lora b_t {}: {}", pair.target, e.0))?;
            by_target.insert(pair.target.clone(), (a_t, b_t));
        }
        Ok(Self {
            by_target,
            scale: adapter.pairs.first().map(|p| p.scale).unwrap_or(0.0),
            digest: adapter.digest.clone(),
        })
    }

    pub fn len(&self) -> usize {
        self.by_target.len()
    }

    pub fn is_empty(&self) -> bool {
        self.by_target.is_empty()
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

/// `<module>.lora_a` -> (`<module>`, 'A'); `<module>.lora_b` -> (`<module>`, 'B').
///
/// The mlx-lm tuner's on-disk naming (no `.weight` suffix, lowercase a/b).
fn split_mlx_lm_name(name: &str) -> Option<(String, char)> {
    if let Some(m) = name.strip_suffix(".lora_a") {
        Some((m.to_string(), 'A'))
    } else if let Some(m) = name.strip_suffix(".lora_b") {
        Some((m.to_string(), 'B'))
    } else {
        None
    }
}

/// Which on-disk LoRA layout a file uses.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdapterFormat {
    /// mlx-lm tuner layout: `<module>.lora_a` `[in, r]` / `<module>.lora_b` `[r, out]`.
    MlxLm,
    /// PEFT layout: `<module>.lora_A.weight` `[r, in]` / `<module>.lora_B.weight` `[out, r]`.
    Peft,
}

/// Detect the layout from tensor NAMES. Pure: no file read, no GPU.
///
/// The refusal is the point. A file that has no recognisable LoRA tensors, or
/// that has BOTH layouts in it, is not silently given one of them.
pub fn detect_format_from_names<'a, I: IntoIterator<Item = &'a str>>(
    names: I,
) -> Result<AdapterFormat, String> {
    let (mut mlx_lm, mut peft) = (0usize, 0usize);
    for name in names {
        if split_mlx_lm_name(name).is_some() {
            mlx_lm += 1;
        }
        if split_peft_name(name).is_some() {
            peft += 1;
        }
    }
    match (mlx_lm > 0, peft > 0) {
        (true, false) => Ok(AdapterFormat::MlxLm),
        (false, true) => Ok(AdapterFormat::Peft),
        (true, true) => Err(format!(
            "adapter mixes mlx-lm and PEFT tensor names ({} lora_a/lora_b, \
             {} lora_A/lora_B.weight); refusing to guess the format",
            mlx_lm, peft
        )),
        (false, false) => Err(
            "adapter contains no LoRA tensors; expected mlx-lm `*.lora_a`/`*.lora_b` \
             or PEFT `*.lora_A.weight`/`*.lora_B.weight`"
                .to_string(),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A live Metal stream for a TEST binary.
    ///
    /// The kernel library is pinned inside `mlx::gpu()` (see
    /// `pin_metallib_colocated`), so the ORDER of the tests cannot decide
    /// whether a stream is created against a foreign MLX build — which is
    /// what aborted these two tests in the lib test binary while they passed
    /// in their own integration-test binary. No GPU means no stream, and no
    /// stream means these assertions are vacuous: they skip.
    fn gpu_stream() -> Option<Stream> {
        match crate::mlx::gpu() {
            Ok(s) => Some(s),
            Err(_) => None,
        }
    }

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
    fn zero_adapter_is_identity() {
        // A zero B makes the delta zero, so the merge must return the base
        // unchanged. This is the "adapter off == base" law.
        let Some(s) = gpu_stream() else {
            return;
        };
        let base = Array::full_f32(2.0, &[4, 3], s).unwrap();
        let a = Array::full_f32(1.0, &[2, 3], s).unwrap();
        let b = Array::full_f32(0.0, &[4, 2], s).unwrap();
        let merged = merge(&base, &a, &b, 1.0, s).unwrap();
        merged.eval().unwrap();
        // The merged array is [4, 3] — 12 elements — so `item_f32` (which
        // only reads a SIZE-1 array) cannot be used here; read the whole
        // vector and check every element. (This test was `#[ignore]`d until
        // the metallib pin made it runnable, so the defect was never hit.)
        let vals = merged.to_f32_vec(s).unwrap();
        assert_eq!(vals.len(), 12, "the merged shape changed");
        for v in vals {
            assert!((v - 2.0).abs() < 1e-6, "zero adapter changed the base: {v}");
        }
    }

    #[test]
    fn the_format_is_detected_not_assumed() {
        assert_eq!(
            detect_format_from_names(["model.layers.0.mlp.down_proj.lora_a"]),
            Ok(AdapterFormat::MlxLm)
        );
        assert_eq!(
            detect_format_from_names(["model.layers.0.mlp.down_proj.lora_A.weight"]),
            Ok(AdapterFormat::Peft)
        );
        // No LoRA tensors at all -> a REFUSAL, never a guess.
        assert!(detect_format_from_names(["model.embed_tokens.weight"]).is_err());
        // Both layouts in one file -> a REFUSAL, never a guess.
        assert!(detect_format_from_names([
            "model.layers.0.mlp.down_proj.lora_a",
            "model.layers.0.mlp.down_proj.lora_A.weight"
        ])
        .is_err());
    }

    #[test]
    fn mlx_lm_names_resolve_to_base_weights() {
        assert_eq!(
            split_mlx_lm_name("model.layers.20.mlp.down_proj.lora_a"),
            Some(("model.layers.20.mlp.down_proj".to_string(), 'A'))
        );
        assert_eq!(
            split_mlx_lm_name("model.layers.20.mlp.down_proj.lora_b"),
            Some(("model.layers.20.mlp.down_proj".to_string(), 'B'))
        );
        // A PEFT name must NOT match the mlx-lm splitter.
        assert_eq!(
            split_mlx_lm_name("model.layers.20.mlp.down_proj.lora_A.weight"),
            None
        );
        assert_eq!(
            split_mlx_lm_name("model.layers.20.mlp.down_proj.weight"),
            None
        );
    }

    /// The format bridge's contract: the SAME adapter, written in the two
    /// on-disk formats, must merge to the SAME weights.
    ///
    /// mlx-lm writes `lora_a [in, r]` + `lora_b [r, out]` and merges as
    /// `W + scale * (B^T @ A^T)`; PEFT writes `lora_A [r, in]` +
    /// `lora_B [out, r]` and merges as `W + scale * (B @ A)`. The loader
    /// transposes the mlx-lm pair once, so both must land on the same
    /// result. This is the test that makes the 2026-10-21 Python-trained
    /// adapter usable by the native surface at all.
    #[test]
    fn mlx_lm_and_peft_formats_merge_identically() {
        let Some(s) = gpu_stream() else {
            return;
        };
        const IN: usize = 3;
        const OUT: usize = 4;
        const R: usize = 2;
        // A deterministic, non-symmetric pair so a wrong transpose shows up.
        let a_mlx: Vec<f32> = (0..(IN * R)).map(|i| (i as f32) * 0.25 + 0.5).collect();
        let b_mlx: Vec<f32> = (0..(R * OUT)).map(|i| (i as f32) * -0.5 + 1.0).collect();
        let base: Vec<f32> = (0..(OUT * IN)).map(|i| (i as f32) * 0.1).collect();

        let base_arr = Array::from_data_f32(&base, &[OUT, IN]).unwrap();
        let a_mlx_arr = Array::from_data_f32(&a_mlx, &[IN, R]).unwrap();
        let b_mlx_arr = Array::from_data_f32(&b_mlx, &[R, OUT]).unwrap();
        // the mlx-lm merge, as the python side computes it
        let mlx_merged = {
            let at = a_mlx_arr.transpose_axes(&[1, 0], s).unwrap();
            let bt = b_mlx_arr.transpose_axes(&[1, 0], s).unwrap();
            let delta = bt.matmul(&at, s).unwrap();
            let scaled = delta.mul(&Array::scalar_f32(2.0), s).unwrap();
            base_arr.add(&scaled, s).unwrap()
        };
        // the PEFT orientation, as the loader produces it
        let a_peft = a_mlx_arr.transpose_axes(&[1, 0], s).unwrap();
        let b_peft = b_mlx_arr.transpose_axes(&[1, 0], s).unwrap();
        let peft_merged = merge(&base_arr, &a_peft, &b_peft, 2.0, s).unwrap();
        mlx_merged.eval().unwrap();
        peft_merged.eval().unwrap();
        let m = mlx_merged.to_f32_vec(s).unwrap();
        let p = peft_merged.to_f32_vec(s).unwrap();
        assert_eq!(m.len(), p.len(), "shape mismatch");
        let mut max_diff = 0.0f32;
        for (x, y) in m.iter().zip(p.iter()) {
            max_diff = max_diff.max((x - y).abs());
        }
        assert!(
            max_diff < 1e-6,
            "the two formats merged differently: max diff {max_diff}"
        );
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

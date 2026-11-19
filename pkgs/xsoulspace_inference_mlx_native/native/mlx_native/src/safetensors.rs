//! Direct safetensors reading — the Swift port's approach, kept: eager fp16
//! buffers handed to `mlx_array_new_data` (one copy at load), so no lazy
//! Load primitives ever enter the mlx graph (their GPU eval is not
//! implemented in the C route and the scheduling differs from the Swift
//! runtime's eager loader).

use std::collections::HashMap;

use crate::mlx::{Array, Dtype, MlxError, MlxResult, Stream};

pub struct SafetensorsFile {
    /// Whole file bytes (header + data). Tensors copy out of here on take.
    bytes: Vec<u8>,
    tensors: HashMap<String, TensorInfo>,
}

struct TensorInfo {
    dtype: String,
    shape: Vec<usize>,
    start: usize,
    end: usize,
}

impl SafetensorsFile {
    pub fn open(path: &std::path::Path) -> MlxResult<SafetensorsFile> {
        let bytes = std::fs::read(path).map_err(|_| MlxError(-12))?;
        if bytes.len() < 8 {
            return Err(MlxError(-12));
        }
        let header_len = u64::from_le_bytes(bytes[..8].try_into().unwrap()) as usize;
        if 8 + header_len > bytes.len() {
            return Err(MlxError(-12));
        }
        let header: HashMap<String, serde_json::Value> =
            serde_json::from_slice(&bytes[8..8 + header_len]).map_err(|_| MlxError(-12))?;
        let mut tensors = HashMap::new();
        for (name, entry) in header {
            if name == "__metadata__" {
                continue;
            }
            let dtype = entry["dtype"].as_str().unwrap_or_default().to_string();
            let shape: Vec<usize> = entry["shape"]
                .as_array()
                .map(|a| {
                    a.iter()
                        .filter_map(|v| v.as_u64().map(|d| d as usize))
                        .collect()
                })
                .unwrap_or_default();
            let offsets = entry["data_offsets"]
                .as_array()
                .cloned()
                .unwrap_or_default();
            if offsets.len() != 2 {
                return Err(MlxError(-12));
            }
            let start = 8 + header_len + offsets[0].as_u64().unwrap_or(0) as usize;
            let end = 8 + header_len + offsets[1].as_u64().unwrap_or(0) as usize;
            if end > bytes.len() {
                return Err(MlxError(-12));
            }
            tensors.insert(
                name,
                TensorInfo {
                    dtype,
                    shape,
                    start,
                    end,
                },
            );
        }
        Ok(SafetensorsFile { bytes, tensors })
    }

    pub fn take(&self, name: &str, s: Stream) -> MlxResult<Array> {
        let info = self.tensors.get(name).ok_or(MlxError(-13))?;
        let data = &self.bytes[info.start..info.end];
        match info.dtype.as_str() {
            "F16" => Array::from_data_f16(data, &info.shape),
            "BF16" => {
                let _ = s;
                Err(MlxError(-14))
            }
            "F32" => {
                let _ = s;
                Err(MlxError(-14))
            }
            _ => Err(MlxError(-14)),
        }
    }

    fn raw_bytes(&self, name: &str, want: &str) -> MlxResult<(&[u8], Vec<usize>)> {
        let info = self.tensors.get(name).ok_or(MlxError(-13))?;
        if info.dtype != want {
            return Err(MlxError(-14));
        }
        Ok((&self.bytes[info.start..info.end], info.shape.clone()))
    }

    /// Packed quantized weight (safetensors "U32") — R2's Qwen3 weights.
    pub fn take_u32(&self, name: &str) -> MlxResult<Array> {
        let (data, shape) = self.raw_bytes(name, "U32")?;
        let u32s: Vec<u32> = data
            .chunks_exact(4)
            .map(|c| u32::from_le_bytes(c.try_into().unwrap()))
            .collect();
        Array::from_data_u32(&u32s, &shape)
    }

    /// bfloat16 tensor (safetensors "BF16") — scales/biases/norm weights.
    pub fn take_bf16(&self, name: &str) -> MlxResult<Array> {
        let (data, shape) = self.raw_bytes(name, "BF16")?;
        Array::from_data_bf16(data, &shape)
    }

    /// All tensor names in the file (sorted, deterministic).
    pub fn names(&self) -> Vec<String> {
        let mut v: Vec<String> = self.tensors.keys().cloned().collect();
        v.sort();
        v
    }

    /// Plain checkpoint tensor in whatever float storage it ships as (fp16,
    /// bf16, or f32 — LoRA adapters are commonly saved f32).
    pub fn take_any(&self, name: &str) -> MlxResult<Array> {
        let (data, shape, dtype) = {
            let info = self.tensors.get(name).ok_or(MlxError(-13))?;
            (
                &self.bytes[info.start..info.end],
                info.shape.clone(),
                info.dtype.clone(),
            )
        };
        match dtype.as_str() {
            "F16" => Array::from_data_f16(data, &shape),
            "BF16" => Array::from_data_bf16(data, &shape),
            "F32" => {
                let vals: Vec<f32> = data
                    .chunks_exact(4)
                    .map(|c| f32::from_le_bytes(c.try_into().unwrap()))
                    .collect();
                Array::from_data_f32(&vals, &shape)
            }
            _ => Err(MlxError(-14)),
        }
    }

    /// One affine-quantized linear/embedding weight: `name.weight` (U32
    /// packed), `name.scales`, `name.biases` — the triple mlx's quantized
    /// ops take.
    pub fn take_quantized(&self, name: &str) -> MlxResult<QuantizedTensor> {
        Ok(QuantizedTensor {
            w: self.take_u32(&format!("{name}.weight"))?,
            scales: self.take_bf16(&format!("{name}.scales"))?,
            biases: self.take_bf16(&format!("{name}.biases"))?,
        })
    }

    #[allow(dead_code)]
    pub fn dtype_of(&self, name: &str) -> Option<Dtype> {
        match self.tensors.get(name)?.dtype.as_str() {
            "F16" => Some(Dtype::Float16),
            "BF16" => Some(Dtype::BFloat16),
            "U32" => Some(Dtype::UInt32),
            _ => None,
        }
    }
}

/// An affine-quantized weight triple as stored by MLX (weight packed U32,
/// per-group scales/biases bf16).
pub struct QuantizedTensor {
    pub w: Array,
    pub scales: Array,
    pub biases: Array,
}

/// A checkpoint directory's weight store: EITHER the single
/// `model.safetensors` file (every pre-qwen3_5 caller's layout — behavior
/// unchanged) OR the HF sharded layout described by
/// `model.safetensors.index.json` (qwen3_5 ships an index whose one shard
/// is literally named `model.safetensors-00001-of-00001.safetensors`).
/// Additive: no existing call site changes; single-file directories never
/// read the index.
pub struct WeightStore {
    files: Vec<SafetensorsFile>,
    /// Tensor name → `files` index. `None` = single-file store (file 0).
    route: Option<HashMap<String, usize>>,
}

impl WeightStore {
    /// Opens the store for a checkpoint directory. Single file wins when
    /// present; otherwise the index is required.
    pub fn open_dir(dir: &std::path::Path) -> MlxResult<WeightStore> {
        let single = dir.join("model.safetensors");
        if single.is_file() {
            return Ok(WeightStore {
                files: vec![SafetensorsFile::open(&single)?],
                route: None,
            });
        }
        let raw = std::fs::read_to_string(dir.join("model.safetensors.index.json"))
            .map_err(|_| MlxError(-12))?;
        let doc: serde_json::Value = serde_json::from_str(&raw).map_err(|_| MlxError(-12))?;
        let weight_map = doc
            .get("weight_map")
            .and_then(|m| m.as_object())
            .ok_or(MlxError(-12))?;
        // Unique shard files, opened once each, in first-reference order of
        // the sorted tensor names (deterministic across runs).
        let mut files: Vec<SafetensorsFile> = Vec::new();
        let mut shard_ids: HashMap<String, usize> = HashMap::new();
        let mut route: HashMap<String, usize> = HashMap::with_capacity(weight_map.len());
        let mut names: Vec<&String> = weight_map.keys().collect();
        names.sort();
        for name in names {
            let shard = weight_map
                .get(name)
                .and_then(|v| v.as_str())
                .ok_or(MlxError(-12))?;
            let idx = match shard_ids.get(shard) {
                Some(i) => *i,
                None => {
                    files.push(SafetensorsFile::open(&dir.join(shard))?);
                    let i = files.len() - 1;
                    shard_ids.insert(shard.to_string(), i);
                    i
                }
            };
            route.insert(name.clone(), idx);
        }
        Ok(WeightStore {
            files,
            route: Some(route),
        })
    }

    fn file_for(&self, name: &str) -> MlxResult<&SafetensorsFile> {
        match &self.route {
            None => Ok(&self.files[0]),
            Some(route) => {
                let idx = route.get(name).ok_or(MlxError(-13))?;
                Ok(&self.files[*idx])
            }
        }
    }

    /// Whether the store holds a tensor by that name.
    pub fn has(&self, name: &str) -> bool {
        match &self.route {
            None => self.files[0].dtype_of(name).is_some() || self.names_contains(name),
            Some(route) => route.contains_key(name),
        }
    }

    fn names_contains(&self, name: &str) -> bool {
        self.files[0].names().iter().any(|n| n == name)
    }

    /// [`SafetensorsFile::take_any`] routed through the store.
    pub fn take_any(&self, name: &str) -> MlxResult<Array> {
        self.file_for(name)?.take_any(name)
    }

    /// [`SafetensorsFile::take_quantized`] routed through the store (the
    /// qwen3_5 loader reads the affine triple from either store layout).
    pub fn take_quantized(&self, name: &str) -> MlxResult<QuantizedTensor> {
        self.file_for(name)?.take_quantized(name)
    }
}

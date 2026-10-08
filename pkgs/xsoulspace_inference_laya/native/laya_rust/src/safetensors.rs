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
        let header_len =
            u64::from_le_bytes(bytes[..8].try_into().unwrap()) as usize;
        if 8 + header_len > bytes.len() {
            return Err(MlxError(-12));
        }
        let header: HashMap<String, serde_json::Value> =
            serde_json::from_slice(&bytes[8..8 + header_len])
                .map_err(|_| MlxError(-12))?;
        let mut tensors = HashMap::new();
        for (name, entry) in header {
            if name == "__metadata__" {
                continue;
            }
            let dtype = entry["dtype"].as_str().unwrap_or_default().to_string();
            let shape: Vec<usize> = entry["shape"]
                .as_array()
                .map(|a| a.iter().filter_map(|v| v.as_u64().map(|d| d as usize)).collect())
                .unwrap_or_default();
            let offsets = entry["data_offsets"].as_array().cloned().unwrap_or_default();
            if offsets.len() != 2 {
                return Err(MlxError(-12));
            }
            let start = 8 + header_len + offsets[0].as_u64().unwrap_or(0) as usize;
            let end = 8 + header_len + offsets[1].as_u64().unwrap_or(0) as usize;
            if end > bytes.len() {
                return Err(MlxError(-12));
            }
            tensors.insert(name, TensorInfo { dtype, shape, start, end });
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

    #[allow(dead_code)]
    pub fn dtype_of(&self, name: &str) -> Option<Dtype> {
        match self.tensors.get(name)?.dtype.as_str() {
            "F16" => Some(Dtype::Float16),
            _ => None,
        }
    }
}

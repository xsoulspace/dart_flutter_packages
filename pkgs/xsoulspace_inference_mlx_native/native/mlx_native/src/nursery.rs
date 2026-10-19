//! Nursery weights-splat store reader (contract `nursery.weights-splat.v1`).
//!
//! The in-crate consumer of the pack-at-birth pipeline
//! (`tool/nursery/pack_at_birth.py`): content-addressed packed segments,
//! offset-indexed point reads, sha256 digest verification on load. This is
//! the segment pattern's contract — shared with the codemap fact store and
//! the stage1 paged-MoE store — so its laws hold here verbatim: a wrong
//! digest is a HARD error, never a silent zero, and a report of
//! `mismatched == 0` means checks RAN, not checks skipped.
//!
//! Phase-1 scope (Line I nursery): the LOAD path only — open, verify,
//! addressable tensor reads, exact dtype conversion. No forward pass and
//! no GPU: this module never touches mlx, so it works wherever the crate
//! links. The Metal runtime rides this same cdylib when RUNG-0 models
//! exist; the router contract they must satisfy is pinned in
//! `PORTING-MOE.md`, and their training gates in `TRAIN-GATES.md`.

use serde::Deserialize;
use sha2::{Digest, Sha256};
use std::collections::{HashMap, HashSet};
use std::fs::File;
use std::io::Read;
use std::os::unix::fs::FileExt;
use std::path::{Path, PathBuf};

pub const CONTRACT: &str = "nursery.weights-splat.v1";

#[derive(Debug, Deserialize)]
pub struct Manifest {
    pub contract: String,
    #[serde(default)]
    pub generator: String,
    #[serde(default)]
    pub source: serde_json::Value,
    #[serde(default)]
    pub quantization: Option<Quantization>,
    pub segments: HashMap<String, SegmentEntry>,
}

#[derive(Debug, Deserialize)]
pub struct Quantization {
    pub bits: u32,
    pub group_size: u32,
}

#[derive(Debug, Deserialize)]
pub struct SegmentEntry {
    pub file: String,
    pub digest: String,
    pub size: usize,
    pub tensors: HashMap<String, TensorEntry>,
}

#[derive(Debug, Deserialize)]
pub struct TensorEntry {
    pub offset: usize,
    pub nbytes: usize,
    pub shape: Vec<usize>,
    pub dtype: String,
    #[serde(default)]
    pub role: String,
}

/// Counting verify report: `checked` is how many segment digests were
/// actually recomputed (the "checks RAN" law), `missing` counts segment
/// files absent from disk.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct VerifyReport {
    pub checked: usize,
    pub mismatched: usize,
    pub missing: usize,
    pub bytes: u64,
    pub first_problem: Option<String>,
}

pub struct NurseryStore {
    dir: PathBuf,
    pub manifest: Manifest,
    verified: HashSet<String>,
}

pub struct Tensor {
    pub shape: Vec<usize>,
    pub dtype: String,
    pub role: String,
    pub data: Vec<u8>,
}

impl Tensor {
    pub fn elements(&self) -> usize {
        self.shape.iter().product::<usize>().max(if self.shape.is_empty() { 0 } else { 1 })
    }

    /// Exact-or-documented conversions only. float32/float16/bfloat16 are
    /// bit-exact widenings; the integer paths round like numpy's astype
    /// (round-to-nearest), which is what the fixture pins.
    pub fn to_f32_vec(&self) -> Result<Vec<f32>, String> {
        let out = match self.dtype.as_str() {
            "float32" => self
                .data
                .chunks_exact(4)
                .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
                .collect::<Vec<f32>>(),
            "float64" => self
                .data
                .chunks_exact(8)
                .map(|c| f64::from_le_bytes(c.try_into().unwrap()) as f32)
                .collect(),
            "float16" => self
                .data
                .chunks_exact(2)
                .map(|c| f16_bits_to_f32(u16::from_le_bytes([c[0], c[1]])))
                .collect(),
            "bfloat16" => self
                .data
                .chunks_exact(2)
                .map(|c| f32::from_bits((u16::from_le_bytes([c[0], c[1]]) as u32) << 16))
                .collect(),
            "uint32" => self
                .data
                .chunks_exact(4)
                .map(|c| u32::from_le_bytes(c.try_into().unwrap()) as f32)
                .collect(),
            "int32" => self
                .data
                .chunks_exact(4)
                .map(|c| i32::from_le_bytes(c.try_into().unwrap()) as f32)
                .collect(),
            "uint8" => self.data.iter().map(|b| *b as f32).collect(),
            "int64" => self
                .data
                .chunks_exact(8)
                .map(|c| i64::from_le_bytes(c.try_into().unwrap()) as f32)
                .collect(),
            other => {
                return Err(format!(
                    "dtype {other} has no f32 conversion in the nursery reader"
                ))
            }
        };
        if out.len() != self.elements() {
            return Err(format!(
                "byte length {} does not match shape {:?} for dtype {}",
                self.data.len(),
                self.shape,
                self.dtype
            ));
        }
        Ok(out)
    }
}

/// IEEE half → f32, bit-exact (normals, subnormals, infinities, NaN).
pub fn f16_bits_to_f32(bits: u16) -> f32 {
    let sign = ((bits & 0x8000) as u32) << 16;
    let exp = (bits >> 10) & 0x1f;
    let frac = (bits & 0x03ff) as u32;
    match exp {
        0 => {
            if frac == 0 {
                f32::from_bits(sign)
            } else {
                let mag = (frac as f32) * 2f32.powi(-24);
                if sign != 0 {
                    -mag
                } else {
                    mag
                }
            }
        }
        0x1f => f32::from_bits(sign | 0x7f80_0000 | (frac << 13)),
        e => f32::from_bits(sign | ((e as u32 + 112) << 23) | (frac << 13)),
    }
}

pub fn sha256_hex(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex(&hasher.finalize())
}

fn hex(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{b:02x}"));
    }
    s
}

impl NurseryStore {
    /// Opens `<dir>/manifest.json` and validates the contract string.
    /// Read-only at runtime, per the store contract — nothing here writes.
    pub fn open(dir: &Path) -> Result<Self, String> {
        let path = dir.join("manifest.json");
        let raw = std::fs::read(&path)
            .map_err(|e| format!("manifest unreadable at {}: {e}", path.display()))?;
        let manifest: Manifest = serde_json::from_slice(&raw)
            .map_err(|e| format!("manifest unparsable: {e}"))?;
        if manifest.contract != CONTRACT {
            return Err(format!(
                "contract mismatch: expected {CONTRACT}, got {}",
                manifest.contract
            ));
        }
        Ok(Self {
            dir: dir.to_path_buf(),
            manifest,
            verified: HashSet::new(),
        })
    }

    fn segment_entry(&self, key: &str) -> Result<&SegmentEntry, String> {
        self.manifest
            .segments
            .get(key)
            .ok_or_else(|| format!("manifest has no segment {key}"))
    }

    fn segment_path(&self, entry: &SegmentEntry) -> Result<PathBuf, String> {
        if entry.file.contains('/') || entry.file.contains("..") {
            return Err(format!(
                "manifest names a segment outside the store dir: {}",
                entry.file
            ));
        }
        Ok(self.dir.join(&entry.file))
    }

    /// Digest-verifies one segment (once per store instance); a mismatch is
    /// a hard error naming the segment — the trust model of every point
    /// read depends on it.
    pub fn verify_segment(&mut self, key: &str) -> Result<(), String> {
        if self.verified.contains(key) {
            return Ok(());
        }
        let entry = self.segment_entry(key)?;
        let path = self.segment_path(entry)?;
        let mut data = Vec::with_capacity(entry.size);
        File::open(&path)
            .and_then(|mut f| f.read_to_end(&mut data))
            .map_err(|e| format!("segment {key} unreadable: {e}"))?;
        if data.len() != entry.size {
            return Err(format!(
                "segment {key} is {} bytes, manifest says {}",
                data.len(),
                entry.size
            ));
        }
        let digest = sha256_hex(&data);
        if digest != entry.digest {
            return Err(format!(
                "segment {key} digest mismatch: store corrupt (got {digest})",
            ));
        }
        self.verified.insert(key.to_string());
        Ok(())
    }

    /// Verifies EVERY segment. `checked` counts real digest recomputations;
    /// any mismatch or missing file is a hard error AFTER the full count —
    /// a partial walk never masquerades as a clean store.
    pub fn verify_all(&mut self) -> Result<VerifyReport, String> {
        let mut report = VerifyReport::default();
        let mut keys: Vec<&String> = self.manifest.segments.keys().collect();
        keys.sort();
        for key in keys {
            let entry = self.segment_entry(key)?;
            let path = self.segment_path(entry)?;
            match File::open(&path).and_then(|mut f| {
                let mut data = Vec::with_capacity(entry.size);
                f.read_to_end(&mut data)?;
                Ok(data)
            }) {
                Ok(data) if data.len() == entry.size => {
                    report.checked += 1;
                    report.bytes += data.len() as u64;
                    if sha256_hex(&data) != entry.digest {
                        report.mismatched += 1;
                        if report.first_problem.is_none() {
                            report.first_problem =
                                Some(format!("segment {key} digest mismatch"));
                        }
                    }
                }
                Ok(data) => {
                    report.mismatched += 1;
                    if report.first_problem.is_none() {
                        report.first_problem = Some(format!(
                            "segment {key} is {} bytes, manifest says {}",
                            data.len(),
                            entry.size
                        ));
                    }
                }
                Err(_) => {
                    report.missing += 1;
                    if report.first_problem.is_none() {
                        report.first_problem =
                            Some(format!("segment {key} missing at {}", path.display()));
                    }
                }
            }
            if report.mismatched == 0 && report.missing == 0 {
                self.verified.insert(key.clone());
            }
        }
        if report.mismatched > 0 || report.missing > 0 {
            return Err(format!(
                "store corrupt: checked {}, mismatched {}, missing {} — {}",
                report.checked,
                report.mismatched,
                report.missing,
                report.first_problem.clone().unwrap_or_default()
            ));
        }
        Ok(report)
    }

    pub fn tensor_names(&self) -> Vec<String> {
        let mut names: Vec<String> = self
            .manifest
            .segments
            .values()
            .flat_map(|s| s.tensors.keys().cloned())
            .collect();
        names.sort();
        names
    }

    /// Point read of one tensor: verifies its segment (once), then
    /// `read_exact_at` the recorded byte span. Digest trust comes from the
    /// segment verification, so a corrupt store can never yield bytes.
    pub fn read_tensor(&mut self, name: &str) -> Result<Tensor, String> {
        let located = {
            let mut found = None;
            for (key, entry) in &self.manifest.segments {
                if let Some(t) = entry.tensors.get(name) {
                    found = Some((
                        key.clone(),
                        entry.file.clone(),
                        entry.size,
                        t.offset,
                        t.nbytes,
                        t.shape.clone(),
                        t.dtype.clone(),
                        t.role.clone(),
                    ));
                    break;
                }
            }
            found.ok_or_else(|| format!("manifest has no tensor {name}"))?
        };
        let (key, file, _size, offset, nbytes, shape, dtype, role) = located;
        self.verify_segment(&key)?;
        let path = self.dir.join(&file);
        let file_handle =
            File::open(&path).map_err(|e| format!("segment {key} unreadable: {e}"))?;
        let mut data = vec![0u8; nbytes];
        file_handle
            .read_exact_at(&mut data, offset as u64)
            .map_err(|e| format!("tensor {name} read failed: {e}"))?;
        Ok(Tensor { shape, dtype, role, data })
    }

    /// The (segment, entry) pair for a tensor, for meta reporting.
    pub fn tensor_location(&self, name: &str) -> Option<(String, usize, usize)> {
        for (key, entry) in &self.manifest.segments {
            if let Some(t) = entry.tensors.get(name) {
                return Some((key.clone(), t.offset, t.nbytes));
            }
        }
        None
    }

    pub fn tensor_meta(&self, name: &str) -> Option<&TensorEntry> {
        self.manifest
            .segments
            .values()
            .find_map(|s| s.tensors.get(name))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha256_matches_known_vectors() {
        assert_eq!(
            sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn f16_conversion_is_bit_exact_on_all_classes() {
        assert_eq!(f16_bits_to_f32(0x0000), 0.0);
        assert_eq!(f16_bits_to_f32(0x8000), -0.0);
        assert_eq!(f16_bits_to_f32(0x3c00), 1.0);
        assert_eq!(f16_bits_to_f32(0xbc00), -1.0);
        assert_eq!(f16_bits_to_f32(0x4300), 3.5);
        assert_eq!(f16_bits_to_f32(0x4248), 3.140625);
        // Smallest normal: 2^-14.
        assert_eq!(f16_bits_to_f32(0x0400), 2f32.powi(-14));
        // Smallest subnormal: 1 x 2^-24; largest: 1023 x 2^-24.
        assert_eq!(f16_bits_to_f32(0x0001), 2f32.powi(-24));
        assert_eq!(f16_bits_to_f32(0x03ff), 1023.0 * 2f32.powi(-24));
        // Subnormal sign carries.
        assert_eq!(f16_bits_to_f32(0x8001), -2f32.powi(-24));
        // Infinity and a NaN keep their classes.
        assert!(f16_bits_to_f32(0x7c00).is_infinite());
        assert!(f16_bits_to_f32(0x7e00).is_nan());
    }

    #[test]
    fn bf16_conversion_is_a_widening_shift() {
        let t = Tensor {
            shape: vec![4],
            dtype: "bfloat16".into(),
            role: "expert".into(),
            data: {
                let mut v = Vec::new();
                for bits in [0u16, 0x3f80u16, 0xbf80u16, 0x4048u16] {
                    v.extend_from_slice(&bits.to_le_bytes());
                }
                v
            },
        };
        // 0x4048 widens to f32 bits 0x40480000 = 3.125.
        assert_eq!(t.to_f32_vec().unwrap(), vec![0.0, 1.0, -1.0, 3.125]);
    }
}

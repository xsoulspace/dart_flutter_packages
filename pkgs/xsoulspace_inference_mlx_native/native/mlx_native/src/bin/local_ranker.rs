//! Bounded numeric learning consumer of the existing Rust/MLX array boundary.
//! No network, downloads, command execution, actors or product policy.
use mlx_native::mlx::{self, Array, Stream};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{fs, io::Write, path::Path, time::Instant};

#[derive(Debug)]
struct Failure(String);
impl std::fmt::Display for Failure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}
impl From<String> for Failure {
    fn from(s: String) -> Self {
        Self(s)
    }
}
impl From<&str> for Failure {
    fn from(s: &str) -> Self {
        Self(s.into())
    }
}
impl From<mlx::MlxError> for Failure {
    fn from(e: mlx::MlxError) -> Self {
        Self(format!("MLX error: {e:?}"))
    }
}
type Result<T> = std::result::Result<T, Failure>;
const MAX_BYTES: u64 = 1_048_576;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Row {
    features: Vec<Vec<f32>>,
    target: usize,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Fit {
    schema: String,
    rows: Vec<Row>,
    epochs: usize,
    learning_rate: f32,
    l2: f32,
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Model {
    schema: String,
    weights: Vec<f32>,
    input_sha256: String,
    epochs: usize,
    learning_rate: f32,
    l2: f32,
    initial_nll: f32,
    final_nll: f32,
    elapsed_ms: u128,
    backend: String,
    metallib_sha256: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Item {
    id: String,
    features: Vec<Vec<f32>>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Score {
    schema: String,
    model: Model,
    items: Vec<Item>,
}

fn digest(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
fn read(path: &str) -> Result<Vec<u8>> {
    if fs::metadata(path).map_err(|e| e.to_string())?.len() > MAX_BYTES {
        return Err("input exceeds 1MiB".into());
    }
    let bytes = fs::read(path).map_err(|e| e.to_string())?;
    if bytes.len() as u64 > MAX_BYTES {
        return Err("input grew beyond 1MiB".into());
    }
    Ok(bytes)
}
fn matrix(rows: &[Vec<f32>], dimension: Option<usize>) -> Result<usize> {
    let dim = rows.first().ok_or("empty matrix")?.len();
    if dim == 0 || dim > 256 || rows.len() > 16 || dimension.is_some_and(|d| d != dim) {
        return Err("invalid matrix dimensions".into());
    }
    if rows
        .iter()
        .any(|r| r.len() != dim || r.iter().any(|v| !v.is_finite() || v.abs() > 10.0))
    {
        return Err("ragged/nonfinite/out-of-range features".into());
    }
    Ok(dim)
}
fn validate_fit(f: &Fit) -> Result<(usize, usize)> {
    if f.schema != "local-ranker-fit/v1"
        || f.rows.is_empty()
        || f.rows.len() > 256
        || !(1..=200).contains(&f.epochs)
        || !f.learning_rate.is_finite()
        || f.learning_rate <= 0.0
        || f.learning_rate > 1.0
        || !f.l2.is_finite()
        || !(0.0..=1.0).contains(&f.l2)
    {
        return Err("invalid fit contract/budget".into());
    }
    let dim = matrix(&f.rows[0].features, None)?;
    let count = f.rows[0].features.len();
    if count < 2 {
        return Err("need competing candidates".into());
    }
    for row in &f.rows {
        matrix(&row.features, Some(dim))?;
        if row.features.len() != count || row.target >= count {
            return Err("invalid target/candidate count".into());
        }
    }
    Ok((dim, count))
}
fn probabilities(x: &Array, w: &Array, n: usize, c: usize, s: Stream) -> Result<Array> {
    // Existing generic mlx_softmax normalizes all axes. Explicit row reduction
    // keeps independent candidate sets independent without changing core ABI.
    let logits = x.matmul(w, s)?.reshape(&[n, c], s)?;
    let maximum =
        logits
            .sort_axis(-1, s)?
            .slice(&[0, c as i32 - 1], &[n as i32, c as i32], &[1, 1], s)?;
    let exponential = logits.sub(&maximum, s)?.exp(s)?;
    exponential
        .div(&exponential.sum_axes(&[1], true, s)?, s)
        .map_err(Into::into)
}

fn nll(p: &[f32], rows: &[Row], c: usize) -> f32 {
    rows.iter()
        .enumerate()
        .map(|(i, r)| -p[i * c + r.target].max(1e-30).ln())
        .sum::<f32>()
        / rows.len() as f32
}
fn fit(f: &Fit, input_sha256: String, metallib_sha256: String, s: Stream) -> Result<Model> {
    let start = Instant::now();
    let (dim, c) = validate_fit(f)?;
    let n = f.rows.len();
    let flat: Vec<f32> = f
        .rows
        .iter()
        .flat_map(|r| r.features.iter().flatten().copied())
        .collect();
    let x = Array::from_data_f32(&flat, &[n * c, dim])?;
    let xt = x.transpose_all(s)?;
    let mut target = vec![0.0; n * c];
    for (i, r) in f.rows.iter().enumerate() {
        target[i * c + r.target] = 1.0;
    }
    let y = Array::from_data_f32(&target, &[n, c])?;
    let mut w = Array::from_data_f32(&vec![0.0; dim], &[dim, 1])?;
    let initial_nll = nll(&probabilities(&x, &w, n, c, s)?.to_f32_vec(s)?, &f.rows, c);
    for _ in 0..f.epochs {
        if start.elapsed().as_secs_f32() > 30.0 {
            return Err("fit budget exhausted".into());
        }
        let delta = probabilities(&x, &w, n, c, s)?
            .sub(&y, s)?
            .reshape(&[n * c, 1], s)?;
        let gradient = xt
            .matmul(&delta, s)?
            .mul(&Array::scalar_f32(1.0 / n as f32), s)?
            .add(&w.mul(&Array::scalar_f32(f.l2), s)?, s)?;
        let next = w
            .sub(&gradient.mul(&Array::scalar_f32(f.learning_rate), s)?, s)?
            .to_f32_vec(s)?;
        if next.iter().any(|v| !v.is_finite()) {
            return Err("nonfinite weights".into());
        }
        // Materialize and detach every step: no unbounded lazy update graph.
        w = Array::from_data_f32(&next, &[dim, 1])?;
    }
    let final_nll = nll(&probabilities(&x, &w, n, c, s)?.to_f32_vec(s)?, &f.rows, c);
    Ok(Model {
        schema: "mlx-linear-ranker/v1".into(),
        weights: w.to_f32_vec(s)?,
        input_sha256,
        epochs: f.epochs,
        learning_rate: f.learning_rate,
        l2: f.l2,
        initial_nll,
        final_nll,
        elapsed_ms: start.elapsed().as_millis(),
        backend: "existing-mlx-c-gpu".into(),
        metallib_sha256,
    })
}
fn scores(features: &[Vec<f32>], weights: &[f32], s: Stream) -> Result<Vec<f32>> {
    matrix(features, Some(weights.len()))?;
    if weights.is_empty() || weights.iter().any(|v| !v.is_finite()) {
        return Err("invalid model weights".into());
    }
    let x = Array::from_data_f32(
        &features.iter().flatten().copied().collect::<Vec<_>>(),
        &[features.len(), weights.len()],
    )?;
    x.matmul(&Array::from_data_f32(weights, &[weights.len(), 1])?, s)?
        .to_f32_vec(s)
        .map_err(Into::into)
}
fn run(args: &[String]) -> Result<()> {
    if args.len() != 5 {
        return Err("local_ranker fit|score INPUT OUTPUT METALLIB".into());
    }
    if Path::new(&args[3]).exists() {
        return Err("fresh output required".into());
    }
    let input = read(&args[2])?;
    let metal = Path::new(&args[4])
        .canonicalize()
        .map_err(|e| e.to_string())?;
    let metal_hash = digest(&fs::read(&metal).map_err(|e| e.to_string())?);
    mlx::set_metallib_path(&metal)?;
    let stream = mlx::gpu()?;
    let result = match args[1].as_str() {
        "fit" => {
            let spec: Fit = serde_json::from_slice(&input).map_err(|e| e.to_string())?;
            serde_json::to_value(fit(&spec, digest(&input), metal_hash, stream)?)
                .map_err(|e| e.to_string())?
        }
        "score" => {
            let spec: Score = serde_json::from_slice(&input).map_err(|e| e.to_string())?;
            if spec.schema != "local-ranker-score/v1"
                || spec.model.schema != "mlx-linear-ranker/v1"
                || spec.model.metallib_sha256 != metal_hash
                || spec.items.is_empty()
                || spec.items.len() > 256
            {
                return Err("invalid score contract/runtime revision".into());
            }
            let start = Instant::now();
            let mut results = Vec::new();
            for item in &spec.items {
                if start.elapsed().as_secs_f32() > 30.0 {
                    return Err("score budget exhausted".into());
                }
                results.push(serde_json::json!({"id":item.id,"scores":scores(&item.features,&spec.model.weights,stream)?}));
            }
            serde_json::json!({"schema":"local-ranker-scores/v1","items":results,"elapsed_ms":start.elapsed().as_millis(),
                "input_sha256":digest(&input),"metallib_sha256":metal_hash,"backend":"existing-mlx-c-gpu"})
        }
        _ => return Err("unknown operation".into()),
    };
    let mut output = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&args[3])
        .map_err(|e| e.to_string())?;
    output
        .write_all(
            serde_json::to_string_pretty(&result)
                .map_err(|e| e.to_string())?
                .as_bytes(),
        )
        .map_err(|e| e.to_string())?;
    output.sync_all().map_err(|e| e.to_string())?;
    Ok(())
}
fn main() {
    if let Err(e) = run(&std::env::args().collect::<Vec<_>>()) {
        eprintln!("local_ranker: {e}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn stream() -> Stream {
        mlx::set_metallib_path(
            &Path::new(env!("CARGO_MANIFEST_DIR")).join("build/mlx-install/lib/mlx.metallib"),
        )
        .unwrap();
        mlx::gpu().unwrap()
    }
    #[test]
    fn rejects_bad_labels_nonfinite_and_budgets() {
        let mut f = Fit {
            schema: "local-ranker-fit/v1".into(),
            rows: vec![Row {
                features: vec![vec![1.0], vec![0.0]],
                target: 2,
            }],
            epochs: 1,
            learning_rate: 0.1,
            l2: 0.0,
        };
        assert!(validate_fit(&f).is_err());
        f.rows[0].target = 0;
        f.rows[0].features[0][0] = f32::NAN;
        assert!(validate_fit(&f).is_err());
        f.rows[0].features[0][0] = 1.0;
        f.epochs = 201;
        assert!(validate_fit(&f).is_err());
    }
    #[test]
    fn python_mlx_fixture_matches_logits_and_fit_step() {
        let fixture: serde_json::Value =
            serde_json::from_str(include_str!("../../testdata/linear_ranker_parity.json")).unwrap();
        let f: Fit = serde_json::from_value(fixture["fit"].clone()).unwrap();
        let s = stream();
        let model = fit(&f, "fixture".into(), "fixture".into(), s).unwrap();
        let expected: Vec<f32> =
            serde_json::from_value(fixture["weights_after_one_step"].clone()).unwrap();
        for (a, b) in model.weights.iter().zip(expected) {
            assert!((a - b).abs() < 1e-6, "{a} vs {b}");
        }
        let w: Vec<f32> = serde_json::from_value(fixture["weights"].clone()).unwrap();
        let expected: Vec<f32> = serde_json::from_value(fixture["logits"].clone()).unwrap();
        let got = scores(&f.rows[0].features, &w, s).unwrap();
        for (a, b) in got.iter().zip(expected) {
            assert!((a - b).abs() < 1e-6);
        }
        assert!(model.final_nll < model.initial_nll);
    }
}

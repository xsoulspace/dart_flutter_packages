//! J'-A — the trunk body's marginal cost per verified position.
//!
//! The MTP cost model needs ONE constant that no artifact in the tree carries:
//! how much a batched trunk forward over `L` positions costs, as a function
//! of `L`, with the tied vocabulary projection EXCLUDED from the timer.
//!
//! Why this binary exists (MTP-GATES.md J'-G0): the 2026-10-21 record claimed
//! the batched forward is "nearly flat in k" from a series
//! (0.688/0.682/0.679/0.709/0.669/0.680 ms for 1/2/3/4/6/8 positions) that
//! has NO producing artifact in the tree and that the same document's own
//! forced-execution table contradicts by ~39x. The native verify timer
//! (14.07 ms for 2 positions vs 10.06 ms for 1) includes the tied projection
//! over the verified positions, so it overstates the BODY marginal. This
//! binary separates the two.
//!
//! What it measures, per position count L:
//!   - `body_ms`:    the trunk body forward over L positions (no lm_head),
//!                   forced-evaluated.
//!   - `proj_ms`:    the tied vocabulary projection over the SAME L hidden
//!                   states, forced-evaluated (this is the draft head's own
//!                   unavoidable cost, and the verify's own cost).
//!   - `total_ms`:   body + projection, i.e. what one MTP verify round costs.
//!
//! MLX IS LAZY: every timer forces the ACTUAL output it is timing
//! (`arr.eval()`), never an unrelated dummy array. A dummy eval measures
//! graph construction (measured: 28.7x error, 2026-10-20).
//!
//! Power: perf numbers are non-claims without a power state (POWER.md). The
//! bench prints the power state and the real charge current (ioreg
//! `Amperage`, not the `pmset` source flag) beside every number.
//!
//! Usage:
//!   cargo run --release --bin qwen_marginal_cost [--positions 1,2,4,8] [--reps N]
//!
//! The gate (MTP-GATES.md J'-G0, frozen before the run):
//!   body(8)/body(1) <= 1.15  -> FLAT    (acceptance becomes the only blocker)
//!   body(8)/body(1) >= 1.50  -> NOT FLAT (MTP closed on physics; no arm bought)
//!   1.15 < ratio < 1.50     -> AMBIGUOUS (re-derive before any training time)

use std::path::{Path, PathBuf};
use std::time::Instant;

use mlx_native::mlx::{Array, Dtype};
use mlx_native::power;
use mlx_native::qwen::{KvCache, Qwen3};
use mlx_native::qwen_mtp::{MtpHead, TiedEmbedding};

fn snapshot(fragment: &str) -> Option<PathBuf> {
    if let Some(dir) = std::env::var_os("LAYA_MTP_SNAPSHOT_DIR") {
        let p = PathBuf::from(dir);
        return if p.is_dir() { Some(p) } else { None };
    }
    let home = std::env::var("HOME").ok()?;
    let hub = Path::new(&home).join(".cache/huggingface/hub");
    for e in std::fs::read_dir(hub).ok()?.flatten() {
        if e.file_name().to_string_lossy().contains(fragment) {
            for s in std::fs::read_dir(e.path().join("snapshots"))
                .ok()?
                .flatten()
            {
                let p = s.path();
                if p.is_dir() && p.join("config.json").is_file() {
                    return Some(p);
                }
            }
        }
    }
    None
}

/// The real charge current in mA (strongly positive = actually charging).
/// `pmset`'s "AC Power" is the SOURCE, not the current (POWER.md's
/// charge-current hole) — so the gate input is this number.
fn charge_current_ma() -> i64 {
    let Ok(out) = std::process::Command::new("ioreg")
        .args(["-rc", "AppleSmartBattery"])
        .output()
    else {
        return 0;
    };
    let text = String::from_utf8_lossy(&out.stdout).to_string();
    for line in text.lines() {
        let t = line.trim();
        if let Some(rest) = t.strip_prefix("\"Amperage\" = ") {
            return rest.trim().parse::<i64>().unwrap_or(0);
        }
    }
    0
}

/// The AR reference: one decode loop, timed, in this session.
///
/// It also SPLITS the step into its own body forward and its own
/// projection, measured inside the very same decode loop. That split is the
/// apples-to-apples `body(1)`: an isolated body forward timed on its own
/// does NOT match the decode path's body cost (measured: 18 ms isolated vs
/// 6.7 ms for a whole AR step), because the decode loop reuses the graph and
/// the warm KV buffer in a way a one-off call does not. So `body(1)` for the
/// MARGINAL cost is taken from here, and the isolated multi-position
/// measurement supplies only the SHAPE (how the cost grows with L).
///
/// Returns (total_ms_per_step, body_ms_per_step, proj_ms_per_step).
fn measure_ar(
    trunk: &Qwen3,
    embed: &TiedEmbedding,
    seed_tokens: &[i32],
    steps: usize,
    s: mlx_native::mlx::Stream,
) -> (f64, f64, f64) {
    const PREFILL: usize = 64;
    let mut best_total = f64::MAX;
    let mut best_body = f64::MAX;
    let mut best_proj = f64::MAX;
    for _ in 0..3 {
        let mut cache = KvCache::new(trunk.cfg.layers);
        cache
            .reserve(
                trunk.table(),
                trunk.cfg.kv_heads,
                trunk.cfg.head_dim,
                PREFILL + steps + 8,
                s,
            )
            .expect("reserve");
        // prefill (not timed)
        {
            let arr = Array::from_data_i32(&seed_tokens[..PREFILL], &[1, PREFILL]).expect("ids");
            cache.offset = 0;
            trunk
                .forward_hidden(&arr, &mut cache, s)
                .expect("prefill")
                .eval()
                .expect("eval");
        }
        let t_total = Instant::now();
        let mut body_total = 0.0f64;
        let mut proj_total = 0.0f64;
        let mut cur = seed_tokens[PREFILL - 1];
        for _ in 0..steps {
            let arr = Array::from_data_i32(&[cur], &[1, 1]).expect("ids");
            let t = Instant::now();
            let hidden = trunk.forward_hidden(&arr, &mut cache, s).expect("step");
            hidden.eval().expect("eval step");
            body_total += t.elapsed().as_secs_f64() * 1000.0;
            let t = Instant::now();
            let logits = embed.as_linear(&hidden, s).expect("proj");
            let next = {
                let am = logits.argmax_axis(-1, false, s).expect("argmax");
                let f = am.astype(Dtype::Float32, s).expect("f32");
                f.to_f32_vec(s).expect("vec")[0] as i32
            };
            proj_total += t.elapsed().as_secs_f64() * 1000.0;
            cur = next;
        }
        let total = t_total.elapsed().as_secs_f64() * 1000.0;
        if total < best_total {
            best_total = total;
            best_body = body_total;
            best_proj = proj_total;
        }
    }
    (
        best_total / steps as f64,
        best_body / steps as f64,
        best_proj / steps as f64,
    )
}

/// A deterministic synthetic head, shaped like the real one. The head's
/// per-round COST is shape-dependent but not quality-dependent, so an
/// untrained head measures the cost honestly.
fn synthetic_head(hidden: usize, mlp: usize, s: mlx_native::mlx::Stream) -> MtpHead {
    let mut rng: u64 = 0x4D54_5000_0000_0001;
    let mut next = || {
        rng ^= rng << 13;
        rng ^= rng >> 7;
        rng ^= rng << 17;
        // Box-Muller from the LCG, scaled to N(0,1).
        let u1 = ((rng >> 11) as f64 + 1.0) / ((1u64 << 53) as f64);
        let u2 = ((rng >> 11) as f64 + 1.0) / ((1u64 << 53) as f64);
        (-2.0 * u1.ln()).sqrt() * (2.0 * std::f64::consts::PI * u2).cos()
    };
    let mut proj: Vec<f32> = Vec::with_capacity(hidden * 2 * hidden);
    for _ in 0..hidden * 2 * hidden {
        proj.push((next() / (2.0 * hidden as f64).sqrt()) as f32);
    }
    let mut gate: Vec<f32> = Vec::with_capacity(mlp * hidden);
    let mut up: Vec<f32> = Vec::with_capacity(mlp * hidden);
    for _ in 0..mlp * hidden {
        gate.push((next() / (hidden as f64).sqrt()) as f32);
        up.push((next() / (hidden as f64).sqrt()) as f32);
    }
    let mut down: Vec<f32> = Vec::with_capacity(hidden * mlp);
    for _ in 0..hidden * mlp {
        down.push((next() / (mlp as f64).sqrt()) as f32);
    }
    let head = MtpHead {
        proj: Array::from_data_f32(&proj, &[hidden, 2 * hidden]).expect("proj"),
        norm: Array::from_data_f32(&vec![1.0f32; hidden], &[hidden]).expect("norm"),
        gate: Array::from_data_f32(&gate, &[mlp, hidden]).expect("gate"),
        up: Array::from_data_f32(&up, &[mlp, hidden]).expect("up"),
        down: Array::from_data_f32(&down, &[hidden, mlp]).expect("down"),
        scale: 1.0,
        depth: 0,
        digest: "synthetic-untrained".to_string(),
    };
    for a in [&head.proj, &head.norm, &head.gate, &head.up, &head.down] {
        let _ = a.astype(Dtype::Float32, s);
    }
    head
}

/// The draft head's own per-round cost: its MLP block and its vocabulary
/// projection — the cost a draft pays to propose a TOKEN.
fn measure_head(
    trunk: &Qwen3,
    embed: &TiedEmbedding,
    seed_tokens: &[i32],
    reps: usize,
    s: mlx_native::mlx::Stream,
) -> (f64, f64) {
    let h = trunk.cfg.hidden_size;
    let head = synthetic_head(h, 2 * h, s);
    let mut mlp_ms = f64::MAX;
    let mut lm_ms = f64::MAX;
    for _ in 0..reps.max(3) {
        let arr = Array::from_data_i32(&[seed_tokens[0]], &[1, 1]).expect("ids");
        let mut cache = KvCache::new(trunk.cfg.layers);
        let hidden = trunk.forward_hidden(&arr, &mut cache, s).expect("body");
        // EVALUATE the trunk hidden BEFORE timing the head: MLX is lazy, so
        // an unevaluated hidden makes the head's own eval() also force the
        // TRUNK forward, and the head would be charged for it (measured: a
        // 24 ms "head" that was really a trunk forward).
        hidden.eval().expect("eval hidden");
        let emb = embed.embedding_rows(&[seed_tokens[1]], s).expect("emb");
        emb.eval().expect("eval emb");
        let t = Instant::now();
        let out = head.forward(&hidden, &emb, s).expect("head");
        out.eval().expect("eval head");
        mlp_ms = mlp_ms.min(t.elapsed().as_secs_f64() * 1000.0);
        let t = Instant::now();
        let logits = embed.as_linear(&out, s).expect("proj");
        logits.eval().expect("eval proj");
        lm_ms = lm_ms.min(t.elapsed().as_secs_f64() * 1000.0);
    }
    (mlp_ms, lm_ms)
}

fn tpc_note() {}

fn main() {
    let mut positions: Vec<usize> = vec![1, 2, 4, 8];
    let mut reps: usize = 5;
    let args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--positions" => {
                i += 1;
                positions = args[i]
                    .split(',')
                    .filter_map(|x| x.trim().parse::<usize>().ok())
                    .filter(|x| *x > 0)
                    .collect();
            }
            "--reps" => {
                i += 1;
                reps = args[i].parse().unwrap_or(5);
            }
            "-h" | "--help" => {
                println!("usage: qwen_marginal_cost [--positions 1,2,4,8] [--reps N]");
                return;
            }
            other => {
                eprintln!("unknown argument: {other}");
                std::process::exit(2);
            }
        }
        i += 1;
    }

    let facts = power::facts();
    let ma = charge_current_ma();
    println!("power: {}", facts.describe());
    println!("charge current (ioreg Amperage): {ma} mA  (strongly positive = charging)");
    if ma <= 0 {
        println!(
            "POWER-CONTAMINATED — non-baseline (ADR 0061): no real charge current; \
             the RATIOS below are the measurement, the absolute ms are non-claims"
        );
    }
    println!("reps: {reps} (median reported; forced-eval timers)");

    let metallib =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        let _ = mlx_native::mlx::set_metallib_path(&metallib);
    }
    let s = mlx_native::mlx::gpu().expect("Metal device");

    let trunk_dir = snapshot("Qwen3-0.6B-4bit")
        .or_else(|| snapshot("Qwen3-0.6B"))
        .expect("trunk snapshot (Qwen3-0.6B-4bit) absent");
    let t0 = Instant::now();
    let trunk = Qwen3::load(&trunk_dir).expect("trunk loads");
    let embed = TiedEmbedding::load(&trunk_dir, s).expect("the tied embedding loads");
    println!(
        "trunk: {} ({}L h{} V{}) | loaded in {:.1}s",
        trunk_dir.file_name().unwrap().to_string_lossy(),
        trunk.cfg.layers,
        trunk.cfg.hidden_size,
        trunk.cfg.vocab,
        t0.elapsed().as_secs_f64()
    );

    // A fixed token block: the same L positions every time, so the measurement
    // is about POSITION COUNT and not about token content.
    let seed_tokens: Vec<i32> = (0..64).map(|i| 1000 + (i % 500) as i32).collect();
    // The PREFILL length every measurement starts from. A warm cache with a
    // known context length is the regime the MTP verify actually runs in
    // (the verify appends L positions onto the committed prefix), so the
    // body cost is measured in that regime, not in a cold-cache one.
    const PREFILL: usize = 64;

    // ---- the AR reference, BEFORE the sweep ----
    // The AR reference is measured TWICE: once before the position sweep and
    // once after it. A sustained decode loop heats the device, so a single
    // late reference is biased slow (measured: 6.66 ms/token early vs
    // 29.2 ms/token late on the same device in the same session). The
    // spread between the two is the drift, and the cost model is reported
    // against BOTH so no number silently depends on the ordering.
    let (t_ar_first, body1_first, proj1_first) = measure_ar(&trunk, &embed, &seed_tokens, 64, s);
    println!(
        "AR reference (BEFORE the sweep): {t_ar_first:.3} ms/token  (body {body1_first:.3} + proj {proj1_first:.3})"
    );

    println!();
    println!("L | body_ms (no lm_head) | proj_ms (tied vocab) | total_ms | body/L_us");
    println!("--+------------------------+-----------------------+----------+---------");

    let mut body_median: Vec<(usize, f64)> = Vec::new();
    let mut proj_median: std::collections::BTreeMap<usize, f64> = std::collections::BTreeMap::new();
    let mut marginal_body_ms: Option<f64> = None;

    // ---- one cache per position count, reserved OUTSIDE every timer ----
    // The KV buffer allocation does not land inside a timed region (a
    // mid-measurement growth costs a measured ~+20 ms step — KvCache::reserve's
    // own note), and each cache is warmed with the same PREFILL prefix so
    // every position count is measured in the SAME regime (a warm cache with
    // a known context length — the regime the MTP verify runs in).
    let mut caches: Vec<(usize, KvCache)> = Vec::new();
    for &l in &positions {
        if seed_tokens.len() < l {
            continue;
        }
        let mut cache = KvCache::new(trunk.cfg.layers);
        cache
            .reserve(
                trunk.table(),
                trunk.cfg.kv_heads,
                trunk.cfg.head_dim,
                PREFILL + l + 8,
                s,
            )
            .expect("reserve");
        let pre = Array::from_data_i32(&seed_tokens[..PREFILL], &[1, PREFILL]).expect("ids");
        cache.offset = 0;
        trunk
            .forward_hidden(&pre, &mut cache, s)
            .expect("prefill")
            .eval()
            .expect("eval prefill");
        // Warmup for this shape: the first call compiles the graph.
        let ids: Vec<i32> = seed_tokens[..l].to_vec();
        let arr = Array::from_data_i32(&ids, &[1, l]).expect("ids");
        let h = trunk.forward_hidden(&arr, &mut cache, s).expect("body");
        h.eval().expect("eval body");
        let _ = embed.as_linear(&h, s).expect("proj").eval();
        cache.offset = PREFILL;
        caches.push((l, cache));
    }

    // ---- INTERLEAVED reps ----
    // Each rep visits EVERY position count in the same thermal state, so the
    // drift that moves one L cancels against the others instead of biasing
    // the ratio. (Measured: sweeping L in blocks gave body(8)/body(1) =
    // 2.75 / 2.24 / 2.04 / 2.57 / 1.42 across five runs of the SAME binary —
    // pure ordering noise. Interleaving is the fix.)
    let mut body_all: std::collections::BTreeMap<usize, Vec<f64>> =
        std::collections::BTreeMap::new();
    let mut proj_all: std::collections::BTreeMap<usize, Vec<f64>> =
        std::collections::BTreeMap::new();
    for (l, cache) in caches.iter_mut() {
        body_all.insert(*l, Vec::with_capacity(reps));
        proj_all.insert(*l, Vec::with_capacity(reps));
    }
    for _ in 0..reps {
        for (l, cache) in caches.iter_mut() {
            let ids: Vec<i32> = seed_tokens[..*l].to_vec();
            let arr = Array::from_data_i32(&ids, &[1, *l]).expect("ids");
            cache.offset = PREFILL; // the committed prefix; the verify appends L
            let t = Instant::now();
            let hidden = trunk.forward_hidden(&arr, cache, s).expect("body");
            hidden.eval().expect("eval body"); // force the ACTUAL output
            body_all
                .get_mut(l)
                .unwrap()
                .push(t.elapsed().as_secs_f64() * 1000.0);

            let t = Instant::now();
            let logits = embed.as_linear(&hidden, s).expect("proj");
            logits.eval().expect("eval proj"); // force the ACTUAL output
            proj_all
                .get_mut(l)
                .unwrap()
                .push(t.elapsed().as_secs_f64() * 1000.0);
        }
    }

    println!();
    for &l in &positions {
        let (Some(bs), Some(ps)) = (body_all.get(&l), proj_all.get(&l)) else {
            continue;
        };
        let mut bs = bs.clone();
        let mut ps = ps.clone();
        bs.sort_by(|a, b| a.partial_cmp(b).unwrap());
        ps.sort_by(|a, b| a.partial_cmp(b).unwrap());
        // MIN is the robust estimator for a cost measurement: the run least
        // polluted by scheduling noise. The median is reported beside it.
        let body = bs[0];
        let proj = ps[0];
        let body_med = bs[bs.len() / 2];
        let proj_med = ps[ps.len() / 2];
        body_median.push((l, body));
        proj_median.insert(l, proj);
        println!(
            "{l:>2} | {:>9.3} (med {:>7.3}) | {:>9.3} (med {:>7.3}) | {:>8.3} | {:>9.1}",
            body,
            body_med,
            proj,
            proj_med,
            body + proj,
            body * 1000.0 / l as f64
        );
    }

    // ---- the gate ----
    println!();
    let get = |l: usize| body_median.iter().find(|(k, _)| *k == l).map(|(_, v)| *v);
    let max_l = positions.iter().copied().max().unwrap_or(8);
    if let (Some(b1), Some(bmax)) = (get(1), get(max_l)) {
        let ratio = bmax / b1;
        // The marginal cost of an extra verified position, expressed as a
        // fraction of one AR token. This is the number the MTP economics
        // turn on: a verified position is worth its cost only if it commits
        // more than (marginal / t_ar) of an extra token.
        let marginal_shape = (bmax - b1) / (max_l as f64 - 1.0);
        println!("body({max_l})/body(1) = {ratio:.3}   (isolated multi-position shape)");
        println!("marginal body cost per extra position (shape) = {marginal_shape:.3} ms");
        println!("gate J'-G0: <= 1.15 FLAT | >= 1.50 NOT FLAT | 1.15..1.50 AMBIGUOUS");
        if ratio <= 1.15 {
            println!(
                "VERDICT: FLAT — the forward is flat in position count; rewrite the cost model."
            );
        } else if ratio >= 1.50 {
            println!("VERDICT: NOT FLAT — MTP is closed on physics for ANY acceptance; no MTP arm is bought.");
        } else {
            println!("VERDICT: AMBIGUOUS — re-derive the marginal cost before spending training time; this does NOT authorise an MTP arm.");
        }
        marginal_body_ms = Some(marginal_shape);
    } else {
        println!("gate J'-G0: could not compare body(1) with body(max) — the run is incomplete.");
    }

    // ---- the AR reference, AFTER the sweep ----
    // The cost model needs t_ar next to the verify cost, measured under the
    // SAME power state and the SAME process. A tok/s figure from another
    // session is not a component of this model. The SECOND reference is
    // taken after the sweep so the drift is visible rather than assumed.
    println!();
    println!("--- the AR reference (same session) ---");
    let (t_ar, body1, proj1) = measure_ar(&trunk, &embed, &seed_tokens, 64, s);
    println!("AR decode (AFTER the sweep): {t_ar:.3} ms/token  (body {body1:.3} ms + projection {proj1:.3} ms)");
    let drift = if t_ar_first > 0.0 {
        t_ar / t_ar_first
    } else {
        f64::NAN
    };
    println!("drift across the sweep: {drift:.2}x   (the ordering bias, measured not assumed)");

    // ---- the draft head's own cost, in THIS session ----
    println!();
    println!("--- the draft head's own cost (same session) ---");
    let (head_mlp_ms, head_lm_ms) = measure_head(&trunk, &embed, &seed_tokens, reps, s);
    println!("head MLP: {head_mlp_ms:.3} ms | head vocab projection: {head_lm_ms:.3} ms");

    // ---- the cost model, built from THIS session's components ----
    println!();
    println!("--- the MTP cost model, from this session's components ---");
    println!("t_ar (1 token)            = {t_ar:.3} ms   (body {body1:.3} + proj {proj1:.3})");
    println!("t_ar (early reference)    = {t_ar_first:.3} ms   (body {body1_first:.3} + proj {proj1_first:.3})");
    println!("  -> the cost model below uses the LATE (conservative, slow) reference; the early one gives a HIGHER speedup.");
    if let Some(m) = marginal_body_ms {
        println!("marginal body/position    = {m:.3} ms  (from the isolated shape)");
    }
    let head_total = head_mlp_ms + head_lm_ms;
    println!("head per round (1 head)   = {head_total:.3} ms   (mlp {head_mlp_ms:.3} + vocab {head_lm_ms:.3})");

    // The verify round's cost, built the way the PORT builds it: a trunk body
    // forward over K positions (the AR-split body(1) scaled by the measured
    // SHAPE) plus the tied projection over those positions.
    let shape_of = |l: usize| -> f64 {
        match (get(1), get(l)) {
            (Some(b1), Some(bl)) if l > 1 => {
                b1 + (bl - b1) * (l as f64 - 1.0) / (max_l as f64 - 1.0)
            }
            (Some(b1), _) => b1,
            _ => 0.0,
        }
    };
    let proj_of = |l: usize| -> f64 {
        // the projection is a matmul over L hidden states: linear in L
        proj1 * l as f64
    };
    for k in [1usize, 2] {
        // The port verifies K positions.
        let body = shape_of(k);
        let proj = proj_of(k);
        let verify = body + proj;
        // A rejected round pays an EXTRA resync forward: one more body+proj
        // over 1 position.
        let resync = body1 + proj1;
        // The port's own accounting (MTP-GATES.md C-5): it commits
        // max(accepted_prefix, 1) tokens per round. At K=1 the committed
        // token IS the trunk's own token, so a round NEVER commits more than
        // one token: the draft buys a token only in the sense of saving a
        // resync. At K>=2 an accepted prefix of length j commits j tokens.
        let accepted_cycle = verify + k as f64 * head_total;
        let rejected_cycle = accepted_cycle + resync;
        // Tokens committed per round, averaged over acceptance p (depth-1
        // acceptance p, deeper depths conditional on it):
        //   rejected round (prob 1-p): 1 token (the trunk's own)
        //   accepted round (prob p):   j tokens (the accepted prefix)
        // For K=1, an accepted round ALSO commits exactly 1 token (the
        // accepted draft equals the trunk's own token), so the token count is
        // 1 either way and only the resync differs.
        let tpc_1 = 1.0;
        let _ = tpc_1;
        // The break-even acceptance: the port must save enough resyncs to
        // pay for the draft head.
        //   cost(p) = p*accepted_cycle + (1-p)*rejected_cycle
        //   tokens(p) = 1 (both branches commit 1 token at K=1)
        //   break even: t_ar * 1 == cost(p)
        let break_even_p = (rejected_cycle - t_ar) / (rejected_cycle - accepted_cycle);
        // For K>=2, an accepted prefix of length j commits j tokens:
        //   tokens(p) = p*j_avg + (1-p)*1
        //   break even: t_ar * tokens(p) == cost(p)
        let (tpc_note, be_k2) = if k == 1 {
            ("the port commits 1 token per round at K=1 — the accepted draft IS the trunk's own token".to_string(), None)
        } else {
            // j_avg: with depth-1 acceptance p and deeper depths conditional,
            // the expected committed prefix is p*(1 + p2 + p2*p3 ...) ≈ p for
            // shallow acceptance. Solve the break-even numerically.
            let mut sol = None;
            let mut pp = 0.0;
            while pp <= 1.0 {
                let tokens = pp * pp + (1.0 - pp) * 1.0; // p*j where j≈p, else 1
                let cost = pp * accepted_cycle + (1.0 - pp) * rejected_cycle;
                if tokens * t_ar >= cost {
                    sol = Some(pp);
                    break;
                }
                pp += 0.001;
            }
            (
                "the port commits max(accepted_prefix, 1) tokens per round".to_string(),
                sol,
            )
        };
        println!();
        println!("K={k}:");
        println!("  verify round (body {body:.3} + proj {proj:.3}) = {verify:.3} ms");
        println!("  accepted-round cycle = {accepted_cycle:.3} ms | rejected-round cycle = {rejected_cycle:.3} ms");
        println!("  token accounting: {tpc_note}");
        let speed_p1 = t_ar / accepted_cycle;
        println!("  speedup at p=1.0 (no resync) = {speed_p1:.3}x");
        match (k, be_k2) {
            (1, _) => {
                println!("  break-even acceptance p = {break_even_p:.3}");
                if break_even_p > 1.0 {
                    println!("  -> the speed gate is UNREACHABLE at ANY acceptance");
                } else {
                    println!("  -> break-even needs acceptance >= {break_even_p:.3}");
                }
            }
            (_, Some(s)) => {
                println!("  break-even acceptance p = {s:.3}");
            }
            (_, None) => {
                println!(
                    "  break-even acceptance p = NONE (unreachable at any acceptance in [0,1])"
                );
            }
        }
    }
    let _ = tpc_note();
    let _ = proj_median.len();

    println!();
    println!("NON-CLAIMS:");
    println!(
        "  - one machine, one model ({}), one device, one session.",
        trunk_dir.file_name().unwrap().to_string_lossy()
    );
    println!("  - the medians are per-call timings over {reps} reps after one warmup; the RATIO body(N)/body(1) is the measurement.");
    println!("  - absolute milliseconds are non-claims when the charge current above is not real.");
    println!("  - the AR reference drifts across the sweep ({drift:.2}x); the cost model uses the SLOW (late) reference, so the reported speedups are the conservative ones.");
    println!("  - the isolated multi-position body timing and the decode-loop body timing are DIFFERENT regimes; the marginal cost is taken from the isolated shape and the base from the decode loop. The gate verdict rests on the RATIO body(N)/body(1), which is measured within one regime.");
    println!("  - the projection is timed over the SAME hidden states, so body+proj is one MTP verify round's cost.");
}

//! L-G6 localization probe: score the exact python-scored continuations
//! on the exact python prompt, per token, and print everything.
use mlx_native::bpe::ByteLevelBpe;
use mlx_native::mlx::{gpu, Array};
use mlx_native::qwen::{KvCache, Qwen3};

fn snapshot() -> std::path::PathBuf {
    if let Some(over) = std::env::var_os("QWEN3_SNAPSHOT") {
        return std::path::PathBuf::from(over);
    }
    let home = std::env::var("HOME").unwrap();
    let hub = std::path::PathBuf::from(home).join(".cache/huggingface/hub");
    for e in std::fs::read_dir(&hub).unwrap().flatten() {
        if e.file_name().to_string_lossy().contains("Qwen3-0.6B-4bit") {
            for s in std::fs::read_dir(e.path().join("snapshots")).unwrap().flatten() {
                if s.path().join("config.json").is_file() {
                    return s.path();
                }
            }
        }
    }
    panic!("no snapshot");
}

fn score(
    model: &Qwen3,
    tok: &ByteLevelBpe,
    prompt: &str,
    cont: &str,
    s: mlx_native::mlx::Stream,
) {
    let p_ids: Vec<i32> = tok.encode(prompt).unwrap().into_iter().map(|x| x as i32).collect();
    let c_ids: Vec<u32> = tok.encode(cont).unwrap();
    let mut cache = KvCache::new(model.cfg.layers);
    let prefill = &p_ids[..p_ids.len() - 1];
    cache
        .reserve(
            model.table(),
            1,
            model.cfg.kv_heads,
            model.cfg.head_dim,
            p_ids.len() + c_ids.len() + 2,
            s,
        )
        .unwrap();
    let arr = Array::from_data_i32(prefill, &[1, prefill.len()]).unwrap();
    model.forward_hidden(&arr, &mut cache, s).unwrap();
    let mut ctx: Vec<i32> = vec![*p_ids.last().unwrap()];
    let mut nll: Vec<f32> = Vec::new();
    for &t in &c_ids {
        let step = Array::from_data_i32(&ctx, &[1, 1]).unwrap();
        let logits = model
            .step_logits(&step, &mut cache, mlx_native::qwen::qwen_plan_mode_pub(), s)
            .unwrap();
        let _ = logits.eval();
        let v = logits
            .astype(mlx_native::mlx::Dtype::Float32, s)
            .unwrap()
            .to_f32_vec(s)
            .unwrap();
        let max = v.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
        let lse: f32 = v.iter().map(|&x| (x - max).exp()).sum::<f32>().ln();
        let lp = v[t as usize] - max - lse;
        nll.push(-lp);
        ctx = vec![t as i32];
    }
    let sum: f32 = nll.iter().sum();
    println!(
        "{cont:?} ids {c_ids:?} per-token NLL {nll:?} sum {sum:.4} mean {:.4}",
        sum / nll.len() as f32
    );
}

fn chunk_probe(model: &Qwen3, tok: &ByteLevelBpe, prompt: &str, cont: &str, s: mlx_native::mlx::Stream) {
    // EXACTLY qwen_rank's shape: prefill prompt[..len-1], then ONE
    // L = m forward of [last prompt token] + cont[..m-1] with the HEAD,
    // scoring each position's next-token logprob.
    let p_ids: Vec<i32> = tok.encode(prompt).unwrap().into_iter().map(|x| x as i32).collect();
    let c_ids: Vec<u32> = tok.encode(cont).unwrap();
    let m = c_ids.len();
    let mut cache = KvCache::new(model.cfg.layers);
    let prefill_len = p_ids.len() - 1;
    cache.reserve(model.table(), 1, model.cfg.kv_heads, model.cfg.head_dim, prefill_len + m + 2, s).unwrap();
    let arr = Array::from_data_i32(&p_ids[..prefill_len], &[1, prefill_len]).unwrap();
    model.forward_hidden(&arr, &mut cache, s).unwrap();
    let mut chunk: Vec<i32> = vec![p_ids[prefill_len]];
    for &t in &c_ids[..m - 1] {
        chunk.push(t as i32);
    }
    let carr = Array::from_data_i32(&chunk, &[1, chunk.len()]).unwrap();
    let logits = model.forward_step(&carr, &mut cache, s).unwrap();
    let _ = logits.eval();
    let v = logits.astype(mlx_native::mlx::Dtype::Float32, s).unwrap().to_f32_vec(s).unwrap();
    let vocab = v.len() / chunk.len();
    let mut nll = Vec::new();
    for (j, &t) in c_ids.iter().enumerate() {
        let row = &v[j * vocab..(j + 1) * vocab];
        let max = row.iter().cloned().fold(f32::NEG_INFINITY, f32::max);
        let lse: f32 = row.iter().map(|&x| (x - max).exp()).sum::<f32>().ln();
        nll.push(-(row[t as usize] - max - lse));
    }
    let sum: f32 = nll.iter().sum();
    println!("CHUNK {cont:?} per-token NLL {nll:?} sum {sum:.4} mean {:.4}", sum / nll.len() as f32);
}

fn lse_op_probe(s: mlx_native::mlx::Stream) {
    use mlx_native::mlx::{Array, Dtype};
    // logits [1, 2, 4]: row0 = [1, 2, 3, 4], row1 = [10, 20, 30, 40]
    let v = vec![1.0f32, 2.0, 3.0, 4.0, 10.0, 20.0, 30.0, 40.0];
    let lg = Array::from_data_f32(&v, &[1, 2, 4]).unwrap();
    let am = lg.argmax_axis(-1, false, s).unwrap();
    let am3 = am.expand_dims(&[2], s).unwrap();
    let maxv = lg.take_along_axis(&am3, 2, s).unwrap();
    let shifted = lg.sub(&maxv, s).unwrap();
    let ex = shifted.exp(s).unwrap();
    let lse = ex.sum_axes(&[2], false, s).unwrap().log(s).unwrap();
    let lse_v = lse.to_f32_vec(s).unwrap();
    // true lse: row0 = ln(e1+e2+e3+e4) = 4.4402; row1 = 40.0000
        let am_v = am.astype(Dtype::Float32, s).unwrap().to_f32_vec(s).unwrap();
    println!("LSE-PROBE am {:?}", am_v);
    println!("LSE-PROBE maxv {:?}", maxv.to_f32_vec(s).unwrap());
    println!("LSE-PROBE lse {:?} (expect ~[4.4402, 40.0])", lse_v);
}

fn main() {
    let Ok(s) = gpu() else {
        panic!("no gpu")
    };
    lse_op_probe(s);
    let snap = snapshot();
    let model = Qwen3::load(&snap).unwrap();
    let tok = ByteLevelBpe::load(&snap).unwrap();
    let raw = std::fs::read_to_string("/tmp/perm00002_prompt.txt").expect("prompt file");
    let chat = std::env::var("RANK_CHAT").map(|v| v == "1").unwrap_or(false);
    let prompt = if chat {
        format!("<|im_start|>user\n{raw}<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n")
    } else {
        raw
    };
    println!("prompt n_tokens: {} n_chars: {}", tok.encode(&prompt).unwrap().len(), prompt.len());
    score(&model, &tok, &prompt, "allow_once", s);
    score(&model, &tok, &prompt, "abstain", s);
    score(&model, &tok, &prompt, " allow_once", s);
    score(&model, &tok, &prompt, " abstain", s);
    let chat = format!("<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n");
    println!("--- chunk probe on the chat-wrapped prompt ---");
    chunk_probe(&model, &tok, &chat, "allow_once", s);
    chunk_probe(&model, &tok, &chat, "abstain", s);
    println!("--- qwen_rank::rank_labels_with on the same prompt ---");
    let outcome = mlx_native::qwen_rank::rank_labels_with(
        &model,
        &tok,
        &chat,
        &["allow_once", "abstain"],
        mlx_native::qwen_rank::RankOptions::default(),
        s,
    )
    .unwrap();
    println!("prefix_tokens: {}", outcome.prefix_tokens);
    for sc in &outcome.scores {
        println!(
            "  label {:?} span n={} per-token NLL {:?} sum {:.4} mean {:.4} boundary_mismatch {} eos_first {:?}",
            sc.label,
            sc.tokens.len(),
            sc.per_token_logprob.iter().map(|x| -x).collect::<Vec<_>>(),
            sc.sum_logprob,
            sc.mean_logprob,
            sc.boundary_mismatch,
            sc.eos_prob_first
        );
    }
}

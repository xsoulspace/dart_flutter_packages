fn main() {
    let dir = std::path::PathBuf::from(std::env::var("QWEN3_SNAPSHOT").unwrap_or_else(|_| {
        let home = std::env::var("HOME").unwrap();
        let hub = std::path::PathBuf::from(home).join(".cache/huggingface/hub");
        for e in std::fs::read_dir(&hub).unwrap() {
            let e = e.unwrap();
            if e.file_name().to_string_lossy().contains("Qwen3-0.6B-4bit") {
                for s in std::fs::read_dir(e.path().join("snapshots")).unwrap() {
                    let s = s.unwrap();
                    if s.path().join("config.json").is_file() { return s.path().to_string_lossy().to_string(); }
                }
            }
        }
        panic!("no snapshot");
    }));
    let tok = mlx_native::bpe::ByteLevelBpe::load(&dir).unwrap();
    for t in ["allow_once", "abstain", " allow_once", " abstain", "no_grant", "destructive_op", "outside_workspace", "secret_path", " no_grant", " destructive_op", " outside_workspace", " secret_path"] {
        println!("{t:?} -> {} tokens {:?}", tok.encode(t).unwrap().len(), tok.encode(t).unwrap());
    }
}

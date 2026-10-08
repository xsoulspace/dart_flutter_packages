use std::path::PathBuf;

fn main() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let build_root = std::env::var("LAYA_MLX_BUILD_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| manifest.join("build"));

    let mlx_lib = build_root.join("mlx-install").join("lib");
    let mlxc_lib = build_root.join("mlxc-install").join("lib");
    for dir in [&mlx_lib, &mlxc_lib] {
        if !dir.is_dir() {
            panic!(
                "laya_native: mlx build artifacts missing at {} — run the mlx/mlx-c \
                 cmake build first (see hook/build.dart or ADR 0051)",
                dir.display()
            );
        }
        println!("cargo:rustc-link-search=native={}", dir.display());
    }

    // Static link order matters: mlxc (C wrapper) references mlx (C++ core).
    println!("cargo:rustc-link-lib=static=mlxc");
    println!("cargo:rustc-link-lib=static=mlx");
    // Any extra static archives MLX installs (metal-cpp and friends).
    if let Ok(entries) = std::fs::read_dir(&mlx_lib) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            if let Some(stem) = name
                .strip_prefix("lib")
                .and_then(|n| n.strip_suffix(".a"))
            {
                if stem != "mlx" {
                    println!("cargo:rustc-link-lib=static={stem}");
                }
            }
        }
    }

    println!("cargo:rustc-link-lib=dylib=c++");
    for framework in ["Metal", "Foundation", "Accelerate"] {
        println!("cargo:rustc-link-lib=framework={framework}");
    }

    println!("cargo:rerun-if-env-changed=LAYA_MLX_BUILD_DIR");
    println!("cargo:rerun-if-changed=build.rs");
}

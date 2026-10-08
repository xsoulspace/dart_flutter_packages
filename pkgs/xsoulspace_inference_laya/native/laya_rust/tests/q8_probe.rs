#[test]
#[ignore]
fn q8_round_trip() {
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }
    let s = laya_native::mlx::gpu().unwrap();
    use laya_native::mlx::Array;
    // [3072, 1024] fp16 like the encoder Wi
    let n = 3072 * 1024;
    let data: Vec<u8> = (0..n)
        .flat_map(|i| {
            let bits = 0x3800u16.wrapping_add((i % 97) as u16);
            bits.to_le_bytes().to_vec()
        })
        .collect();
    let w = Array::from_data_f16(&data, &[3072, 1024]).unwrap();
    let outs = Array::quantize(&w, 64, 8, s).unwrap();
    for o in &outs {
        println!("quantize out shape: {} x {} dtype {:?}", o.dim(0), o.dim(1), o.dtype());
    }
    let x = Array::from_data_f16(&data[..5 * 1024 * 2], &[1, 5, 1024]).unwrap();
    let out = Array::quantized_matmul(&x, &outs[0], &outs[1], &outs[2], true, 64, 8, s).unwrap();
    println!("qmat ok: {} x {} x {}", out.dim(0), out.dim(1), out.dim(2));
}

#[test]
#[ignore]
fn dequant_debug_tiny() {
    let metallib = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("build/mlx-install/lib/mlx.metallib");
    if metallib.is_file() {
        laya_native::mlx::set_metallib_path(&metallib);
    }
    let s = laya_native::mlx::gpu().unwrap();
    use laya_native::mlx::{Array, Dtype};
    let n = 8usize;
    let k = 64usize;
    // x = all 1.0 bf16
    let x = Array::from_data_bf16(&vec![0u8, 0x3F].repeat(k), &[1, 1, k]).unwrap();
    // w fp16 pattern 0.5*(i%10+1)
    let mut wbytes = vec![0u8; n * k * 2];
    for (i, chunk) in wbytes.chunks_exact_mut(2).enumerate() {
        let bits = 0x3800u16 + ((i % 10) as u16) << 3; // ~0.5..5.0
        chunk[0] = (bits & 0xFF) as u8;
        chunk[1] = (bits >> 8) as u8;
    }
    let w_fp = Array::from_data_bf16(&wbytes, &[n, k]).unwrap();
    let outs = Array::quantize(&w_fp, 64, 4, s).unwrap();
    println!("wq dtype {:?} dims {}x{}", outs[0].dtype(), outs[0].dim(0), outs[0].dim(1));
    println!("scales dims {}x{} dtype {:?}", outs[1].dim(0), outs[1].dim(1), outs[1].dtype());

    let node = laya_native::plan::Node {
        name: "d".into(),
        group: "g".into(),
        op: laya_native::plan::Op::QuantizedMatmul { group_size: 64, bits: 4, transpose: true },
        inputs: vec![],
        dump: None,
    };
    let mlxc = laya_native::bindings::BindingTable::baseline();
    let mut msl = laya_native::bindings::BindingTable::baseline();
    msl.install("quantized_matmul", laya_native::bindings::ShapeClass::Gemv, Dtype::BFloat16, laya_native::bindings::Backend::DequantGemmMsl);
    let rc = laya_native::bindings::eval(&node, &[&x, &outs[0], &outs[1], &outs[2]], &mlxc, s).unwrap().remove(0);
    let rm = laya_native::bindings::eval(&node, &[&x, &outs[0], &outs[1], &outs[2]], &msl, s).unwrap().remove(0);
    let vc = rc.astype(Dtype::Float32, s).unwrap().to_f32_vec(s).unwrap();
    let vm = rm.astype(Dtype::Float32, s).unwrap().to_f32_vec(s).unwrap();
    println!("mlx : {:?}", &vc[..8]);
    println!("msl : {:?}", &vm[..8]);
}

// ADR 0054 R3/R4 — fused dequant-GEMV (M == 1, affine 4-bit, group 64,
// bfloat16 x/scales/biases). mlx_fast_metal_kernel generates the kernel
// SIGNATURE (inputs are typed by mlx: bf16 arrays arrive as its `bfloat`
// type with implicit float conversion; small inputs may live in constant
// memory) and splices this file in as the function BODY;
// tool/build_msl.sh wraps it in the same signature for the xcrun gate.
//
// One warp per output row n: lanes stride the packed U32 weight row in
// 32-u32 blocks (fully coalesced), each lane dequantizes its 8 nibbles
// against x broadcast through cache, accumulating (x * (q - bias) * scale)
// in f32; a simd_sum reduces the lane partials. The fp16/bf16 weight
// copy never exists — the packed stream IS the memory traffic.

const int N = nk[0];
const int K = nk[1];
const int lane = static_cast<int>(thread_index_in_threadgroup) % 32;
const int warp_in_group = static_cast<int>(thread_index_in_threadgroup) / 32;
const int group_id = static_cast<int>(threadgroup_position_in_grid.x);
const int n = group_id * 8 + warp_in_group;
if (n >= N) {
  return;
}
device const uint* wrow =
    reinterpret_cast<device const uint*>(w) + static_cast<long>(n) * (K / 8);
const int u32_count = K / 8;
float acc = 0.0f;
for (int base = 0; base < u32_count; base += 32) {
  const int u = base + lane;
  if (u >= u32_count) {
    break;
  }
  const uint packed = wrow[u];
  const int g = u / 8;
  // MLX affine dequant is w = q * scale + bias (verified against
  // mx.dequantize — NOT (q - bias) * scale).
  const float scale =
      as_type<float>(static_cast<uint>(*reinterpret_cast<device const ushort*>(&scales[static_cast<long>(n) * (K / 64) + g])) << 16);
  const float bias =
      as_type<float>(static_cast<uint>(*reinterpret_cast<device const ushort*>(&biases[static_cast<long>(n) * (K / 64) + g])) << 16);
  const int k0 = u * 8;
  float part_q = 0.0f;
  float part_x = 0.0f;
#pragma unroll
  for (int nib = 0; nib < 8; ++nib) {
    const uint q = (packed >> (nib * 4)) & 0xFu;
    const float xv = static_cast<float>(x[k0 + nib]);
    part_q += xv * static_cast<float>(q);
    part_x += xv;
  }
  acc += scale * part_q + bias * part_x;
}
acc = simd_sum(acc);
if (lane == 0) {
  out[n] = bfloat(acc);
}

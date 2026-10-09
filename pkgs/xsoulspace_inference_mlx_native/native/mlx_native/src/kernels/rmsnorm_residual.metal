// ADR 0054 R4 — fused RMSNorm+residual epilogue (bfloat16). mlx
// generates the kernel SIGNATURE and splices this file in as the BODY;
// tool/build_msl.sh wraps it in the same signature for the xcrun gate.
//
// One 256-wide threadgroup per row: threads stride the row summing
// (x + r)^2, reduce through threadgroup shared memory, then write the
// normalized row in a second pass. One read of each input and one write
// — the Add-then-RmsNorm composition it replaces does two full round
// trips of the hidden tensor.
//
// eps arrives as a float32 [1] array (the C API has no float template
// argument); shape as int32 [rows, cols].
//
// HISTORY (the 1.7B lesson): pass 2 originally read the row sums from a
// `threadgroup float cached[1024]` array — correct at cols = 1024 (the
// 0.6B gate) and an OUT-OF-BOUNDS threadgroup write at cols = 2048
// (Qwen3-1.7B), corrupting neighbouring threadgroup memory and NaN-ing
// the model from layer 4. Threadgroup memory cannot be sized at launch
// for a plain array, so pass 2 re-reads x + r from global (L2-resident);
// the fused op keeps its one-pass structure for ANY cols.

const int rows = shape[0];
const int cols = shape[1];
const float e = eps[0];
const int row = static_cast<int>(threadgroup_position_in_grid.x);
const int tid = static_cast<int>(thread_index_in_threadgroup);
if (row >= rows) {
  return;
}
// NOTE: no typed element pointers — mlx names the bf16 type bfloat16_t
// while Metal 3.2 calls it bfloat; direct indexing with implicit float
// conversions stays type-agnostic across both.
threadgroup float shared[32];
const long base = static_cast<long>(row) * cols;
// The bf16 element type is named differently by mlx (bfloat16_t) and
// Metal 3.2 (bfloat, no implicit float conversion) — write bf16 bits
// through a uint16 view with round-to-nearest-even (matching mlx's
// conversion, so the only drift vs the composition is accumulate order).
device uint16_t* out_bits = reinterpret_cast<device uint16_t*>(out);
device uint16_t* sum_bits = reinterpret_cast<device uint16_t*>(sum);

const int lane = tid % 32;
const int warp = tid / 32;

float local = 0.0f;
for (int c = tid; c < cols; c += 256) {
  const float v = static_cast<float>(x[base + c]) + static_cast<float>(r[base + c]);
  local += v * v;
}
// Warp reduce, then one partial per warp into shared memory.
for (uint stride = 16; stride > 0; stride >>= 1) {
  local += simd_shuffle_down(local, stride);
}
if (lane == 0) {
  shared[warp] = local;
}
threadgroup_barrier(mem_flags::mem_threadgroup);
// First warp reduces the 8 partials.
if (warp == 0) {
  float part = (tid < 8) ? shared[tid] : 0.0f;
  for (uint stride = 4; stride > 0; stride >>= 1) {
    part += simd_shuffle_down(part, stride);
  }
  if (tid == 0) {
    shared[0] = part;
  }
}
threadgroup_barrier(mem_flags::mem_threadgroup);
const float ms = shared[0] / static_cast<float>(cols);
const float inv = 1.0f / sqrt(ms + e);
for (int c = tid; c < cols; c += 256) {
  const float v = static_cast<float>(x[base + c]) + static_cast<float>(r[base + c]);
  uint vbits = as_type<uint>(v);
  vbits += 0x7FFFu + ((vbits >> 16) & 1u);
  sum_bits[base + c] = static_cast<uint16_t>(vbits >> 16);
  const float scaled = v * inv * static_cast<float>(w[c]);
  uint sbits = as_type<uint>(scaled);
  sbits += 0x7FFFu + ((sbits >> 16) & 1u);
  out_bits[base + c] = static_cast<uint16_t>(sbits >> 16);
}

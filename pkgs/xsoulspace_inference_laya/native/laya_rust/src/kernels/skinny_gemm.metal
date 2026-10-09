// ADR 0054 R4 — weight-stationary skinny GEMM (M ≤ 128, fp16 in, f32
// accumulate). mlx_fast_metal_kernel generates the kernel SIGNATURE and
// splices this file in as the function BODY (attribute names below are
// detected verbatim by mlx to add the thread attributes), so the source
// is body-only. One threadgroup per (m, n-tile): each thread owns one
// output column n and streams B[k, n] coalesced across the threadgroup
// while A[m, :] broadcasts from cache. Computes C = A × B where A is
// [..., M, K] row-contiguous and B is [K, N] — the plan's post-transpose
// weight view, so no materialized transpose is needed.
//
// tool/build_msl.sh wraps this body in the same signature and compiles
// it with `xcrun -sdk macosx metal` as the build-time syntax gate
// (colocated metallib = the proof artifact).

const int M = mnk[0];
const int N = mnk[1];
const int K = mnk[2];
const int gid = static_cast<int>(threadgroup_position_in_grid.x);
const int lane = static_cast<int>(thread_position_in_threadgroup.x);
const int n_tiles = (N + 255) / 256;
const int m = gid / n_tiles;
const int n = (gid % n_tiles) * 256 + lane;
if (m >= M || n >= N) {
  return;
}
device const half* arow = a + static_cast<long>(m) * K;
float acc = 0.0f;
for (int k = 0; k < K; ++k) {
  acc += static_cast<float>(arow[k]) * static_cast<float>(b[static_cast<long>(k) * N + n]);
}
out[static_cast<long>(m) * N + n] = static_cast<half>(acc);

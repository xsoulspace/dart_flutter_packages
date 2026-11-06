// softplus_compiled — bitwise replica of the mx.compile'd `nn.softplus(x)`
// (= `mx.logaddexp(x, 0)`) as the reference pipeline runs it.
//
// WHY A KERNEL: the python reference calls nn.softplus, which is
// @mx.compile-wrapped. MLX's compiled codegen (metal/compiled.cpp) emits
// `T tmp_out = LogAddExp()(tmp_x, tmp_const0)` with the temporaries in the
// NODE dtype (bf16 here) — the LogAddExp functor from
// mlx/backend/metal/kernels/binary_ops.h evaluated with bfloat16_t
// sub-expression semantics. That is bitwise-DIFFERENT from the eager
// mlx_logaddexp route (measured on this machine 2026-11-06: at
// x=-0.224609375 compiled=0.5859375 vs eager=0.58984375; a 9474-point
// exhaustive bf16 grid probe showed THIS verbatim functor replica matches
// the compiled reference 9474/9474, while f32-math replicas match ~93%).
//
// Functor body copied verbatim from binary_ops.h @ ml-explore/mlx v0.32.3
// (identical in v0.32.2 and main):
//
//   struct LogAddExp {
//     template <typename T> T operator()(T x, T y) thread {
//       if (metal::isnan(x) || metal::isnan(y))
//         return metal::numeric_limits<T>::quiet_NaN();
//       constexpr T inf = metal::numeric_limits<T>::infinity();
//       T maxval = metal::max(x, y);
//       T minval = metal::min(x, y);
//       return (minval == -inf || maxval == inf)
//           ? maxval
//           : (maxval + log1p(metal::exp(minval - maxval)));
//     }
//   };

const int n = shape[0];
const uint idx = thread_position_in_grid.x;
if (idx >= (uint)n) {
  return;
}
auto tmp_x = x[idx];
auto tmp_0 = static_cast<decltype(tmp_x)>(0);
auto lae = [&](auto xx, auto yy) {
  using T = decltype(xx);
  if (metal::isnan(xx) || metal::isnan(yy)) {
    return metal::numeric_limits<T>::quiet_NaN();
  }
  constexpr T inf = metal::numeric_limits<T>::infinity();
  T maxval = metal::max(xx, yy);
  T minval = metal::min(xx, yy);
  return (minval == -inf || maxval == inf)
      ? maxval
      : (maxval + log1p(metal::exp(minval - maxval)));
};
out[idx] = lae(tmp_x, tmp_0);

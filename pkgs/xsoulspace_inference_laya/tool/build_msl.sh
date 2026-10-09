#!/bin/zsh
# ADR 0054 R4 build gate: every .metal kernel in
# native/laya_rust/src/kernels must compile clean with Apple's metal
# compiler; the colocated .metallib is the proof artifact (runtime
# dispatch rides mlx_fast_metal_kernel on the same source - the C API
# has no load-from-metallib entry for custom kernels; the deviation is
# recorded in the ADR).
#
# mlx_fast_metal_kernel generates the kernel SIGNATURE and splices each
# kernel file in as the BODY (attribute names detected verbatim), so the
# gate wraps the body in the same signature before compiling.
set -euo pipefail
cd "$(dirname "$0")/../native/laya_rust"
out_dir="build/msl-install"
mkdir -p "$out_dir"
rc=0
for src in src/kernels/*.metal; do
  name="$(basename "${src%.metal}")"
  wrapped="$out_dir/$name.wrapped.metal"
  {
    echo '#include <metal_stdlib>'
    echo 'using namespace metal;'
    case "$name" in
      skinny_gemm)
        echo "kernel void custom_kernel_${name}("
        echo '  const device half* a [[buffer(0)]],'
        echo '  const device half* b [[buffer(1)]],'
        echo '  const device int* mnk [[buffer(2)]],'
        echo '  device half* out [[buffer(3)]],'
        ;;
      dequant_gemv)
        echo "kernel void custom_kernel_${name}("
        echo '  const device bfloat* x [[buffer(0)]],'
        echo '  const device uint* w [[buffer(1)]],'
        echo '  const device bfloat* scales [[buffer(2)]],'
        echo '  const device bfloat* biases [[buffer(3)]],'
        echo '  const device int* nk [[buffer(4)]],'
        echo '  device bfloat* out [[buffer(5)]],'
        ;;
    esac
    echo '  uint3 threadgroup_position_in_grid [[threadgroup_position_in_grid]],'
    echo '  uint thread_index_in_threadgroup [[thread_index_in_threadgroup]],'
    echo '  uint3 thread_position_in_threadgroup [[thread_position_in_threadgroup]]) {'
    awk 'c && !/^\/\// {p=1} /^\/\// {c=1} p' "$src"
    echo '}'
  } > "$wrapped"
  if xcrun -sdk macosx metal -c "$wrapped" -o "$out_dir/$name.air" 2> >(head -20 >&2); then
    if xcrun -sdk macosx metallib "$out_dir/$name.air" -o "$out_dir/$name.metallib" 2>> >(head -20 >&2); then
      echo "msl gate: $name OK ($(wc -c < "$out_dir/$name.metallib" | tr -d ' ') bytes metallib)"
    else
      echo "msl gate: $name metallib FAILED"; rc=1
    fi
  else
    echo "msl gate: $name compile FAILED"; rc=1
  fi
done
exit $rc

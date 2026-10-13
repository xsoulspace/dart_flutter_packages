# Native Qwen runtime smoke, 2026-10-13

[Captured parent result](native-qwen-smoke-2026-10-13.json) proves a bounded
read-only local inference through the prepared Dart 3.13.2 macOS ARM64 bundle.
The existing native build hook and qualified Metal closure packaging were used.
No downloads, hosted calls, coding tools, camera or foreground UI were involved.

- Explicit cached checkpoint: Qwen3-1.7B-4bit snapshot
  `3b1b1768f8f8cf8351c712464f906e86c2b8269e`.
- Weight SHA-256: `0e86d9677e519323849eac1bc272caae88567a481ff188c431f70be543d9995f`.
- Actual loaded image SHA-256: `bc816b00812febe015e769b8deaf63353f4fcc1b16c89070933237413e48da12`.
- Colocated Metal SHA-256: `512f31ee0b4b08f87cc5bd7095c080b7d39d11bb1b6ebeed23a778d2f647980f`.
- Tokenizer/config, executable, weights, dylib and Metal hashes remained
  identical before and after inference.
- Host-selected cap: 16 generated tokens; temperature 0, thinking false.
- Response: literal `Clear.`; 3 completion tokens, 28 prompt tokens.
- Parent deadline: 120 seconds. Exit 0, no survivors, no settlement problem,
  empty stderr; the lazy engine was unloaded before normal child exit.

The probe measured 432 ms for load and 10,828 ms overall after hashes were
captured. Overall duration includes post-inference rehashing and is not a
throughput benchmark. The harmless prompt asked for a sky color; `Clear.` is
not treated as a correct semantic answer. This gate establishes actual weight
load, GPU generation, bounded output and transport/closure identity. It does
not establish tool-call reasoning, multi-turn coding, correctness, product
adoption, decision-model delegation or independent coding acceptance.

Reproduction uses the package's `tool/prepare_native_cli.dart` with the existing
prepared SDK configuration and `tool/qwen_cached_runtime_smoke.dart` target,
then `tool/run_qwen_runtime_smoke.dart` to enforce the parent deadline and
capture physical settlement. The independent coding driver/oracle remains
separate and must be sealed before scored runs.

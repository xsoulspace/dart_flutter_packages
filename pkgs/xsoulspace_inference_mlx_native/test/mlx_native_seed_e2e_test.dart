import 'package:test/test.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// ADR 0071 — the per-request seed contract, asserted END-TO-END through
/// the real native client (the Tier-C record repair: the contract existed
/// with core golden tests for the SplitMix64 sampler, but no test asserted
/// reproducibility through `MlxNativeTextClient`).
///
/// The native engines decode greedily, so the draw is
/// deterministic-by-construction, NOT seed-derived. The contract pinned
/// here: (1) the same request reproduces byte-identically across calls;
/// (2) the seed cannot move the answer (two different seeds, same text);
/// (3) the seed is echoed in the response meta (`inference_seed`) and the
/// honesty warning is present — map-or-refuse, never silently dropped
/// (ADR 0059). Skips honestly when the snapshot is not cached.
void main() {
  test('qwen: seeded request reproduces; seed echoed and warned', () async {
    final client = MlxNativeTextClient.lazyQwen();
    try {
      await client.load();
      if (!client.isAvailable) {
        return markTestSkipped('qwen snapshot not cached: ${client.loadError}');
      }
      const prompt =
          'Classify the text. Answer with exactly one of: allow_once, abstain\n\n'
          "Text: the nightly backup will overwrite yesterday's export.\nAnswer:";
      InferenceRequest mkReq(int seed) => InferenceRequest(
            prompt: prompt,
            maxTokens: 8,
            seed: seed,
          );

      final a = await client.infer(mkReq(42));
      expect(a.success, isTrue, reason: a.error?.toJson().toString());
      final b = await client.infer(mkReq(42));
      final c = await client.infer(mkReq(43));

      // 1. Reproducibility: the same request, twice, byte-identical.
      expect(
        a.data!.presentationText,
        b.data!.presentationText,
        reason: 'greedy decode is deterministic by construction',
      );
      // 2. The seed cannot move the draw (the contract's honest shape:
      // reproducibility comes from greedy argmax, not from the seed).
      expect(a.data!.presentationText, c.data!.presentationText);
      // 3. The meta echo carries the REQUEST's seed per call.
      expect(a.data!.meta[inferenceSeedMetaKey], 42);
      expect(c.data!.meta[inferenceSeedMetaKey], 43);
      // 4. The honesty warning says what the contract does.
      expect(
        a.warnings.join(' '),
        contains('deterministic-by-construction'),
      );
    } finally {
      client.dispose();
    }
  });
}

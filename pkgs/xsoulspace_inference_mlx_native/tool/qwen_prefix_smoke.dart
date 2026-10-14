/// Direct VM native-asset probe when Flutter's runner cannot resolve the image.
library;
import 'dart:convert';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

Future<void> main(List<String> args) async {
  final engine = await NativeQwenTextEngine.load(snapshotDir: args.single);
  const scope = QwenCacheScope(actor: 'smoke/alpha', epoch: '1');
  const prompt = 'The capital of France is';
  bool equal(List<int> a, List<int> b) => jsonEncode(a) == jsonEncode(b);
  try {
    final fresh = await engine.generateAsync(prompt: prompt, maxTokens: 8);
    final cold = await engine.generateAsync(
      prompt: prompt,
      maxTokens: 8,
      cacheScope: scope,
    );
    final warm = await engine.generateAsync(
      prompt: prompt,
      maxTokens: 8,
      cacheScope: scope,
    );
    engine.clearCache(scope.actor);
    final cleared = engine.generate(
      prompt: prompt,
      maxTokens: 8,
      cacheScope: scope,
    );
    final checks = {
      'cold_zero': cold.cacheReusedTokens == 0,
      'warm_reuses': warm.cacheReusedTokens == warm.promptIds.length - 1,
      'warm_exact': equal(warm.ids, fresh.ids),
      'clear_zero': cleared.cacheReusedTokens == 0,
      'clear_exact': equal(cleared.ids, fresh.ids),
    };
    print(jsonEncode(checks));
    if (checks.values.contains(false)) {
      throw StateError('prefix_cache_regression');
    }
  } finally {
    engine.dispose();
  }
}

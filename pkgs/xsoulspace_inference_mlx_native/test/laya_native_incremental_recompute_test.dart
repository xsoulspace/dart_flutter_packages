import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx_native/xsoulspace_inference_mlx_native.dart';

/// The probability tolerance for a distribution comparison, matching
/// laya_native_batch_isolation_test.dart.
///
/// The Dart softmax runs in float64 on float32 logits, so its own rounding
/// contributes ~1e-16. The floor is set by the native forward: the trunk
/// stores activations in float16 (`ACT_DTYPE = Float16`), so a differently
/// shaped forward re-rounds them at float16 granularity (one float16 ULP at
/// the observed logit magnitude is ~2.1e-3), and the softmax is
/// 1-Lipschitz in the max norm, so that drift lands in the 1e-4 range.
/// Measured on this machine against the fp16 laya-mlx checkpoint: a pure
/// batch-size change moved a probability by at most 3.6e-4, while the
/// shorter-row defect of the native heterogeneous-batch path moved one by
/// 0.31. 1e-3 admits the former and rejects the latter.
const double _probabilityTolerance = 1e-3;

/// The categorical decision a question resolves to — never a float: the
/// chosen option label for a choice question, the modal level for a score
/// question, the true/false side for a noul question.
String _decision(LayaTypedDecision decision) {
  switch (decision.type) {
    case 'choice':
      return decision.choice!;
    case 'score':
    case 'noul':
      return _argmaxLabel(decision.probabilities);
  }
  throw StateError('unknown decision type ${decision.type}');
}

/// The label whose probability is highest, first-wins on a tie — the same
/// tie-break the engine's own argmax loop uses.
String _argmaxLabel(Map<String, double> probabilities) {
  var best = probabilities.keys.first;
  for (final entry in probabilities.entries) {
    if (entry.value > probabilities[best]!) {
      best = entry.key;
    }
  }
  return best;
}

/// DeepInfer's INCREMENTAL == FULL RECOMPUTE property, on the surface that
/// actually has an incremental path.
///
/// The package holds two engines with different shapes:
///
///  * the Qwen text engine decodes autoregressively and keeps a
///    host-bound prefix KV cache (`cache_scope` / `cache_reset`). Reusing a
///    cached prefix is a genuine incremental path: the cached KV covers the
///    shared prompt prefix and only the remaining tokens are computed. The
///    DeepInfer analogue of `tests/models/test_kl.py` is then exact: the
///    incrementally decoded token ids must equal the ids of a decode that
///    recomputes the whole sequence from scratch. This is the test that
///    catches KV-cache write/read bugs, RoPE position off-by-one, and
///    chunking bugs — a wrong cached prefix silently changes the answer.
///
///  * the laya DECISION engine has NO incremental path: it is a single
///    forward over the whole prompt (a ModernBERT encoder plus a decision
///    head — no autoregressive decode, no KV cache), and the package
///    exposes no per-token logprobs anywhere (the FFI returns decision
///    logits and an action logit, never a per-token distribution). A true
///    incremental-vs-recompute test for it would need the native side to
///    expose a resumable, cacheable forward plus per-token logprobs; until
///    then the strongest real property available is that the SAME engine,
///    asked the SAME question twice — and asked the same question repeated
///    in one batch and at a different batch position — answers identically.
///    That is what the second test below proves.
///
/// Skips honestly (with the reason) when the native artifacts or the cached
/// snapshot are absent; runs by default otherwise.
void main() {
  test(
    'qwen prefix-cached decode equals a full recompute of the same prompt',
    () async {
      final NativeQwenTextEngine engine;
      try {
        engine = await NativeQwenTextEngine.load();
      } on Object catch (error) {
        return markTestSkipped('native qwen unavailable: $error');
      }
      addTearDown(engine.dispose);

      const scope = QwenCacheScope(actor: 'test/incremental', epoch: '1');
      const prompt = 'The capital of France is';

      // The full recompute, with no cache in play at all.
      final full = engine.generate(prompt: prompt, maxTokens: 8);
      expect(full.ids, isNotEmpty, reason: 'the decode produced no tokens');

      // A cold scoped call has nothing to reuse: it must equal the full
      // recompute, so entering the cache changes nothing.
      final cold = engine.generate(
        prompt: prompt,
        maxTokens: 8,
        cacheScope: scope,
      );
      expect(
        cold.cacheReusedTokens,
        0,
        reason: 'a cold cache scope must reuse nothing',
      );
      expect(
        cold.ids,
        full.ids,
        reason: 'a cold scoped decode must equal the full recompute',
      );

      // The incremental path: the second scoped call reuses the cached
      // prompt prefix. This is the case the property is about — the reused
      // KV must not change the answer.
      final warm = engine.generate(
        prompt: prompt,
        maxTokens: 8,
        cacheScope: scope,
      );
      expect(
        warm.cacheReusedTokens,
        greaterThan(0),
        reason:
            'the incremental path did not run — nothing was reused, so '
            'this test proved nothing',
      );
      expect(
        warm.ids,
        full.ids,
        reason: 'the incrementally decoded ids must equal the full recompute',
      );

      // Extend the prompt by replacing its last token: the cached prefix is
      // still reused, but the continuation is computed from a different
      // final prompt token. A KV read at the wrong position, or a RoPE
      // offset off by one, shows up here and nowhere else.
      final promptIds = full.promptIds;
      final generated = full.ids[promptIds.length];
      final extended = <int>[
        ...promptIds.take(promptIds.length - 1),
        generated,
      ];
      final incremental = engine.generate(
        promptIds: extended,
        maxTokens: 8,
        cacheScope: scope,
      );
      final recomputed = engine.generate(promptIds: extended, maxTokens: 8);
      expect(
        incremental.cacheReusedTokens,
        greaterThan(0),
        reason:
            'the incremental path did not run — the extended prompt reused '
            'nothing, so this test proved nothing',
      );
      expect(
        incremental.ids,
        recomputed.ids,
        reason:
            'the incrementally decoded ids must equal the full recompute of '
            'the same prompt',
      );

      // Revoking the cache must restore the full path, with the same answer.
      final reset = engine.generate(
        promptIds: extended,
        maxTokens: 8,
        cacheScope: scope,
        cacheReset: true,
      );
      expect(
        reset.cacheReusedTokens,
        0,
        reason: 'cacheReset must force the full recompute',
      );
      expect(
        reset.ids,
        recomputed.ids,
        reason: 'the cache-reset decode must equal the full recompute',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'the greedy decode path is seed-independent: one prompt, one answer',
    () async {
      final NativeQwenTextEngine engine;
      try {
        engine = await NativeQwenTextEngine.load();
      } on Object catch (error) {
        return markTestSkipped('native qwen unavailable: $error');
      }
      addTearDown(engine.dispose);

      // The decode is greedy (argmax), so no seed can move it: the same
      // prompt must produce the same tokens on every call, on the same engine
      // and after the prefix cache has been warmed by other work.
      const prompt = 'The capital of France is';
      final first = engine.generate(prompt: prompt, maxTokens: 8);
      final second = engine.generate(prompt: prompt, maxTokens: 8);
      expect(
        second.ids,
        first.ids,
        reason: 'the greedy decode must not vary between identical calls',
      );

      final scope = QwenCacheScope(actor: 'test/determinism', epoch: '1');
      engine.generate(
        prompt: 'Count: one two three',
        maxTokens: 4,
        cacheScope: scope,
      );
      final afterCache = engine.generate(
        prompt: prompt,
        maxTokens: 8,
        cacheScope: scope,
      );
      expect(
        afterCache.ids,
        first.ids,
        reason: 'the greedy decode must not vary with the prefix cache state',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'the decision engine answers the same question identically every time',
    () async {
      final NativeLayaDecisionEngine engine;
      try {
        engine = await NativeLayaDecisionEngine.load();
      } on Object catch (error) {
        return markTestSkipped('native artifacts absent: $error');
      }
      addTearDown(engine.dispose);

      const state =
          'Subject: Duplicate charge on invoice #4411\n'
          'We were billed twice for March. Please refund the duplicate today.';
      const choice = LayaTypedQuestion.choice(
        'Which department should handle this email?',
        {
          'billing': 'invoices, payments, refunds',
          'technical': 'bugs, outages, system errors',
          'sales': 'pricing, new contracts',
          'other': 'everything else',
        },
      );
      const score = LayaTypedQuestion.score('How urgent is this request?', [
        'not urgent',
        'soon',
        'critical deadline or blocking issue',
      ]);
      const noul = LayaTypedQuestion.noul(
        'Does the customer ask for money back?',
      );

      // The same question, asked twice on the same engine.
      final first = engine.decideTyped(state: state, questions: {'q': choice});
      final second = engine.decideTyped(state: state, questions: {'q': choice});
      for (final id in ['q']) {
        expect(
          _decision(first[id]!),
          _decision(second[id]!),
          reason:
              '$id: the same question asked twice must resolve to the same '
              'decision',
        );
        for (final probability in first[id]!.probabilities.entries) {
          expect(
            second[id]!.probabilities[probability.key],
            closeTo(probability.value, _probabilityTolerance),
            reason:
                '$id/${probability.key}: the same question asked twice must '
                'resolve to the same distribution',
          );
        }
      }

      // The same question repeated inside one batch, and asked at a different
      // batch position: neither the repetition nor the position may move the
      // answer. The noul question is included because it is the SHORTEST row
      // (2 option markers, against the choice question's 4) — the shape the
      // native heterogeneous-batch path is known to disturb.
      final repeated = engine.decideTyped(
        state: state,
        questions: {
          'first': choice,
          'second': choice,
          'score': score,
          'noul': noul,
        },
      );
      final repositioned = engine.decideTyped(
        state: state,
        questions: {
          'noul': noul,
          'score': score,
          'second': choice,
          'first': choice,
        },
      );
      for (final batch in [repeated, repositioned]) {
        expect(
          _decision(batch['first']!),
          _decision(first['q']!),
          reason:
              'a question repeated in a batch must resolve to the same '
              'decision',
        );
        for (final probability in first['q']!.probabilities.entries) {
          expect(
            batch['first']!.probabilities[probability.key],
            closeTo(probability.value, _probabilityTolerance),
            reason:
                'a question repeated in a batch must resolve to the same '
                'distribution',
          );
        }
      }
      expect(
        _decision(repeated['second']!),
        _decision(first['q']!),
        reason:
            'the same question at another batch position must resolve to '
            'the same decision',
      );
      expect(
        _decision(repeated['noul']!),
        _decision(repositioned['noul']!),
        reason:
            'the shortest question at another batch position must resolve to '
            'the same decision',
      );
      expect(
        _decision(repeated['score']!),
        _decision(repositioned['score']!),
        reason:
            'a question at another batch position must resolve to the same '
            'decision',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

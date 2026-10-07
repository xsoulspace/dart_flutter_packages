# xsoulspace_inference_anthropic

Anthropic Messages API-backed implementation of [xsoulspace_inference_core](https://github.com/xsoulspace/dart_flutter_packages/tree/main/pkgs/xsoulspace_inference_core).

Implements `InferenceClient` for free text, best-effort structured output, and
native `tool_use` tool calling against `POST /v1/messages`.

## Wire family

This package is the **Anthropic family** adapter: it owns the Messages wire
(`x-api-key` + `anthropic-version` headers, top-level `system` parameter,
content blocks, `tool_use`) and never leaks vendor vocabulary upstream. The
OpenAI-family chat wire lives in `xsoulspace_inference_openrouter`; bounded
finite-choice decisions are a separate capability contract
(`DecisionProvider`), not a chat mode.

## Required token budget

The Messages API rejects requests without `max_tokens`. Set
`InferenceRequest.maxTokens`; when absent the client fails with the named
code `missing_max_tokens` instead of inventing a default.
`temperature` and `stopSequences` pass through when set.

```dart
final client = AnthropicInferenceClient(apiKey: '...');
final result = await client.infer(
  InferenceRequest(
    prompt: 'Summarize the failing test.',
    maxTokens: 512,
  ),
);
```

## Non-claims

- SSE streaming is not implemented; the client is request/response only.
- Structured output is prompt-guided and parsed best-effort — Anthropic has
  no server-enforced `response_format`.
- The client never executes tools; it re-emits `tool_use` blocks as
  `ToolCall` records for the host to route.

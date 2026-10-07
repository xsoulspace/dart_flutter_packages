# Changelog

## 0.1.0

- Initial `AnthropicInferenceClient`: Messages API transport for text,
  prompt-guided structured output, and native `tool_use` tool calling.
- Requires an explicit `InferenceRequest.maxTokens` (named
  `missing_max_tokens` failure when absent); `temperature` and
  `stopSequences` pass through.
- Context fragments render into a native multi-turn `messages` array via
  `SituationMessagesCodec`.

/// Shared deterministic token estimation for benchmark handlers.
library;

/// Rough token estimate: ~4 chars per token. Good enough to enforce a budget
/// and observe growth; keeps benchmarks LLM-free and repeatable.
int estimateTokensFromChars(int chars) => (chars / 4).ceil();

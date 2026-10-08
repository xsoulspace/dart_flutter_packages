/// Prompt contracts for the nap-drafting lane.
///
/// The lane drafts DERIVED, forgettable memory summaries from raw material
/// the deterministic tool shows it; the model's only freedom is which
/// lasting facts to keep. The refusal contract is part of the prompt:
/// a model that cannot compress faithfully must answer with the refusal
/// token, and a refusal is a PASS for the faithfulness gate — an empty
/// draft is never better than an invented one.
library;

/// Prompt builders + the refusal contract for draft generation.
final class NapDraftPrompts {
  NapDraftPrompts._();

  /// The exact token a faithful refusal must be.
  static const String refusalToken = 'REFUSE';

  /// The system role text for summary drafting. The laws are the OptMem
  /// laws: derived, faithful, one line, bounded.
  static String summarySystem({required int maxBytes}) =>
      'You compress agent-memory blocks into one-line summaries for a '
      'permanent memory store. Hard laws:\n'
      '- Be EXTRACTIVE: name the concrete subjects of the most '
      'consequential source lines (repos, tools, outcomes, numbers). '
      'Never generalize into abstract phrases like "key events" or '
      '"performance across layers".\n'
      '- Invent nothing: every substantive word must be traceable to a '
      'source line; never add topics, categories or names that appear in '
      'no source line.\n'
      '- If the material does not determine a faithful summary, or you are '
      'uncertain, reply with exactly: $refusalToken\n'
      '- One line, no newlines, at most $maxBytes bytes (UTF-8). '
      'No preamble, no quotes around the summary, no explanations.';

  /// The user role text: the same instruction the OptMem nap prompt shows
  /// a human, then the verbatim material.
  static String summaryUser({
    required String blockLabel,
    required int maxBytes,
    required String material,
  }) =>
      'Compress memories $blockLabel into one line of at most $maxBytes '
      'bytes.\n'
      'Keep what has lasting effect, drop what does not. Invent nothing.\n'
      '\n'
      '$material';

  /// Whether [text] is a faithful refusal (the exact token, trimmed).
  static bool isRefusal(final String text) => text.trim() == refusalToken;

  /// Annotation prompt (topic derivation + clause-kind refinement over the
  /// mechanical segmentation). v1 ships the contract and the fake-server
  /// path; no production consumer is wired yet — the deterministic
  /// classifier in ecsly_context stays the only read-path annotation.
  static String annotationSystem() =>
      'You annotate one-line agent memories. The input already has a '
      'mechanical topic guess and clause kinds (open, done, action, fact). '
      'Reply with ONLY a JSON object:\n'
      '{"topic": "<corrected topic or null>",'
      ' "clauses": [{"index": 1, "kind": "open|done|action|fact"}]}\n'
      '- Never rewrite clause text; annotate kinds only.\n'
      '- If unsure about a clause, keep the mechanical kind.';
}

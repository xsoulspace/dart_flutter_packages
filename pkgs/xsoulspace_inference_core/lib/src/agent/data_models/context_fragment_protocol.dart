// ignore_for_file: lines_longer_than_80_chars

/// Context fragment protocol — the shared wire contract between the
/// projection side (producer: `actorActSystem`, which flattens the cinematic
/// cut into fragments) and backend codecs (consumers, e.g. the OpenRouter
/// chat-completions messages codec).
///
/// Design ruling (ADR 0009 / fair-comparison plan Step 1): the `messages`
/// array is a **codec, not state**. Beats are the only source of truth;
/// fragments are computed per call and carry just enough role structure for
/// a codec to render native message roles faithfully:
///
/// | Fragment form            | Rendered as        | Produced from |
/// | ------------------------ | ------------------ | ------------- |
/// | `asst:<text>`            | assistant message  | actor's own response beats |
/// | `tool:<name> <output>`   | tool result note   | tool-result beats |
/// | `absence:<text>`         | green-screen note  | explicit absences |
/// | plain text               | context/user       | other projected content |
///
/// Pairing atomicity holds by construction at v1: each tool result is one
/// self-contained fragment, so a codec can never split a call/result pair
/// across a budget boundary.
///
/// This is deliberately a string protocol, not typed objects: every backend
/// (including FFI bridges that JSON-encode whole requests) can carry it
/// without per-backend serialization changes.
library;

/// Prefixes and helpers for role-tagged context fragments.
abstract final class ContextFragmentProtocol {
  /// The actor's own prior output (rendered as an assistant message).
  static const String assistantPrefix = 'asst:';

  /// A tool result (rendered as a tool-role note).
  static const String toolResultPrefix = 'tool:';

  /// An explicit green-screen absence.
  static const String absencePrefix = 'absence:';

  static String assistant(String text) => '$assistantPrefix$text';

  static String toolResult(String toolName, String output) =>
      '$toolResultPrefix$toolName $output';

  static String absence(String text) => '$absencePrefix$text';

  /// Strip any known role prefix; used by codecs that flatten to text.
  static String stripPrefixes(String fragment) {
    for (final p in [assistantPrefix, toolResultPrefix, absencePrefix]) {
      if (fragment.startsWith(p)) return fragment.substring(p.length);
    }
    return fragment;
  }
}

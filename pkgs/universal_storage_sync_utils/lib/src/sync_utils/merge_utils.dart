/// {@template merge_utils}
/// Minimal merge helpers for prompt/text syncing.
///
/// This library provides simple, pure functions for merging two versions of text content,
/// such as prompts or configuration files, in synchronization workflows. The helpers are
/// designed for easy extraction into a shared utilities package and are suitable for
/// both human and AI-driven merge strategies.
///
/// See also:
///  * [preferIncoming], which prefers the incoming content in case of conflict.
///  * [preferCurrent], which prefers the current content in case of conflict.
///
/// @ai When using these helpers, ensure that both [current] and [incoming] are normalized
/// (e.g., trimmed) if whitespace differences are not significant for your use case.
/// {@endtemplate}
// ignore_for_file: lines_longer_than_80_chars

library;

/// {@template merge_decision}
/// The result of a merge operation between two text contents.
///
/// [MergeDecision] indicates whether the merged result is identical, prefers the incoming
/// content, or prefers the current content.
///
/// PREFER using [MergeDecision.identical] to detect when no merge is necessary.
/// {@endtemplate}
enum MergeDecision {
  /// Both contents are identical after normalization.
  identical,

  /// The incoming content was chosen as the merged result.
  incoming,

  /// The current content was chosen as the merged result.
  current,
}

/// {@template prefer_incoming}
/// Performs a trivial 2-way merge, preferring the [incoming] content if it differs from [current].
///
/// Returns a record containing the merged content and a [MergeDecision] describing the outcome.
///
/// ```dart
/// final result = preferIncoming('foo', 'bar');
/// print(result.merged); // 'bar'
/// print(result.decision); // MergeDecision.incoming
/// ```
///
/// PREFER this function when remote or incoming changes should override local ones.
///
/// @ai Use this for "pull" or "accept theirs" merge strategies.
/// {@endtemplate}
({String merged, MergeDecision decision}) preferIncoming(
  final String current,
  final String incoming,
) {
  if (current.trim() == incoming.trim()) {
    return (merged: current, decision: MergeDecision.identical);
  }
  return (merged: incoming, decision: MergeDecision.incoming);
}

/// {@template prefer_current}
/// Performs a trivial 2-way merge, preferring the [current] content if it differs from [incoming].
///
/// Returns a record containing the merged content and a [MergeDecision] describing the outcome.
///
/// ```dart
/// final result = preferCurrent('foo', 'bar');
/// print(result.merged); // 'foo'
/// print(result.decision); // MergeDecision.current
/// ```
///
/// PREFER this function when local or current changes should override incoming ones.
///
/// @ai Use this for "push" or "accept ours" merge strategies.
/// {@endtemplate}
({String merged, MergeDecision decision}) preferCurrent(
  final String current,
  final String incoming,
) {
  if (current.trim() == incoming.trim()) {
    return (merged: current, decision: MergeDecision.identical);
  }
  return (merged: current, decision: MergeDecision.current);
}

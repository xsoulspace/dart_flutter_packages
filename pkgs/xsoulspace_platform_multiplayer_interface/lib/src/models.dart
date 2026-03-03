import 'package:meta/meta.dart';

@immutable
final class MultiplayerMetaRange {
  const MultiplayerMetaRange({required this.min, required this.max});

  final int min;
  final int max;
}

@immutable
final class MultiplayerMetaRanges {
  const MultiplayerMetaRanges({this.meta1, this.meta2, this.meta3});

  final MultiplayerMetaRange? meta1;
  final MultiplayerMetaRange? meta2;
  final MultiplayerMetaRange? meta3;
}

@immutable
final class MultiplayerMeta {
  const MultiplayerMeta({this.meta1, this.meta2, this.meta3});

  final int? meta1;
  final int? meta2;
  final int? meta3;
}

@immutable
final class MultiplayerCommitPayload {
  const MultiplayerCommitPayload({required this.data, required this.time});

  final Map<String, Object?> data;
  final int time;
}

@immutable
final class MultiplayerTransaction {
  const MultiplayerTransaction({required this.data, required this.time});

  final Map<String, Object?> data;
  final int time;
}

@immutable
final class MultiplayerSessionOpponent {
  const MultiplayerSessionOpponent({
    required this.id,
    required this.meta,
    required this.transactions,
  });

  final String id;
  final MultiplayerMeta meta;
  final List<MultiplayerTransaction> transactions;
}

@immutable
final class MultiplayerSessionInitRequest {
  const MultiplayerSessionInitRequest({
    this.count,
    this.isEventBased,
    this.maxOpponentTurnTime,
    this.metaRanges,
  });

  final int? count;
  final bool? isEventBased;
  final int? maxOpponentTurnTime;
  final MultiplayerMetaRanges? metaRanges;
}

@immutable
final class MultiplayerSessionInitResult {
  const MultiplayerSessionInitResult({required this.opponents});

  final List<MultiplayerSessionOpponent> opponents;

  static const empty = MultiplayerSessionInitResult(
    opponents: <MultiplayerSessionOpponent>[],
  );
}

@immutable
final class MultiplayerPushResult {
  const MultiplayerPushResult({required this.status, this.data, this.error});

  final String status;
  final Object? data;
  final String? error;
}

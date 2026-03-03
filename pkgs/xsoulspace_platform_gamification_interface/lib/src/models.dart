import 'package:meta/meta.dart';

@immutable
final class AchievementState {
  const AchievementState({
    required this.id,
    required this.unlocked,
    this.unlockedAt,
  });

  final String id;
  final bool unlocked;
  final DateTime? unlockedAt;
}

@immutable
final class LeaderboardQuery {
  const LeaderboardQuery({
    this.includeUser,
    this.quantityAround,
    this.quantityTop,
    this.limit,
    this.offset,
  });

  final bool? includeUser;
  final int? quantityAround;
  final int? quantityTop;
  final int? limit;
  final int? offset;
}

@immutable
final class LeaderboardEntry {
  const LeaderboardEntry({
    required this.playerId,
    required this.playerName,
    required this.rank,
    required this.score,
    this.extraData,
  });

  final String playerId;
  final String playerName;
  final int rank;
  final int score;
  final String? extraData;
}

@immutable
final class LeaderboardEntries {
  const LeaderboardEntries({required this.entries, this.userRank, this.total});

  final List<LeaderboardEntry> entries;
  final int? userRank;
  final int? total;

  static const empty = LeaderboardEntries(entries: <LeaderboardEntry>[]);
}

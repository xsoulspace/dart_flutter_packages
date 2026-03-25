import 'package:test/test.dart';
import 'package:xsoulspace_platform_gamification_interface/xsoulspace_platform_gamification_interface.dart';

void main() {
  group('Leaderboard models', () {
    test('LeaderboardEntries.empty has deterministic defaults', () {
      expect(LeaderboardEntries.empty.entries, isEmpty);
      expect(LeaderboardEntries.empty.userRank, isNull);
      expect(LeaderboardEntries.empty.total, isNull);
    });

    test('stores leaderboard query and entry values', () {
      const query = LeaderboardQuery(limit: 10, includeUser: true);
      const entry = LeaderboardEntry(
        playerId: 'player-1',
        playerName: 'Alice',
        rank: 1,
        score: 999,
      );

      expect(query.limit, 10);
      expect(query.includeUser, isTrue);
      expect(entry.playerId, 'player-1');
      expect(entry.rank, 1);
    });
  });

  group('AchievementState', () {
    test('keeps unlock metadata', () {
      final unlockedAt = DateTime.utc(2026, 1, 1);
      final state = AchievementState(
        id: 'first-win',
        unlocked: true,
        unlockedAt: unlockedAt,
      );

      expect(state.id, 'first-win');
      expect(state.unlocked, isTrue);
      expect(state.unlockedAt, unlockedAt);
    });
  });
}

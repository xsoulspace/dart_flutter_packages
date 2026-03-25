import 'package:xsoulspace_platform_core_interface/xsoulspace_platform_core_interface.dart';

import 'models.dart';

abstract interface class AchievementReadCapability
    implements PlatformCapability {
  Future<AchievementState?> getAchievement(String id);
}

abstract interface class AchievementWriteCapability
    implements PlatformCapability {
  Future<void> unlockAchievement(String id);

  Future<void> clearAchievement(String id);
}

abstract interface class StatsReadCapability implements PlatformCapability {
  Future<int?> getIntStat(String name);

  Future<double?> getDoubleStat(String name);
}

abstract interface class StatsWriteCapability implements PlatformCapability {
  Future<void> setIntStat(String name, int value);

  Future<void> setDoubleStat(String name, double value);
}

abstract interface class StatsSyncCapability implements PlatformCapability {
  Future<void> requestCurrentStats();

  Future<void> flushStats();
}

abstract interface class LeaderboardReadCapability
    implements PlatformCapability {
  Future<LeaderboardEntries> getEntries(
    String leaderboardId,
    LeaderboardQuery q,
  );

  Future<LeaderboardEntry?> getPlayerEntry(String leaderboardId);
}

abstract interface class LeaderboardWriteCapability
    implements PlatformCapability {
  Future<void> submitScore(
    String leaderboardId,
    int score, {
    String? extraData,
  });
}

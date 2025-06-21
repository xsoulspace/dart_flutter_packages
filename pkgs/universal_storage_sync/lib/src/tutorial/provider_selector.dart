import '../models/models.dart';
import '../utils/path_normalizer.dart';

/// {@template provider_recommendation}
/// Recommendation for a storage provider based on requirements.
/// {@endtemplate}
class ProviderRecommendation {
  /// {@macro provider_recommendation}
  const ProviderRecommendation({
    required this.providerType,
    required this.configTemplate,
    required this.reason,
    required this.score,
    this.alternatives = const [],
  });

  /// Recommended provider type
  final ProviderType providerType;

  /// Template configuration for the provider
  final StorageConfig configTemplate;

  /// Reason for the recommendation
  final String reason;

  /// Recommendation score (0-100)
  final int score;

  /// Alternative provider recommendations
  final List<ProviderRecommendation> alternatives;

  @override
  String toString() =>
      'ProviderRecommendation(type: $providerType, score: $score, reason: $reason)';
}

/// {@template provider_requirements}
/// Requirements specification for provider selection.
/// {@endtemplate}
class ProviderRequirements {
  /// {@macro provider_requirements}
  const ProviderRequirements({
    this.needsVersionControl = false,
    this.needsOffline = false,
    this.hasGitCli = false,
    this.isWeb = false,
    this.needsRemoteSync = false,
    this.needsCollaboration = false,
    this.prioritizeSimplicity = false,
    this.expectedDataSize,
    this.maxLatencyMs,
    this.securityLevel,
  });

  /// Requires version control capabilities
  final bool needsVersionControl;

  /// Requires offline functionality
  final bool needsOffline;

  /// Git CLI is available
  final bool hasGitCli;

  /// Running in web environment
  final bool isWeb;

  /// Needs remote synchronization
  final bool needsRemoteSync;

  /// Needs collaboration features
  final bool needsCollaboration;

  /// Prioritize simplicity over features
  final bool prioritizeSimplicity;

  /// Expected data size in MB
  final double? expectedDataSize;

  /// Maximum acceptable latency in milliseconds
  final int? maxLatencyMs;

  /// Required security level
  final SecurityLevel? securityLevel;
}

/// {@template security_level}
/// Security levels for provider selection.
/// {@endtemplate}
enum SecurityLevel {
  /// Basic security requirements
  basic,

  /// Standard security requirements
  standard,

  /// High security requirements
  high,

  /// Enterprise security requirements
  enterprise,
}

/// {@template provider_selector}
/// Utility class for recommending storage providers based on requirements.
/// {@endtemplate}
mixin ProviderSelector {
  /// Recommends the best provider based on requirements
  static ProviderRecommendation recommend(
    final ProviderRequirements requirements,
  ) {
    final candidates = _evaluateProviders(requirements);
    candidates.sort((final a, final b) => b.score.compareTo(a.score));

    final primary = candidates.first;
    final alternatives = candidates.skip(1).take(2).toList();

    return ProviderRecommendation(
      providerType: primary.providerType,
      configTemplate: primary.configTemplate,
      reason: primary.reason,
      score: primary.score,
      alternatives: alternatives,
    );
  }

  /// Gets all provider recommendations ranked by suitability
  static List<ProviderRecommendation> getAllRecommendations(
    final ProviderRequirements requirements,
  ) {
    final candidates = _evaluateProviders(requirements);
    candidates.sort((final a, final b) => b.score.compareTo(a.score));
    return candidates;
  }

  /// Evaluates all available providers against requirements
  static List<ProviderRecommendation> _evaluateProviders(
    final ProviderRequirements requirements,
  ) => [
    _evaluateFileSystem(requirements),
    _evaluateGitHub(requirements),
    _evaluateOfflineGit(requirements),
  ];

  /// Evaluates FileSystem provider
  static ProviderRecommendation _evaluateFileSystem(
    final ProviderRequirements requirements,
  ) {
    var score = 50; // Base score
    final reasons = <String>[];

    // Advantages
    if (requirements.prioritizeSimplicity) {
      score += 30;
      reasons.add('simple setup and usage');
    }

    if (requirements.needsOffline) {
      score += 20;
      reasons.add('excellent offline support');
    }

    if (requirements.maxLatencyMs != null && requirements.maxLatencyMs! < 100) {
      score += 25;
      reasons.add('minimal latency for local operations');
    }

    if (requirements.expectedDataSize != null &&
        requirements.expectedDataSize! > 100) {
      score += 15;
      reasons.add('handles large datasets efficiently');
    }

    // Disadvantages
    if (requirements.needsVersionControl) {
      score -= 40;
      reasons.add('no version control capabilities');
    }

    if (requirements.needsRemoteSync) {
      score -= 35;
      reasons.add('no remote synchronization');
    }

    if (requirements.needsCollaboration) {
      score -= 40;
      reasons.add('no collaboration features');
    }

    if (requirements.isWeb) {
      score -= 10;
      reasons.add('limited web platform support');
    }

    final configTemplate = FileSystemConfig(
      basePath: requirements.isWeb ? 'app_data' : '/path/to/data',
      databaseName: requirements.isWeb ? 'app_database' : '',
    );

    return ProviderRecommendation(
      providerType: ProviderType.filesystem,
      configTemplate: configTemplate,
      reason: reasons.join(', '),
      score: score.clamp(0, 100),
    );
  }

  /// Evaluates GitHub API provider
  static ProviderRecommendation _evaluateGitHub(
    final ProviderRequirements requirements,
  ) {
    var score = 50; // Base score
    final reasons = <String>[];

    // Advantages
    if (requirements.needsVersionControl) {
      score += 35;
      reasons.add('full version control with Git');
    }

    if (requirements.needsRemoteSync) {
      score += 30;
      reasons.add('cloud-based with automatic sync');
    }

    if (requirements.needsCollaboration) {
      score += 40;
      reasons.add('excellent collaboration features');
    }

    if (requirements.isWeb) {
      score += 25;
      reasons.add('perfect for web applications');
    }

    if (requirements.securityLevel == SecurityLevel.high ||
        requirements.securityLevel == SecurityLevel.enterprise) {
      score += 20;
      reasons.add('enterprise-grade security');
    }

    // Disadvantages
    if (requirements.needsOffline) {
      score -= 45;
      reasons.add('requires internet connection');
    }

    if (requirements.maxLatencyMs != null && requirements.maxLatencyMs! < 500) {
      score -= 20;
      reasons.add('network latency affects performance');
    }

    if (requirements.prioritizeSimplicity) {
      score -= 15;
      reasons.add('requires API token setup');
    }

    final configTemplate = GitHubApiConfig(
      authToken: 'YOUR_GITHUB_TOKEN',
      repositoryOwner: const VcRepositoryOwner('your-username'),
      repositoryName: const VcRepositoryName('your-repo'),
    );

    return ProviderRecommendation(
      providerType: ProviderType.github,
      configTemplate: configTemplate,
      reason: reasons.join(', '),
      score: score.clamp(0, 100),
    );
  }

  /// Evaluates Offline Git provider
  static ProviderRecommendation _evaluateOfflineGit(
    final ProviderRequirements requirements,
  ) {
    var score = 50; // Base score
    final reasons = <String>[];

    // Advantages
    if (requirements.needsVersionControl) {
      score += 40;
      reasons.add('full Git version control');
    }

    if (requirements.needsOffline) {
      score += 35;
      reasons.add('works offline with local Git repository');
    }

    if (requirements.needsRemoteSync && requirements.hasGitCli) {
      score += 35;
      reasons.add('supports remote sync when online');
    }

    if (requirements.hasGitCli) {
      score += 25;
      reasons.add('leverages existing Git installation');
    }

    if (requirements.securityLevel == SecurityLevel.high ||
        requirements.securityLevel == SecurityLevel.enterprise) {
      score += 15;
      reasons.add('local control over data security');
    }

    // Disadvantages
    if (!requirements.hasGitCli) {
      score -= 50;
      reasons.add('requires Git CLI installation');
    }

    if (requirements.isWeb) {
      score -= 40;
      reasons.add('not available in web environments');
    }

    if (requirements.prioritizeSimplicity) {
      score -= 20;
      reasons.add('complex setup and configuration');
    }

    if (requirements.needsCollaboration && !requirements.needsRemoteSync) {
      score -= 30;
      reasons.add('limited collaboration without remote sync');
    }

    final configTemplate = OfflineGitConfig(
      localPath: '/path/to/git/repo',
      branchName: const VcBranchName('main'),
      authorName: 'Your Name',
      authorEmail: 'your.email@example.com',
      remoteUrl: const VcUrl('https://github.com'),
      remoteRepositoryName: const VcRepositoryName('your-repo'),
      remoteRepositoryOwner: const VcRepositoryOwner('your-username'),
    );

    return ProviderRecommendation(
      providerType: ProviderType.git,
      configTemplate: configTemplate,
      reason: reasons.join(', '),
      score: score.clamp(0, 100),
    );
  }

  /// Creates requirements from simple use case descriptions
  static ProviderRequirements fromUseCase(final String useCase) {
    final lowerCase = useCase.toLowerCase();

    // Simple local storage
    if (lowerCase.contains('simple') ||
        lowerCase.contains('local') ||
        lowerCase.contains('basic')) {
      return const ProviderRequirements(
        prioritizeSimplicity: true,
        needsOffline: true,
      );
    }

    // Collaboration and sharing
    if (lowerCase.contains('collaboration') ||
        lowerCase.contains('sharing') ||
        lowerCase.contains('team')) {
      return const ProviderRequirements(
        needsCollaboration: true,
        needsRemoteSync: true,
        needsVersionControl: true,
      );
    }

    // Version control focused
    if (lowerCase.contains('version') ||
        lowerCase.contains('history') ||
        lowerCase.contains('backup')) {
      return const ProviderRequirements(
        needsVersionControl: true,
        needsOffline: true,
        hasGitCli: true, // Assume available for version control use cases
      );
    }

    // Web application
    if (lowerCase.contains('web') ||
        lowerCase.contains('browser') ||
        lowerCase.contains('online')) {
      return const ProviderRequirements(isWeb: true, needsRemoteSync: true);
    }

    // Offline-first
    if (lowerCase.contains('offline') ||
        lowerCase.contains('disconnected') ||
        lowerCase.contains('local-first')) {
      return const ProviderRequirements(
        needsOffline: true,
        needsVersionControl: true,
        hasGitCli: true,
      );
    }

    // Default to balanced requirements
    return const ProviderRequirements(
      needsOffline: true,
      needsVersionControl: true,
    );
  }
}

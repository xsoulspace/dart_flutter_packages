import 'package:github/github.dart';

import '../models/models.dart';
import 'github_version_control_service.dart';
import 'offline_git_version_control_service.dart';
import 'version_control_service.dart';

/// Factory for creating [VersionControlService] instances.
///
/// Provides a unified way to create version control services for different
/// providers (GitHub, GitLab, local Git, etc.) with provider-agnostic models.
class VersionControlFactory {
  /// Creates a GitHub version control service with authentication.
  static VersionControlService createGitHub({
    required final String token,
    final VcRepositoryId? currentRepository,
  }) {
    final github = GitHub(auth: Authentication.withToken(token));
    return GitHubVersionControlService(
      github: github,
      currentRepository: currentRepository,
    );
  }

  /// Creates an offline Git version control service for local operations.
  static VersionControlService createOfflineGit({
    required final String workingDirectory,
    final VcRepositoryId? currentRepository,
  }) => OfflineGitVersionControlService(
    workingDirectory: workingDirectory,
    currentRepository: currentRepository,
  );

  /// Creates a version control service based on provider type.
  static VersionControlService create({
    required final VcProviderType providerType,
    final String? token,
    final String? workingDirectory,
    final VcRepositoryId? currentRepository,
  }) {
    switch (providerType) {
      case VcProviderType.github:
        if (token == null) {
          throw ArgumentError('Token is required for GitHub provider');
        }
        return createGitHub(token: token, currentRepository: currentRepository);

      case VcProviderType.offlineGit:
        if (workingDirectory == null) {
          throw ArgumentError(
            'Working directory is required for offline Git provider',
          );
        }
        return createOfflineGit(
          workingDirectory: workingDirectory,
          currentRepository: currentRepository,
        );
    }
  }
}

/// Supported version control provider types.
enum VcProviderType {
  /// GitHub cloud provider
  github,

  /// Local Git repositories
  offlineGit,
}

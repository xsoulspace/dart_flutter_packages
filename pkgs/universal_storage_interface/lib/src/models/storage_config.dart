import 'version_control_models.dart';

sealed class StorageConfig {
  const StorageConfig();
  Map<String, dynamic> toMap();
}

class FileSystemConfig extends StorageConfig {
  FileSystemConfig({required this.basePath, this.databaseName = ''}) {
    if (basePath.isEmpty) throw ArgumentError('Base path cannot be empty');
  }
  final String basePath;
  final String databaseName;
  @override
  Map<String, dynamic> toMap() => {
    'basePath': basePath,
    if (databaseName.isNotEmpty) 'databaseName': databaseName,
  };
}

class OfflineGitConfig extends StorageConfig {
  OfflineGitConfig({
    this.localPath = './',
    this.branchName = VcBranchName.main,
    this.authorName,
    this.authorEmail,
    this.remoteUrl = VcUrl.empty,
    this.remoteRepositoryName = VcRepositoryName.empty,
    this.remoteRepositoryOwner = VcRepositoryOwner.empty,
    this.remoteName = 'origin',
    this.remoteType,
    this.remoteApiSettings,
    this.defaultPullStrategy = 'merge',
    this.defaultPushStrategy = 'rebase-local',
    this.conflictResolution = 'client-always-right',
    this.sshKeyPath,
    this.httpsToken,
  }) {
    if (localPath.isEmpty) throw ArgumentError('Local path cannot be empty');
    if (branchName.isEmpty) throw ArgumentError('Branch name cannot be empty');
    if (defaultPullStrategy.isEmpty)
      throw ArgumentError('Pull strategy cannot be empty');
    if (defaultPushStrategy.isEmpty)
      throw ArgumentError('Push strategy cannot be empty');
  }
  final String localPath;
  final VcBranchName branchName;
  final String? authorName;
  final String? authorEmail;
  final VcUrl remoteUrl;
  final VcRepositoryName remoteRepositoryName;
  final VcRepositoryOwner remoteRepositoryOwner;
  VcRepositorySlug get remoteRepositorySlug => VcRepositorySlug.fromJson(
    repositoryName: remoteRepositoryName,
    repositoryOwner: remoteRepositoryOwner,
  );
  final String remoteName;
  final String? remoteType;
  final Map<String, dynamic>? remoteApiSettings;
  final String defaultPullStrategy;
  final String defaultPushStrategy;
  final String conflictResolution;
  final String? sshKeyPath;
  final String? httpsToken;

  @override
  Map<String, dynamic> toMap() => {
    'localPath': localPath,
    'branchName': branchName,
    if (authorName != null) 'authorName': authorName,
    if (authorEmail != null) 'authorEmail': authorEmail,
    'remoteName': remoteName,
    if (remoteUrl.isNotEmpty) 'remoteUrl': remoteUrl,
    if (remoteRepositorySlug.isNotEmpty)
      'remoteRepositorySlug': remoteRepositorySlug,
    if (remoteRepositoryName.isNotEmpty)
      'remoteRepositoryName': remoteRepositoryName,
    if (remoteRepositoryOwner.isNotEmpty)
      'remoteRepositoryOwner': remoteRepositoryOwner,
    if (remoteType != null) 'remoteType': remoteType,
    if (remoteApiSettings != null) 'remoteApiSettings': remoteApiSettings,
    'defaultPullStrategy': defaultPullStrategy,
    'defaultPushStrategy': defaultPushStrategy,
    'conflictResolution': conflictResolution,
    if (sshKeyPath != null) 'sshKeyPath': sshKeyPath,
    if (httpsToken != null) 'httpsToken': httpsToken,
  };
}

class GitHubApiConfig extends StorageConfig {
  GitHubApiConfig({
    required this.authToken,
    required this.repositoryOwner,
    required this.repositoryName,
    this.branchName = VcBranchName.main,
  }) {
    if (authToken.isEmpty) throw ArgumentError('Auth token cannot be empty');
    if (repositoryOwner.isEmpty)
      throw ArgumentError('Repository owner cannot be empty');
    if (repositoryName.isEmpty)
      throw ArgumentError('Repository name cannot be empty');
    if (branchName.isEmpty) throw ArgumentError('Branch name cannot be empty');
  }
  final String authToken;
  final VcRepositoryOwner repositoryOwner;
  final VcRepositoryName repositoryName;
  final VcBranchName branchName;

  @override
  Map<String, dynamic> toMap() => {
    'authToken': authToken,
    'repositoryOwner': repositoryOwner,
    'repositoryName': repositoryName,
    'branchName': branchName,
  };
}

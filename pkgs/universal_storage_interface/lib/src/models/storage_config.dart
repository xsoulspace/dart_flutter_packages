import 'conflict_resolution_strategy.dart';
import 'file_path_config.dart';
import 'version_control_models.dart';

/// {@template storage_config}
/// Base class for all storage configurations.
/// {@endtemplate}
sealed class StorageConfig {
  /// {@macro storage_config}
  const StorageConfig();

  /// Converts the configuration to a JSON-serializable map.
  Map<String, dynamic> toMap();
}

/// {@template file_system_config}
/// Configuration for the file system storage provider.
/// {@endtemplate}
class FileSystemConfig extends StorageConfig {
  /// {@macro file_system_config}
  FileSystemConfig({required this.filePathConfig, this.databaseName = ''})
    : _allowEmpty = false {
    _validate();
  }

  FileSystemConfig._empty()
    : filePathConfig = FilePathConfig.empty,
      databaseName = '',
      _allowEmpty = true;

  /// Creates a [FileSystemConfig] from a [FilePathConfig].
  factory FileSystemConfig.fromFilePathConfig(
    final FilePathConfig filePathConfig, {
    final String? databaseName,
  }) => FileSystemConfig(
    filePathConfig: filePathConfig,
    databaseName: databaseName ?? '',
  );

  /// The file path configuration.
  final FilePathConfig filePathConfig;

  /// The base path of the file system.
  String get basePath => filePathConfig.path.path;

  /// The name of the database.
  final String databaseName;

  final bool _allowEmpty;

  void _validate() {
    if (!_allowEmpty && filePathConfig.isEmpty) {
      throw ArgumentError('filePathConfig cannot be empty');
    }
  }

  /// Whether the configuration is empty.
  bool get isEmpty => filePathConfig.isEmpty;

  /// Whether the configuration is not empty.
  bool get isNotEmpty => !isEmpty;

  @override
  Map<String, dynamic> toMap() => {
    'basePath': basePath,
    if (databaseName.isNotEmpty) 'databaseName': databaseName,
  };

  static final empty = FileSystemConfig._empty();
}

/// {@template local_db_storage_config}
/// Configuration for the local database storage provider.
/// {@endtemplate}
class LocalDbStorageConfig extends StorageConfig {
  /// {@macro local_db_storage_config}
  const LocalDbStorageConfig({required this.keyspacePrefix});

  final String keyspacePrefix;

  @override
  Map<String, dynamic> toMap() => <String, dynamic>{
    'keyspacePrefix': keyspacePrefix,
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
    this.conflictResolution = ConflictResolutionStrategy.clientAlwaysRight,
    this.sshKeyPath,
    this.httpsToken,
  }) {
    if (localPath.isEmpty) throw ArgumentError('Local path cannot be empty');
    if (branchName.isEmpty) throw ArgumentError('Branch name cannot be empty');
    if (defaultPullStrategy.isEmpty) {
      throw ArgumentError('Pull strategy cannot be empty');
    }
    if (defaultPushStrategy.isEmpty) {
      throw ArgumentError('Push strategy cannot be empty');
    }
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
  final ConflictResolutionStrategy conflictResolution;
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
    'conflictResolution': conflictResolution.name,
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
    if (repositoryOwner.isEmpty) {
      throw ArgumentError('Repository owner cannot be empty');
    }
    if (repositoryName.isEmpty) {
      throw ArgumentError('Repository name cannot be empty');
    }
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

/// CloudKit runtime environment.
enum CloudKitEnvironment { development, production }

/// CloudKit database scope for v1 provider surface.
enum CloudKitDatabaseScope { privateDb }

/// CloudKit data mode for universal storage behavior.
enum CloudKitDataMode { remoteOnly, localMirror }

/// Configuration for the CloudKit storage provider.
class CloudKitConfig extends StorageConfig {
  CloudKitConfig({
    required this.containerId,
    this.environment = CloudKitEnvironment.development,
    this.databaseScope = CloudKitDatabaseScope.privateDb,
    this.dataMode = CloudKitDataMode.remoteOnly,
    this.zoneName = 'UniversalStorageZone',
    this.recordType = 'USFile',
    this.maxInlineBytes = 262144,
    this.webApiToken,
    this.localMirrorConfig,
    this.fallbackConfig,
  }) {
    _validate();
  }

  final String containerId;
  final CloudKitEnvironment environment;
  final CloudKitDatabaseScope databaseScope;
  final CloudKitDataMode dataMode;
  final String zoneName;
  final String recordType;
  final int maxInlineBytes;
  final String? webApiToken;
  final FileSystemConfig? localMirrorConfig;
  final StorageConfig? fallbackConfig;

  static bool get _isWeb =>
      const bool.fromEnvironment('dart.library.js_interop') ||
      const bool.fromEnvironment('dart.library.js');

  void _validate() {
    if (containerId.trim().isEmpty) {
      throw ArgumentError('containerId cannot be empty');
    }
    if (zoneName.trim().isEmpty) {
      throw ArgumentError('zoneName cannot be empty');
    }
    if (recordType.trim().isEmpty) {
      throw ArgumentError('recordType cannot be empty');
    }
    if (maxInlineBytes <= 0) {
      throw ArgumentError('maxInlineBytes must be greater than 0');
    }
    if (databaseScope != CloudKitDatabaseScope.privateDb) {
      throw ArgumentError(
        'CloudKit v1 supports only CloudKitDatabaseScope.privateDb',
      );
    }
    if (dataMode == CloudKitDataMode.localMirror &&
        (localMirrorConfig == null || localMirrorConfig!.isEmpty)) {
      throw ArgumentError(
        'localMirrorConfig is required when dataMode is localMirror',
      );
    }
    if (_isWeb && (webApiToken == null || webApiToken!.trim().isEmpty)) {
      throw ArgumentError('webApiToken is required on web platforms');
    }
    if (fallbackConfig is CloudKitConfig) {
      throw ArgumentError(
        'fallbackConfig cannot be CloudKitConfig to avoid recursion',
      );
    }
  }

  @override
  Map<String, dynamic> toMap() => {
    'containerId': containerId,
    'environment': environment.name,
    'databaseScope': databaseScope.name,
    'dataMode': dataMode.name,
    'zoneName': zoneName,
    'recordType': recordType,
    'maxInlineBytes': maxInlineBytes,
    if (webApiToken != null) 'webApiToken': webApiToken,
    if (localMirrorConfig != null)
      'localMirrorConfig': localMirrorConfig!.toMap(),
    if (fallbackConfig != null) 'fallbackConfig': fallbackConfig!.toMap(),
  };
}

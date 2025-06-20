import 'package:from_json_to_json/from_json_to_json.dart';

/// Extension type that represents a version control repository.
///
/// Provider-agnostic model that can work with GitHub, GitLab, Bitbucket, etc.
/// Contains essential repository information needed for version control operations.
///
/// Uses from_json_to_json for type-safe JSON handling.
extension type const VcRepository(Map<String, dynamic> value) {
  // ignore: avoid_annotating_with_dynamic
  factory VcRepository.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return VcRepository(map);
  }

  /// Repository unique identifier
  String get id => jsonDecodeString(value['id']);

  /// Repository name
  String get name => jsonDecodeString(value['name']);

  /// Repository description
  String get description => jsonDecodeString(value['description']);

  /// Repository clone URL (HTTPS)
  String get cloneUrl => jsonDecodeString(value['clone_url']);

  /// Default branch name (typically 'main' or 'master')
  String get defaultBranch => jsonDecodeString(value['default_branch']);

  /// Whether the repository is private
  bool get isPrivate => jsonDecodeBool(value['is_private']);

  /// Repository owner/organization name
  String get owner => jsonDecodeString(value['owner']);

  /// Full repository name (owner/repo)
  String get fullName => jsonDecodeString(value['full_name']);

  /// Repository web URL
  String get webUrl => jsonDecodeString(value['web_url']);

  Map<String, dynamic> toJson() => value;

  static const empty = VcRepository({});
}

/// Extension type that represents a version control branch.
///
/// Provider-agnostic model for branch information across different
/// version control systems.
extension type const VcBranch(Map<String, dynamic> value) {
  // ignore: avoid_annotating_with_dynamic
  factory VcBranch.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return VcBranch(map);
  }

  /// Branch name
  String get name => jsonDecodeString(value['name']);

  /// Latest commit SHA/hash on this branch
  String get commitSha => jsonDecodeString(value['commit_sha']);

  /// Whether this is the default branch
  bool get isDefault => jsonDecodeBool(value['is_default']);

  /// Whether this branch is protected
  bool get isProtected => jsonDecodeBool(value['is_protected']);

  Map<String, dynamic> toJson() => value;

  static const empty = VcBranch({});
}

/// Extension type that represents a request to create a new repository.
///
/// Provider-agnostic model for repository creation parameters that
/// can be adapted to different version control platforms.
extension type const VcCreateRepositoryRequest(Map<String, dynamic> value) {
  // ignore: avoid_annotating_with_dynamic
  factory VcCreateRepositoryRequest.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return VcCreateRepositoryRequest(map);
  }

  /// Repository name (required)
  String get name => jsonDecodeString(value['name']);

  /// Repository description
  String get description => jsonDecodeString(value['description']);

  /// Whether the repository should be private
  bool get isPrivate => jsonDecodeBool(value['is_private']);

  /// Whether to initialize with README
  bool get initializeWithReadme =>
      jsonDecodeBool(value['initialize_with_readme']);

  /// License identifier (e.g., 'mit', 'apache-2.0')
  String get license => jsonDecodeString(value['license']);

  /// .gitignore template name
  String get gitignoreTemplate => jsonDecodeString(value['gitignore_template']);

  /// Organization/team name (if creating in an organization)
  String get organization => jsonDecodeString(value['organization']);

  Map<String, dynamic> toJson() => value;

  static const empty = VcCreateRepositoryRequest({});
}

/// Extension type that represents a repository identifier.
///
/// Simple string-based identifier for referencing repositories
/// across different providers.
extension type const VcRepositoryId(String value) {
  // ignore: avoid_annotating_with_dynamic
  factory VcRepositoryId.fromJson(final dynamic value) =>
      VcRepositoryId(jsonDecodeString(value));

  String toJson() => value;

  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;

  VcRepositoryId whenEmptyUse(final VcRepositoryId other) =>
      isEmpty ? other : this;

  static const empty = VcRepositoryId('');
}

/// Extension type that represents a branch name.
///
/// Simple string-based identifier for branch names that provides
/// type safety and common branch operations.
extension type const VcBranchName(String value) {
  // ignore: avoid_annotating_with_dynamic
  factory VcBranchName.fromJson(final dynamic value) =>
      VcBranchName(jsonDecodeString(value));

  String toJson() => value;

  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;

  /// Check if this is a main/master branch
  bool get isMainBranch => value == 'main' || value == 'master';

  /// Check if this is a development branch
  bool get isDevelopmentBranch =>
      value == 'develop' || value == 'dev' || value.startsWith('feature/');

  VcBranchName whenEmptyUse(final VcBranchName other) => isEmpty ? other : this;

  static const empty = VcBranchName('');
  static const main = VcBranchName('main');
  static const master = VcBranchName('master');
  static const develop = VcBranchName('develop');
}

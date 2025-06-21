import 'package:from_json_to_json/from_json_to_json.dart';

/// Extension type that represents a version control repository.
///
/// Provider-agnostic model that can work with GitHub, GitLab, Bitbucket, etc.
/// Contains essential repository information needed for version control
/// operations.
///
/// Uses from_json_to_json for type-safe JSON handling.
///
/// Example usage:
/// ```dart
/// final repo = VcRepository.fromJson(jsonData);
/// print('Repository: ${repo.fullName}');
/// print('Clone URL: ${repo.cloneUrl}');
/// ```
extension type const VcRepository(Map<String, dynamic> value) {
  /// Creates a [VcRepository] from JSON data.
  ///
  /// Throws [FormatException] if the JSON data is invalid.
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

  /// Converts this repository to JSON format.
  Map<String, dynamic> toJson() => value;

  /// Empty repository instance.
  static const empty = VcRepository({});
}

/// Extension type that represents a version control branch.
///
/// Provider-agnostic model for branch information across different
/// version control systems.
///
/// Example usage:
/// ```dart
/// final branch = VcBranch.fromJson(jsonData);
/// print('Branch: ${branch.name}');
/// print('Latest commit: ${branch.commitSha}');
/// ```
extension type const VcBranch(Map<String, dynamic> value) {
  /// Creates a [VcBranch] from JSON data.
  ///
  /// Throws [FormatException] if the JSON data is invalid.
  // ignore: avoid_annotating_with_dynamic
  factory VcBranch.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return VcBranch(map);
  }

  /// Branch name
  VcBranchName get name => VcBranchName.fromJson(value['name']);

  /// Latest commit SHA/hash on this branch
  String get commitSha => jsonDecodeString(value['commit_sha']);

  /// Whether this is the default branch
  bool get isDefault => jsonDecodeBool(value['is_default']);

  /// Whether this branch is protected
  bool get isProtected => jsonDecodeBool(value['is_protected']);

  /// Converts this branch to JSON format.
  Map<String, dynamic> toJson() => value;

  /// Empty branch instance.
  static const empty = VcBranch({});
}

/// Extension type that represents a request to create a new repository.
///
/// Provider-agnostic model for repository creation parameters that
/// can be adapted to different version control platforms.
///
/// Example usage:
/// ```dart
/// final request = VcCreateRepositoryRequest({
///   'name': 'my-repo',
///   'description': 'A new repository',
///   'is_private': true,
///   'initialize_with_readme': true,
/// });
/// ```
extension type const VcCreateRepositoryRequest(Map<String, dynamic> value) {
  /// Creates a [VcCreateRepositoryRequest] from JSON data.
  ///
  /// Throws [FormatException] if the JSON data is invalid.
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

  /// Converts this request to JSON format.
  Map<String, dynamic> toJson() => value;

  /// Empty repository creation request instance.
  static const empty = VcCreateRepositoryRequest({});
}

/// Extension type that represents a URL.
///
/// Simple string-based identifier for URLs that provides
/// type safety and common URL operations.
///
/// Example usage:
/// ```dart
/// final url = VcUrl('https://github.com/owner/repo.git');
/// if (url.isNotEmpty) {
///   print('URL: $url');
/// }
/// ```
extension type const VcUrl(String value) {
  /// Creates a [VcUrl] from JSON data.
  ///
  /// Throws [FormatException] if the JSON data is invalid.
  // ignore: avoid_annotating_with_dynamic
  factory VcUrl.fromJson(final dynamic value) => VcUrl(jsonDecodeString(value));

  /// Converts this URL to JSON format.
  String toJson() => value;

  /// Whether this URL is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether this URL is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns this URL if not empty, otherwise returns [other].
  ///
  /// Useful for providing fallback values.
  VcUrl whenEmptyUse(final VcUrl other) => isEmpty ? other : this;

  /// Empty URL instance.
  static const empty = VcUrl('');
}

/// Extension type that represents a repository slug.
///
/// Simple string-based identifier for referencing repositories
/// across different providers.
///
/// Example usage:
/// ```dart
/// final repoSlug = VcRepositorySlug('https://github.com/owner/repo-name');
extension type const VcRepositorySlug._(String value) {
  /// Creates a [VcRepositorySlug] from JSON data.
  ///
  /// Throws [FormatException] if the JSON data is invalid.
  // ignore: avoid_annotating_with_dynamic
  factory VcRepositorySlug.fromJson({
    required final VcRepositoryName repositoryName,
    required final VcRepositoryOwner repositoryOwner,
  }) => VcRepositorySlug._('$repositoryOwner/$repositoryName');

  /// Converts this repository slug to JSON format.
  String toJson() => value;

  /// Whether this repository slug is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether this repository slug is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns this repository slug if not empty, otherwise returns [other].
  ///
  /// Useful for providing fallback values.
  VcRepositorySlug whenEmptyUse(final VcRepositorySlug other) =>
      isEmpty ? other : this;

  /// Empty repository slug instance.
  static const empty = VcRepositorySlug._('');
}

/// Extension type that represents a repository owner.
///
/// Simple string-based identifier for referencing repository owners
/// across different providers.
///
/// Example usage:
/// ```dart
/// final repoOwner = VcRepositoryOwner('owner');
/// if (repoOwner.isNotEmpty) {
///   print('Repository owner: $repoOwner');
/// }
/// ```
extension type const VcRepositoryOwner(String value) {
  /// Creates a [VcRepositoryOwner] from JSON data.
  ///
  /// Throws [FormatException] if the JSON data is invalid.
  // ignore: avoid_annotating_with_dynamic
  factory VcRepositoryOwner.fromJson(final dynamic value) =>
      VcRepositoryOwner(jsonDecodeString(value));

  /// Converts this repository owner to JSON format.
  String toJson() => value;

  /// Whether this repository owner is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether this repository owner is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns this repository owner if not empty, otherwise returns [other].
  ///
  /// Useful for providing fallback values.
  VcRepositoryOwner whenEmptyUse(final VcRepositoryOwner other) =>
      isEmpty ? other : this;

  /// Empty repository owner instance.
  static const empty = VcRepositoryOwner('');
}

/// Extension type that represents a repository name.
///
/// Simple string-based identifier for referencing repositories
/// across different providers.
///
/// Example usage:
/// ```dart
/// final repoName = VcRepositoryName('repo-name');
/// if (repoName.isNotEmpty) {
///   print('Repository: $repoName');
/// }
/// ```
extension type const VcRepositoryName(String value) {
  /// Creates a [VcRepositoryName] from JSON data.
  ///
  /// Throws [FormatException] if the JSON data is invalid.
  // ignore: avoid_annotating_with_dynamic
  factory VcRepositoryName.fromJson(final dynamic value) =>
      VcRepositoryName(jsonDecodeString(value));

  /// Converts this repository name to JSON format.
  String toJson() => value;

  /// Whether this repository name is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether this repository name is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns this repository name if not empty, otherwise returns [other].
  ///
  /// Useful for providing fallback values.
  VcRepositoryName whenEmptyUse(final VcRepositoryName other) =>
      isEmpty ? other : this;

  /// Empty repository name instance.
  static const empty = VcRepositoryName('');
}

/// Extension type that represents a branch name.
///
/// Simple string-based identifier for branch names that provides
/// type safety and common branch operations.
///
/// Example usage:
/// ```dart
/// final branchName = VcBranchName('feature/new-feature');
/// if (branchName.isDevelopmentBranch) {
///   print('Development branch: $branchName');
/// }
/// ```
extension type const VcBranchName(String value) {
  /// Creates a [VcBranchName] from JSON data.
  ///
  /// Throws [FormatException] if the JSON data is invalid.
  // ignore: avoid_annotating_with_dynamic
  factory VcBranchName.fromJson(final dynamic value) =>
      VcBranchName(jsonDecodeString(value));

  /// Converts this branch name to JSON format.
  String toJson() => value;

  /// Whether this branch name is empty.
  bool get isEmpty => value.isEmpty;

  /// Whether this branch name is not empty.
  bool get isNotEmpty => value.isNotEmpty;

  /// Check if this is a main/master branch
  bool get isMainBranch => value == 'main' || value == 'master';

  /// Check if this is a development branch
  bool get isDevelopmentBranch =>
      value == 'develop' ||
      value == 'dev' ||
      value.startsWith('feature/') ||
      value.startsWith('feat/');

  /// Returns this branch name if not empty, otherwise returns [other].
  ///
  /// Useful for providing fallback values.
  VcBranchName whenEmptyUse(final VcBranchName other) => isEmpty ? other : this;

  /// Empty branch name instance.
  static const empty = VcBranchName('');

  /// Main branch name instance.
  static const main = VcBranchName('main');

  /// Master branch name instance.
  static const master = VcBranchName('master');

  /// Develop branch name instance.
  static const develop = VcBranchName('develop');
}

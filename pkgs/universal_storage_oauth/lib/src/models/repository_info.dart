import 'package:from_json_to_json/from_json_to_json.dart';

/// Extension type that represents a repository ID.
///
/// Type-safe wrapper around repository identifiers to prevent mixing
/// with other string types at compile time. This ensures that repository IDs
/// are handled consistently throughout the codebase and prevents accidental
/// type mismatches.
///
/// Example usage:
/// ```dart
/// final repoId = RepositoryId('123456789');
/// final isEmpty = repoId.isEmpty; // false
/// final fallbackId = repoId.whenEmptyUse(RepositoryId('default'));
/// ```
extension type const RepositoryId(String value) {
  /// Creates a RepositoryId from JSON data.
  ///
  /// Safely decodes the input value to a string and wraps it in a RepositoryId.
  /// Handles null values and invalid JSON gracefully.
  ///
  /// [value] - The JSON value to decode, typically a string or number
  /// Returns a new RepositoryId instance
  // ignore: avoid_annotating_with_dynamic
  factory RepositoryId.fromJson(final dynamic value) =>
      RepositoryId(jsonDecodeString(value));

  /// Converts the RepositoryId back to JSON format.
  ///
  /// Returns the underlying string value, which can be directly serialized
  /// to JSON.
  ///
  /// Returns the repository ID as a string
  String toJson() => value;

  /// Checks if the repository ID is empty.
  ///
  /// Returns true if the underlying string value is empty or contains only
  /// whitespace characters.
  ///
  /// Returns true if the repository ID is empty, false otherwise
  bool get isEmpty => value.isEmpty;

  /// Checks if the repository ID is not empty.
  ///
  /// Returns true if the underlying string value contains at least one
  /// non-whitespace character.
  ///
  /// Returns true if the repository ID is not empty, false otherwise
  bool get isNotEmpty => value.isNotEmpty;

  /// Returns this repository ID if not empty, otherwise returns
  /// the provided fallback.
  ///
  /// Useful for providing default values when a repository ID might be empty.
  /// This method ensures that you always have a valid repository ID to work
  /// with.
  ///
  /// [other] - The fallback repository ID to use if this one is empty
  /// Returns this repository ID if not empty, otherwise returns [other]
  RepositoryId whenEmptyUse(final RepositoryId other) => isEmpty ? other : this;

  /// An empty repository ID instance.
  ///
  /// Useful as a default value or for representing missing repository IDs.
  /// This is a singleton instance that can be safely shared.
  static const empty = RepositoryId('');
}

/// Extension type that represents repository owner type.
///
/// Distinguishes between user and organization accounts in a type-safe manner.
enum RepositoryOwnerType {
  /// A user account.
  user('User'),

  /// An organization account.
  organization('Organization'),

  /// An unknown account.
  unknown('Unknown');

  const RepositoryOwnerType(this.value);

  factory RepositoryOwnerType.fromJson(final String value) =>
      RepositoryOwnerType.values.firstWhere(
        (final type) => type.value == value,
        orElse: () => unknown,
      );

  /// The value of the repository owner type.
  final String value;

  /// Converts the repository owner type to JSON format.
  ///
  /// Returns the underlying string value, which can be directly serialized
  /// to JSON.
  String toJson() => value;

  /// Whether the repository owner is a user.
  bool get isUser => this == user;

  /// Whether the repository owner is an organization.
  bool get isOrganization => this == organization;
}

/// Extension type that represents a repository owner.
///
/// Contains information about the user or organization that owns a repository.
/// Provides type-safe access to owner data with graceful handling of missing
/// fields.
extension type const RepositoryOwner(Map<String, dynamic> value) {
  /// Creates a repository owner from JSON data.
  ///
  /// Decodes the JSON value to a map and wraps it in a RepositoryOwner.
  ///
  /// Parameters:
  /// - [jsonData]: The JSON data to decode, typically a map or dynamic value.
  // ignore: avoid_annotating_with_dynamic
  factory RepositoryOwner.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return RepositoryOwner(map);
  }

  /// Creates a repository owner with required fields.
  factory RepositoryOwner.create({
    required final String id,
    required final String login,
    required final RepositoryOwnerType type,
    final String? avatarUrl,
    final String? htmlUrl,
  }) => RepositoryOwner({
    'id': id,
    'login': login,
    'type': type.value,
    'avatar_url': avatarUrl,
    'html_url': htmlUrl,
  });

  /// The unique identifier for the owner.
  String get id => jsonDecodeString(value['id']);

  /// The username/login handle.
  String get login => jsonDecodeString(value['login']);

  /// Type of owner (user or organization)
  RepositoryOwnerType get type =>
      RepositoryOwnerType.fromJson(jsonDecodeString(value['type']));

  /// URL to owner's avatar image (may be null)
  String? get avatarUrl {
    final str = jsonDecodeString(value['avatar_url']);
    return str.isEmpty ? null : str;
  }

  /// URL to owner's profile page (may be null)
  String? get htmlUrl {
    final str = jsonDecodeString(value['html_url']);
    return str.isEmpty ? null : str;
  }

  /// Converts the repository owner to JSON format.
  ///
  /// Returns the underlying map of strings to dynamic values directly.
  Map<String, dynamic> toJson() => value;

  /// An empty repository owner instance.
  ///
  /// Represents a repository owner with no information.
  static const empty = RepositoryOwner({});
}

/// Extension type that represents repository permissions.
///
/// Contains permission flags for repository access levels.
/// Used to determine what operations a user can perform on a repository.
extension type const RepositoryPermissions(Map<String, dynamic> value) {
  /// Creates repository permissions from JSON data.
  ///
  /// Decodes the JSON value to a map and wraps it in a RepositoryPermissions.
  ///
  /// Parameters:
  /// - [jsonData]: The JSON data to decode, typically a map or dynamic value.
  // ignore: avoid_annotating_with_dynamic
  factory RepositoryPermissions.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return RepositoryPermissions(map);
  }

  /// Create repository permissions with specific flags
  factory RepositoryPermissions.create({
    required final bool admin,
    required final bool push,
    required final bool pull,
  }) => RepositoryPermissions({'admin': admin, 'push': push, 'pull': pull});

  /// Whether user has admin permissions
  bool get admin => jsonDecodeBool(value['admin']);

  /// Whether user can push to the repository
  bool get push => jsonDecodeBool(value['push']);

  /// Whether user can pull from the repository
  bool get pull => jsonDecodeBool(value['pull']);

  /// Whether user has write access (push or admin)
  bool get canWrite => push || admin;

  /// Whether user has read access
  bool get canRead => pull || push || admin;

  /// Converts the repository permissions to JSON format.
  ///
  /// Returns the underlying map of strings to dynamic values directly.
  Map<String, dynamic> toJson() => value;

  /// An empty repository permissions instance.
  ///
  /// Represents repository permissions with no information.
  static const empty = RepositoryPermissions({});

  /// A read-only repository permissions instance.
  ///
  /// Represents repository permissions with read-only access.
  static const readOnly = RepositoryPermissions({
    'admin': false,
    'push': false,
    'pull': true,
  });

  /// A full access repository permissions instance.
  ///
  /// Represents repository permissions with full access.
  static const fullAccess = RepositoryPermissions({
    'admin': true,
    'push': true,
    'pull': true,
  });
}

/// Extension type that represents complete repository information.
///
/// Contains all relevant data about a Git repository including metadata,
/// ownership, permissions, and URLs for various operations.
///
/// Uses from_json_to_json for type-safe JSON handling.
extension type const RepositoryInfo(Map<String, dynamic> value) {
  /// Creates a repository info from JSON data.
  ///
  /// Decodes the JSON value to a map and wraps it in a RepositoryInfo.
  ///
  /// Parameters:
  /// - [jsonData]: The JSON data to decode, typically a map or dynamic value.
  // ignore: avoid_annotating_with_dynamic
  factory RepositoryInfo.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return RepositoryInfo(map);
  }

  /// Create repository info with required fields
  factory RepositoryInfo.create({
    required final String id,
    required final String name,
    required final String fullName,
    required final RepositoryOwner owner,
    final String? description,
    final bool isPrivate = false,
    final String? defaultBranch,
    final String? cloneUrl,
    final String? sshUrl,
    final String? htmlUrl,
    final DateTime? createdAt,
    final DateTime? updatedAt,
    final RepositoryPermissions? permissions,
    final String? language,
    final int starCount = 0,
    final int forkCount = 0,
    final int size = 0,
  }) => RepositoryInfo({
    'id': id,
    'name': name,
    'full_name': fullName,
    'owner': owner.toJson(),
    'description': description,
    'private': isPrivate,
    'default_branch': defaultBranch,
    'clone_url': cloneUrl,
    'ssh_url': sshUrl,
    'html_url': htmlUrl,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'permissions': permissions?.toJson(),
    'language': language,
    'stargazers_count': starCount,
    'forks_count': forkCount,
    'size': size,
  });

  /// Repository unique identifier
  RepositoryId get id => RepositoryId.fromJson(value['id']);

  /// Repository name
  String get name => jsonDecodeString(value['name']);

  /// Full name including owner (e.g., "owner/repo")
  String get fullName => jsonDecodeString(value['full_name']);

  /// Repository owner information
  RepositoryOwner get owner => RepositoryOwner.fromJson(value['owner']);

  /// Repository description (may be null)
  String? get description {
    final str = jsonDecodeString(value['description']);
    return str.isEmpty ? null : str;
  }

  /// Whether the repository is private
  bool get isPrivate => jsonDecodeBool(value['private']);

  /// Whether the repository is public
  bool get isPublic => !isPrivate;

  /// Default branch name (may be null)
  String? get defaultBranch {
    final str = jsonDecodeString(value['default_branch']);
    return str.isEmpty ? null : str;
  }

  /// HTTPS clone URL (may be null)
  String? get cloneUrl {
    final str = jsonDecodeString(value['clone_url']);
    return str.isEmpty ? null : str;
  }

  /// SSH clone URL (may be null)
  String? get sshUrl {
    final str = jsonDecodeString(value['ssh_url']);
    return str.isEmpty ? null : str;
  }

  /// HTML URL to repository page (may be null)
  String? get htmlUrl {
    final str = jsonDecodeString(value['html_url']);
    return str.isEmpty ? null : str;
  }

  /// Repository creation date (may be null)
  DateTime? get createdAt {
    final dateStr = jsonDecodeString(value['created_at']);
    return dateStr.isEmpty ? null : dateTimeFromIso8601String(dateStr);
  }

  /// Repository last update date (may be null)
  DateTime? get updatedAt {
    final dateStr = jsonDecodeString(value['updated_at']);
    return dateStr.isEmpty ? null : dateTimeFromIso8601String(dateStr);
  }

  /// User permissions for this repository (may be null)
  RepositoryPermissions? get permissions {
    final permMap = value['permissions'];
    if (permMap == null) return null;
    return RepositoryPermissions.fromJson(permMap);
  }

  /// Whether user can read from this repository
  bool get canRead => permissions?.canRead ?? isPublic;

  /// Whether user can write to this repository
  bool get canWrite => permissions?.canWrite ?? false;

  /// Whether user has admin access to this repository
  bool get canAdmin => permissions?.admin ?? false;

  /// Primary programming language (may be null)
  String? get language {
    final str = jsonDecodeString(value['language']);
    return str.isEmpty ? null : str;
  }

  /// Number of stars/stargazers
  int get starCount => jsonDecodeInt(value['stargazers_count']);

  /// Number of forks
  int get forkCount => jsonDecodeInt(value['forks_count']);

  /// Repository size in KB
  int get size => jsonDecodeInt(value['size']);

  /// Converts the repository info to JSON format.
  ///
  /// Returns the underlying map of strings to dynamic values directly.
  Map<String, dynamic> toJson() => value;

  /// An empty repository info instance.
  ///
  /// Represents repository info with no information.
  static const empty = RepositoryInfo({});
}

import 'package:from_json_to_json/from_json_to_json.dart';

/// Extension type that represents a repository ID.
///
/// Type-safe wrapper around repository identifiers to prevent mixing
/// with other string types at compile time.
extension type const RepositoryId(String value) {
  factory RepositoryId.fromJson(final dynamic value) =>
      RepositoryId(jsonDecodeString(value));

  String toJson() => value;

  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;

  RepositoryId whenEmptyUse(final RepositoryId other) => isEmpty ? other : this;

  static const empty = RepositoryId('');
}

/// Extension type that represents repository owner type.
///
/// Distinguishes between user and organization accounts in a type-safe manner.
extension type const RepositoryOwnerType(String value) {
  factory RepositoryOwnerType.fromJson(final dynamic value) =>
      RepositoryOwnerType(jsonDecodeString(value));

  String toJson() => value;

  bool get isUser => value == 'User';
  bool get isOrganization => value == 'Organization';

  static const user = RepositoryOwnerType('User');
  static const organization = RepositoryOwnerType('Organization');
  static const unknown = RepositoryOwnerType('Unknown');
}

/// Extension type that represents a repository owner.
///
/// Contains information about the user or organization that owns a repository.
/// Provides type-safe access to owner data with graceful handling of missing fields.
extension type const RepositoryOwner(Map<String, dynamic> value) {
  factory RepositoryOwner.fromJson(final dynamic jsonData) {
    final map = jsonDecodeMap(jsonData);
    return RepositoryOwner(map);
  }

  /// Create a repository owner with required fields
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

  /// Unique identifier for the owner
  String get id => jsonDecodeString(value['id']);

  /// Username/login handle
  String get login => jsonDecodeString(value['login']);

  /// Type of owner (user or organization)
  RepositoryOwnerType get type => RepositoryOwnerType.fromJson(value['type']);

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

  Map<String, dynamic> toJson() => value;

  static const empty = RepositoryOwner({});
}

/// Extension type that represents repository permissions.
///
/// Contains permission flags for repository access levels.
/// Used to determine what operations a user can perform on a repository.
extension type const RepositoryPermissions(Map<String, dynamic> value) {
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

  Map<String, dynamic> toJson() => value;

  static const empty = RepositoryPermissions({});
  static const readOnly = RepositoryPermissions({
    'admin': false,
    'push': false,
    'pull': true,
  });
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

  Map<String, dynamic> toJson() => value;

  static const empty = RepositoryInfo({});
}

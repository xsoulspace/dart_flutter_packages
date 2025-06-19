/// Repository owner type
enum RepositoryOwnerType {
  user,
  organization;

  @override
  String toString() => name;
}

/// Repository owner information
class RepositoryOwner {
  const RepositoryOwner({
    required this.id,
    required this.login,
    required this.type,
    this.avatarUrl,
    this.htmlUrl,
  });

  factory RepositoryOwner.fromJson(final Map<String, dynamic> json) =>
      RepositoryOwner(
        id: json['id'].toString(),
        login: json['login'] as String,
        type: RepositoryOwnerType.values.firstWhere(
          (final e) => e.name == json['type'],
          orElse: () => RepositoryOwnerType.user,
        ),
        avatarUrl: json['avatarUrl'] as String?,
        htmlUrl: json['htmlUrl'] as String?,
      );

  final String id;
  final String login;
  final RepositoryOwnerType type;
  final String? avatarUrl;
  final String? htmlUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'login': login,
    'type': type.name,
    'avatarUrl': avatarUrl,
    'htmlUrl': htmlUrl,
  };

  @override
  String toString() => 'RepositoryOwner(login: $login, type: $type)';
}

/// Repository permissions
class RepositoryPermissions {
  const RepositoryPermissions({
    required this.admin,
    required this.push,
    required this.pull,
  });

  factory RepositoryPermissions.fromJson(final Map<String, dynamic> json) =>
      RepositoryPermissions(
        admin: json['admin'] as bool,
        push: json['push'] as bool,
        pull: json['pull'] as bool,
      );

  final bool admin;
  final bool push;
  final bool pull;

  Map<String, dynamic> toJson() => {'admin': admin, 'push': push, 'pull': pull};

  @override
  String toString() =>
      'RepositoryPermissions(admin: $admin, push: $push, pull: $pull)';
}

/// Git repository information
class RepositoryInfo {
  const RepositoryInfo({
    required this.id,
    required this.name,
    required this.fullName,
    required this.owner,
    required this.isPrivate,
    this.description,
    this.defaultBranch,
    this.cloneUrl,
    this.sshUrl,
    this.htmlUrl,
    this.createdAt,
    this.updatedAt,
    this.permissions,
    this.language,
    this.starCount,
    this.forkCount,
    this.size,
  });

  factory RepositoryInfo.fromJson(final Map<String, dynamic> json) =>
      RepositoryInfo(
        id: json['id'].toString(),
        name: json['name'] as String,
        fullName: json['fullName'] as String,
        owner: RepositoryOwner.fromJson(json['owner'] as Map<String, dynamic>),
        description: json['description'] as String?,
        isPrivate: json['isPrivate'] as bool,
        defaultBranch: json['defaultBranch'] as String?,
        cloneUrl: json['cloneUrl'] as String?,
        sshUrl: json['sshUrl'] as String?,
        htmlUrl: json['htmlUrl'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
        permissions: json['permissions'] != null
            ? RepositoryPermissions.fromJson(
                json['permissions'] as Map<String, dynamic>,
              )
            : null,
        language: json['language'] as String?,
        starCount: json['starCount'] as int?,
        forkCount: json['forkCount'] as int?,
        size: json['size'] as int?,
      );

  final String id;
  final String name;
  final String fullName;
  final RepositoryOwner owner;
  final String? description;
  final bool isPrivate;
  final String? defaultBranch;
  final String? cloneUrl;
  final String? sshUrl;
  final String? htmlUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final RepositoryPermissions? permissions;
  final String? language;
  final int? starCount;
  final int? forkCount;
  final int? size;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fullName': fullName,
    'owner': owner.toJson(),
    'description': description,
    'isPrivate': isPrivate,
    'defaultBranch': defaultBranch,
    'cloneUrl': cloneUrl,
    'sshUrl': sshUrl,
    'htmlUrl': htmlUrl,
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'permissions': permissions?.toJson(),
    'language': language,
    'starCount': starCount,
    'forkCount': forkCount,
    'size': size,
  };

  @override
  String toString() => 'RepositoryInfo(name: $fullName, private: $isPrivate)';

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is RepositoryInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          fullName == other.fullName;

  @override
  int get hashCode => id.hashCode ^ fullName.hashCode;
}

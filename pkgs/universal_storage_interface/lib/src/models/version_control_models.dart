/// Version control models shared across providers.

class VcRepository {
  const VcRepository({
    required this.id,
    required this.name,
    this.description = '',
    this.cloneUrl = '',
    this.defaultBranch = '',
    this.isPrivate = false,
    this.owner = '',
    this.fullName = '',
    this.webUrl = '',
  });

  final String id;
  final String name;
  final String description;
  final String cloneUrl;
  final String defaultBranch;
  final bool isPrivate;
  final String owner;
  final String fullName;
  final String webUrl;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'clone_url': cloneUrl,
    'default_branch': defaultBranch,
    'is_private': isPrivate,
    'owner': owner,
    'full_name': fullName,
    'web_url': webUrl,
  };

  factory VcRepository.fromJson(final Map<String, dynamic> json) =>
      VcRepository(
        id: (json['id'] ?? '').toString(),
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        cloneUrl: json['clone_url'] as String? ?? '',
        defaultBranch: json['default_branch'] as String? ?? '',
        isPrivate: json['is_private'] as bool? ?? false,
        owner: json['owner'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        webUrl: json['web_url'] as String? ?? '',
      );

  static const empty = VcRepository(id: '', name: '');
}

class VcBranch {
  const VcBranch({
    required this.name,
    this.commitSha = '',
    this.isDefault = false,
    this.isProtected = false,
  });

  final VcBranchName name;
  final String commitSha;
  final bool isDefault;
  final bool isProtected;

  Map<String, dynamic> toJson() => {
    'name': name.value,
    'commit_sha': commitSha,
    'is_default': isDefault,
    'is_protected': isProtected,
  };

  factory VcBranch.fromJson(final Map<String, dynamic> json) => VcBranch(
    name: VcBranchName(json['name'] as String? ?? ''),
    commitSha: json['commit_sha'] as String? ?? '',
    isDefault: json['is_default'] as bool? ?? false,
    isProtected: json['is_protected'] as bool? ?? false,
  );

  static const empty = VcBranch(name: VcBranchName(''));
}

class VcCreateRepositoryRequest {
  const VcCreateRepositoryRequest({
    required this.name,
    this.description = '',
    this.isPrivate = true,
    this.initializeWithReadme = true,
    this.license = '',
    this.gitignoreTemplate = '',
    this.organization = '',
  });

  final String name;
  final String description;
  final bool isPrivate;
  final bool initializeWithReadme;
  final String license;
  final String gitignoreTemplate;
  final String organization;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'is_private': isPrivate,
    'initialize_with_readme': initializeWithReadme,
    'license': license,
    'gitignore_template': gitignoreTemplate,
    'organization': organization,
  };

  factory VcCreateRepositoryRequest.fromJson(final Map<String, dynamic> json) =>
      VcCreateRepositoryRequest(
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        isPrivate: json['is_private'] as bool? ?? true,
        initializeWithReadme: json['initialize_with_readme'] as bool? ?? true,
        license: json['license'] as String? ?? '',
        gitignoreTemplate: json['gitignore_template'] as String? ?? '',
        organization: json['organization'] as String? ?? '',
      );

  static const empty = VcCreateRepositoryRequest(name: '');
}

class VcUrl {
  const VcUrl(this.value);
  final String value;
  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;
  String toJson() => value;
  static const empty = VcUrl('');
}

class VcRepositorySlug {
  const VcRepositorySlug._(this.value);
  final String value;
  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;
  String toJson() => value;
  static VcRepositorySlug fromJson({
    required final VcRepositoryName repositoryName,
    required final VcRepositoryOwner repositoryOwner,
  }) => VcRepositorySlug._('${repositoryOwner.value}/${repositoryName.value}');
  static const empty = VcRepositorySlug._('');
}

class VcRepositoryOwner {
  const VcRepositoryOwner(this.value);
  final String value;
  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;
  String toJson() => value;
  static const empty = VcRepositoryOwner('');
}

class VcRepositoryName {
  const VcRepositoryName(this.value);
  final String value;
  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;
  String toJson() => value;
  static const empty = VcRepositoryName('');
}

class VcBranchName {
  const VcBranchName(this.value);
  final String value;
  bool get isEmpty => value.isEmpty;
  bool get isNotEmpty => value.isNotEmpty;
  bool get isMainBranch => value == 'main' || value == 'master';
  bool get isDevelopmentBranch =>
      value == 'develop' ||
      value == 'dev' ||
      value.startsWith('feature/') ||
      value.startsWith('feat/');
  String toJson() => value;
  static const empty = VcBranchName('');
  static const main = VcBranchName('main');
  static const master = VcBranchName('master');
  static const develop = VcBranchName('develop');
}

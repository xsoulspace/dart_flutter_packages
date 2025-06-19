RepositoryInfo _mapGitHubRepoToRepositoryInfo(final Repository githubRepo) {
  return RepositoryInfo.fromJson({
    'id': githubRepo.id.toString(),
    'name': githubRepo.name ?? '',
    'full_name': githubRepo.fullName ?? '',
    'owner': {
      'id': githubRepo.owner?.id.toString() ?? '',
      'login': githubRepo.owner?.login ?? '',
      'type': githubRepo.owner?.type ?? 'User',
      'avatar_url': githubRepo.owner?.avatarUrl ?? '',
      'html_url': githubRepo.owner?.htmlUrl ?? '',
    },
    'description': githubRepo.description ?? '',
    'private': githubRepo.private ?? false,
    'default_branch': githubRepo.defaultBranch ?? '',
    'clone_url': githubRepo.cloneUrls?.https ?? '',
    'ssh_url': githubRepo.cloneUrls?.ssh ?? '',
    'html_url': githubRepo.htmlUrl ?? '',
    'created_at': githubRepo.createdAt?.toIso8601String() ?? '',
    'updated_at': githubRepo.updatedAt?.toIso8601String() ?? '',
    'permissions': githubRepo.permissions != null
        ? {
            'admin': githubRepo.permissions!.admin,
            'push': githubRepo.permissions!.push,
            'pull': githubRepo.permissions!.pull,
          }
        : null,
    'language': githubRepo.language ?? '',
    'stargazers_count': githubRepo.stargazersCount ?? 0,
    'forks_count': githubRepo.forksCount ?? 0,
    'size': githubRepo.size ?? 0,
  });
}

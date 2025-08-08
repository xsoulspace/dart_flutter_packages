# universal_storage_interface

Core contracts and models for Universal Storage providers.

- Contracts: `StorageProvider`, `StorageService`
- Configs: `FileSystemConfig`, `GitHubApiConfig`, `OfflineGitConfig`
- Models: `FileEntry`, `FileOperationResult`, VC models
- Exceptions: `StorageException`, `FileNotFoundException`, etc.

Used by concrete providers:

- `universal_storage_filesystem`
- `universal_storage_github_api`
- `universal_storage_git_offline`

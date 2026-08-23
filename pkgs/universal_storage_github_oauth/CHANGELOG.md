# Changelog

## 0.1.0-dev.1

- Initial version: GitHub OAuth for Universal Storage, device-flow-first.
- `GithubDeviceFlowAuthProvider`: OAuth Device Flow (no deep links,
  loopback servers, or client secret); configurable
  device-code/token/API endpoints for web proxies and GHES.
- `DefaultDeviceFlowDelegate`: ready-made UI delegate (`url_launcher` +
  copyable one-time code dialog).
- `GitHubRepositoryService`: repository management via the `github`
  package, authenticated with the stored token.

# universal_storage_github_oauth

GitHub OAuth authentication for Universal Storage. **Device-flow-first**:
one uniform flow on Android, iOS, macOS, Linux, and Windows — no deep
links, no loopback servers, no client secret.

Part of the Universal Storage family; implements the contracts from
[`universal_storage_oauth`](../universal_storage_oauth).

## Setup

1. Create a GitHub App (a manifest helper lives in last_answer's
   `configs/oauth/`) and check **Enable Device Flow** in its settings.
2. Note the **Client ID** — that is all the device flow needs.

## Usage

```dart
final provider = GithubDeviceFlowAuthProvider(
  flowConfig: const GithubDeviceFlowConfig(
    clientId: 'Iv1.xxx',
    scopes: ['repo'], // empty for fine-grained GitHub Apps
  ),
  delegate: DefaultDeviceFlowDelegate(context: context),
);

final result = await provider.authenticate(); // opens browser, polls token
```

The delegate shows the one-time code, opens `github.com/login/device`,
and the provider polls until authorization completes.

### Web

`github.com/login/*` does not send CORS headers, so browser clients must
proxy the two endpoints. Point the config at your proxy:

```dart
const GithubDeviceFlowConfig(
  clientId: 'Iv1.xxx',
  deviceCodeUrl: 'https://your-proxy.example/device/code',
  tokenUrl: 'https://your-proxy.example/access_token',
  apiBaseUrl: 'https://api.github.com', // api.github.com has CORS enabled
)
```

## Repository management

```dart
final repos = GitHubRepositoryService(provider);
final list = await repos.getUserRepositories();
```

Authenticated with the token stored by the provider; no separate login.

## Platform notes

- All platforms: token stored via `flutter_secure_storage`.
- macOS: needs network + keychain entitlements.
- Web: see proxy section above.

# Git OAuth Provider - Implementation Guide for AI Agent

## 🎯 **Current Status**

✅ **Completed:**

- Package structure and dependencies
- Core data models (GitPlatform, OAuthConfig, OAuthResult, RepositoryInfo)
- Demo application with Provider + ChangeNotifier
- Comprehensive README and documentation

🚧 **Next Steps Required:**

- OAuth provider interfaces and implementations
- GitHub OAuth service with real authentication using `oauth2_client`
- Credential storage system
- Repository management services
- Integration with universal_storage_sync

## 📋 **Step-by-Step Implementation Plan**

### **Note on OAuth Library**

To streamline the OAuth 2.0 flow, this guide has been updated to use the [`oauth2_client`](https://pub.dev/packages/oauth2_client) package. This will handle the complexities of web-based authentication and token exchange, particularly for mobile and desktop platforms.

First, add the dependency to your `git_oauth_provider` package's `pubspec.yaml`:

```yaml
dependencies:
  git_oauth_provider:
    path: ../git_oauth_provider
  oauth2_client: ^_latest_version_
```

### **Phase 1: Core OAuth Infrastructure** (Priority: CRITICAL)

#### **Step 1.1: Create OAuth Provider Interface**

**File:** `lib/src/providers/oauth_provider.dart`

```dart
import '../../models/models.dart';

/// Base interface for OAuth providers
abstract class OAuthProvider {
  /// The platform this provider handles
  GitPlatform get platform;

  /// Current configuration
  OAuthConfig get config;

  /// Start OAuth authentication flow
  Future<OAuthResult> authenticate();

  /// Refresh access token if possible
  Future<OAuthResult> refreshToken(String refreshToken);

  /// Check if currently authenticated
  Future<bool> isAuthenticated();

  /// Sign out and clear credentials
  Future<void> signOut();

  /// Get current user information
  Future<OAuthUser?> getCurrentUser();
}
```

#### **Step 1.2: Create Repository Service Interface**

**File:** `lib/src/services/repository_service.dart`

```dart
import '../../models/models.dart';

/// Service for managing repositories
abstract class RepositoryService {
  /// Get list of user's repositories
  Future<List<RepositoryInfo>> getUserRepositories();

  /// Get list of organization repositories
  Future<List<RepositoryInfo>> getOrganizationRepositories(String orgName);

  /// Create a new repository
  Future<RepositoryInfo> createRepository(CreateRepositoryRequest request);

  /// Get repository by name
  Future<RepositoryInfo?> getRepository(String owner, String name);

  /// Search repositories
  Future<List<RepositoryInfo>> searchRepositories(String query);
}

/// Request model for creating repositories
class CreateRepositoryRequest {
  final String name;
  final String? description;
  final bool isPrivate;
  final String? organizationName;

  const CreateRepositoryRequest({
    required this.name,
    this.description,
    this.isPrivate = false,
    this.organizationName,
  });
}
```

#### **Step 1.3: Create Exception Classes**

**File:** `lib/src/exceptions/oauth_exceptions.dart`

```dart
/// Base exception for OAuth operations
abstract class OAuthException implements Exception {
  const OAuthException(this.message, [this.details]);

  final String message;
  final String? details;

  @override
  String toString() => 'OAuthException: $message${details != null ? ' ($details)' : ''}';
}

/// Authentication failed
class AuthenticationException extends OAuthException {
  const AuthenticationException(super.message, [super.details]);
}

/// Invalid configuration
class ConfigurationException extends OAuthException {
  const ConfigurationException(super.message, [super.details]);
}

/// Network/API errors
class ApiException extends OAuthException {
  const ApiException(super.message, [super.details]);

  const ApiException.network([String? details])
    : super('Network error occurred', details);

  const ApiException.unauthorized([String? details])
    : super('Unauthorized access', details);

  const ApiException.rateLimited([String? details])
    : super('Rate limit exceeded', details);
}

/// Repository operation errors
class RepositoryException extends OAuthException {
  const RepositoryException(super.message, [super.details]);

  const RepositoryException.notFound(String repoName)
    : super('Repository not found', repoName);

  const RepositoryException.accessDenied(String repoName)
    : super('Access denied to repository', repoName);
}
```

### **Phase 2: GitHub OAuth Implementation** (Priority: HIGH)

#### **Step 2.1: Update GitHub OAuth Configuration**

The `GitHubOAuthConfig` will need to be updated to include a `customUriScheme`. This is required by `oauth2_client` to correctly handle the redirect from the browser on mobile platforms.

**File:** `lib/src/models/oauth_config.dart` (or wherever `GitHubOAuthConfig` is defined)

```dart
// Add `customUriScheme` to your config class
class GitHubOAuthConfig extends OAuthConfig {
  // ... existing properties
  final String customUriScheme;

  const GitHubOAuthConfig({
    // ... existing parameters
    required this.customUriScheme,
  });

  // ...
}
```

#### **Step 2.2: Create GitHub OAuth Provider using `oauth2_client`**

**File:** `lib/src/github/github_oauth_provider.dart`

This implementation now uses `GitHubOAuth2Client` to manage the authentication flow, simplifying the code significantly.

```dart
import 'dart:convert';
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:oauth2_client/github_oauth2_client.dart';
import 'package:oauth2_client/access_token_response.dart';

import '../../providers/oauth_provider.dart';
import '../../models/models.dart';
import '../../exceptions/exceptions.dart';
import '../../storage/storage.dart';

/// GitHub OAuth implementation using oauth2_client
class GitHubOAuthProvider implements OAuthProvider {
  GitHubOAuthProvider(this._config, [CredentialStorage? storage])
      : _storage = storage ?? SecureCredentialStorage();

  final GitHubOAuthConfig _config;
  final CredentialStorage _storage;
  oauth2.Client? _client;

  @override
  GitPlatform get platform => GitPlatform.github;

  @override
  OAuthConfig get config => _config;

  @override
  Future<OAuthResult> authenticate() async {
    try {
      final ghClient = GitHubOAuth2Client(
        redirectUri: _config.redirectUri,
        customUriScheme: _config.customUriScheme,
      );

      final tokenResponse = await ghClient.getTokenWithAuthCodeFlow(
        clientId: _config.clientId,
        clientSecret: _config.clientSecret,
        scopes: _config.scopes,
      );

      if (tokenResponse?.accessToken == null) {
        throw AuthenticationException('Authentication failed: No access token received.');
      }

      final credentials = StoredCredentials(
        accessToken: tokenResponse!.accessToken!,
        refreshToken: tokenResponse.refreshToken,
        expiresAt: tokenResponse.expirationDate,
        scopes: tokenResponse.scope,
      );

      await _storage.storeCredentials(platform, credentials);

      final user = await getCurrentUser();

      return OAuthResult(credentials: credentials, user: user);

    } on Exception catch (e) {
      throw AuthenticationException('GitHub authentication failed', e.toString());
    }
  }

  @override
  Future<OAuthResult> refreshToken(String refreshToken) async {
    // GitHub tokens don't expire, but this could be implemented if needed
    // using the oauth2_client's refreshToken method if available.
    throw UnimplementedError('GitHub tokens do not support refresh.');
  }

  @override
  Future<bool> isAuthenticated() async {
    final credentials = await _storage.getCredentials(platform);
    return credentials != null && credentials.accessToken.isNotEmpty;
  }

  @override
  Future<void> signOut() async {
    await _storage.clearCredentials(platform);
    _client?.close();
    _client = null;
  }

  @override
  Future<OAuthUser?> getCurrentUser() async {
    final client = await _getAuthenticatedClient();
    if (client == null) return null;

    try {
      final response = await client.get(Uri.parse('${platform.apiBaseUrl}/user'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return OAuthUser(
          id: data['id'].toString(),
          login: data['login'] as String,
          email: data['email'] as String?,
          name: data['name'] as String?,
          avatarUrl: data['avatar_url'] as String?,
        );
      }
    } on Exception catch (e) {
      throw ApiException('Failed to get user information', e.toString());
    }
    return null;
  }

  Future<oauth2.Client?> _getAuthenticatedClient() async {
    if (_client != null) return _client;

    final credentials = await _storage.getCredentials(platform);
    if (credentials == null) return null;

    final oauth2Credentials = oauth2.Credentials(
      credentials.accessToken,
      refreshToken: credentials.refreshToken,
    );

    _client = oauth2.Client(oauth2Credentials,
      onCredentialsRefreshed: (newCreds) async {
        await _storage.storeCredentials(
          platform,
          StoredCredentials.fromOauth2Credentials(newCreds),
        );
      },
    );

    return _client;
  }
}
```

#### **Step 2.3: Create GitHub Repository Service**

**File:** `lib/src/github/github_repository_service.dart`

```dart
import 'dart:convert';
import 'package:github/github.dart';

import '../../services/repository_service.dart';
import '../../models/models.dart';
import '../../exceptions/exceptions.dart';
import '../docs/github_oauth_provider.dart'vider.dart';

/// GitHub repository management service
class GitHubRepositoryService implements RepositoryService {
  GitHubRepositoryService(this._oauthProvider);

  final GitHubOAuthProvider _oauthProvider;
  GitHub? _github;

  @override
  Future<List<RepositoryInfo>> getUserRepositories() async {
    final github = await _getGitHubClient();

    try {
      final repos = await github.repositories.listRepositories().toList();
      return repos.map(_convertRepository).toList();
    } catch (e) {
      throw ApiException('Failed to fetch repositories', e.toString());
    }
  }

  @override
  Future<List<RepositoryInfo>> getOrganizationRepositories(String orgName) async {
    final github = await _getGitHubClient();

    try {
      final repos = await github.repositories.listOrganizationRepositories(orgName).toList();
      return repos.map(_convertRepository).toList();
    } catch (e) {
      throw ApiException('Failed to fetch organization repositories', e.toString());
    }
  }

  @override
  Future<RepositoryInfo> createRepository(CreateRepositoryRequest request) async {
    final github = await _getGitHubClient();

    try {
      final createRepo = CreateRepository(
        request.name,
        description: request.description,
        private: request.isPrivate,
      );

      final repo = await github.repositories.createRepository(createRepo);
      return _convertRepository(repo);
    } catch (e) {
      throw RepositoryException('Failed to create repository', e.toString());
    }
  }

  @override
  Future<RepositoryInfo?> getRepository(String owner, String name) async {
    final github = await _getGitHubClient();

    try {
      final repo = await github.repositories.getRepository(RepositorySlug(owner, name));
      return _convertRepository(repo);
    } catch (e) {
      if (e.toString().contains('404')) {
        return null;
      }
      throw RepositoryException('Failed to get repository', e.toString());
    }
  }

  @override
  Future<List<RepositoryInfo>> searchRepositories(String query) async {
    final github = await _getGitHubClient();

    try {
      final results = await github.search.repositories(query).toList();
      return results.map(_convertRepository).toList();
    } catch (e) {
      throw ApiException('Failed to search repositories', e.toString());
    }
  }

  Future<GitHub> _getGitHubClient() async {
    if (_github != null) return _github!;

    final user = await _oauthProvider.getCurrentUser();
    if (user == null) {
      throw AuthenticationException('Not authenticated with GitHub');
    }

    // Get credentials to create authenticated client
    final credentials = await _oauthProvider._storage.getCredentials(GitPlatform.github);
    if (credentials == null) {
      throw AuthenticationException('No GitHub credentials found');
    }

    _github = GitHub(auth: Authentication.withToken(credentials.accessToken));
    return _github!;
  }

  RepositoryInfo _convertRepository(Repository repo) {
    return RepositoryInfo(
      id: repo.id.toString(),
      name: repo.name,
      fullName: repo.fullName,
      owner: RepositoryOwner(
        id: repo.owner?.id.toString() ?? '',
        login: repo.owner?.login ?? '',
        type: repo.owner?.type == 'Organization'
          ? RepositoryOwnerType.organization
          : RepositoryOwnerType.user,
        avatarUrl: repo.owner?.avatarUrl,
        htmlUrl: repo.owner?.htmlUrl,
      ),
      description: repo.description,
      isPrivate: repo.isPrivate,
      defaultBranch: repo.defaultBranch,
      cloneUrl: repo.cloneUrls?.https,
      sshUrl: repo.cloneUrls?.ssh,
      htmlUrl: repo.htmlUrl,
      createdAt: repo.createdAt,
      updatedAt: repo.updatedAt,
      permissions: repo.permissions != null ? RepositoryPermissions(
        admin: repo.permissions!.admin,
        push: repo.permissions!.push,
        pull: repo.permissions!.pull,
      ) : null,
    );
  }
}
```

### **Phase 3: Credential Storage** (Priority: HIGH)

#### **Step 3.1: Create Credential Storage Interface**

**File:** `lib/src/storage/credential_storage.dart`

```dart
import '../../models/models.dart';

/// Stored OAuth credentials
class StoredCredentials {
  const StoredCredentials({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.scopes,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;
  final List<String>? scopes;

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt?.toIso8601String(),
    'scopes': scopes,
  };

  factory StoredCredentials.fromJson(Map<String, dynamic> json) {
    return StoredCredentials(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      expiresAt: json['expiresAt'] != null
        ? DateTime.parse(json['expiresAt'] as String)
        : null,
      scopes: (json['scopes'] as List<dynamic>?)?.cast<String>(),
    );
  }
}

/// Interface for storing OAuth credentials securely
abstract class CredentialStorage {
  /// Store credentials for a platform
  Future<void> storeCredentials(GitPlatform platform, StoredCredentials credentials);

  /// Retrieve credentials for a platform
  Future<StoredCredentials?> getCredentials(GitPlatform platform);

  /// Clear credentials for a platform
  Future<void> clearCredentials(GitPlatform platform);

  /// Clear all stored credentials
  Future<void> clearAllCredentials();

  /// Check if credentials exist for a platform
  Future<bool> hasCredentials(GitPlatform platform);
}
```

#### **Step 3.2: Create Secure Storage Implementation**

**File:** `lib/src/storage/secure_credential_storage.dart`

```dart
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../docs/credential_storage.dart'orage.dart';
import '../../models/models.dart';

/// Secure credential storage using platform keychain/keystore
class SecureCredentialStorage implements CredentialStorage {
  SecureCredentialStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(
            encryptedSharedPreferences: true,
          ),
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
        );

  final FlutterSecureStorage _storage;

  String _getKey(GitPlatform platform) => 'oauth_credentials_${platform.name}';

  @override
  Future<void> storeCredentials(GitPlatform platform, StoredCredentials credentials) async {
    final key = _getKey(platform);
    final value = jsonEncode(credentials.toJson());
    await _storage.write(key: key, value: value);
  }

  @override
  Future<StoredCredentials?> getCredentials(GitPlatform platform) async {
    final key = _getKey(platform);
    final value = await _storage.read(key: key);

    if (value == null) return null;

    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      return StoredCredentials.fromJson(json);
    } catch (e) {
      // Invalid stored data, clear it
      await clearCredentials(platform);
      return null;
    }
  }

  @override
  Future<void> clearCredentials(GitPlatform platform) async {
    final key = _getKey(platform);
    await _storage.delete(key: key);
  }

  @override
  Future<void> clearAllCredentials() async {
    for (final platform in GitPlatform.values) {
      await clearCredentials(platform);
    }
  }

  @override
  Future<bool> hasCredentials(GitPlatform platform) async {
    final credentials = await getCredentials(platform);
    return credentials != null && !credentials.isExpired;
  }
}
```

### **Phase 4: Integration & Testing** (Priority: MEDIUM)

#### **Step 4.1: Update Universal Storage Sync Integration**

**File:** `../universal_storage_sync/pubspec.yaml` (Add dependency)

```yaml
dependencies:
  git_oauth_provider:
    path: ../git_oauth_provider
```

#### **Step 4.2: Update GitHubApiStorageProvider**

**File:** `../universal_storage_sync/lib/src/providers/github_api_storage_provider.dart`

```dart
// Add imports
import 'package:git_oauth_provider/git_oauth_provider.dart';

class GitHubApiStorageProvider extends StorageProvider {
  // Add OAuth provider
  GitHubOAuthProvider? _oauthProvider;
  GitHubRepositoryService? _repositoryService;

  @override
  Future<void> init(Map<String, dynamic> config) async {
    final gitHubConfig = config['github'] as GitHubApiConfig?;
    if (gitHubConfig == null) {
      throw StorageException('GitHub configuration is required');
    }

    // Initialize OAuth if configured
    if (gitHubConfig.oauthConfig != null) {
      _oauthProvider = GitHubOAuthProvider(gitHubConfig.oauthConfig!);
      _repositoryService = GitHubRepositoryService(_oauthProvider!);

      // Auto-authenticate or show auth UI
      await _handleAuthentication();
    }

    // ... rest of initialization
  }

  Future<void> _handleAuthentication() async {
    if (!await _oauthProvider!.isAuthenticated()) {
      // Need to authenticate - this would trigger OAuth flow
      await _oauthProvider!.authenticate();
    }
  }
}
```

### **Phase 5: Demo App Enhancement** (Priority: LOW)

#### **Step 5.1: Real OAuth Flow in Demo**

Update the demo app to use the new `oauth2_client`-based provider. The key change is providing a valid `customUriScheme` and `redirectUri`.

**Note on Mobile Configuration:** For the OAuth flow to work on Android, you must configure an `intent-filter` in `AndroidManifest.xml` as described in the `flutter_web_auth_2` (a dependency of `oauth2_client`) documentation.

Example `AndroidManifest.xml` entry:

```xml
<activity android:name="com.linusu.flutter_web_auth_2.CallbackActivity" android:exported="true">
    <intent-filter android:label="flutter_web_auth_2">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="your.custom.scheme" /> <!-- CHANGE THIS -->
    </intent-filter>
</activity>
```

Update the demo app's authentication logic:

```dart
// In OAuthState class
Future<void> authenticateWithGitHub() async {
  _isLoading = true;
  notifyListeners();

  try {
    // Real OAuth configuration for a desktop/mobile app
    final config = GitHubOAuthConfig(
      clientId: 'your_github_client_id',       // From environment
      clientSecret: 'your_github_client_secret', // From environment
      redirectUri: 'your.custom.scheme://callback', // Must match intent filter
      customUriScheme: 'your.custom.scheme',      // Must match intent filter
      scopes: ['repo', 'user:email'],
    );

    final provider = GitHubOAuthProvider(config);
    final result = await provider.authenticate();

    _isAuthenticated = true;
    _currentPlatform = 'GitHub';
    _userName = result.user?.login ?? 'Unknown';

    // Get repositories
    final repoService = GitHubRepositoryService(provider);
    final repos = await repoService.getUserRepositories();
    _repositoryName = repos.isNotEmpty ? repos.first.name : 'No repositories';

  } catch (e) {
    _isAuthenticated = false;
    _errorMessage = e.toString();
  } finally {
    _isLoading = false;
    notifyListeners();
  }
}
```

## 🚧 **Implementation Priority Order**

1.  **Phase 1: Core Infrastructure** - Essential abstractions
2.  **Phase 2: GitHub Implementation** - Core OAuth functionality using `oauth2_client`
3.  **Phase 3: Credential Storage** - Secure token management
4.  **Phase 4: Integration** - Connect with universal_storage_sync
5.  **Phase 5: Demo Enhancement** - Real OAuth testing

## 🧪 **Testing Strategy**

Create tests for each component:

- `test/models/` - Data model tests
- `test/github/` - GitHub implementation tests (mocking `oauth2_client`)
- `test/storage/` - Credential storage tests
- `test/integration/` - End-to-end flow tests

## 🔍 **Key Implementation Notes**

1.  **OAuth Redirect Handling**: `oauth2_client` simplifies this, but proper configuration of `redirectUri` and `customUriScheme` is critical. You must configure each platform (Android, iOS, Web, etc.) to handle the callback URI.
2.  **Error Handling**: Comprehensive error handling for network issues, authentication failures (e.g., user cancellation), and API rate limits remains crucial.
3.  **Security**: Never store client secrets in publicly distributed client-side code. Use a backend proxy for the token exchange in production for public applications. For local tools and internal apps, storing it securely on the device or using environment variables might be acceptable.
4.  **Platform Configuration**: The biggest challenge shifts from writing the flow by hand to correctly configuring each platform (especially mobile `intent-filter`s and URL schemes) to work with `oauth2_client`.

## 🎯 **Success Criteria**

✅ **Complete when:**

- GitHub OAuth authentication works in the demo app using `oauth2_client`.
- Credentials are securely stored and retrieved.
- Repository selection/creation functions.
- Integration with `universal_storage_sync` works.
- Comprehensive error handling is implemented.

**The next AI agent should start with Phase 2, Step 2.1 and work sequentially through the updated phases.**

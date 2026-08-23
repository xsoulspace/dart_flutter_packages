/// Universal Storage GitHub OAuth - device-flow-first GitHub
/// authentication for Universal Storage.
///
/// Works uniformly on Android, iOS, macOS, Linux, and Windows without any
/// redirect plumbing. For web, point [GithubDeviceFlowAuthProvider]'s
/// endpoints at a CORS-unblocking proxy.
///
/// ```dart
/// final provider = GithubDeviceFlowAuthProvider(
///   config: const GithubDeviceFlowConfig(
///     clientId: 'Iv1.xxx',
///     scopes: ['repo'],
///   ),
///   delegate: DefaultDeviceFlowDelegate(context: context),
/// );
/// final result = await provider.authenticate();
/// ```
library;

export 'package:universal_storage_oauth/universal_storage_oauth.dart'
    show
        ApiException,
        AuthenticationException,
        CredentialStorage,
        GitPlatform,
        OAuthAccessToken,
        OAuthConfig,
        OAuthFlowCancelledException,
        OAuthFlowDelegate,
        OAuthFlowException,
        OAuthProvider,
        OAuthRefreshToken,
        OAuthResult,
        OAuthScopes,
        OAuthUser,
        RepositoryInfo,
        RepositoryService,
        SecureCredentialStorage,
        StoredCredentials,
        CreateRepositoryRequest;

export 'src/default_device_flow_delegate.dart';
export 'src/github_device_flow_auth_provider.dart';
export 'src/github_repository_service.dart';

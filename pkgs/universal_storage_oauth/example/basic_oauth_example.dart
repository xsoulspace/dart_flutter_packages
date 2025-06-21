// ignore_for_file: avoid_print, avoid_catches_without_on_clauses

import 'package:universal_storage_oauth/universal_storage_oauth.dart';

void main() async {
  await runGitHubOAuthExample();
}

Future<void> runGitHubOAuthExample() async {
  print('🚀 Git OAuth Provider Example\n');

  // Step 1: Create OAuth configuration using the GitHubOAuthConfig
  final config = GitHubOAuthConfig(
    clientId: 'your_github_client_id',
    clientSecret: 'your_github_client_secret',
    redirectUri: 'your.app.scheme://callback',
    customUriScheme: 'your.app.scheme',
    scopes: ['repo', 'user:email'],
  );

  print('📋 Configuration created for ${config.platform.displayName}');

  // Step 2: Create OAuth flow delegate (using mock implementation)
  final delegate = MockOAuthFlowDelegate();

  // Step 3: Create OAuth provider with config and delegate
  final oauthProvider = GitHubOAuthProvider(config, delegate);
  print('✅ OAuth provider initialized');

  try {
    // Step 4: Check if already authenticated
    final isAuthenticated = await oauthProvider.isAuthenticated();
    print('🔐 Already authenticated: $isAuthenticated');

    OAuthUser? user;

    if (!isAuthenticated) {
      print('\n🔑 Starting authentication process...');
      print(
        '💡 Note: This example uses a mock delegate that will not actually '
        'authenticate.',
      );
      print('   In a real app, implement OAuthFlowDelegate for your platform.');

      // This will fail with mock implementation, which is expected
      // final result = await oauthProvider.authenticate();
      // user = result.user;
    } else {
      // Get current user info
      user = await oauthProvider.getCurrentUser();
      print('👤 Current user: ${user?.login}');
    }

    // Step 5: Repository service example (requires authentication)
    if (user != null) {
      await demonstrateRepositoryService(oauthProvider);
    } else {
      print('\n📁 Repository Service Demo (skipped - not authenticated)');
      print('💡 To test repository operations, implement proper OAuth flow');
    }
  } catch (e) {
    print('❌ Error: $e');
    print('💡 This is expected with the mock implementation.');
  }
}

Future<void> demonstrateRepositoryService(
  final GitHubOAuthProvider oauthProvider,
) async {
  print('\n📁 Repository Service Demo');

  final repoService = GitHubRepositoryService(oauthProvider);

  try {
    // Get user repositories
    print('🔍 Fetching user repositories...');
    final repos = await repoService.getUserRepositories();

    print('📚 Found ${repos.length} repositories:');
    for (final repo in repos.take(5)) {
      print('  • ${repo.fullName} (${repo.isPrivate ? 'private' : 'public'})');
    }

    if (repos.isNotEmpty) {
      final firstRepo = repos.first;
      print('\n🌿 Branches in ${firstRepo.fullName}:');

      final branches = await repoService.getRepositoryBranches(
        firstRepo.owner.login,
        firstRepo.name,
      );

      for (final branch in branches.take(3)) {
        print('  • $branch');
      }
    }
  } catch (e) {
    print('❌ Repository service error: $e');
  }
}

// Example of creating a repository
Future<void> createRepositoryExample(
  final GitHubRepositoryService repoService,
) async {
  print('\n🏗️ Creating Repository Example');

  try {
    final request = CreateRepositoryRequest(
      name: 'test-repo-${DateTime.now().millisecondsSinceEpoch}',
      description: 'Test repository created by universal_storage_oauth',
      autoInit: true,
    );

    final newRepo = await repoService.createRepository(request);
    print('✅ Created repository: ${newRepo.fullName}');
    print('🔗 URL: ${newRepo.htmlUrl}');
  } catch (e) {
    print('❌ Failed to create repository: $e');
  }
}

/// Mock implementation of OAuthFlowDelegate for demonstration purposes.
/// This will not perform actual OAuth flow but shows the interface structure.
///
/// In a real application, you would implement OAuthFlowDelegate for
/// your specific platform:
/// - Flutter: Use webview or custom tabs
/// - CLI: Use device flow with console output
/// - Desktop: Use system browser with local server
class MockOAuthFlowDelegate implements OAuthFlowDelegate {
  @override
  Future<String> getAuthorizationCode(
    final Uri authorizationUrl,
    final Uri redirectUrl, {
    final String? state,
  }) {
    print('🌐 Mock: Would open authorization URL: $authorizationUrl');
    print('📱 Mock: Would wait for redirect to: $redirectUrl');

    // Simulate cancellation since this is just a mock
    throw Exception('Mock delegate - implement for actual OAuth flow');
  }

  @override
  Future<void> handleDeviceFlow({
    required final String deviceCode,
    required final String userCode,
    required final Uri verificationUrl,
    required final int expiresIn,
    required final int interval,
    final Uri? verificationUrlComplete,
  }) async {
    print('\n📱 Mock Device Flow Authentication:');
    print('🔢 User Code: $userCode');
    print('🌐 Verification URL: $verificationUrl');
    if (verificationUrlComplete != null) {
      print('🔗 Direct URL: $verificationUrlComplete');
    }
    print('⏰ Expires in: ${expiresIn}s');
    print('🕒 Poll interval: ${interval}s');
    print(
      '\n👤 Mock: In real implementation, user would visit URL and enter code.',
    );
  }

  @override
  Future<void> onAuthorizationSuccess({
    required final String maskedToken,
    required final List<String> scopes,
  }) async {
    print('✅ Mock: Authorization successful!');
    print('🔑 Token: $maskedToken');
    print('🔒 Scopes: ${scopes.join(', ')}');
  }

  @override
  Future<void> onAuthorizationError({
    required final String error,
    final String? description,
  }) async {
    print('❌ Mock: Authorization failed: $error');
    if (description != null) {
      print('📝 Description: $description');
    }
  }
}

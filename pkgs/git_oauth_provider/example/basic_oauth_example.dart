import 'package:git_oauth_provider/git_oauth_provider.dart';

void main() async {
  await runGitHubOAuthExample();
}

Future<void> runGitHubOAuthExample() async {
  print('🚀 Git OAuth Provider Example\n');

  // Step 1: Create OAuth configuration
  final config = GitHubOAuthConfig(
    clientId: 'your_github_client_id',
    clientSecret: 'your_github_client_secret',
    redirectUri: 'your.app.scheme://callback',
    customUriScheme: 'your.app.scheme',
    scopes: ['repo', 'user:email'],
  );

  print('📋 Configuration created for ${config.platform.displayName}');

  // Step 2: Create OAuth provider
  final oauthProvider = GitHubOAuthProvider(config);
  print('✅ OAuth provider initialized');

  try {
    // Step 3: Check if already authenticated
    final isAuthenticated = await oauthProvider.isAuthenticated();
    print('🔐 Already authenticated: $isAuthenticated');

    OAuthUser? user;

    if (!isAuthenticated) {
      print('\n🔑 Starting authentication process...');

      // Step 4: Authenticate (this would open browser)
      final result = await oauthProvider.authenticate();
      user = result.user;

      print('✅ Authentication successful!');
      print('📧 User: ${user?.login} (${user?.email})');
    } else {
      // Get current user info
      user = await oauthProvider.getCurrentUser();
      print('👤 Current user: ${user?.login}');
    }

    // Step 5: Use repository service
    if (user != null) {
      await demonstrateRepositoryService(oauthProvider);
    }
  } catch (e) {
    print('❌ Error: $e');
  }
}

Future<void> demonstrateRepositoryService(
    GitHubOAuthProvider oauthProvider) async {
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
    GitHubRepositoryService repoService) async {
  print('\n🏗️ Creating Repository Example');

  try {
    final request = CreateRepositoryRequest(
      name: 'test-repo-${DateTime.now().millisecondsSinceEpoch}',
      description: 'Test repository created by git_oauth_provider',
      isPrivate: false,
      autoInit: true,
    );

    final newRepo = await repoService.createRepository(request);
    print('✅ Created repository: ${newRepo.fullName}');
    print('🔗 URL: ${newRepo.htmlUrl}');
  } catch (e) {
    print('❌ Failed to create repository: $e');
  }
}

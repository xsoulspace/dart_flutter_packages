import 'package:universal_storage_sync/universal_storage_sync.dart';

/// Example demonstrating GitHub OAuth authentication with automatic repository selection.
///
/// This showcases the enhanced GitHub API Storage Provider that supports:
/// - OAuth sign-in (no manual token generation)
/// - Automatic repository selection/creation
/// - Seamless user experience for web and desktop apps
Future<void> main() async {
  print('=== GitHub OAuth Storage Provider Example ===\n');

  // Example 1: OAuth configuration for web applications
  await webAppOAuthExample();

  // Example 2: OAuth configuration for desktop/CLI applications
  await desktopAppOAuthExample();

  // Example 3: OAuth with automatic repository creation
  await autoRepoCreationExample();

  // Example 4: Migration from manual tokens to OAuth
  await migrationExample();
}

/// Web application OAuth example
Future<void> webAppOAuthExample() async {
  print('📱 Web Application OAuth Example:\n');

  try {
    // Configure OAuth for web applications
    final config = GitHubApiConfig.builder()
        .oauth(
          clientId: 'your_github_app_client_id',
          clientSecret:
              'your_github_app_client_secret', // Optional for public apps
          redirectUri: 'https://yourapp.com/auth/callback',
          scopes: ['repo', 'user'], // Customize permissions
        )
        .repository(
          suggestedName: 'my-app-data',
          defaultDescription: 'Data storage for MyApp',
        )
        .build();

    print('✅ OAuth Configuration Created');
    print('   - Client ID: ${config.oauthConfig!.clientId}');
    print('   - Redirect URI: ${config.oauthConfig!.redirectUri}');
    print('   - Scopes: ${config.oauthConfig!.scopes.join(', ')}');
    print(
      '   - Repository Selection: ${config.repositoryConfig!.allowSelection}',
    );
    print(
      '   - Repository Creation: ${config.repositoryConfig!.allowCreation}',
    );

    // Create the storage service with OAuth
    // Note: This will trigger the OAuth flow when initialized
    final service = await StorageFactory.createGitHubApi(config);

    print(
      '🔐 OAuth Flow Completed (platform-specific implementation required)',
    );
    print('📂 Repository Selected/Created Automatically');

    // Normal file operations work the same
    await service.saveFile('welcome.txt', 'Welcome to OAuth-powered storage!');
    final content = await service.readFile('welcome.txt');
    print('📄 File saved and read: $content');
  } catch (e) {
    print('❌ Web OAuth Example Error: $e');
    print('💡 This example requires platform-specific OAuth implementation');
  }

  print('\n${'=' * 50}\n');
}

/// Desktop application OAuth example (device flow)
Future<void> desktopAppOAuthExample() async {
  print('🖥️  Desktop Application OAuth Example:\n');

  try {
    // Configure OAuth for desktop/CLI applications using device flow
    final config = GitHubApiConfig.builder()
        .oauth(clientId: 'your_github_app_client_id', scopes: ['repo'])
        .repository(suggestedName: 'desktop-app-storage')
        .build();

    print('✅ Desktop OAuth Configuration Created');
    print('   - Uses Device Flow: ${config.oauthConfig!.deviceFlowEnabled}');
    print('   - No Client Secret Required');

    // In a real implementation, this would:
    // 1. Display a user code
    // 2. Ask user to visit GitHub and enter the code
    // 3. Poll for authorization completion
    // 4. Receive access token

    print('🔐 Device Flow Process:');
    print('   1. App displays: "Go to https://github.com/login/device"');
    print('   2. App displays: "Enter code: ABCD-1234"');
    print('   3. User authorizes on GitHub');
    print('   4. App receives access token');
  } catch (e) {
    print('❌ Desktop OAuth Example Error: $e');
  }

  print('\n${'=' * 50}\n');
}

/// Automatic repository creation example
Future<void> autoRepoCreationExample() async {
  print('🏗️  Automatic Repository Creation Example:\n');

  try {
    // Configuration that automatically creates a repository
    final config = GitHubApiConfig.builder()
        .autoOAuth(
          clientId: 'your_github_app_client_id',
          suggestedRepoName: 'my-awesome-app-${DateTime.now().year}',
          repoDescription:
              'Automatically created storage repository for MyAwesomeApp',
          privateRepo: false, // Make it public
        )
        .build();

    print('✅ Auto-Creation Configuration');
    print('   - Repository Name: ${config.repositoryConfig!.suggestedName}');
    print('   - Description: ${config.repositoryConfig!.defaultDescription}');
    print('   - Private: ${config.repositoryConfig!.defaultPrivate}');

    // This configuration will:
    // 1. Authenticate via OAuth
    // 2. Create the repository automatically if it doesn't exist
    // 3. Start using it for storage

    print('🔄 Auto-creation process:');
    print('   1. OAuth authentication');
    print('   2. Check if suggested repository exists');
    print('   3. Create repository if not found');
    print('   4. Ready for file operations');
  } catch (e) {
    print('❌ Auto-creation Example Error: $e');
  }

  print('\n${'=' * 50}\n');
}

/// Migration from manual tokens to OAuth
Future<void> migrationExample() async {
  print('🔄 Migration from Manual Tokens to OAuth:\n');

  // Old way (manual token)
  print('❌ Old Manual Token Approach:');
  print('''
  final config = GitHubApiConfig.builder()
      .authToken('ghp_your_manual_token_here')
      .repositoryOwner('your-username')
      .repositoryName('your-repo')
      .build();
  ''');

  print('Issues with manual approach:');
  print('   • User must generate token manually');
  print('   • User must provide repository details');
  print('   • Token management and security concerns');
  print('   • Poor user experience for onboarding');
  print('   • No repository discovery/creation');

  print('\n✅ New OAuth Approach:');
  print('''
  final config = GitHubApiConfig.builder()
      .oauth(clientId: 'your_app_client_id')
      .repository(allowSelection: true, allowCreation: true)
      .build();
  ''');

  print('Benefits of OAuth approach:');
  print('   ✅ One-click GitHub sign-in');
  print('   ✅ Automatic repository selection/creation');
  print('   ✅ Better security (OAuth tokens)');
  print('   ✅ Seamless user experience');
  print('   ✅ Platform-appropriate flows (web/desktop)');
  print('   ✅ Granular permission control');

  print('\n🔧 Migration Steps:');
  print('   1. Create GitHub App for your application');
  print('   2. Update configuration to use OAuth');
  print('   3. Implement platform-specific OAuth handlers');
  print('   4. Test authentication and repository flows');
  print('   5. Deploy updated application');

  print('\n${'=' * 50}\n');
}

/// Configuration comparison showing different use cases
void showConfigurationExamples() {
  print('📋 OAuth Configuration Examples:\n');

  print('1. Simple OAuth (minimal setup):');
  print('''
  GitHubApiConfig.builder()
      .oauth(clientId: 'your_client_id')
      .build();
  ''');

  print('2. Web app with custom repository:');
  print('''
  GitHubApiConfig.builder()
      .oauth(
        clientId: 'your_client_id',
        redirectUri: 'https://app.com/callback',
      )
      .repository(suggestedName: 'user-data')
      .build();
  ''');

  print('3. Desktop app with auto-creation:');
  print('''
  GitHubApiConfig.builder()
      .autoOAuth(
        clientId: 'your_client_id',
        suggestedRepoName: 'my-app-storage',
        privateRepo: true,
      )
      .build();
  ''');

  print('4. Enterprise with template repository:');
  print('''
  GitHubApiConfig.builder()
      .oauth(
        clientId: 'your_client_id',
        scopes: ['repo', 'user', 'admin:org'],
      )
      .repository(
        templateRepository: 'company/data-template',
        allowCreation: true,
      )
      .build();
  ''');
}

/// Implementation guidance for developers
void implementationGuidance() {
  print('🔨 Implementation Guidance:\n');

  print('📱 Web Application Implementation:');
  print('   1. Create GitHubOAuthHandler for web platform');
  print('   2. Handle redirect URI in your web app');
  print('   3. Exchange code for access token');
  print('   4. Store token securely (HttpOnly cookies)');

  print('\n🖥️  Desktop Application Implementation:');
  print('   1. Create GitHubDeviceFlowHandler');
  print('   2. Display user code and GitHub URL');
  print('   3. Poll for authorization completion');
  print('   4. Store token in secure local storage');

  print('\n📦 Required Dependencies:');
  print('   - http: For OAuth requests');
  print('   - url_launcher: For opening GitHub auth URLs');
  print('   - secure_storage: For token persistence');

  print('\n🔐 Security Best Practices:');
  print('   • Use PKCE for web OAuth flows');
  print('   • Store tokens in secure storage');
  print('   • Implement token refresh logic');
  print('   • Use minimal required scopes');
  print('   • Validate OAuth state parameters');
}

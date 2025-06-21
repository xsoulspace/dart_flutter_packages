// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:universal_storage_sync/universal_storage_sync.dart';

/// {@template repository_selection_result}
/// Result of repository selection or creation operation.
/// {@endtemplate}
class RepositorySelectionResult {
  /// {@macro repository_selection_result}
  const RepositorySelectionResult({
    required this.repository,
    required this.wasCreated,
  });

  /// The selected or created repository.
  final VcRepository repository;

  /// Whether the repository was newly created.
  final bool wasCreated;
}

/// {@template repository_selection_config}
/// Configuration for repository selection and creation operations.
/// {@endtemplate}
class RepositorySelectionConfig {
  /// {@macro repository_selection_config}
  const RepositorySelectionConfig({
    this.allowSelection = true,
    this.allowCreation = true,
    this.suggestedName,
    this.defaultDescription,
    this.defaultPrivate = true,
    this.templateRepository,
  });

  /// Whether to allow user to select from existing repositories.
  final bool allowSelection;

  /// Whether to allow user to create new repositories.
  final bool allowCreation;

  /// Suggested repository name for creation or selection.
  final String? suggestedName;

  /// Default repository description for creation.
  final String? defaultDescription;

  /// Whether created repositories should be private by default.
  final bool defaultPrivate;

  /// Template repository to use for creation (owner/repo format).
  final String? templateRepository;
}

/// {@template repository_selection_ui}
/// Interface for repository selection UI operations.
///
/// Platform implementations should provide UI for:
/// - Displaying list of repositories for selection
/// - Collecting repository creation details
/// - Showing progress during operations
/// {@endtemplate}
abstract interface class RepositorySelectionUIDelegate {
  /// {@macro repository_selection_ui}
  const RepositorySelectionUIDelegate();

  /// Shows repository selection dialog to user.
  ///
  /// [repositories] - Available repositories to choose from
  /// [suggestedName] - Suggested repository name to highlight
  ///
  /// Returns the selected repository or null if cancelled.
  Future<VcRepository?> selectRepository(
    final List<VcRepository> repositories, {
    final String? suggestedName,
  });

  /// Collects repository creation details from user.
  ///
  /// [config] - Configuration with defaults and suggestions
  ///
  /// Returns repository creation details or null if cancelled.
  Future<VcCreateRepositoryRequest?> getRepositoryCreationDetails(
    final RepositorySelectionConfig config,
  );

  /// Shows progress during repository operations.
  ///
  /// [message] - Progress message to display
  Future<void> showProgress(final String message);

  /// Hides progress indicator.
  Future<void> hideProgress();

  /// Shows error message to user.
  ///
  /// [title] - Error title
  /// [message] - Error message
  Future<void> showError(final String title, final String message);
}

/// {@template repository_manager}
/// High-level repository management helper.
///
/// This class provides convenient methods for repository selection,
/// creation, and management using the low-level primitives from
/// storage providers.
///
/// It bridges the gap between storage providers and application UI,
/// orchestrating common repository workflows while remaining UI-agnostic
/// through the RepositorySelectionUI delegate pattern.
/// {@endtemplate}
class RepositoryManager {
  /// {@macro repository_manager}
  const RepositoryManager({required this.service, required this.ui});

  /// The version control service to use.
  final VersionControlService service;

  /// The UI delegate to use.
  final RepositorySelectionUIDelegate ui;

  /// Selects or creates a repository based on configuration.
  ///
  /// This method orchestrates the complete repository selection workflow:
  /// 1. Lists available repositories if selection is allowed
  /// 2. Checks for suggested repository name
  /// 3. Presents selection UI if multiple options exist
  /// 4. Creates new repository if creation is allowed and needed
  ///
  /// [config] - Repository selection and creation configuration
  ///
  /// Returns the selected or created repository details.
  /// Throws [RepositorySelectionException] if operation fails or is cancelled.
  Future<RepositorySelectionResult> selectOrCreateRepository(
    final RepositorySelectionConfig config,
  ) async {
    try {
      await ui.showProgress('Loading repositories...');

      // Step 1: List existing repositories if selection is allowed
      List<VcRepository> repositories = [];
      if (config.allowSelection) {
        repositories = await service.listRepositories();
      }

      await ui.hideProgress();

      // Step 2: Check for suggested repository in existing list
      if (config.suggestedName != null && repositories.isNotEmpty) {
        final suggested = repositories
            .where((final repo) => _extractName(repo) == config.suggestedName)
            .firstOrNull;

        if (suggested != null) {
          return RepositorySelectionResult(
            repository: suggested,
            wasCreated: false,
          );
        }
      }

      // Step 3: Present selection UI if repositories are available
      if (config.allowSelection && repositories.isNotEmpty) {
        final selected = await ui.selectRepository(
          repositories,
          suggestedName: config.suggestedName,
        );

        if (selected != null) {
          return RepositorySelectionResult(
            repository: selected,
            wasCreated: false,
          );
        }
      }

      // Step 4: Create new repository if allowed
      if (config.allowCreation) {
        return _createNewRepository(config);
      }

      throw const RepositorySelectionException(
        'No repository selected and creation is not allowed',
      );
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      await ui.hideProgress();
      if (e is RepositorySelectionException) rethrow;

      await ui.showError(
        'Repository Selection Failed',
        'Failed to select or create repository: $e',
      );
      throw RepositorySelectionException('Repository operation failed: $e');
    }
  }

  /// Creates a new repository with user input.
  Future<RepositorySelectionResult> _createNewRepository(
    final RepositorySelectionConfig config,
  ) async {
    // Get creation details from user
    final VcCreateRepositoryRequest? createDetails = await ui
        .getRepositoryCreationDetails(config);
    if (createDetails == null) {
      throw const RepositorySelectionException('Repository creation cancelled');
    }

    await ui.showProgress('Creating repository...');

    try {
      final repository = await service.createRepository(createDetails);
      await ui.hideProgress();

      return RepositorySelectionResult(
        repository: repository,
        wasCreated: true,
      );
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      await ui.hideProgress();
      await ui.showError(
        'Repository Creation Failed',
        'Failed to create repository: $e',
      );
      throw RepositorySelectionException('Repository creation failed: $e');
    }
  }

  /// Lists all repositories accessible to the authenticated user.
  ///
  /// This is a convenience wrapper around the provider's
  /// listRepositories method.
  Future<List<VcRepository>> listRepositories() async {
    await ui.showProgress('Loading repositories...');
    try {
      final repositories = await service.listRepositories();
      await ui.hideProgress();
      return repositories;
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      await ui.hideProgress();
      await ui.showError(
        'Failed to Load Repositories',
        'Could not load repositories: $e',
      );
      rethrow;
    }
  }

  /// Gets information about the current repository.
  ///
  /// This is a convenience wrapper around the provider's
  /// getRepositoryInfo method.
  Future<VcRepository> getRepositoryInfo() async {
    await ui.showProgress('Loading repository information...');
    try {
      final repository = await service.getRepositoryInfo();
      await ui.hideProgress();
      return repository;
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      await ui.hideProgress();
      await ui.showError(
        'Failed to Load Repository Info',
        'Could not load repository information: $e',
      );
      rethrow;
    }
  }

  /// Lists branches in the current repository.
  ///
  /// This is a convenience wrapper around the provider's listBranches method.
  Future<List<VcBranch>> listBranches() async {
    await ui.showProgress('Loading branches...');
    try {
      final branches = await service.listBranches();
      await ui.hideProgress();
      return branches;
    } catch (e, stackTrace) {
      log('Error: $e', stackTrace: stackTrace);
      await ui.hideProgress();
      await ui.showError(
        'Failed to Load Branches',
        'Could not load branches: $e',
      );
      rethrow;
    }
  }

  /// Helper to extract repository name in a provider-agnostic way.
  ///
  /// VcRepository extension type provides a name getter that can be used
  /// to extract the repository name for suggested-name pre-selection.
  String? _extractName(final VcRepository repo) {
    try {
      return repo.name;
    } catch (_) {
      return null;
    }
  }
}

/// {@template repository_selection_exception}
/// Exception thrown when repository selection or creation fails.
/// {@endtemplate}
class RepositorySelectionException implements Exception {
  /// {@macro repository_selection_exception}
  const RepositorySelectionException(this.message);

  /// The error message.
  final String message;

  @override
  String toString() => 'RepositorySelectionException: $message';
}

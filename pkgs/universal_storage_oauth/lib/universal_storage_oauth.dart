/// Platform-agnostic OAuth contracts for Universal Storage.
///
/// This package contains only interfaces, models, and credential storage.
/// Platform implementations live in dedicated packages, e.g.
/// `universal_storage_github_oauth`.
library;

// Exceptions
export 'src/exceptions/exceptions.dart';
// Models
export 'src/models/models.dart';
// Providers (contracts)
export 'src/providers/oauth_flow_delegate.dart';
export 'src/providers/oauth_provider.dart';
// Services (contracts)
export 'src/services/repository_service.dart';
// Storage
export 'src/storage/storage.dart';

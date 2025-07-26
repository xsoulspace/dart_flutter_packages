/// Represents the status of the monetization system.
enum MonetizationStoreStatus {
  /// Store is loading, initializing, or not initialized
  loading,

  /// Store is not available, not initialized
  /// or not installed
  notAvailable,

  /// User is not authorized in the store
  userNotAuthorized,

  /// Store is available and user is authorized
  loaded,
}

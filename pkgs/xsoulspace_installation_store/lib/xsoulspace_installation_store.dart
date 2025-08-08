/// Public API exports for xsoulspace_installation_store.
///
/// - `InstallationStoreSource`: detected installation source across platforms
/// - `InstallationStoreUtils`: helper for detecting source (IO/Web)
/// - `InstallationTargetStore`: your intended target store(s)
export 'src/installation_store_source.dart';
export 'src/installation_store_utils_io.dart'
    if (dart.library.web) 'src/installation_store_utils_web.dart';
export 'src/installation_target_store.dart';

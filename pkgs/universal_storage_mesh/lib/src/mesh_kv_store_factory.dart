/// Default (unsupported-platform) backing selector.
///
/// Conditional import fallback: `mesh_kv_store_io.dart` is selected where
/// `dart:io` exists, `mesh_kv_store_web.dart` where `dart:js_interop`
/// exists. This stub only remains for platforms with neither.
library;

import 'mesh_kv_store.dart';

/// Always throws: no persistence backing is available on this platform.
MeshKeyValueStore createMeshKvStore(final String root) =>
    throw UnsupportedError(
      'Mesh replica persistence is not supported on this platform '
      '(no file or web backing available).',
    );

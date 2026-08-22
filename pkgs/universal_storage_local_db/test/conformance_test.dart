import 'package:test/test.dart';
import 'package:universal_storage_conformance/universal_storage_conformance.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_local_db/universal_storage_local_db.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

import 'local_db_storage_provider_test.dart' show InMemoryLocalDb;

void main() {
  storageProviderConformanceTests(
    'LocalDbStorageProvider',
    create: () async {
      final provider = LocalDbStorageProvider(localDb: InMemoryLocalDb());
      await provider.initWithConfig(
        const LocalDbStorageConfig(keyspacePrefix: 'conformance'),
      );
      return provider;
    },
    supportsSync: false,
  );
}

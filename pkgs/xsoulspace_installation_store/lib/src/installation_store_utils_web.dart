import 'package:web/web.dart' as web;

import 'installation_store_source.dart';

/// Web implementation to detect install source by hostname.
class InstallationStoreUtils {
  const InstallationStoreUtils();

  Future<InstallationStoreSource> getInstallationSource() async =>
      switch (web.window.location.hostname) {
        'itch.io' => InstallationStoreSource.webItchIo,
        _ => InstallationStoreSource.webSelfhost,
      };
}

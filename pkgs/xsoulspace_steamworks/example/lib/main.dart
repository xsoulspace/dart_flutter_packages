import 'package:flutter/widgets.dart';

import 'app.dart';

void main() {
  const useFakeBackend = bool.fromEnvironment(
    'STEAMWORKS_EXAMPLE_FAKE',
  );

  runApp(const SteamworksExampleApp());
}

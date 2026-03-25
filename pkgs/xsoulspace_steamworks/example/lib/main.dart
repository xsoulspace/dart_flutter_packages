import 'package:flutter/widgets.dart';

import 'app.dart';

void main() {
  const useFakeBackend = bool.fromEnvironment(
    'STEAMWORKS_EXAMPLE_FAKE',
    defaultValue: false,
  );

  runApp(const SteamworksExampleApp(useFakeBackend: useFakeBackend));
}

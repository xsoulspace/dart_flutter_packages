import 'package:flutter/widgets.dart';

import 'app.dart';

void main() {
  // ignore: do_not_use_environment
  const useFakeBackend = bool.fromEnvironment('STEAMWORKS_EXAMPLE_FAKE');

  runApp(
    const SteamworksExampleApp(
      // ignore: avoid_redundant_argument_values
      useFakeBackend: useFakeBackend,
    ),
  );
}

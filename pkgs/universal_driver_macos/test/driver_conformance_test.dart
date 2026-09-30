import 'package:universal_automation_conformance/universal_automation_conformance.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

import 'macos_driver_test.dart' show FakeBridge;

void main() {
  // Contract conformance against the injectable bridge (no TCC needed);
  // the live smoke file covers the real-tree path.
  automationDriverConformanceTests(
    'MacosDriver(fake bridge)',
    createDriver: () async => MacosDriver(bridge: FakeBridge()),
  );
}

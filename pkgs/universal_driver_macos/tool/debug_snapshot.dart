import 'package:universal_driver_macos/universal_driver_macos.dart';

void main() {
  final driver = MacosDriver();
  // ignore: avoid_print
  print('trusted: ${driver.axTrusted}');
  final r = driver.bridge.snapshotJson(maxDepth: 12, maxNodes: 600);
  // ignore: avoid_print
  print('code: ${r.code}');
  if (r.code == 0) {
    // ignore: avoid_print
    print(r.json.length > 800 ? r.json.substring(0, 800) : r.json);
  }
  final hover = driver.bridge.elementAtPositionJson(x: 720, y: 450);
  // ignore: avoid_print
  print('hover code: ${hover.code} json: '
      '${hover.json.length > 300 ? hover.json.substring(0, 300) : hover.json}');
}

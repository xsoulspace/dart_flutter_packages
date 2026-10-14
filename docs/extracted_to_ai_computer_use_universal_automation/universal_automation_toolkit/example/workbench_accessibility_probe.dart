import 'dart:convert';
import 'dart:io';
import 'package:universal_driver_macos/universal_driver_macos.dart';
Future<void> main() async {
 final d = MacosDriver(snapshotDepth: 32, snapshotMaxNodes: 2000);
 final apps = await d.runningApps();
 final target = apps.singleWhere((a)=>a.bundleId=='dev.xsoulspace.workbenchCandidate');
 print('windows: ${await d.windows(pid: target.pid)}');
 print('target: $target hidden=${target.hidden}');
 final before = await d.frontmost();
 print(jsonEncode(requestAppAccessibility(target.pid)));
 final snap = await d.snapshotOfApp(target.pid);
 final after = await d.frontmost();
 print(jsonEncode({'frontmostBefore':before.pid,'frontmostAfter':after.pid,'nodes':snap.nodes.map((n)=>{'role':n.role,'name':n.name}).toList()}));
 final windows = await d.windows(pid: target.pid);
 if (windows.length == 1) await File('/tmp/workbench-anchored-window.png').writeAsBytes(await d.windowScreenshot(windows.single.windowId));
 await d.close();
}

import 'dart:io';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

Future<void> main() async {
  final jail = await Directory.systemTemp.createTemp('probe_');
  final tools = fsTools(FsToolsRoot(jail.path));
  final write = tools.firstWhere((t) => t.name.value == 'write');
  try {
    final r = await write.execute({'path': 'src/lib.dart', 'content': 'x'});
    print('nested OK: $r');
    print('exists: ${File('${jail.path}/src/lib.dart').existsSync()}');
  } catch (e) {
    print('nested FAIL: $e');
  }
  try {
    final r = await write.execute({'path': 'count.txt', 'content': '2'});
    print(
      'plain OK: $r content=${File('${jail.path}/count.txt').readAsStringSync()}',
    );
  } catch (e) {
    print('plain FAIL: $e');
  }
  await jail.delete(recursive: true);
}

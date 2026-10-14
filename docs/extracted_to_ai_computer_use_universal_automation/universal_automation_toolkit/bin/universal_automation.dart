import 'dart:io';

import 'package:universal_automation_toolkit/universal_automation_toolkit.dart';

Future<void> main(List<String> arguments) async {
  final code = await runToolkitCli(arguments);
  exit(code);
}

import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_js_interop_codegen/xsoulspace_js_interop_codegen.dart';

void main() {
  test(
    'TypeScript parser reads interfaces and symbols',
    () async {
      final nodeVersion = await Process.run('node', <String>['--version']);
      if (nodeVersion.exitCode != 0) {
        return;
      }

      final packageRoot = Directory.current.path;
      final parser = TypeScriptIrParser.fromSharedCore(
        currentPackageRoot: packageRoot,
      );
      await parser.ensureDependencies();

      final temp = await Directory.systemTemp.createTemp('codegen_ts_parser_');
      addTearDown(() => temp.delete(recursive: true));
      final dtsFile = File('${temp.path}/sample.d.ts');
      dtsFile.writeAsStringSync('''
export interface SampleApi {
  ping(value: string): Promise<string>;
}

declare global {
  const CrazyGames: { SDK: SampleApi };
}
''');

      final ir = await parser.parseFileToIr(dtsFile.path);
      final symbols = (ir['symbols'] as List<dynamic>).cast<String>();
      expect(symbols, contains('SampleApi'));

      final globals = (ir['globalDeclarations'] as List<dynamic>)
          .cast<Map<String, Object?>>();
      expect(globals.any((final g) => g['name'] == 'CrazyGames'), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

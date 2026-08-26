// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_agentic_harness/xsoulspace_agentic_harness.dart';

const _source = '''
class Pricing {
  double total(List<double> items, {double tax = 0.19}) {
    var sum = 0.0;
    for (final i in items) {
      sum += i;
    }
    return sum * (1 + tax);
  }

  double discounted(double value, double pct) => value * (1 - pct);
}
''';

void main() {
  late Directory jail;

  setUp(() async {
    jail = await Directory.systemTemp.createTemp('tree-patch-test');
    final f = File('${jail.path}/lib/pricing.dart')
      ..createSync(recursive: true);
    f.writeAsStringSync(_source);
  });

  tearDown(() => jail.delete(recursive: true));

  Future<Map<String, dynamic>> run(Map<String, dynamic> args) async {
    final tool = patchSymbolTool(jail.path);
    final out = await tool.execute(args);
    return (out is String ? jsonDecode(out) : out) as Map<String, dynamic>;
  }

  test('replaces one method body; siblings and formatting survive', () async {
    final out = await run({
      'path': 'lib/pricing.dart',
      'symbol': 'total',
      'new_body': '''
double total(List<double> items, {double tax = 0.19, double fee = 0}) {
  var sum = items.fold<double>(0, (a, b) => a + b);
  return (sum + fee) * (1 + tax);
}
''',
    });
    expect(out['ok'], true);
    final text = File('${jail.path}/lib/pricing.dart').readAsStringSync();
    expect(text, contains('(sum + fee) * (1 + tax)'));
    expect(text, contains('discounted(double value, double pct)'));
    expect(text, contains('class Pricing'));
  });

  test('unknown symbol → structured diagnostic, nothing written', () async {
    final before = File('${jail.path}/lib/pricing.dart').readAsStringSync();
    final out = await run({
      'path': 'lib/pricing.dart',
      'symbol': 'nope',
      'new_body': 'void nope() {}',
    });
    expect(out['ok'], false);
    expect(out['code'], 'symbol_not_found');
    expect(File('${jail.path}/lib/pricing.dart').readAsStringSync(), before);
  });

  test('invalid replacement body rejected BEFORE write', () async {
    final before = File('${jail.path}/lib/pricing.dart').readAsStringSync();
    final out = await run({
      'path': 'lib/pricing.dart',
      'symbol': 'total',
      'new_body': 'double total( {',
    });
    expect(out['ok'], false);
    expect(
      (out['code'] ?? out['hint']),
      isNotNull,
    );
    expect(File('${jail.path}/lib/pricing.dart').readAsStringSync(), before);
  });

  test('missing file → structured diagnostic', () async {
    final out = await run({
      'path': 'lib/nope.dart',
      'symbol': 'x',
      'new_body': 'void x() {}',
    });
    expect(out['code'], 'file_missing');
  });

  test('patch_symbol tool end-to-end via ToolDef.execute', () async {
    final tool = patchSymbolTool(jail.path);
    final raw = await tool.execute({
      'path': 'lib/pricing.dart',
      'symbol': 'discounted',
      'new_body': '''
double discounted(double value, double pct, {double floor = 0}) {
  final v = value * (1 - pct);
  return v < floor ? floor : v;
}
''',
    });
    final map =
        (raw is String ? jsonDecode(raw) : raw) as Map<String, dynamic>;
    expect(map['ok'], true);
    expect(
      File('${jail.path}/lib/pricing.dart').readAsStringSync(),
      contains('v < floor ? floor : v'),
    );
  });

  group('rename_symbol', () {
    late Directory jailRename;
    setUp(() async {
      jailRename = await Directory.systemTemp.createTemp('tree-rename-test');
      final f = File('${jailRename.path}/lib/consts.dart')
        ..createSync(recursive: true);
      f.writeAsStringSync('''
const kTimeout = 5000;

int retry(int attempts) {
  if (attempts <= 0) return 0;
  return (kTimeout + attempts) * 2;
}

class Service {
  int call() => retry(kTimeout);
}
''');
    });
    tearDown(() => jailRename.delete(recursive: true));

    Future<Map<String, dynamic>> runRename(Map<String, dynamic> args) async {
      final tool = renameSymbolTool(jailRename.path);
      final out = await tool.execute(args);
      return (out is String ? jsonDecode(out) : out) as Map<String, dynamic>;
    }

    test('renames a top-level const, its own name token, and all references in-file', () async {
      final out = await runRename({
        'path': 'lib/consts.dart',
        'symbol': 'kTimeout',
        'new_name': 'requestTimeout',
      });
      expect(out['ok'], true);
      expect(out['renames'], greaterThan(1));
      final text = File('${jailRename.path}/lib/consts.dart').readAsStringSync();
      expect(text, contains('const requestTimeout'));
      expect(text, contains('(requestTimeout + attempts) * 2'));
      expect(text, contains('retry(requestTimeout)'));
      expect(text.contains('kTimeout'), isFalse);
    });

    test('unknown symbol → structured diagnostic, nothing written', () async {
      final before = File('${jailRename.path}/lib/consts.dart').readAsStringSync();
      final out = await runRename({
        'path': 'lib/consts.dart',
        'symbol': 'doesNotExist',
        'new_name': 'whatever',
      });
      expect(out['ok'], false);
      expect(out['code'], 'symbol_not_found');
      expect(File('${jailRename.path}/lib/consts.dart').readAsStringSync(), before);
    });

    test('multi-file rename rewrites declaration + referencing file', () async {
      final def = File('${jailRename.path}/lib/store.dart')
        ..createSync(recursive: true);
      def.writeAsStringSync('class DataStore {\n  final Map m = {};\n}\n');
      final usr = File('${jailRename.path}/lib/app.dart')
        ..createSync(recursive: true);
      usr.writeAsStringSync("import 'store.dart';\nfinal store = DataStore();\n");

      final tool = renameSymbolMultiTool(jailRename.path);
      final raw = await tool.execute({
        'path': 'lib/store.dart',
        'symbol': 'DataStore',
        'new_name': 'KeyValueStore',
        'extra_files': ['lib/app.dart'],
      });
      final map = (raw is String ? jsonDecode(raw) : raw) as Map<String, dynamic>;
      expect(map['ok'], true);
      expect(map['renames'], 2);

      final storeText = File('${jailRename.path}/lib/store.dart').readAsStringSync();
      final appText = File('${jailRename.path}/lib/app.dart').readAsStringSync();
      expect(storeText, contains('class KeyValueStore'));
      expect(storeText.contains('DataStore'), isFalse);
      expect(appText, contains('KeyValueStore'));
      expect(appText.contains('DataStore'), isFalse);
    });
  });
}

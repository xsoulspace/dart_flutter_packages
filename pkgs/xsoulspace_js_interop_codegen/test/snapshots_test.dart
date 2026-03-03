import 'package:test/test.dart';
import 'package:xsoulspace_js_interop_codegen/xsoulspace_js_interop_codegen.dart';

void main() {
  test('buildApiDiff computes added and removed symbols', () {
    final diff = buildApiDiff(
      fromVersion: '1.0.0',
      toVersion: '1.1.0',
      oldSymbols: <String>{'A', 'B'},
      newSymbols: <String>{'B', 'C'},
    );

    expect(diff['fromVersion'], '1.0.0');
    expect(diff['toVersion'], '1.1.0');
    expect(diff['addedSymbols'], <String>['C']);
    expect(diff['removedSymbols'], <String>['A']);
  });
}

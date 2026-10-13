import 'package:test/test.dart';
import 'package:xsoulspace_materialization_core/xsoulspace_materialization_core.dart';

void main() {
  test('portable graph materializes explicit signatures without a world', () {
    final result = materializeDartGraph(
      nodes: [
        {
          'id': 'arg',
          'kind': 'op',
          'label': 'load_arg',
          'props': {'a': 'x'},
        },
        {'id': 'ret', 'kind': 'op', 'label': 'return'},
      ],
      edges: [
        {'from': 'identity', 'to': 'arg', 'relation': 'impl'},
        {'from': 'arg', 'to': 'ret', 'relation': 'then'},
      ],
      intents: [
        DartMaterializationIntent(
          intent: 'identity',
          targetFile: 'lib/identity.dart',
          params: [(name: 'x', type: 'int')],
          returns: 'int',
        ),
      ],
    );
    expect(result.problems, isEmpty);
    expect(result.files, {'lib/identity.dart': 'int identity(int x) => x;\n'});
  });

  test('observed expression stays one evaluation and preserves precedence', () {
    const observed = ObservedReturn(
      text: 'x + 1',
      kind: 'numeric',
      precedence: 3,
      atomic: false,
      simple: false,
    );
    final result = compileOpChainBody(
      [
        {'label': 'load_return'},
        {'label': 'literal', 'b': '2'},
        {'label': 'mul'},
        {'label': 'return'},
      ],
      paramNames: {'x'},
      observedReturn: observed,
    );
    expect(result.problem, isNull);
    expect(result.expression, '(x + 1) * 2');
    final duplicate = compileOpChainBody(
      [
        {'label': 'load_return'},
        {'label': 'load_return'},
        {'label': 'add'},
        {'label': 'return'},
      ],
      paramNames: {'x'},
      observedReturn: observed,
    );
    expect(duplicate.problem, contains('only once'));
  });

  test('unsupported state operations produce no source candidate', () {
    final result = compileOpChainBody([
      {'label': 'load_state', 'a': 'secret'},
      {'label': 'return'},
    ], paramNames: {});
    expect(result.problem, contains('no workspace-Dart realization'));
    expect(result.code, isNull);
  });

  test('typed admission refuses mismatched scalar and executable slots', () {
    expect(
      () => admitNodeEditPayload(
        fileClass: 'json',
        action: 'set_key',
        anchor: 'enabled',
        payload: const ScalarNodeEditPayload('true', false),
      ),
      throwsA(isA<NodeEditPayloadError>()),
    );
    expect(
      () => admitNodeEditPayload(
        fileClass: 'yaml',
        action: 'set_key',
        anchor: 'scripts.build',
        payload: const ScalarNodeEditPayload('hello', 'hello'),
      ),
      throwsA(isA<NodeEditPayloadError>()),
    );
    expect(
      admitNodeEditPayload(
        fileClass: 'json',
        action: 'set_key',
        anchor: 'enabled',
        payload: const ScalarNodeEditPayload('true', true),
      ),
      'true',
    );
  });
}

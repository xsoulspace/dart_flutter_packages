import 'dart:convert';

import 'package:test/test.dart';
import 'package:xsoulspace_meaning_core/xsoulspace_meaning_core.dart';
import 'package:intentcall_schema/intentcall_schema.dart' as native;
import 'package:agentic_executables_wire/agentic_executables_wire.dart' as ae;

void main() {
  final subject = MeaningRef(namespace: 'workspace', id: 'fixture::greeting');
  final dependency = MeaningDependency(
    ref: subject,
    revision: MeaningRevision(kind: 'source_sha256', value: 'baseline'),
  );
  final prediction = MeaningEvidence(
    ref: MeaningRef(namespace: 'experiment', id: 'prediction'),
    stage: MeaningEvidenceStage.predicted,
  );

  test(
    'IntentCall owns validation; candidate snapshots resist argument drift',
    () {
      final schema = <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
        'required': ['suffix'],
        'properties': {
          'suffix': {'type': 'string'},
        },
      };
      final operation = MeaningOperation(
        ref: MeaningRef(namespace: 'workspace', id: 'observed_return'),
        inputSchema: schema,
      );
      final args = <String, Object?>{'suffix': ' again'};
      final change = MeaningChange(
        operation: operation,
        arguments: args,
        reads: [dependency],
        writes: [subject],
        predictions: [prediction],
        recovery: MeaningRecovery(
          kind: MeaningRecoveryKind.exactInverse,
          operation: MeaningRef(namespace: 'live_apply', id: 'rollback'),
          conditions: [dependency],
        ),
      );
      args['suffix'] = 'drift';
      (schema['properties'] as Map).clear();
      expect(change.arguments['suffix'], ' again');
      expect(
        () => change.arguments['suffix'] = 'mutate',
        throwsUnsupportedError,
      );
      expect(
        () => operation.validate({'suffix': 2}),
        throwsA(isA<native.AgentValidationException>()),
      );
      expect(
        () => operation.validate({'suffix': 'ok', 'extra': true}),
        throwsA(isA<native.AgentValidationException>()),
      );
      final json = jsonDecode(jsonEncode(change.toJson())) as Map;
      expect(
        MeaningChange.fromJson(Map<String, Object?>.from(json)).toJson(),
        change.toJson(),
      );
      expect(
        () => MeaningChange.fromJson({
          ...Map<String, Object?>.from(json),
          'schema': 'xsoulspace.meaning_change.v2',
        }),
        throwsArgumentError,
      );
      expect(json['schema'], 'xsoulspace.meaning_change.v1');
      expect(((json['reads'] as List).single as Map)['revision'], {
        'kind': 'source_sha256',
        'value': 'baseline',
      });
    },
  );

  test('AE executable remains the same owned wire type and vocabulary', () {
    final wire = ae.EditExecutableWire.fromJson({
      'id': 'project/rename',
      'kind': 'rename_symbol',
      'params': ['name'],
      'verification': [],
    });
    final operation = MeaningOperation(
      ref: subject,
      inputSchema: {'type': 'object'},
      executable: wire,
    );
    expect(operation.executable, isA<ae.EditExecutableWire>());
    expect(operation.toJson()['executable'], wire.toJson());
  });

  test(
    'predicted evidence cannot establish exact mapping or applied result',
    () {
      expect(
        () => MeaningCorrespondence(
          from: dependency,
          to: dependency,
          kind: MeaningCorrespondenceKind.exact,
          evidence: [prediction],
        ),
        throwsArgumentError,
      );
      expect(
        () => MeaningCorrespondence(
          from: dependency,
          to: dependency,
          kind: MeaningCorrespondenceKind.candidate,
          evidence: [],
        ),
        throwsArgumentError,
      );
      final observed = MeaningEvidence(
        ref: prediction.ref,
        stage: MeaningEvidenceStage.observed,
      );
      expect(
        MeaningCorrespondence(
          from: dependency,
          to: dependency,
          kind: MeaningCorrespondenceKind.exact,
          evidence: [observed],
        ).kind,
        MeaningCorrespondenceKind.exact,
      );
      expect(
        () => MeaningChange(
          operation: MeaningOperation(
            ref: subject,
            inputSchema: {'type': 'object'},
          ),
          arguments: {},
          reads: [dependency],
          writes: [subject],
          predictions: [observed],
          recovery: MeaningRecovery(
            kind: MeaningRecoveryKind.unavailable,
            conditions: [],
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test('malformed references, recovery and non-JSON operands refuse', () {
    expect(() => MeaningRef(namespace: '', id: 'x'), throwsArgumentError);
    expect(() => MeaningRevision(kind: 'sha', value: ''), throwsArgumentError);
    expect(
      () => MeaningRecovery(
        kind: MeaningRecoveryKind.exactInverse,
        conditions: [],
      ),
      throwsArgumentError,
    );
    expect(
      () => MeaningOperation(
        ref: subject,
        inputSchema: {'type': 'object', 'invalid': Object()},
      ),
      throwsArgumentError,
    );
  });

  test('read refusals retain the legacy wire and lazy op validation', () {
    expect(meaningProgramEnvelopeRefusal([]), {
      'ok': false,
      'program_halt': {
        'index': 0,
        'error': 'ops_required',
        'hint': 'ops is a non-empty array of {op: locate|zoom|impact|read}',
      },
    });
    expect(
      meaningProgramEnvelopeRefusal(
        List.filled(9, {'op': 'read'}),
      )!['program_halt'],
      {
        'index': 0,
        'error': 'too_many_ops: 9 > 8',
        'hint':
            'split the work across decisions — the next decision sees this verdict',
      },
    );
    // Unknown operations must not preempt an earlier valid native operation.
    expect(
      meaningProgramEnvelopeRefusal([
        {'op': 'read'},
        {'op': 'bad'},
      ]),
      isNull,
    );
    expect(meaningProgramOpError('apply', ['apply']), isNull);
    expect(
      meaningProgramOpError('bad', ['apply']),
      'unknown_op — closed set: [locate, zoom, impact, read] + registered: [apply]',
    );
    expect(
      meaningProgramOpError('bad', []),
      'unknown_op — closed set: [locate, zoom, impact, read]',
    );
  });
}

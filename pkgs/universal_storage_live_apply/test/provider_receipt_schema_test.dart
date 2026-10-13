import 'dart:convert';

import 'package:test/test.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_live_apply/universal_storage_live_apply.dart';

Map<String, dynamic> metadata(int n) => {
  'durability_protocol': 'journal_v1',
  'durability_namespace': 'lib',
  'durability_sequence': n,
  'durability_operation_id': 'lib:update:$n:123456',
  'durability_checkpoint_sequence': n,
};

LiveApplyProviderReceipt receipt(int n, LiveApplyReceiptPhase phase) =>
    LiveApplyProviderReceipt.fromMetadata(metadata(n), phase: phase)!;

LiveApplyJournal journal({String? profile = storagePosixRwxProfile}) =>
    LiveApplyJournal(
      runId: 'receipt-roundtrip',
      createdUtc: '2026-10-13T00:00:00Z',
      fileStateProfile: profile,
      entries: [
        LiveApplyEntry(path: 'lib/source', postSha256: 'hash', postMode: 0x180),
      ],
    );

void main() {
  test(
    'native selected metadata preserves repeated forward and inverse order',
    () {
      final value = journal();
      value.entries.single.providerReceipts.addAll([
        receipt(1, LiveApplyReceiptPhase.forward),
        receipt(2, LiveApplyReceiptPhase.forward),
        receipt(3, LiveApplyReceiptPhase.inverse),
      ]);
      final copy = LiveApplyJournal.fromMap(
        jsonDecode(jsonEncode(value.toMap())) as Map<String, dynamic>,
      );
      expect(copy.toMap(), value.toMap());
      expect(copy.entries.single.providerReceipts.map((r) => r.sequence), [
        1,
        2,
        3,
      ]);
      expect(
        copy.entries.single.providerReceipts.last.phase,
        LiveApplyReceiptPhase.inverse,
      );
      expect(copy.entries.single.providerReceipts.first.toMap().keys.toSet(), {
        'phase',
        'durability_protocol',
        'namespace',
        'sequence',
        'operation_id',
        'checkpoint_sequence',
      });
    },
  );

  test('missing metadata yields no evidence; extra metadata is omitted', () {
    expect(
      LiveApplyProviderReceipt.fromMetadata({
        'anything': 'not evidence',
      }, phase: LiveApplyReceiptPhase.forward),
      isNull,
    );
    final raw = metadata(1)
      ..['authority'] = 'not authority'
      ..['phase'] = 'inverse';
    final observed = LiveApplyProviderReceipt.fromMetadata(
      raw,
      phase: LiveApplyReceiptPhase.forward,
    )!;
    expect(observed.phase, LiveApplyReceiptPhase.forward);
    expect(observed.toMap().containsKey('authority'), isFalse);
    expect(
      ((journal().toMap()['entries'] as List).single as Map).containsKey(
        'provider_receipts',
      ),
      isFalse,
    );
  });

  test(
    'partial malformed advertised receipts refuse rather than invent fields',
    () {
      for (final key in metadata(1).keys) {
        expect(
          () => LiveApplyProviderReceipt.fromMetadata({
            key: metadata(1)[key],
          }, phase: LiveApplyReceiptPhase.forward),
          throwsFormatException,
        );
      }
      final wire = receipt(1, LiveApplyReceiptPhase.forward).toMap();
      for (final entry in <String, List<Object?>>{
        'durability_protocol': [null, 1, 'unsupported'],
        'namespace': [null, false, '', 'x' * 257, 'private\nmarker'],
        'operation_id': [null, 4, '', 'x' * 513, '\u0000'],
        'sequence': [null, true, '1', 1.0, 0, -1, 2],
        'checkpoint_sequence': [null, false, '1', 1.0, 0, -1, 9007199254740992],
        'phase': [null, false, 'unknown'],
      }.entries) {
        for (final bad in entry.value) {
          expect(
            () => LiveApplyProviderReceipt.fromMap({...wire, entry.key: bad}),
            throwsFormatException,
            reason: '${entry.key}: $bad',
          );
        }
      }
      expect(
        () => LiveApplyProviderReceipt.fromMap({...wire, 'authority': true}),
        throwsFormatException,
      );
      expect(
        () => const LiveApplyProviderReceipt(
          phase: LiveApplyReceiptPhase.forward,
          durabilityProtocol: 'journal_v1',
          namespace: 'lib',
          sequence: 1,
          operationId: 'operation',
          checkpointSequence: 0,
        ).toMap(),
        throwsFormatException,
      );
    },
  );

  test('UTF8 length bounds are enforced, not only character count', () {
    final wire = receipt(1, LiveApplyReceiptPhase.forward).toMap();
    expect(
      () => LiveApplyProviderReceipt.fromMap({...wire, 'namespace': 'é' * 129}),
      throwsFormatException,
    );
    expect(
      LiveApplyProviderReceipt.fromMap({
        ...wire,
        'namespace': 'é' * 128,
      }).namespace,
      'é' * 128,
    );
  });

  test('legacy journals omit and strip receipts without upgrading', () {
    final value = journal(profile: null);
    value.entries.single.providerReceipts.add(
      receipt(1, LiveApplyReceiptPhase.forward),
    );
    final legacy = value.toMap();
    expect(legacy['schema_version'], 2);
    expect(
      ((legacy['entries'] as List).single as Map).containsKey(
        'provider_receipts',
      ),
      isFalse,
    );
    for (final version in [1, 2]) {
      legacy['schema_version'] = version;
      ((legacy['entries'] as List).single as Map)['provider_receipts'] =
          'malformed unqualified data';
      final decoded = LiveApplyJournal.fromMap(legacy);
      expect(decoded.fileStateProfile, isNull);
      expect(decoded.entries.single.providerReceipts, isEmpty);
    }
  });

  test('bounded v3 history refuses oversized or non-list wire data', () {
    final value = journal();
    final one = receipt(1, LiveApplyReceiptPhase.forward);
    value.entries.single.providerReceipts.addAll(
      List.filled(LiveApplyProviderReceipt.maxReceipts, one),
    );
    expect(
      LiveApplyJournal.fromMap(
        value.toMap(),
      ).entries.single.providerReceipts.length,
      1024,
    );
    value.entries.single.providerReceipts.add(one);
    expect(value.toMap, throwsFormatException);
    final wire = journal().toMap();
    final row = (wire['entries'] as List).single as Map;
    for (final invalid in [
      42,
      {},
      [42],
      List.filled(1025, one.toMap()),
    ]) {
      row['provider_receipts'] = invalid;
      expect(() => LiveApplyJournal.fromMap(wire), throwsFormatException);
    }
  });
}

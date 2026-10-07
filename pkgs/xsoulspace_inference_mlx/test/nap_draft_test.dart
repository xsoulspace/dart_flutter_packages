import 'dart:io';

import 'package:test/test.dart';
import 'package:xsoulspace_inference_mlx/xsoulspace_inference_mlx.dart';

void main() {
  group('NapDraftRecord', () {
    test('JSON round-trip preserves provenance', () {
      final record = NapDraftRecord(
        id: '10-25-1760000000000',
        createdAt: DateTime.utc(2026, 10, 8, 3),
        blockLo: 10,
        blockHi: 25,
        model: 'LFM2.5-1.2B-Instruct-MLX-4bit',
        providerId: 'mlx_local',
        draft: 'transport v2 landed; mesh gate green',
        draftBytes: 38,
        status: NapDraftStatus.pending,
        elapsedMs: 812,
        promptBytes: 1400,
        promptTokens: 340,
        completionTokens: 22,
        finishReason: 'stop',
      );
      final restored = NapDraftRecord.fromJson(
        record.toJson().cast<String, Object?>(),
      );

      expect(restored.id, record.id);
      expect(restored.blockLo, 10);
      expect(restored.blockHi, 25);
      expect(restored.model, record.model);
      expect(restored.providerId, 'mlx_local');
      expect(restored.draft, record.draft);
      expect(restored.status, NapDraftStatus.pending);
      expect(restored.promptTokens, 340);
      expect(restored.napArgument, '10-25 "transport v2 landed; mesh gate green"');
    });
  });

  group('NapDraftStore', () {
    late Directory dir;
    late NapDraftStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('nap_draft_store_test');
      store = NapDraftStore(File('${dir.path}/drafts/nap.jsonl'));
    });

    tearDown(() {
      dir.deleteSync(recursive: true);
    });

    test('append creates the queue; load returns records oldest first',
        () async {
      await store.append(_record('10-25-1', 10, 25, NapDraftStatus.pending));
      await store.append(_record('26-41-2', 26, 41, NapDraftStatus.refused));

      final records = store.load();
      expect(records, hasLength(2));
      expect(records.first.id, '10-25-1');
      expect(records.last.status, NapDraftStatus.refused);
    });

    test('latestPerBlock keeps one worklist entry per block, block order',
        () async {
      await store.append(_record('10-25-1', 10, 25, NapDraftStatus.tooLong));
      await store.append(
        _record('10-25-2', 10, 25, NapDraftStatus.pending, minutes: 5),
      );
      await store.append(_record('2-3-3', 2, 3, NapDraftStatus.pending));

      final latest = store.latestPerBlock();
      expect(latest, hasLength(2));
      expect(latest[0].blockLo, 2);
      expect(latest[1].blockLo, 10);
      // The superseded too-long attempt is not the worklist entry.
      expect(latest[1].id, '10-25-2');
      expect(latest[1].status, NapDraftStatus.pending);
    });

    test('a missing queue loads as empty', () {
      expect(store.load(), isEmpty);
      expect(store.latestPerBlock(), isEmpty);
    });
  });
}

NapDraftRecord _record(
  final String id,
  final int lo,
  final int hi,
  final NapDraftStatus status, {
  final int minutes = 0,
}) => NapDraftRecord(
  id: id,
  createdAt: DateTime.utc(2026, 10, 8, 3, minutes),
  blockLo: lo,
  blockHi: hi,
  model: 'fake',
  providerId: 'mlx_local',
  draft: 'a draft',
  draftBytes: 8,
  status: status,
  elapsedMs: 100,
  promptBytes: 500,
);

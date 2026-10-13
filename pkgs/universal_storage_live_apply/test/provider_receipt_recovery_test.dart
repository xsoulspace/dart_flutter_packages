import 'dart:io';

import 'package:test/test.dart';
import 'package:universal_storage_filesystem/universal_storage_filesystem.dart';
import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_live_apply/universal_storage_live_apply.dart';

void main() {
  late Directory tmp;
  late FileSystemStorageProvider inner;
  late LiveApplyJournalStore store;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('provider_receipt_');
    inner = FileSystemStorageProvider();
    await inner.initWithConfig(
      FileSystemConfig(
        filePathConfig: FilePathConfig({'path': '${tmp.path}/source'}),
      ),
    );
    store = LiveApplyJournalStore(storePath: '${tmp.path}/runs');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'receipt capacity refuses before effects and reserves native Undo',
    () async {
      await inner.createFile('a', 'original');
      final tx = await LiveApplyTransaction.begin(inner, store);
      await tx.writeFile('a', 'changed');
      final saved = (await store.read(tx.runId))!;
      final rows = saved.entries.single.providerReceipts;
      final observed = rows.single;
      // Exercise the capacity boundary without dispatching 1023 real writes.
      rows.addAll(
        List.filled(LiveApplyProviderReceipt.maxReceipts - 2, observed),
      );
      await store.write(saved);
      var dispatched = false;
      await expectLater(
        tx.mutate('a', 'overflow', () {
          dispatched = true;
          return inner.updateFile('a', 'overflow');
        }),
        throwsA(isA<LiveApplyRefusalException>()),
      );
      expect(dispatched, isFalse);
      expect(await inner.getFile('a'), 'changed');
      await tx.rollback();
      expect(await inner.getFile('a'), 'original');
      final restored = (await store.read(tx.runId))!.entries.single;
      expect(
        restored.providerReceipts,
        hasLength(LiveApplyProviderReceipt.maxReceipts),
      );
      expect(
        restored.providerReceipts.last.phase,
        LiveApplyReceiptPhase.inverse,
      );
    },
    skip: !(Platform.isMacOS || Platform.isLinux),
  );

  test(
    'native repeated effects and inverse retain actual IDs under each run',
    () async {
      await inner.createFile('a', 'original');
      final tx = await LiveApplyTransaction.begin(inner, store);
      final first = await tx.writeFile('a', 'first');
      final second = await tx.writeFile('a', 'second');
      await tx.markApplied();
      var saved = (await store.read(tx.runId))!;
      expect(saved.entries.single.providerReceipts.map((r) => r.operationId), [
        first.metadata['durability_operation_id'],
        second.metadata['durability_operation_id'],
      ]);
      final reopened = await LiveApplyTransaction.reopen(
        inner,
        store,
        tx.runId,
      );
      await reopened.rollback();
      saved = (await store.read(tx.runId))!;
      final receipts = saved.entries.single.providerReceipts;
      expect(receipts.map((r) => r.phase), [
        LiveApplyReceiptPhase.forward,
        LiveApplyReceiptPhase.forward,
        LiveApplyReceiptPhase.inverse,
      ]);
      expect(receipts.map((r) => r.operationId).toSet(), hasLength(3));
      expect(receipts.every((r) => r.namespace == '_root'), isTrue);
      expect(saved.runId, tx.runId);
      expect(saved.entries.single.path, 'a');
      final next = await LiveApplyTransaction.begin(inner, store);
      final repeated = await next.writeFile('a', 'first');
      expect(next.runId, isNot(tx.runId));
      expect(
        repeated.metadata['durability_operation_id'],
        isNot(first.metadata['durability_operation_id']),
      );
      await next.rollback();
    },
    skip: !(Platform.isMacOS || Platform.isLinux),
  );

  test(
    'throw after publication leaves no invented receipt on recovery',
    () async {
      await inner.createFile('a', 'original');
      final tx = await LiveApplyTransaction.begin(inner, store);
      await expectLater(
        tx.mutate('a', 'changed', () async {
          await inner.updateFile('a', 'changed');
          throw StateError('effect returned no receipt');
        }),
        throwsStateError,
      );
      final pending = (await store.read(tx.runId))!.entries.single;
      expect(pending.pending, isTrue);
      expect(pending.providerReceipts, isEmpty);
      final reopened = await LiveApplyTransaction.reopen(
        inner,
        store,
        tx.runId,
      );
      await reopened.rollback();
      expect(
        (await store.read(
          tx.runId,
        ))!.entries.single.providerReceipts.map((r) => r.phase),
        [LiveApplyReceiptPhase.inverse],
      );
      expect(await inner.getFile('a'), 'original');
    },
    skip: !(Platform.isMacOS || Platform.isLinux),
  );

  test(
    'malformed advertised metadata preserves pending recovery state',
    () async {
      await inner.createFile('a', 'original');
      final tx = await LiveApplyTransaction.begin(inner, store);
      await expectLater(
        tx.mutate('a', 'changed', () async {
          await inner.updateFile('a', 'changed');
          return const FileOperationResult(
            path: 'a',
            metadata: {'durability_operation_id': 'partial'},
          );
        }),
        throwsFormatException,
      );
      final pending = (await store.read(tx.runId))!.entries.single;
      expect(pending.pending, isTrue);
      expect(pending.providerReceipts, isEmpty);
      await (await LiveApplyTransaction.reopen(
        inner,
        store,
        tx.runId,
      )).rollback();
      expect(await inner.getFile('a'), 'original');
    },
    skip: !(Platform.isMacOS || Platform.isLinux),
  );
}

import 'package:test/test.dart';
import 'package:universal_storage_convergence/universal_storage_convergence.dart';
import 'package:universal_storage_world/universal_storage_world.dart';

void main() {
  const codec = SingleFieldMemberCodec();

  ConvergenceDoc doc() => ConvergenceDoc(docId: 'docs/a', actorId: 'tester');

  group('SingleFieldMemberCodec', () {
    test('fresh doc: never written, no live value, reads null', () {
      final d = doc();
      expect(codec.wasWritten(d), isFalse);
      expect(codec.hasLiveValue(d), isFalse);
      expect(codec.readValue(d), isNull);
    });

    test('write makes the value live through the codec and the register', () {
      final d = doc();
      for (final op in codec.writeOps('hello')) {
        d.applyLocal(op, DateTime.now());
      }
      expect(codec.wasWritten(d), isTrue);
      expect(codec.hasLiveValue(d), isTrue);
      expect(codec.readValue(d), 'hello');
      // The op shape is exactly the ADR 0010 wire register — wire-format
      // preservation is the whole point of this codec.
      expect(
        LwwMapStrategy.readValue(d.state, 'content'),
        'hello',
      );
    });

    test('delete tombstones without losing the written flag', () {
      final d = doc();
      d.applyLocal({'k': 'content', 'v': 'x'}, DateTime.now());
      for (final op in codec.deleteOps()) {
        d.applyLocal(op, DateTime.now());
      }
      expect(codec.wasWritten(d), isTrue);
      expect(codec.hasLiveValue(d), isFalse);
      expect(codec.readValue(d), isNull);
    });

    test('custom register key keeps kinds out of each other\'s way', () {
      const manifestCodec = SingleFieldMemberCodec(registerKey: 'catalog');
      final d = doc();
      d.applyLocal({'k': 'content', 'v': 'a file'}, DateTime.now());
      expect(manifestCodec.hasLiveValue(d), isFalse);
      for (final op in manifestCodec.writeOps('a manifest')) {
        d.applyLocal(op, DateTime.now());
      }
      expect(manifestCodec.readValue(d), 'a manifest');
      expect(codec.readValue(d), 'a file');
    });
  });
}

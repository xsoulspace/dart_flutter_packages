import 'package:test/test.dart';
import 'package:xsoulspace_platform_multiplayer_interface/xsoulspace_platform_multiplayer_interface.dart';

void main() {
  group('MultiplayerSessionInitResult', () {
    test('empty factory keeps no opponents', () {
      expect(MultiplayerSessionInitResult.empty.opponents, isEmpty);
    });
  });

  group('Multiplayer model contracts', () {
    test('stores metadata ranges and payload content', () {
      const ranges = MultiplayerMetaRanges(
        meta1: MultiplayerMetaRange(min: 0, max: 10),
      );
      const request = MultiplayerSessionInitRequest(
        count: 2,
        maxOpponentTurnTime: 60,
        metaRanges: ranges,
      );
      const payload = MultiplayerCommitPayload(
        data: <String, Object?>{'turn': 1},
        time: 123,
      );

      expect(request.count, 2);
      expect(request.metaRanges?.meta1?.max, 10);
      expect(payload.data['turn'], 1);
      expect(payload.time, 123);
    });

    test('push result keeps status and optional error', () {
      const result = MultiplayerPushResult(status: 'ok', error: null);

      expect(result.status, 'ok');
      expect(result.error, isNull);
    });
  });
}

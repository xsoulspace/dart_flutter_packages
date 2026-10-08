import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:xsoulspace_inference_local_serve/xsoulspace_inference_local_serve.dart';

void main() {
  test(
    'opt-in route concurrency bounded, health available, slots released after real completion',
    () async {
      final gate = Completer<void>();
      final arrived = Completer<void>();
      var active = 0;
      final server = LoopbackJsonServer(
        maxConcurrentRequests: 2,
        healthPayload: () => {'status': 'ok'},
        route: (_) async {
          active++;
          if (active == 2) arrived.complete();
          await gate.future;
          return const LoopbackReply(200, {'done': true});
        },
      );
      await server.start();
      addTearDown(server.stop);
      final client = http.Client();
      addTearDown(client.close);
      final first = client.get(server.url.replace(path: '/a'));
      final second = client.get(server.url.replace(path: '/b'));
      await arrived.future;
      final health = await client.get(server.url.replace(path: '/health'));
      expect(health.statusCode, 200);
      expect(jsonDecode(health.body), {'status': 'ok'});
      final overflow = await client.get(server.url.replace(path: '/c'));
      expect(overflow.statusCode, 429);
      expect(
        jsonDecode(overflow.body)['error']['code'],
        'loopback_capacity_exhausted',
      );
      expect(active, 2);
      gate.complete();
      expect((await first).statusCode, 200);
      expect((await second).statusCode, 200);
      expect(
        (await client.get(server.url.replace(path: '/c'))).statusCode,
        200,
      );
    },
  );
}

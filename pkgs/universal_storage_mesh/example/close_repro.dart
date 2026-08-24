import 'dart:async';
import 'dart:io';

/// Minimal repro: does a TCP echo session close() complete?
Future<void> main() async {
  print('A: binding');
  final server = await ServerSocket.bind(InternetAddress.anyIPv4, 45999);
  server.listen((s) {
    print('server: connection');
    s.add([1, 2, 3]);
    unawaited(
      s.flush().then((_) {
        print('server: flushed, destroying');
        s.destroy();
      }),
    );
  });

  print('B: connecting');
  final socket = await Socket.connect('127.0.0.1', 45999);
  final frames = StreamController<List<int>>();
  socket.listen(frames.add, onDone: () => frames.close());

  final iterator = StreamIterator<List<int>>(frames.stream);
  while (await iterator.moveNext()) {
    print('client: got ${iterator.current}');
  }
  print('client: stream closed normally');

  socket.destroy();
  await server.close();
  print('DONE - no hang');
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:universal_storage_interface/universal_storage_interface.dart';
import 'package:universal_storage_mesh/universal_storage_mesh.dart';
import 'package:universal_storage_mesh_transport/universal_storage_mesh_transport.dart';

import '../transport/websocket_mesh_relay.dart';
import '../transport/websocket_mesh_transport.dart';

class MeshAppState extends ChangeNotifier {
  MeshAppState({
    required this.selfId,
    required this.bindPort,
    required this.isHost,
    required this.relayPort,
  });

  final String selfId;
  final int bindPort;
  final bool isHost;
  final int relayPort;

  WebSocketMeshRelay? _relay;
  WebSocketChannel? _clientChannel;
  WebSocketMeshTransport? _transport;
  final MeshStorageProvider _provider = MeshStorageProvider();
  SimpleKeyPair? _identity;
  String _status = 'starting…';
  Uint8List? _qrPayload;
  List<FileEntry> files = const [];
  bool syncing = false;

  String get status => _status;
  Uint8List? get qrPayload => _qrPayload;
  var _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _identity = await PairingService.newIdentityKeyPair();
      if (isHost) {
        _relay = WebSocketMeshRelay(port: bindPort);
        await _relay!.start();
      } else {
        final channel = WebSocketChannel.connect(
          Uri.parse('ws://127.0.0.1:$relayPort'),
        );
        await channel.ready;
        _clientChannel = channel;
      }
      _transport = WebSocketMeshTransport(
        selfId: selfId,
        endpoint: Uri.parse('ws://127.0.0.1:$bindPort'),
      );
      await _transport!.start();
      if (!isHost) {
        _transport!.attachClient(_clientChannel!);
      }
      _provider.attachTransport(_transport!);
      await _provider.initWithConfig(
        MeshStorageConfig(storePath: ':memory:', peerId: selfId),
      );
      final ephemeral = await X25519().newKeyPair();
      _qrPayload = await PairingService.buildQrPayload(
        identityKeyPair: _identity!,
        ephemeralKeyPair: ephemeral,
        peerId: selfId,
        transportHint: 'ws:127.0.0.1:$bindPort',
      );
      _status = 'ready — show or paste a pairing code';
    } catch (error) {
      _status = 'startup failed: $error';
    } finally {
      _initialized = true;
    }
    notifyListeners();
  }

  Future<void> acceptPairing(final String pastedBase64) async {
    if (_identity == null) return;
    try {
      final payload = base64Decode(pastedBase64.trim());
      final result = await PairingService.acceptQrPayload(
        qrPayload: payload,
        peerIdentityKey: _peerIdentityKeyFromEnvelope(payload),
        ownEphemeralKeyPair: await X25519().newKeyPair(),
        ourPeerId: selfId,
      );
      await _provider.registerPeer(
        MeshPeerRecord(
          peerId: '${result.peerId}-ws',
          displayName: result.peerId,
          endpointHints: {'ws': 'ws://127.0.0.1:$_peerPort(payload)'},
        ),
      );
      _status = 'paired with ${result.peerId}';
    } catch (error) {
      _status = 'pairing failed: $error';
    }
    notifyListeners();
  }

  Future<void> createFile(final String path, final String content) async {
    await _provider.createFile(path, content);
    await refreshFiles();
  }

  Future<void> sync() async {
    if (syncing) return;
    syncing = true;
    _status = 'syncing…';
    notifyListeners();
    try {
      await _provider.sync();
      await refreshFiles();
      _status = 'sync complete';
    } catch (error) {
      _status = 'sync failed: $error';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> refreshFiles() async {
    files = await _provider.listDirectory('');
    notifyListeners();
  }

  Future<String?> readFile(final FileEntry entry) =>
      _provider.getFile(entry.name);

  String pairingCodeBase64() {
    if (_qrPayload == null) {
      throw StateError('pairing payload is not ready');
    }
    return base64Encode(_qrPayload!);
  }

  Uint8List _peerIdentityKeyFromEnvelope(final Uint8List payload) {
    final text = utf8.decode(payload, allowMalformed: true);
    final jsonStart = text.indexOf('{');
    final signatureStart = payload.length - 64;
    if (jsonStart < 0 || signatureStart <= jsonStart) {
      throw const FormatException('malformed pairing payload');
    }
    // The example's QR carries the advertiser identity key in a signed
    // extension so two fresh demo identities can pair without durable
    // identity discovery. Production scanners must obtain this key through
    // an authenticated out-of-band channel.
    final envelope = utf8.decode(
      payload.sublist(jsonStart, signatureStart),
      allowMalformed: true,
    );
    final match = RegExp('"idk":"([^"]+)"').firstMatch(envelope);
    if (match == null) {
      throw const FormatException('pairing payload missing identity key');
    }
    return base64Decode(match.group(1)!);
  }

  int _peerPort(final Uint8List payload) {
    final text = utf8.decode(payload, allowMalformed: true);
    final match = RegExp(r'tcp:127\.0\.0\.1:(\d+)').firstMatch(text);
    return int.parse(match?.group(1) ?? '45911');
  }
}

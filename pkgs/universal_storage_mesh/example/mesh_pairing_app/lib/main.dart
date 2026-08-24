import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';

import 'pages/files_page.dart';
import 'pages/pairing_page.dart';
import 'state/mesh_app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MCPToolkitBinding.instance
    ..initialize()
    ..initializeFlutterToolkit();
  const selfId = String.fromEnvironment('MESH_PEER_ID', defaultValue: 'alice');
  const bindPort = int.fromEnvironment(
    'MESH_PORT',
    defaultValue: selfId == 'alice' ? 45910 : 45911,
  );
  const relayPort = int.fromEnvironment('MESH_RELAY_PORT', defaultValue: 45910);
  const isHost = bool.fromEnvironment(
    'MESH_HOST',
    defaultValue: selfId == 'alice',
  );
  runApp(
    MeshPairingApp(
      state: MeshAppState(
        selfId: selfId,
        bindPort: bindPort,
        isHost: isHost,
        relayPort: relayPort,
      ),
    ),
  );
}

class MeshPairingApp extends StatelessWidget {
  const MeshPairingApp({required this.state, super.key});

  final MeshAppState state;

  List<AgentCallEntry> get _automationEntries => [
    AgentCallEntry.tool(
      namespace: 'mesh',
      name: 'pairing_code',
      description: 'Returns this app Base64 mesh-pair/v1 QR payload.',
      inputSchema: const {'type': 'object'},
      handler: (args) async {
        final base64 = state.pairingCodeBase64();
        return AgentResult.success(
          message: 'pairing code',
          data: {
            'parameters': {'base64': base64},
          },
        );
      },
    ),
    AgentCallEntry.tool(
      namespace: 'mesh',
      name: 'accept_pairing',
      description: 'Accepts a peer Base64 mesh-pair/v1 QR payload.',
      inputSchema: const {
        'type': 'object',
        'required': ['base64'],
        'properties': {
          'base64': {'type': 'string'},
        },
      },
      handler: (args) async {
        await state.acceptPairing(args['base64'] as String);
        return AgentResult.success(message: state.status);
      },
    ),
    AgentCallEntry.tool(
      namespace: 'mesh',
      name: 'create_file',
      description: 'Creates a local-first file and refreshes the list.',
      inputSchema: const {
        'type': 'object',
        'required': ['path', 'content'],
        'properties': {
          'path': {'type': 'string'},
          'content': {'type': 'string'},
        },
      },
      handler: (args) async {
        await state.createFile(
          args['path'] as String,
          args['content'] as String,
        );
        return AgentResult.success(message: state.status);
      },
    ),
    AgentCallEntry.tool(
      namespace: 'mesh',
      name: 'sync',
      description: 'Runs opportunistic mesh sync.',
      inputSchema: const {'type': 'object'},
      handler: (args) async {
        await state.sync();
        return AgentResult.success(message: state.status);
      },
    ),
  ];

  @override
  Widget build(final BuildContext context) {
    for (final entry in _automationEntries) {
      MCPToolkitBinding.instance.addEntries(entries: {entry});
    }
    unawaited(state.initialize());
    return MaterialApp(
      title: 'Mesh Pairing Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      home: PairingPage(state: state),
      routes: {'/files': (context) => FilesPage(state: state)},
    );
  }
}

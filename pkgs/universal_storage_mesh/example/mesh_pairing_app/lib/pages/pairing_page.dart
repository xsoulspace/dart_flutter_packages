import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../state/mesh_app_state.dart';

class PairingPage extends StatelessWidget {
  const PairingPage({required this.state, super.key});

  final MeshAppState state;

  @override
  Widget build(final BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${state.selfId} pairing')),
    body: ListenableBuilder(
      listenable: state,
      builder: (context, _) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            spacing: 24,
            children: [
              if (state.qrPayload == null)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(state.status),
                  ],
                )
              else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: CustomPaint(
                    size: const Size.square(260),
                    painter: _TerminalQrPainter(state.qrPayload!),
                  ),
                ),
                Text(state.status, textAlign: TextAlign.center),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: base64Encode(state.qrPayload!)),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Pairing code copied')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy pairing code'),
                ),
                Row(
                  spacing: 12,
                  children: [
                    FilledButton(
                      onPressed: () => _pastePayload(context),
                      child: const Text('Accept peer QR'),
                    ),
                    OutlinedButton(
                      onPressed: () => Navigator.pushNamed(context, '/files'),
                      child: const Text('Files'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _pastePayload(final BuildContext context) async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste scanned QR'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Base64 mesh-pair/v1'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pair'),
          ),
        ],
      ),
    );
    if (accepted ?? false) await state.acceptPairing(controller.text);
  }
}

class _TerminalQrPainter extends CustomPainter {
  const _TerminalQrPainter(this.payload);

  final List<int> payload;

  @override
  void paint(final Canvas canvas, final Size size) {
    final image = QrImage(
      QrCode(
        payload: QrPayload.fromTypedData(Uint8List.fromList(payload)),
        errorCorrectLevel: QrErrorCorrectLevel.medium,
      ),
    );
    final module = size.width / image.moduleCount;
    final paint = Paint()..color = Colors.black;
    for (var y = 0; y < image.moduleCount; y++) {
      for (var x = 0; x < image.moduleCount; x++) {
        if (!image.isDark(y, x)) continue;
        canvas.drawRect(
          Rect.fromLTWH(x * module, y * module, module, module),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(final _TerminalQrPainter oldDelegate) =>
      payload.length != oldDelegate.payload.length ||
      payload
          .indexed
          .any((record) => record.$2 != oldDelegate.payload[record.$1]);
}

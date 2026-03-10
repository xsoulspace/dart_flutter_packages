import 'package:flutter/material.dart';
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() => runApp(const AppleFoundationExampleApp());

class AppleFoundationExampleApp extends StatelessWidget {
  const AppleFoundationExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Apple Foundation Example',
      theme: ThemeData.from(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const _ExamplePage(),
    );
  }
}

class _ExamplePage extends StatefulWidget {
  const _ExamplePage();

  @override
  State<_ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<_ExamplePage> {
  String _status = 'Idle';
  bool? _available;

  static const _schema = <String, dynamic>{
    'type': 'object',
    'properties': <String, dynamic>{
      'answer': <String, dynamic>{'type': 'string'},
    },
  };

  Future<void> _checkAvailability() async {
    setState(() => _status = 'Checking...');
    final available = await AppleFoundationInferenceClient()
        .refreshAvailability();
    setState(() {
      _available = available;
      _status = available
          ? 'Available'
          : 'Unavailable (macOS 26+ and Apple Intelligence required)';
    });
  }

  Future<void> _runInference() async {
    setState(() => _status = 'Running inference...');
    final client = AppleFoundationInferenceClient();
    final result = await client.infer(
      const InferenceRequest(
        prompt: 'Reply with one short word: hello.',
        outputSchema: _schema,
        workingDirectory: '/tmp',
      ),
    );
    setState(() {
      if (result.success && result.data != null) {
        _status = 'OK: ${result.data!.output}';
      } else {
        _status = 'Error: ${result.error?.code} — ${result.error?.message}';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apple Foundation Example')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_available != null)
              Text(
                'Engine: ${_available! ? "Available" : "Unavailable"}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _checkAvailability,
              child: const Text('Check availability'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _available == true ? _runInference : null,
              child: const Text('Run inference'),
            ),
            const SizedBox(height: 24),
            Text(_status, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

abstract class Scenario {
  final ai = AIWorld.fromConfigs(
    runtimeConfig: AIRuntimeConfig(
      inferenceClientBuilders: {
        DefaultModelNames.appleFoundation: () =>
            const AppleFoundationInferenceClient(),
      },
    ),
  );
}

class ScenarioV1SendMessageGetAnswer extends Scenario {
  Future<String> run(String text) async {
    final response = await ai.sendTextMessage(text);
    log(response);
    return response;
  }
}

class ScenarioV2SendMessageGetAnswerLoop extends Scenario {}

class _MyHomePageState extends State<MyHomePage> {
  final scenario = ScenarioV1SendMessageGetAnswer();
  String _response = '';
  String _txt = '';
  bool _isRunning = false;

  Future<void> _run() async {
    setState(() => _isRunning = true);
    final r = await scenario.run(_txt);
    setState(() {
      _response = r;
      _isRunning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: .center,
          children: [
            TextFormField(
              initialValue: _txt,
              onChanged: (v) => setState(() => _txt = v),
            ),

            Text(
              "response: $_response",
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Row(
              children: [
                if (_isRunning) CircularProgressIndicator.adaptive(),
                TextButton(onPressed: _run, child: Text('run')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

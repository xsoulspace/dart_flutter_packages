import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:xsoulspace_inference_apple_foundation/xsoulspace_inference_apple_foundation.dart';
import 'package:xsoulspace_inference_core/xsoulspace_inference_core.dart';
import 'package:xsoulspace_state_utils/xsoulspace_state_utils.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final brightness = hour < 12 || hour > 18
        ? Brightness.dark
        : Brightness.light;
    return MaterialApp(
      title: 'Agent Demo',
      theme: ThemeData(
        colorScheme: .fromSeed(
          seedColor: Colors.indigo,
          brightness: brightness,
        ),
      ),
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

sealed class Scenario {
  bool isInitialized = false;
  final ai = AIWorld.fromConfigs(
    runtimeConfig: AIRuntimeConfig(
      inferenceClientBuilders: {
        DefaultModelNames.appleFoundation: () =>
            const AppleFoundationInferenceClient(),
      },
    ),
  );

  @mustCallSuper
  Future<String> init({
    required String text,
    required AgentConfig config,
  }) async {
    isInitialized = true;
    return '';
  }

  void dispose() {
    isInitialized = false;
    ai.dispose();
  }
}

class ScenarioV1SendMessageGetAnswer extends Scenario {
  @override
  Future<String> init({
    required String text,
    required AgentConfig config,
  }) async {
    super.init(text: text, config: config);
    final response = await ai.sendTextMessage(
      message: text,
      config: config,
      disposeAfterCompletion: true,
    );
    log(response.text);
    return response.text;
  }
}

/// Human -> Agent -> Human -> Agent -> Human
class ScenarioV2KeepPrimitiveMemory extends Scenario {
  late Agent agent;

  @override
  Future<String> init({
    required String text,
    required AgentConfig config,
  }) async {
    super.init(text: text, config: config);
    final response = await ai.sendTextMessage(
      message: text,
      config: config,
      toolRegsitry: ToolRegistry()
        ..register(
          ToolDef(
            name: 'getWeatherForHour',
            description: 'Returns weather for a specific hour of today',
            schema: {
              'type': 'object',
              'properties': {
                'hour': {'type': 'integer', 'minimum': 0, 'maximum': 23},
              },
              'required': ['hour'],
            },
            execute: (args) async {
              final hour = args['hour'] as int;
              final temp = switch (hour) {
                < 4 => 16,
                >= 4 && < 12 => 20,
                >= 12 && < 21 => 20,
                _ => 16,
              };
              // your real implementation
              return {'hour': hour, 'temp': temp, 'condition': 'cloudy'};
            },
          ),
        ),
    );
    log(response.text);
    agent = response.agent;
    return response.text;
  }

  Future<String> reply(String text) async {
    final response = await ai.proceedTextForAgent(message: text, agent: agent);
    log(response);
    return response;
  }
}

class _MyHomePageState extends State<MyHomePage> {
  final scenarioV1 = ScenarioV1SendMessageGetAnswer();
  final scenarioV2 = ScenarioV2KeepPrimitiveMemory();
  final _messages = ImmutableOrderedList<String>();

  AgentConfig _agentConfig = AgentConfig.empty;
  final TextEditingController _controller = TextEditingController();

  String get _txt => _controller.text;

  bool _isRunning = false;
  int _scenarioIndex = 0;

  List<Scenario> get _scenarios => [scenarioV1, scenarioV2];

  T _getScenarioByIndex<T extends Scenario>() =>
      _scenarios[_scenarioIndex] as T;
  void _switchToScenario(int? index) {
    final i = index;
    if (i == null || _scenarioIndex == i) return;
    _cleanup();
    setState(() => _scenarioIndex = i);
  }

  void _cleanup() {
    _messages.clear();
    _agentConfig = AgentConfig.empty;
    for (var scenario in _scenarios) {
      scenario.dispose();
    }
  }

  void _setLoading() => setState(() {
    _isRunning = true;
  });

  Future<void> _initScenario({bool cleanup = false}) async {
    if (cleanup) _cleanup();
    final scenario = _getScenarioByIndex();
    _setLoading();
    final r = await scenario.init(text: _txt, config: _agentConfig);
    setState(() {
      _messages
        ..add(_txt)
        ..add(r);
      _controller.clear();
      _isRunning = false;
    });
  }

  Future<void> _scenario2Reply() async {
    _setLoading();

    final r = await scenarioV2.reply(_txt);
    setState(() {
      _messages
        ..add(_txt)
        ..add(r);
      _controller.clear();
      _isRunning = false;
    });
  }

  void _onReply() {
    final scenario = _getScenarioByIndex();
    switch (scenario) {
      case final ScenarioV1SendMessageGetAnswer _:
        _initScenario(cleanup: true);

      case final ScenarioV2KeepPrimitiveMemory i:
        if (i.isInitialized) {
          _scenario2Reply();
        } else {
          _cleanup();
          const systemPrompt = 'trustworthy agent';
          _agentConfig = AgentConfig(systemPrompt: systemPrompt);
          _initScenario();
        }
    }
  }

  @override
  void dispose() {
    _cleanup();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: .end,
          crossAxisAlignment: .center,
          spacing: 4,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 450),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemBuilder: (context, index) {
                    return Text(_messages[index]);
                  },
                  itemCount: _messages.length,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 600),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Scenario: '),
                  Flexible(
                    child: RadioGroup<int>(
                      onChanged: _switchToScenario,
                      groupValue: _scenarioIndex,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _scenarios.indexed
                            .map(
                              (i) => ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: 100),
                                child: RadioListTile<int>.adaptive(
                                  value: i.$1,
                                  title: Text('${i.$1 + 1}'),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 450, maxHeight: 150),
              child: Row(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        TextFormField(
                          controller: _controller,
                          maxLines: null,
                          textAlignVertical: TextAlignVertical.top,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: ColorScheme.of(context).onSecondary,
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: ColorScheme.of(context).onSecondary,
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            hintText: 'Ask',
                            suffix: SizedBox(width: 24),
                          ),
                          onFieldSubmitted: (value) {
                            _onReply();
                          },
                        ),
                        Positioned(
                          right: 6,
                          bottom: 4,
                          child: ValueListenableBuilder(
                            valueListenable: _controller,
                            builder: (context, value, child) {
                              return IconButton.outlined(
                                icon: Icon(Icons.arrow_upward_rounded),
                                onPressed: _controller.text.isEmpty
                                    ? null
                                    : _onReply,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 24,
                      maxWidth: 24,
                      minHeight: 24,
                      minWidth: 24,
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: .new(milliseconds: 250),

                        child: _isRunning
                            ? CircularProgressIndicator.adaptive()
                            : SizedBox(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

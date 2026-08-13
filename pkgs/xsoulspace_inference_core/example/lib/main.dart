import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:from_json_to_json/from_json_to_json.dart';
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
        DefaultModelNames.appleFoundation: () => AppleFoundationInferenceClient(
          api: AppleFoundationInferenceClient.initApi(),
        ),
      },
    ),
  );

  Future<T> doTry<T>(Future<T> Function() callback, T fallback) async {
    try {
      return await callback();
    } catch (e, st) {
      log('scenario | try failure', error: e, stackTrace: st);
      return fallback;
    }
  }

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
    return doTry(() async {
      final response = await ai.sendTextMessage(
        message: text,
        config: config,
        disposeAfterCompletion: true,
      );
      log(response.text);
      return response.text;
    }, '');
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
    return doTry(() async {
      final response = await ai.sendTextMessage(message: text, config: config);
      log(response.text);
      agent = response.agent;
      return response.text;
    }, "");
  }

  Future<String> reply(String text) async {
    return doTry(() async {
      final response = await ai.proceedTextForAgent(
        message: text,
        agent: agent,
      );
      log(response);
      return response;
    }, '');
  }
}

/// Schema and function call for weather
class ScenarioV3FunctionCallAndSchema extends Scenario {
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
      outputSchema: SchemaBundle(
        root: FM.object(
          'weather',
          properties: () => [FM.prop('condition', FM.string())],
        ),
      ),
      toolRegsitry: ToolRegistry()
        ..register(
          ToolDef.structured(
            name: 'getWeatherForHour',
            description: 'Returns weather for a specific hour of today',
            parameters: SchemaBundle(
              root: FM.object(
                'time',
                properties: () => [
                  FM.prop('hour', FM.double(guides: [RangeGuide(0, 23)])),
                ],
              ),
            ),
            execute: (args) async {
              final params = jsonDecodeMapAs(args);
              final hour = jsonDecodeInt(params['hour']);
              final (temp, condition) = switch (hour) {
                < 4 => (16, 'rain'),
                >= 4 && < 12 => (20, 'sunny'),
                >= 12 && < 21 => (20, 'cloudy'),
                _ => (16, "sunny"),
              };
              // add real implementation
              return jsonEncode({
                'hour': hour,
                'temp': temp,
                'condition': condition,
              });
            },
          ),
        ),
    );
    log(response.text);
    agent = response.agent;
    return response.text;
  }

  SchemaBundle get _schema {
    final npcSchema = FM.object(
      'Npc',
      description: 'A character that can order coffee',
      properties: () => [
        FM.prop('name', description: 'First name, Second Name', FM.string()),
        FM.prop('level', FM.double(guides: [RangeGuide(1, 10)])),
        FM.prop('attributes', FM.array(FM.ref('Attribute'), min: 1, max: 2)),
        FM.prop('encounter', FM.ref('Encounter')),
      ],
    );

    final attributeSchema = FM.enum_('Attribute', ['bold', 'tired', 'hungry']);

    final encounterSchema = FM.anyOf('Encounter', [
      FM.object(
        'OrderCoffee',
        properties: () => [FM.prop('drink', FM.string())],
      ),
      FM.object(
        'WantToTalkToManager',
        properties: () => [FM.prop('complaint', FM.string())],
      ),
    ]);

    // Root + dependencies
    final schema = SchemaBundle(
      root: npcSchema,
      dependencies: [attributeSchema, encounterSchema],
    );
    return schema;
  }

  Future<String> reply(String txt) async {
    return doTry(() async {
      final response = await ai.proceedTextForAgent(
        message: txt,
        agent: agent,
        outputSchema: _schema,
      );
      log(response);
      return response;
    }, "");
  }
}

typedef ScenarioRecord = ({String title, Scenario scenario});

class _MyHomePageState extends State<MyHomePage> {
  final _scenarioV1 = ScenarioV1SendMessageGetAnswer();
  final _scenarioV2 = ScenarioV2KeepPrimitiveMemory();
  final _scenarioV3 = ScenarioV3FunctionCallAndSchema();
  final _messages = ImmutableOrderedList<String>();

  AgentConfig _agentConfig = AgentConfig.empty;
  final TextEditingController _controller = TextEditingController();

  String get _txt => _controller.text;

  bool _isRunning = false;
  int _scenarioIndex = 0;

  List<ScenarioRecord> get _scenarios => [
    (scenario: _scenarioV1, title: 'one-text'),
    (scenario: _scenarioV2, title: 'h -> llm -> h -> llm'),
    (scenario: _scenarioV3, title: 'scheme + tool call: Weather / Character'),
  ];

  T _getScenarioByIndex<T extends Scenario>() =>
      _scenarios[_scenarioIndex].scenario as T;
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
      scenario.scenario.dispose();
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

  Future<void> _scenario3Reply() async {
    _setLoading();

    final r = await _scenarioV3.reply(_txt);
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

    final r = await _scenarioV2.reply(_txt);
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
        _cleanup();
        const systemPrompt = '';
        // 'You are an ASCII art generator for video game tiles. Output: tile with size 5 width by 5 height characters using only standard ASCII text. Wrap the final output in a single markdown code block. Do not include any intro, outro, explanations, or conversational filler. Draw the requested object by user.';
        _agentConfig = AgentConfig(systemPrompt: systemPrompt);
        _initScenario();

      case final ScenarioV2KeepPrimitiveMemory i:
        if (i.isInitialized) {
          _scenario2Reply();
        } else {
          _cleanup();
          const systemPrompt = '';
          _agentConfig = AgentConfig(systemPrompt: systemPrompt);
          _initScenario();
        }
      case final ScenarioV3FunctionCallAndSchema i:
        if (i.isInitialized) {
          _scenario3Reply();
        } else {
          _cleanup();
          const systemPrompt = '';
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
            Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                Text('scenarios'),
                Container(
                  constraints: BoxConstraints(maxWidth: 800, maxHeight: 300),
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      childAspectRatio: 300 / 200,
                    ),
                    shrinkWrap: true,
                    itemCount: _scenarios.length,
                    itemBuilder: (context, index) {
                      final scenario = _scenarios[index];
                      final filled = _scenarioIndex == index;
                      Widget child = Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          crossAxisAlignment: .start,
                          mainAxisSize: .min,
                          children: [Flexible(child: Text(scenario.title))],
                        ),
                      );
                      if (filled) {
                        child = Card.filled(child: child);
                      } else {
                        child = Card.outlined(child: child);
                      }
                      return GestureDetector(
                        onTap: () => _switchToScenario(index),
                        child: child,
                      );
                    },
                  ),
                ),
              ],
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

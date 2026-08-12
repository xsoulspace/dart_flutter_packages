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
      log('e', error: e, stackTrace: st);
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
            // {
            //   'type': 'object',
            //   'properties': {
            //     'hour': {'type': 'integer', 'minimum': 0, 'maximum': 23},
            //   },
            //   'required': ['hour'],
            // },
            execute: (args) async {
              final params = jsonDecodeMapAs(args);
              final hour = jsonDecodeInt(params['hour']);
              final temp = switch (hour) {
                < 4 => 16,
                >= 4 && < 12 => 20,
                >= 12 && < 21 => 20,
                _ => 16,
              };
              // add real implementation
              return jsonEncode({
                'hour': hour,
                'temp': temp,
                'condition': 'cloudy',
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

    final attributeSchema = FM.enum_('Attribute', ['sassy', 'tired', 'hungry']);

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

class _MyHomePageState extends State<MyHomePage> {
  final scenarioV1 = ScenarioV1SendMessageGetAnswer();
  final scenarioV2 = ScenarioV2KeepPrimitiveMemory();
  final scenarioV3 = ScenarioV3FunctionCallAndSchema();
  final messages = ImmutableOrderedList<String>();

  AgentConfig agentConfig = AgentConfig.empty;
  final TextEditingController controller = TextEditingController();

  String get txt => controller.text;

  bool isRunning = false;
  int scenarioIndex = 0;

  List<Scenario> get scenarios => [scenarioV1, scenarioV2, scenarioV3];

  T getScenarioByIndex<T extends Scenario>() => scenarios[scenarioIndex] as T;
  void switchToScenario(int? index) {
    final i = index;
    if (i == null || scenarioIndex == i) return;
    _cleanup();
    setState(() => scenarioIndex = i);
  }

  void _cleanup() {
    messages.clear();
    agentConfig = AgentConfig.empty;
    for (var scenario in scenarios) {
      scenario.dispose();
    }
  }

  void setLoading() => setState(() {
    isRunning = true;
  });

  Future<void> initScenario({bool cleanup = false}) async {
    if (cleanup) _cleanup();
    final scenario = getScenarioByIndex();
    setLoading();
    final r = await scenario.init(text: txt, config: agentConfig);
    setState(() {
      messages
        ..add(txt)
        ..add(r);
      controller.clear();
      isRunning = false;
    });
  }

  Future<void> scenario3Reply() async {
    setLoading();

    final r = await scenarioV3.reply(txt);
    setState(() {
      messages
        ..add(txt)
        ..add(r);
      controller.clear();
      isRunning = false;
    });
  }

  Future<void> scenario2Reply() async {
    setLoading();

    final r = await scenarioV2.reply(txt);
    setState(() {
      messages
        ..add(txt)
        ..add(r);
      controller.clear();
      isRunning = false;
    });
  }

  void onReply() {
    final scenario = getScenarioByIndex();
    switch (scenario) {
      case final ScenarioV1SendMessageGetAnswer _:
        initScenario(cleanup: true);

      case final ScenarioV2KeepPrimitiveMemory i:
        if (i.isInitialized) {
          scenario2Reply();
        } else {
          _cleanup();
          const systemPrompt = 'trustworthy agent';
          agentConfig = AgentConfig(systemPrompt: systemPrompt);
          initScenario();
        }
      case final ScenarioV3FunctionCallAndSchema i:
        if (i.isInitialized) {
          scenario3Reply();
        } else {
          _cleanup();
          const systemPrompt = 'trustworthy agent';
          agentConfig = AgentConfig(systemPrompt: systemPrompt);
          initScenario();
        }
    }
  }

  @override
  void dispose() {
    _cleanup();
    controller.dispose();
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
                    return Text(messages[index]);
                  },
                  itemCount: messages.length,
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
                      onChanged: switchToScenario,
                      groupValue: scenarioIndex,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: scenarios.indexed
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
                          controller: controller,
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
                            onReply();
                          },
                        ),
                        Positioned(
                          right: 6,
                          bottom: 4,
                          child: ValueListenableBuilder(
                            valueListenable: controller,
                            builder: (context, value, child) {
                              return IconButton.outlined(
                                icon: Icon(Icons.arrow_upward_rounded),
                                onPressed: controller.text.isEmpty
                                    ? null
                                    : onReply,
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

                        child: isRunning
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

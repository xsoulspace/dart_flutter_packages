import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_semantics/universal_automation_semantics.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

import '../plan/checks.dart';
import '../plan/plan.dart';
import '../plan/steps.dart';
import '../runner/registry.dart';
import '../runner/runner.dart';

/// MCP protocol versions this server speaks; the client's advertised
/// version is echoed when supported, else the newest one is offered.
const mcpSupportedVersions = ['2024-11-05', '2025-03-26', '2025-06-18'];

/// Server identity advertised at `initialize`.
const mcpServerInfo = {
  'name': 'universal-automation-toolkit',
  'title': 'Universal Automation Toolkit',
  'version': '0.1.0',
};

/// The toolkit's MCP face: observe/act/verify ad-hoc verbs plus plan
/// tools, over newline-delimited JSON-RPC 2.0 on stdio.
///
/// The handler is separable from the stdio shell so tests exercise the
/// protocol in-process.
final class ToolkitMcpServer {
  /// Creates a server; [defaultEndpoint] backs ad-hoc verbs when a tool
  /// call carries no explicit endpoint, and [defaultTransport] selects
  /// the tier those verbs attach to (`--os` serve flag → the desktop
  /// accessibility tier). [factories] extends or replaces the built-in
  /// per-transport drivers (the composition-root seam, e.g. the
  /// instrumented Flutter tier registered by mcp_flutter).
  ToolkitMcpServer({
    Uri? defaultEndpoint,
    AutomationTransport defaultTransport = AutomationTransport.cdp,
    Map<String, String> overrides = const {},
    Map<AutomationTransport, DriverFactory>? factories,
  }) : _defaultEndpoint = defaultEndpoint,
       _defaultTransport = defaultTransport,
       _overrides = overrides,
       _extraFactories = factories;

  final Uri? _defaultEndpoint;
  final AutomationTransport _defaultTransport;
  final Map<String, String> _overrides;
  final Map<AutomationTransport, DriverFactory>? _extraFactories;
  final Map<String, Observation> _lastObservations = {};
  SessionRegistry? _registry;

  SessionRegistry get _sessions {
    final existing = _registry;
    if (existing != null) return existing;
    final registry = SessionRegistry(
      bindings: const {},
      overrides: _overrides,
      factories: _extraFactories,
    );
    _registry = registry;
    return registry;
  }

  /// Handles one decoded JSON-RPC message; returns the full response
  /// (`{id, result}` or `{id, error}`), or `null` for notifications.
  Future<Map<String, Object?>?> handle(Map<String, Object?> message) async {
    final id = message['id'];
    final method = message['method'];
    if (method is! String) {
      return id == null ? null : _error(id, -32600, 'method missing');
    }
    final isNotification = id == null;
    final params = message['params'];
    try {
      switch (method) {
        case 'initialize':
          return _result(id, await _initialize(params));
        case 'notifications/initialized':
        case 'notifications/cancelled':
          return null;
        case 'ping':
          return _result(id, <String, Object?>{});
        case 'tools/list':
          return _result(id, {'tools': toolDescriptors()});
        case 'tools/call':
          if (isNotification) return null;
          return _result(id, await _toolsCall(params));
        default:
          if (isNotification) return null;
          return _error(id, -32601, 'unknown method: $method');
      }
    } on McpToolError catch (error) {
      return isNotification
          ? null
          : _result(id, {
              'content': [
                {'type': 'text', 'text': error.message},
              ],
              'isError': true,
            });
    } on Object catch (error) {
      return isNotification
          ? null
          : _error(id, -32603, 'internal error: $error');
    }
  }

  Map<String, Object?> _initialize(Object? params) {
    final requested = params is Map<String, Object?>
        ? params['protocolVersion']
        : null;
    final version = mcpSupportedVersions.contains(requested)
        ? requested! as String
        : mcpSupportedVersions.last;
    return {
      'protocolVersion': version,
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': mcpServerInfo,
    };
  }

  Future<Map<String, Object?>> _toolsCall(Object? params) async {
    if (params is! Map<String, Object?>) {
      throw const McpToolError('tools/call params must be an object');
    }
    final name = params['name'];
    if (name is! String) throw const McpToolError('tools/call needs a name');
    final arguments =
        (params['arguments'] as Map<Object?, Object?>? ?? const {}).map(
      (key, value) => MapEntry('$key', value),
    );
    final Map<String, Object?> payload;
    try {
      payload = await switch (name) {
        'automation_observe' => _observe(arguments),
        'automation_act' => _act(arguments),
        'automation_verify' => _verify(arguments),
        'automation_screenshot' => _screenshot(arguments),
        'automation_validate_plan' => _validatePlan(arguments),
        'automation_run_plan' => _runPlan(arguments),
        _ => throw McpToolError('unknown tool: $name'),
      };
    } on FormatException catch (error) {
      throw McpToolError(error.message);
    } on AutomationException catch (error) {
      // Tool-level automation failures are results with isError, not
      // protocol errors (MCP contract).
      throw McpToolError('${error.kind}: ${error.message}');
    }
    // A screenshot with `image: true` rides as a second content block;
    // the reserved key never reaches the JSON text.
    final image = payload.remove('_imageContent');
    return {
      'content': [
        {'type': 'text', 'text': jsonEncode(payload)},
        if (image != null) image,
      ],
      'isError': false,
    };
  }

  /// Parses a per-call `transport` argument; `null` when absent, loud
  /// on an unknown name.
  static AutomationTransport? parseTransport(Object? value) {
    if (value == null) return null;
    final transport = switch ('$value') {
      'cdp' => AutomationTransport.cdp,
      'webdriver' => AutomationTransport.webdriver,
      'os' || 'osAccessibility' => AutomationTransport.osAccessibility,
      _ => null,
    };
    if (transport == null) {
      throw McpToolError(
        'unknown transport "$value" (cdp | webdriver | osAccessibility)',
      );
    }
    return transport;
  }

  Future<ResolvedSession> _session(Map<String, Object?> arguments) async {
    final transport =
        parseTransport(arguments['transport']) ?? _defaultTransport;
    final endpointValue = arguments['endpoint'];
    if (transport == AutomationTransport.osAccessibility &&
        endpointValue == null) {
      // The desktop tier binds the focused application; no URI.
      return _sessions.attachFocused(transport);
    }
    Uri? uri;
    if (endpointValue != null) {
      uri = Uri.tryParse('$endpointValue');
      if (uri == null || !uri.hasScheme) {
        throw McpToolError(
          'endpoint must be an absolute URI: $endpointValue',
        );
      }
    }
    uri ??= _defaultEndpoint;
    if (uri == null) {
      throw const McpToolError(
        'no endpoint: start serve with --cdp <uri> or --os (desktop '
        'tier), or pass "endpoint"/"transport" per call',
      );
    }
    return _sessions.attachUri(uri, transport);
  }

  Future<Map<String, Object?>> _observe(Map<String, Object?> arguments) async {
    final session = await _session(arguments);
    final snapshot = await session.driver.snapshot();
    final base = {
      'endpoint':
          '${session.binding.resolveUri(_overrides) ?? _defaultEndpoint}',
      'transport': session.binding.transport.name,
      'url': session.url?.toString(),
    };
    final viewValue = arguments['view'];
    final at = arguments['at'];
    if (viewValue == null && at is! Map<Object?, Object?>) {
      // No view, no grounding point: the raw tree (counts + full
      // snapshot JSON).
      return {...base, 'snapshot': snapshot.toJson()};
    }
    // A view asked: the rendered observation + ref index replace the
    // raw tree (token economy; omit `view` for the raw form). An `at`
    // point grounds to the innermost node covering it (ADR 0053).
    final observation = Observation.of(
      snapshot,
      viewValue == null ? const SemanticView() : SemanticView.fromJson(viewValue),
    );
    final key = session.binding.name;
    final previous = arguments['diff'] == true ? _lastObservations[key] : null;
    _lastObservations[key] = observation;
    return {
      ...base,
      'view': observation.toJson(),
      if (previous != null) 'delta': observation.diff(previous).render(),
      if (at is Map<Object?, Object?> &&
          at['x'] is num &&
          at['y'] is num)
        'at': _groundedAt(observation, (at['x']! as num).toDouble(),
            (at['y']! as num).toDouble()),
    };
  }

  /// The observe-at grounding read (ADR 0053): innermost walked node
  /// whose bounds contain the point; a miss fails the tool call.
  Map<String, Object?> _groundedAt(
    Observation observation,
    double x,
    double y,
  ) {
    final observed = observation.nodeAt(x, y);
    return {
      'ref': observed.ref,
      'role': observed.node.role,
      if (observed.node.name != null) 'name': observed.node.name,
      'x': x,
      'y': y,
    };
  }

  Future<Map<String, Object?>> _act(Map<String, Object?> arguments) async {
    final action = arguments['action'];
    if (action is! String) {
      throw const McpToolError('automation_act needs an action');
    }
    final actionBody = <String, Object?>{};
    switch (action) {
      case 'navigate':
        actionBody['navigate'] = {'url': arguments['url']};
      case 'click':
        actionBody['click'] = {
          if (arguments['css'] != null) 'css': arguments['css'],
          if (arguments['role'] != null) 'role': arguments['role'],
          if (arguments['name'] != null) 'name': arguments['name'],
        };
      case 'clickAt':
        actionBody['clickAt'] = {
          'x': arguments['x'],
          'y': arguments['y'],
          if (arguments['button'] != null) 'button': arguments['button'],
          if (arguments['clickCount'] != null)
            'clickCount': arguments['clickCount'],
          if (arguments['modifiers'] is List) 'modifiers': arguments['modifiers'],
        };
      case 'moveTo':
        actionBody['moveTo'] = {'x': arguments['x'], 'y': arguments['y']};
      case 'drag':
        actionBody['drag'] = {
          'fromX': arguments['fromX'],
          'fromY': arguments['fromY'],
          'toX': arguments['toX'],
          'toY': arguments['toY'],
          if (arguments['button'] != null) 'button': arguments['button'],
          if (arguments['modifiers'] is List) 'modifiers': arguments['modifiers'],
        };
      case 'type':
        actionBody['type'] = {
          'text': arguments['text'],
          if (arguments['css'] != null) 'css': arguments['css'],
          if (arguments['submit'] == true) 'submit': true,
        };
      case 'key':
        actionBody['key'] = {
          'key': arguments['key'],
          if (arguments['modifiers'] is List) 'modifiers': arguments['modifiers'],
        };
      case 'scroll':
        actionBody['scroll'] = {
          if (arguments['direction'] != null) 'direction': arguments['direction'],
          if (arguments['distance'] != null) 'distance': arguments['distance'],
        };
      case 'evaluate':
        actionBody['evaluate'] = arguments['expression'];
      case 'invoke':
        actionBody['invoke'] = {
          'name': arguments['name'],
          if (arguments['args'] is Map<Object?, Object?>)
            'args': arguments['args'],
        };
      default:
        throw McpToolError('unknown action: $action');
    }
    final automationAction = ActStep.actionFromJson(actionBody);
    final session = await _session(arguments);
    final profileName = arguments['profile'];
    Map<String, Object?> payload;
    if (profileName == null) {
      await session.driver.perform(automationAction);
      payload = {'ok': true, 'action': action};
    } else {
      final behavioral = session.asBehavioral();
    if (behavioral == null) {
      throw const McpToolError(
        'this transport cannot honor behavior profiles',
      );
    }
    final profile = profileName is String
        ? (profileName == 'humanPrior'
            ? BehaviorProfile.humanPrior(
                (arguments['seed'] as int?) ??
                    DateTime.now().microsecondsSinceEpoch,
              )
            : throw const McpToolError(
                "string profile must be 'humanPrior'; pass a canonical "
                'profile object for explicit facets',
              ))
        : BehaviorProfile.fromJson(
            (profileName as Map<Object?, Object?>).map(
              (key, value) => MapEntry('$key', value),
            ),
          );
    final seed = arguments['seed'] as int?;
    final outcome = await behavioral.performWith(
      automationAction,
      profile,
      seed: seed,
    );
    payload = {'ok': true, 'action': action, 'behavior': outcome.toJson()};
  }
  if (arguments['returnState'] == true) {
    // The act loop's closing read: post-action state through the
    // default view, in the same tool result.
    final observation = Observation.of(
      await session.driver.snapshot(),
      const SemanticView(maxNodes: 200),
    );
    payload = {...payload, 'state': observation.render()};
  }
  return payload;
}

  Future<Map<String, Object?>> _verify(Map<String, Object?> arguments) async {
    final rawChecks = arguments['checks'];
    if (rawChecks is! List<Object?> || rawChecks.isEmpty) {
      throw const McpToolError('automation_verify needs a checks list');
    }
    final checks = [
      for (final raw in rawChecks) VerifyCheck.fromJson(raw),
    ];
    final session = await _session(arguments);
    final snapshot = await session.driver.snapshot();
    final failures = [
      for (final check in checks)
        if (check.evaluate(snapshot, url: session.url) case final reason?)
          reason,
    ];
    return {
      'ok': failures.isEmpty,
      if (failures.isNotEmpty) 'failures': failures,
      'checks': checks.length,
    };
  }

  Future<Map<String, Object?>> _screenshot(
    Map<String, Object?> arguments,
  ) async {
    final session = await _session(arguments);
    final driver = session.driver;
    final maxPx = arguments['maxPx'] is int ? arguments['maxPx']! as int : 0;
    final imageBlocks = <Map<String, Object?>>[];

    if (arguments['listWindows'] == true) {
      if (driver is! MacosDriver) {
        throw const McpToolError(
          'listWindows needs the OS tier (transport "osAccessibility")',
        );
      }
      final pid = arguments['pid'] is int ? arguments['pid']! as int : 0;
      final windows = await driver.windows(pid: pid);
      return {
        'windows': [
          for (final window in windows)
            {
              'windowId': window.windowId,
              'pid': window.pid,
              'name': window.name,
              if (window.bounds != null)
                'bounds': {
                  'left': window.bounds!.left,
                  'top': window.bounds!.top,
                  'width': window.bounds!.width,
                  'height': window.bounds!.height,
                },
            },
        ],
      };
    }

    final path = arguments['path'];
    Uint8List bytes;
    if (arguments['windowId'] != null) {
      if (arguments['windowId'] is! int) {
        throw const McpToolError('windowId must be an integer');
      }
      if (driver is! MacosDriver) {
        throw const McpToolError(
          'windowId needs the OS tier (transport "osAccessibility")',
        );
      }
      if (path is! String || path.isEmpty) {
        throw const McpToolError('automation_screenshot needs a path');
      }
      bytes = await driver.windowScreenshot(
        arguments['windowId']! as int,
        maxPx: maxPx,
      );
    } else {
      if (path is! String || path.isEmpty) {
        throw const McpToolError('automation_screenshot needs a path');
      }
      if (!driver.capabilities.screenshot) {
        throw const McpToolError(
          'this transport cannot capture screenshots',
        );
      }
      if (maxPx > 0) {
        if (driver is! MacosDriver) {
          throw const McpToolError(
            'maxPx needs the OS tier; this transport cannot resize capture',
          );
        }
        bytes = await driver.screenshot(maxPx: maxPx);
      } else {
        bytes = await driver.screenshot();
      }
    }

    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    // Opt-in image block (ADR 0052: images are enrichment, not the
    // primary channel) — agents that render them read it from content,
    // everyone else ignores it.
    if (arguments['image'] == true) {
      imageBlocks.add({
        'type': 'image',
        'mimeType': 'image/png',
        'data': base64Encode(bytes),
      });
    }
    return {
      'ok': true,
      'path': file.path,
      'bytes': bytes.length,
      if (imageBlocks.isNotEmpty) '_imageContent': imageBlocks.single,
    };
  }

  Future<Map<String, Object?>> _validatePlan(
    Map<String, Object?> arguments,
  ) async {
    final path = _planPath(arguments);
    try {
      final plan = await AutomationPlan.load(path);
      return {'ok': true, 'plan': path, 'scenarios': plan.scenarios.keys.toList()};
    } on SpecViolationException catch (error) {
      return {'ok': false, 'plan': path, 'violations': error.violations};
    }
  }

  Future<Map<String, Object?>> _runPlan(Map<String, Object?> arguments)
      async {
    final path = _planPath(arguments);
    final plan = await AutomationPlan.load(path);
    final overrides = (arguments['set'] as Map<Object?, Object?>? ?? const {})
        .map((key, value) => MapEntry('$key', '$value'));
    final report = await PlanRunner().run(
      plan,
      scenarioName: arguments['scenario'] as String?,
      sessionOverrides: overrides,
      outDir: arguments['out'] as String?,
    );
    return report.toJson();
  }

  String _planPath(Map<String, Object?> arguments) {
    final path = arguments['plan'];
    if (path is! String || path.isEmpty) {
      throw const McpToolError('a plan file path is required');
    }
    return path;
  }

  /// The tool descriptors (name, description, JSON Schema input).
  static List<Map<String, Object?>> toolDescriptors() {
    final transportOverride = {
      'transport': {
        'type': 'string',
        'enum': ['cdp', 'webdriver', 'osAccessibility'],
        'description':
            'Overrides the serve transport for this call. '
            'osAccessibility is the desktop tier (macOS AX / Linux '
            'AT-SPI / Windows UIA): it binds the focused application '
            'and needs no endpoint.',
      },
      'endpoint': {
        'type': 'string',
        'description':
            'CDP/WebDriver HTTP base (e.g. http://127.0.0.1:9222); '
            'defaults to the serve --cdp endpoint',
      },
    };
    Map<String, Object?> tool(
      String name,
      String description,
      Map<String, Object?> inputSchema,
    ) => {
      'name': name,
      'description': description,
      'inputSchema': inputSchema,
    };
    return [
      tool(
        'automation_observe',
        'Capture a semantic (accessibility) snapshot of an automated '
        'surface. Read-only; the observe half of observe/act/verify. '
        'Over the desktop tier this is the focused application\'s tree. '
        'Pass `view` (identifierPrefix/subtreeOf/fields/maxNodes/panes) '
        'to get a rendered, ref-stable observation instead of the raw '
        'tree; pass `diff: true` to also get +/-/~ rows against the '
        'session\'s previous viewed observation.',
        {
          'type': 'object',
          'properties': {
            ...transportOverride,
            'at': {
              'type': 'object',
              'properties': {
                'x': {'type': 'number'},
                'y': {'type': 'number'},
              },
              'required': ['x', 'y'],
              'description':
                  'Ground this surface point to the innermost node '
                  'covering it (ADR 0053)',
            },
            'view': {
              'type': 'object',
              'description':
                  'SemanticView wire form: fields (role/name/value/'
                  'bounds), subtreeOf (a ref like s_3 or an identifier), '
                  'identifierPrefix, maxNodes, panes {name: view}.',
            },
            'diff': {
              'type': 'boolean',
              'description':
                  'With view: also return the delta against this '
                  "session's previous viewed observation.",
            },
          },
        },
      ),
      tool(
        'automation_act',
        'Perform one intent-level action: navigate | click | type | key '
        '| scroll | evaluate | invoke. Optional behavior profile '
        "('humanPrior' or a canonical profile object) dispatches with "
        'ADR 0044 input dynamics and reports the outcome (CDP only). '
        'returnState attaches the post-action state render — the '
        'act loop\'s closing read in one call.',
        {
          'type': 'object',
          'required': ['action'],
          'properties': {
            'action': {
              'type': 'string',
              'enum': [
                'navigate',
                'click',
                'clickAt',
                'moveTo',
                'drag',
                'type',
                'key',
                'scroll',
                'evaluate',
                'invoke',
              ],
            },
            'url': {'type': 'string'},
            'css': {'type': 'string'},
            'role': {'type': 'string'},
            'text': {'type': 'string'},
            'submit': {'type': 'boolean'},
            'key': {'type': 'string'},
            'direction': {
              'type': 'string',
              'enum': ['up', 'down', 'left', 'right'],
            },
            'distance': {'type': 'number'},
            'expression': {'type': 'string'},
            'x': {
              'type': 'number',
              'description': 'clickAt/moveTo: viewport X coordinate',
            },
            'y': {
              'type': 'number',
              'description': 'clickAt/moveTo: viewport Y coordinate',
            },
            'fromX': {'type': 'number', 'description': 'drag: press X'},
            'fromY': {'type': 'number', 'description': 'drag: press Y'},
            'toX': {'type': 'number', 'description': 'drag: release X'},
            'toY': {'type': 'number', 'description': 'drag: release Y'},
            'button': {
              'type': 'string',
              'enum': ['left', 'right', 'middle'],
              'description': 'pointer button for coordinate verbs',
            },
            'clickCount': {
              'type': 'integer',
              'description': 'clickAt: 2 = double-click, 3 = triple',
            },
            'modifiers': {
              'type': 'array',
              'items': {
                'type': 'string',
                'enum': ['shift', 'control', 'alt', 'meta'],
              },
              'description':
                  'Keyboard chord for clickAt/drag/key (ADR 0053)',
            },
            'name': {
              'type': 'string',
              'description':
                  'click accessible name, or catalog action name for invoke',
            },
            'args': {'type': 'object'},
            'returnState': {
              'type': 'boolean',
              'description':
                  'Return the post-action semantic state render with the '
                  'result.',
            },
            ...transportOverride,
            'profile': {
              'description': "'humanPrior' or a canonical BehaviorProfile object",
            },
            'seed': {'type': 'integer'},
          },
        },
      ),
      tool(
        'automation_verify',
        'Assert post-conditions against one fresh snapshot: checks are '
        '{exists: {role?, name?, nameContains?}} | {absent: {...}} | '
        '{value: {locator: {...}, equals?|contains?}} | {urlContains: s}.',
        {
          'type': 'object',
          'required': ['checks'],
          'properties': {
            'checks': {'type': 'array', 'items': {'type': 'object'}},
            ...transportOverride,
          },
        },
      ),
      tool(
        'automation_screenshot',
        'Capture one PNG frame to a local file path. `windowId` scopes '
        'the capture to one window (OS tier); `image` attaches the PNG '
        'as an opt-in image content block; `maxPx` caps the long side.',
        {
          'type': 'object',
          'required': ['path'],
          'properties': {
            'path': {'type': 'string'},
            'windowId': {
              'type': 'integer',
              'description': 'Capture this window instead of the display '
                  '(OS tier; discover ids via listWindows)',
            },
            'listWindows': {
              'type': 'boolean',
              'description': 'List capturable windows (OS tier) instead '
                  'of capturing',
            },
            'image': {
              'type': 'boolean',
              'description': 'Attach the PNG as an image content block '
                  '(opt-in; many agents prefer the semantic channel)',
            },
            'maxPx': {
              'type': 'integer',
              'description': 'Cap the long side in pixels (e.g. 1024)',
            },
            ...transportOverride,
          },
        },
      ),
      tool(
        'automation_validate_plan',
        'Validate a declarative plan document (.yaml/.yml/.json) '
        'fail-closed: every violation is reported, nothing attaches.',
        {
          'type': 'object',
          'required': ['plan'],
          'properties': {
            'plan': {'type': 'string'},
          },
        },
      ),
      tool(
        'automation_run_plan',
        'Run a scenario of a declarative plan: sessions attach lazily, '
        'steps run in order, the report is structured JSON with per-step '
        'status and behavior receipts.',
        {
          'type': 'object',
          'required': ['plan'],
          'properties': {
            'plan': {'type': 'string'},
            'scenario': {'type': 'string'},
            'out': {
              'type': 'string',
              'description': 'output directory for screenshots and receipts',
            },
            'set': {
              'type': 'object',
              'description':
                  'session handle overrides: {handleName: endpointUri}',
            },
          },
        },
      ),
    ];
  }

  static Map<String, Object?> _result(Object? id, Object? result) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': result,
  };

  static Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };
}

/// A tool-level failure surfaced as an MCP result with `isError: true`.
class McpToolError implements Exception {
  /// Creates the error.
  const McpToolError(this.message);

  /// Human-readable message.
  final String message;

  @override
  String toString() => message;
}

/// Runs the stdio loop: reads newline-delimited JSON-RPC from [stdin],
/// writes responses to [stdout]. Returns when stdin closes.
Future<void> serveMcpStdio({
  Uri? defaultEndpoint,
  AutomationTransport defaultTransport = AutomationTransport.cdp,
  Map<String, String> overrides = const {},
}) async {
  final server = ToolkitMcpServer(
    defaultEndpoint: defaultEndpoint,
    defaultTransport: defaultTransport,
    overrides: overrides,
  );
  final lines = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  await for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    Map<String, Object?> message;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, Object?>) {
        stdout.writeln(jsonEncode({
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32600, 'message': 'not a request object'},
        }));
        continue;
      }
      message = decoded;
    } on FormatException catch (error) {
      stdout.writeln(jsonEncode({
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32700, 'message': 'parse error: ${error.message}'},
      }));
      continue;
    }
    final response = await server.handle(message);
    if (response != null) {
      stdout.writeln(jsonEncode(response));
    }
    await stdout.flush();
  }
}

/// Binds a loopback HTTP server exposing the same toolkit as MCP over
/// HTTP: `POST /mcp` with one JSON-RPC message per request, one JSON
/// response per reply (the stateless shape of the MCP streamable-HTTP
/// transport; this server never sends server-initiated messages).
///
/// Loopback only. For remote clients (e.g. the ChatGPT connector, which
/// requires a public HTTPS origin) front it with a tunnel deliberately —
/// the surface can drive real UIs.
Future<HttpServer> startMcpHttp({
  required int port,
  Uri? defaultEndpoint,
  AutomationTransport defaultTransport = AutomationTransport.cdp,
  Map<String, String> overrides = const {},
}) async {
  final server = ToolkitMcpServer(
    defaultEndpoint: defaultEndpoint,
    defaultTransport: defaultTransport,
    overrides: overrides,
  );
  final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  httpServer.listen((request) => _handleHttpMessage(server, request));
  return httpServer;
}

Future<void> _handleHttpMessage(
  ToolkitMcpServer server,
  HttpRequest request,
) async {
  final respond = (int status, Object? body) async {
    request.response.statusCode = status;
    if (body != null) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
    }
    await request.response.close();
  };
  if (request.uri.path != '/mcp') {
    await respond(404, {
      'jsonrpc': '2.0',
      'id': null,
      'error': {'code': -32601, 'message': 'post to /mcp'},
    });
    return;
  }
  if (request.method != 'POST') {
    await respond(405, null);
    return;
  }
  final body = await utf8.decoder.bind(request).join();
  Map<String, Object?> message;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) throw const FormatException('not a request object');
    message = decoded;
  } on FormatException catch (error) {
    await respond(400, {
      'jsonrpc': '2.0',
      'id': null,
      'error': {'code': -32700, 'message': 'parse error: ${error.message}'},
    });
    return;
  }
  final response = await server.handle(message);
  if (response == null) {
    // A notification (or malformed notification): accepted, no body.
    await respond(202, null);
    return;
  }
  await respond(200, response);
}

import 'dart:convert';
import 'dart:io';

import 'package:universal_automation_interface/universal_automation_interface.dart';

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
  /// call carries no explicit endpoint.
  ToolkitMcpServer({Uri? defaultEndpoint, Map<String, String> overrides = const {}})
    : _defaultEndpoint = defaultEndpoint,
      _overrides = overrides;

  final Uri? _defaultEndpoint;
  final Map<String, String> _overrides;
  SessionRegistry? _registry;

  SessionRegistry get _sessions {
    final existing = _registry;
    if (existing != null) return existing;
    final endpoint = _defaultEndpoint;
    final registry = SessionRegistry(
      bindings: endpoint == null
          ? const {}
          : {
              'default': SessionBinding(
                name: 'default',
                transport: AutomationTransport.cdp,
                uri: endpoint,
              ),
            },
      overrides: _overrides,
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
    return {
      'content': [
        {'type': 'text', 'text': jsonEncode(payload)},
      ],
      'isError': false,
    };
  }

  Future<ResolvedSession> _session(Map<String, Object?> arguments) async {
    final endpointValue = arguments['endpoint'];
    if (endpointValue == null) {
      if (_defaultEndpoint == null) {
        throw const McpToolError(
          'no endpoint: start serve with --cdp <uri> or pass "endpoint"',
        );
      }
      return _sessions.attach('default');
    }
    final uri = Uri.tryParse('$endpointValue');
    if (uri == null || !uri.hasScheme) {
      throw McpToolError('endpoint must be an absolute URI: $endpointValue');
    }
    return _sessions.attachUri(uri, AutomationTransport.cdp);
  }

  Future<Map<String, Object?>> _observe(Map<String, Object?> arguments) async {
    final session = await _session(arguments);
    final snapshot = await session.driver.snapshot();
    return {
      'endpoint': '${session.binding.resolveUri(_overrides) ?? _defaultEndpoint}',
      'url': session.url?.toString(),
      'snapshot': snapshot.toJson(),
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
      case 'type':
        actionBody['type'] = {
          'text': arguments['text'],
          if (arguments['css'] != null) 'css': arguments['css'],
          if (arguments['submit'] == true) 'submit': true,
        };
      case 'key':
        actionBody['key'] = arguments['key'];
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
    if (profileName == null) {
      await session.driver.perform(automationAction);
      return {'ok': true, 'action': action};
    }
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
    return {'ok': true, 'action': action, 'behavior': outcome.toJson()};
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
    final path = arguments['path'];
    if (path is! String || path.isEmpty) {
      throw const McpToolError('automation_screenshot needs a path');
    }
    final session = await _session(arguments);
    if (!session.driver.capabilities.screenshot) {
      throw const McpToolError('this transport cannot capture screenshots');
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    final bytes = await session.driver.screenshot();
    await file.writeAsBytes(bytes, flush: true);
    return {'ok': true, 'path': file.path, 'bytes': bytes.length};
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
  static List<Map<String, Object?>> toolDescriptors() => [
    {
      'name': 'automation_observe',
      'description':
          'Capture a semantic (accessibility) snapshot of an automated '
          'surface. Read-only; the observe half of observe/act/verify.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'endpoint': {
            'type': 'string',
            'description':
                'CDP HTTP base (e.g. http://127.0.0.1:9222); defaults to '
                'the serve --cdp endpoint',
          },
        },
      },
    },
    {
      'name': 'automation_act',
      'description':
          'Perform one intent-level action: navigate | click | type | key '
          '| scroll | evaluate | invoke. Optional behavior profile '
          "('humanPrior' or a canonical profile object) dispatches with "
          'ADR 0044 input dynamics and reports the outcome.',
      'inputSchema': {
        'type': 'object',
        'required': ['action'],
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['navigate', 'click', 'type', 'key', 'scroll', 'evaluate', 'invoke'],
          },
          'url': {'type': 'string'},
          'css': {'type': 'string'},
          'role': {'type': 'string'},
          'text': {'type': 'string'},
          'submit': {'type': 'boolean'},
          'key': {'type': 'string'},
          'direction': {'type': 'string', 'enum': ['up', 'down', 'left', 'right']},
          'distance': {'type': 'number'},
          'expression': {'type': 'string'},
          'name': {'type': 'string', 'description': 'click accessible name, or catalog action name for invoke'},
          'args': {'type': 'object'},
          'endpoint': {'type': 'string'},
          'profile': {
            'description': "'humanPrior' or a canonical BehaviorProfile object",
          },
          'seed': {'type': 'integer'},
        },
      },
    },
    {
      'name': 'automation_verify',
      'description':
          'Assert post-conditions against one fresh snapshot: checks are '
          '{exists: {role?, name?, nameContains?}} | {absent: {...}} | '
          '{value: {locator: {...}, equals?|contains?}} | {urlContains: s}.',
      'inputSchema': {
        'type': 'object',
        'required': ['checks'],
        'properties': {
          'checks': {'type': 'array', 'items': {'type': 'object'}},
          'endpoint': {'type': 'string'},
        },
      },
    },
    {
      'name': 'automation_screenshot',
      'description': 'Capture one PNG frame to a local file path.',
      'inputSchema': {
        'type': 'object',
        'required': ['path'],
        'properties': {
          'path': {'type': 'string'},
          'endpoint': {'type': 'string'},
        },
      },
    },
    {
      'name': 'automation_validate_plan',
      'description':
          'Validate a declarative plan document (.yaml/.yml/.json) '
          'fail-closed: every violation is reported, nothing attaches.',
      'inputSchema': {
        'type': 'object',
        'required': ['plan'],
        'properties': {
          'plan': {'type': 'string'},
        },
      },
    },
    {
      'name': 'automation_run_plan',
      'description':
          'Run a scenario of a declarative plan: sessions attach lazily, '
          'steps run in order, the report is structured JSON with per-step '
          'status and behavior receipts.',
      'inputSchema': {
        'type': 'object',
        'required': ['plan'],
        'properties': {
          'plan': {'type': 'string'},
          'scenario': {'type': 'string'},
          'out': {'type': 'string', 'description': 'output directory for screenshots and receipts'},
          'set': {
            'type': 'object',
            'description': 'session handle overrides: {handleName: endpointUri}',
          },
        },
      },
    },
  ];

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
  Map<String, String> overrides = const {},
}) async {
  final server = ToolkitMcpServer(
    defaultEndpoint: defaultEndpoint,
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

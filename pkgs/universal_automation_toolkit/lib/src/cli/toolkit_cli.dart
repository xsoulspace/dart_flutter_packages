import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_semantics/universal_automation_semantics.dart';
import 'package:universal_driver_macos/universal_driver_macos.dart';

import '../mcp/mcp_server.dart' as mcp;
import '../plan/checks.dart';
import '../plan/plan.dart';
import '../runner/registry.dart';
import '../runner/runner.dart';

/// Exit code: every executed step passed.
const exitOk = 0;

/// Exit code: an automation step failed (or the report says not-ok).
const exitFailure = 1;

/// Exit code: usage or input error.
const exitUsage = 2;

/// Runs the `universal-automation` CLI; returns the process exit code.
Future<int> runToolkitCli(List<String> arguments) async {
  late final int code;
  try {
    code = await _dispatch(arguments);
  } on UsageException catch (error) {
    stderr.writeln('usage: ${error.message}');
    code = exitUsage;
  } on SpecViolationException catch (error) {
    stderr.writeln(jsonEncode({
      'ok': false,
      'violations': error.violations,
    }));
    code = exitFailure;
  } on AutomationException catch (error) {
    stderr.writeln(jsonEncode({'ok': false, 'error': error.kind, 'message': error.message}));
    code = exitFailure;
  }
  return code;
}

/// A CLI usage failure.
class UsageException implements Exception {
  /// Creates the exception.
  const UsageException(this.message);

  /// What to print.
  final String message;

  @override
  String toString() => message;
}

Uri? _parseCdp(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme) {
    throw UsageException('--cdp must be an absolute URI (got $value)');
  }
  return uri;
}

Uri? _parseEndpoint(String? value, String flag) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme) {
    throw UsageException('$flag must be an absolute URI (got $value)');
  }
  return uri;
}

/// The resolved default face of a serve command: which transport ad-hoc
/// calls attach to, and over which endpoint (null for the endpoint-free
/// desktop tier).
typedef DefaultSurface = (AutomationTransport, Uri?);

DefaultSurface _defaultSurface(ArgResults options) {
  final cdp = _parseCdp(options['cdp'] as String?);
  final webdriver = _parseEndpoint(
    options['webdriver'] as String?,
    '--webdriver',
  );
  final os = options['os'] == true;
  final chosen = [
    if (cdp != null) '--cdp',
    if (webdriver != null) '--webdriver',
    if (os) '--os',
  ];
  if (chosen.length > 1) {
    throw UsageException('${chosen.join(' and ')} are mutually exclusive');
  }
  if (os) return (AutomationTransport.osAccessibility, null);
  if (webdriver != null) return (AutomationTransport.webdriver, webdriver);
  return (AutomationTransport.cdp, cdp);
}

Future<ResolvedSession> _attachAdHoc(ArgResults options) async {
  final (transport, endpoint) = _defaultSurface(options);
  if (endpoint == null) {
    if (transport == AutomationTransport.osAccessibility) {
      final registry = SessionRegistry(bindings: const {});
      return _DetachingSession(
        await registry.attachFocused(transport),
        registry,
      );
    }
    throw const UsageException(
      'choose a transport: --cdp <http-base>, --webdriver <http-base>, '
      'or --os (the desktop accessibility tier of this host)',
    );
  }
  final registry = SessionRegistry(bindings: const {});
  return _DetachingSession(
    await registry.attachUri(endpoint, transport),
    registry,
  );
}

final class _DetachingSession implements ResolvedSession {
  _DetachingSession(this._inner, this._registry);

  final ResolvedSession _inner;
  final SessionRegistry _registry;

  @override
  SessionBinding get binding => _inner.binding;

  @override
  AutomationDriver get driver => _inner.driver;

  @override
  Uri? get url => _inner.url;

  @override
  BehavioralDriver? asBehavioral() => _inner.asBehavioral();

  @override
  Future<void> detach() => _registry.detachAll();
}

String? _named(String? value, String field) {
  if (value == null) return null;
  if (value.isEmpty) throw UsageException('--$field must not be empty');
  return value;
}

Future<int> _dispatch(List<String> arguments) async {
  final parser = ArgParser(allowTrailingOptions: true)
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
    ..addOption('cdp', help: 'CDP HTTP base (e.g. http://127.0.0.1:9222).')
    ..addOption(
      'webdriver',
      help: 'WebDriver (grid) HTTP base; mutually exclusive with --cdp/--os.',
    )
    ..addFlag(
      'os',
      negatable: false,
      help:
          'Drive the desktop accessibility tier of this host (macOS AX '
          'focused app / Linux AT-SPI / Windows UIA); endpoint-free.',
    )
    ..addOption('timeout', help: 'Attach timeout seconds.', defaultsTo: '10')
    ..addFlag('pretty', negatable: false, help: 'Pretty-print JSON output.');
  parser.addCommand('observe')
    ..addOption('out', help: 'Write the snapshot JSON to a file too.')
    ..addOption(
      'view-subtree',
      help: 'SemanticView subtreeOf: a ref (s_N) or an identifier (ADR 0052).',
    )
    ..addOption('view-prefix', help: 'SemanticView identifierPrefix.')
    ..addOption(
      'view-fields',
      help: 'Comma-separated rendered fields among role,name,value,bounds.',
    )
    ..addOption(
      'at',
      help: 'Ground this x,y point to the innermost node covering it '
          '(ADR 0053).',
    )
    ..addOption(
      'view-max',
      help: 'Cap on shown nodes; the render admits trimming.',
    );
  parser.addCommand('act')
    ..addOption('navigate', help: 'Navigate to this URL.')
    ..addOption('click-name', help: 'Click by accessible name.')
    ..addOption('click-css', help: 'Click by CSS selector.')
    ..addOption('click-role', help: 'Click by semantic role (with a name).')
    ..addOption(
      'click-at',
      help: 'Click at viewport coordinates: x,y (ADR 0053; CDP tier).',
    )
    ..addOption(
      'move-to',
      help: 'Move the pointer to x,y without pressing.',
    )
    ..addOption(
      'drag',
      help: 'Drag from x1,y1 to x2,y2 (ADR 0053; CDP tier).',
    )
    ..addOption(
      'button',
      help: 'Pointer button for coordinate verbs: left (default), right, '
          'middle.',
    )
    ..addOption(
      'click-count',
      help: 'click-at repeats: 2 = double-click, 3 = triple.',
    )
    ..addMultiOption(
      'modifier',
      help: 'Keyboard modifier chord for click-at/drag/key: '
          'shift/control/alt/meta (repeatable).',
    )
    ..addOption('type-text', help: 'Type this text (caret or --type-css).')
    ..addOption('type-css', help: 'CSS selector to focus before typing.')
    ..addFlag('submit', negatable: false, help: 'Press Enter after typing.')
    ..addOption('key', help: 'Press this named key.')
    ..addOption('scroll', help: 'Scroll direction (down/up/left/right).')
    ..addOption('distance', help: 'Scroll distance in logical pixels.')
    ..addOption('evaluate', help: 'Evaluate this read-only expression.')
    ..addOption('invoke', help: 'Invoke this catalog action name.')
    ..addMultiOption('arg', help: 'k=v argument for invoke (repeatable).')
    ..addFlag(
      'return-state',
      negatable: false,
      help: 'Print the post-action state render (ADR 0052) with the result.',
    )
    ..addOption('profile', help: "'humanPrior' or a profile JSON file path.")
    ..addOption('seed', help: 'Deterministic synthesis seed.');
  parser.addCommand('verify')
    ..addMultiOption('exists', help: 'role=,name=,nameContains= (repeatable).')
    ..addMultiOption('absent', help: 'role=,name=,nameContains= (repeatable).')
    ..addMultiOption('value', help: 'locator + equals=/contains= (repeatable).')
    ..addOption('url-contains', help: 'The surface URL must contain this.');
  parser.addCommand('screenshot')
    ..addOption('out', mandatory: true, help: 'PNG destination path.')
    ..addFlag(
      'list-windows',
      negatable: false,
      help: 'List capturable windows (OS tier) instead of capturing.',
    )
    ..addOption(
      'window-id',
      help: 'Capture this window (OS tier) instead of the display.',
    )
    ..addOption(
      'max-px',
      help: 'Cap the long side in pixels (e.g. 1024; OS tier).',
    );
  parser.addCommand('validate')
    ..addOption('plan', mandatory: true, help: 'Plan document path.');
  parser.addCommand('run')
    ..addOption('plan', mandatory: true, help: 'Plan document path.')
    ..addOption('scenario', help: 'Scenario to run (default: the only one).')
    ..addOption('out', help: 'Output directory (screenshots, receipts).')
    ..addMultiOption('set', help: 'handle=uri session override (repeatable).')
    ..addOption(
      'handles-dir',
      help: 'Directory of session-<name>-handle artifacts (endpoint URIs).',
    );
  parser.addCommand('actions');
  parser.addCommand('serve')
    ..addOption(
      'http',
      help:
          'Serve MCP over loopback HTTP (POST /mcp) on this port instead '
          'of stdio; the connector URL is http://127.0.0.1:<port>/mcp.',
    );

  if (arguments.isEmpty || arguments.contains('--help') ||
      arguments.contains('-h')) {
    stderr.writeln(parser.usage);
    return exitUsage;
  }
  ArgResults options;
  try {
    options = parser.parse(arguments);
  } on ArgParserException catch (error) {
    throw UsageException(error.message);
  }
  final command = options.command;
  if (command == null) {
    throw const UsageException('a command is required (observe, act, '
        'verify, screenshot, validate, run, serve)');
  }
  final pretty = options['pretty'] == true;
  final output = (Object? payload) {
    final json = pretty
        ? const JsonEncoder.withIndent('  ').convert(payload)
        : jsonEncode(payload);
    stdout.writeln(json);
  };

  switch (command.name) {
    case 'serve':
      final (defaultTransport, defaultEndpoint) = _defaultSurface(options);
      final httpPort = command['http'] as String?;
      if (httpPort != null) {
        final port = int.tryParse(httpPort);
        if (port == null || port < 0 || port > 65535) {
          throw UsageException('--http must be a TCP port (got $httpPort)');
        }
        final httpServer = await mcp.startMcpHttp(
          port: port,
          defaultEndpoint: defaultEndpoint,
          defaultTransport: defaultTransport,
        );
        stderr.writeln(
          jsonEncode({
            'ok': true,
            'transport': 'http',
            'url': 'http://127.0.0.1:${httpServer.port}/mcp',
          }),
        );
        // Serve until the client terminates the process.
        await Completer<void>().future;
      }
      await mcp.serveMcpStdio(
        defaultEndpoint: defaultEndpoint,
        defaultTransport: defaultTransport,
      );
      return exitOk;
    case 'validate':
      final plan = await AutomationPlan.load(command['plan'] as String);
      output({
        'ok': true,
        'scenarios': plan.scenarios.keys.toList(),
        'sessions': plan.sessions.keys.toList(),
      });
      return exitOk;
    case 'run':
      final plan = await AutomationPlan.load(command['plan'] as String);
      final overrides = {
        for (final entry in command['set'] as List<String>)
          if (entry.contains('=')) entry.split('=')[0]: entry.split('=')[1],
      };
      final report = await PlanRunner(
        attachTimeout: Duration(
          seconds: int.tryParse(options['timeout'] as String) ?? 10,
        ),
        handleBaseDirectory: command['handles-dir'] as String?,
      ).run(
        plan,
        scenarioName: command['scenario'] as String?,
        sessionOverrides: overrides,
        outDir: command['out'] as String?,
      );
      output(report.toJson());
      return report.ok ? exitOk : exitFailure;
    case 'observe':
      final session = await _attachAdHoc(options);
      try {
        final snapshot = await session.driver.snapshot();
        final view = _viewFromArgs(command);
        final atRaw = command['at'] as String?;
        (double, double)? at;
        if (atRaw != null) {
          at = (
            _coordPart(atRaw, 0, '--at'),
            _coordPart(atRaw, 1, '--at'),
          );
        }
        final out = command['out'] as String?;
        if (out != null) {
          final file = File(out);
          await file.parent.create(recursive: true);
          await file.writeAsString(jsonEncode(snapshot.toJson()));
        }
        if (view != null || at != null) {
          // A view asked: the rendered observation + ref index (the
          // raw tree rides `--out` when given). A grounding point
          // resolves against the same full walk.
          final observation = Observation.of(snapshot, view ?? const SemanticView());
          output({
            'observation': observation.toJson(),
            if (at case (final x, final y))
              'at': {
                'ref': observation.nodeAt(x, y).ref,
                'role': observation.nodeAt(x, y).node.role,
                if (observation.nodeAt(x, y).node.name != null)
                  'name': observation.nodeAt(x, y).node.name,
                'x': x,
                'y': y,
              },
          });
        } else {
          output(snapshot.toJson());
        }
        return exitOk;
      } finally {
        await session.detach();
      }
    case 'actions':
      final session = await _attachAdHoc(options);
      try {
        // AutomationActionCatalog is not an AutomationDriver subtype, so
        // an is-check cannot promote: cast explicitly.
        final driver = session.driver;
        final catalog = driver is AutomationActionCatalog
            ? driver as AutomationActionCatalog
            : throw const DriverUnsupportedException(
                'this driver does not advertise a surface-action catalog',
              );
        output({
          'actions': [
            for (final action in await catalog.actions()) action.toJson(),
          ],
        });
        return exitOk;
      } finally {
        await session.detach();
      }
    case 'screenshot':
      final session = await _attachAdHoc(options);
      try {
        final driver = session.driver;
        // An is-check cannot promote through the ResolvedSession seam:
        // cast explicitly (the catalog gotcha).
        final macos = driver is MacosDriver ? driver : null;
        final listWindows = command['list-windows'] == true;
        final windowId = command['window-id'] as String?;
        final maxPx = int.tryParse(command['max-px'] as String? ?? '') ?? 0;
        if (listWindows || windowId != null || maxPx > 0) {
          // Window discovery, window capture, and resizing are the
          // native tier's surface; plain display capture is not.
          if (macos == null) {
            throw const UsageException(
              'window capture needs the OS tier (--os)',
            );
          }
        }
        if (listWindows) {
          final windows = await macos!.windows();
          output([
            for (final window in windows)
              {
                'windowId': window.windowId,
                'pid': window.pid,
                'name': window.name,
              },
          ]);
          return exitOk;
        }
        final bytes = windowId != null
            ? await macos!.windowScreenshot(int.parse(windowId), maxPx: maxPx)
            : maxPx > 0
            ? await macos!.screenshot(maxPx: maxPx)
            : await driver.screenshot();
        final file = File(command['out'] as String);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
        output({'ok': true, 'path': file.path, 'bytes': bytes.length});
        return exitOk;
      } finally {
        await session.detach();
      }
    case 'verify':
      final checks = _checksFromArgs(
        exists: command['exists'] as List<String>,
        absent: command['absent'] as List<String>,
        values: command['value'] as List<String>,
        urlContains: command['url-contains'] as String?,
      );
      if (checks.isEmpty) {
        throw const UsageException('verify needs at least one check');
      }
      final session = await _attachAdHoc(options);
      try {
        final snapshot = await session.driver.snapshot();
        final failures = [
          for (final check in checks)
            if (check.evaluate(snapshot, url: session.url) case final reason?)
              reason,
        ];
        output({
          'ok': failures.isEmpty,
          if (failures.isNotEmpty) 'failures': failures,
        });
        return failures.isEmpty ? exitOk : exitFailure;
      } finally {
        await session.detach();
      }
    case 'act':
      final action = _actionFromArgs(command);
      final wantState = command['return-state'] == true;
      final session = await _attachAdHoc(options);
      try {
        Future<Map<String, Object?>> statePayload() async => wantState
            ? {
                // The act loop's closing read (ADR 0052): post-action
                // state through the default view.
                'state': Observation.of(
                  await session.driver.snapshot(),
                  const SemanticView(maxNodes: 200),
                ).render(),
              }
            : const {};
        final profileName = command['profile'] as String?;
        if (profileName == null) {
          await session.driver.perform(action);
          output({'ok': true, ...await statePayload()});
          return exitOk;
        }
        final behavioral = session.asBehavioral();
        if (behavioral == null) {
          throw const DriverUnsupportedException(
            'this transport cannot honor behavior profiles',
          );
        }
        final profile = profileName == 'humanPrior'
            ? BehaviorProfile.humanPrior(
                int.tryParse(command['seed'] as String? ?? '') ??
                    DateTime.now().microsecondsSinceEpoch,
              )
            : BehaviorProfile.fromJson(
                (jsonDecode(File(profileName).readAsStringSync())
                        as Map<Object?, Object?>)
                    .map((key, value) => MapEntry('$key', value)),
              );
        final outcome = await behavioral.performWith(
          action,
          profile,
          seed: int.tryParse(command['seed'] as String? ?? ''),
        );
        output({
          'ok': true,
          'behavior': outcome.toJson(),
          ...await statePayload(),
        });
        return exitOk;
      } finally {
        await session.detach();
      }
    default:
      throw UsageException('unknown command ${command.name}');
  }
}

/// The `--view-*` flags as a [SemanticView]; `null` when none given.
SemanticView? _viewFromArgs(ArgResults command) {
  final subtree = command['view-subtree'] as String?;
  final prefix = command['view-prefix'] as String?;
  final fieldsRaw = command['view-fields'] as String?;
  final maxRaw = command['view-max'] as String?;
  if (subtree == null && prefix == null && fieldsRaw == null && maxRaw == null) {
    return null;
  }
  final max = maxRaw == null ? null : int.tryParse(maxRaw);
  if (maxRaw != null && max == null) {
    throw UsageException('--view-max must be an integer (got $maxRaw)');
  }
  return SemanticView(
    subtreeOf: subtree,
    identifierPrefix: prefix,
    fields: fieldsRaw == null
        ? SemanticView.defaultFields
        : {
            for (final name in fieldsRaw.split(','))
              SemanticField.parse(name.trim()),
          },
    maxNodes: max,
  );
}

double _coordPart(String spec, int index, String flag) {
  final parts = spec.split(',');
  if (parts.length <= index) {
    throw UsageException('$flag needs comma-separated coordinates (got $spec)');
  }
  final value = double.tryParse(parts[index].trim());
  if (value == null) {
    throw UsageException('$flag coordinates must be numbers (got $spec)');
  }
  return value;
}

String _buttonOption(ArgResults command) {
  final button = command['button'] as String?;
  if (button == null) return 'left';
  if (const {'left', 'right', 'middle'}.contains(button) == false) {
    throw UsageException(
      '--button must be left, right, or middle (got $button)',
    );
  }
  return button;
}

/// The chord modifier list for coordinate/key verbs; unknown names
/// fail closed here (usage error) before any transport sees them.
List<String> _modifierOption(ArgResults command) {
  final raw = command['modifier'] as List<Object?>? ?? const [];
  try {
    return parseModifiers(raw);
  } on FormatException catch (error) {
    throw UsageException(error.message);
  }
}

AutomationAction _actionFromArgs(ArgResults command) {
  final navigate = command['navigate'] as String?;
  if (navigate != null) {
    final uri = Uri.tryParse(navigate);
    if (uri == null || !uri.hasScheme) {
      throw UsageException('--navigate must be an absolute URI');
    }
    return NavigateAction(uri);
  }
  final clickName = _named(command['click-name'] as String?, 'click-name');
  final clickCss = command['click-css'] as String?;
  final clickRole = command['click-role'] as String?;
  if (clickName != null || clickCss != null || clickRole != null) {
    return ClickAction(css: clickCss, role: clickRole, name: clickName);
  }
  final modifiers = _modifierOption(command);
  final clickAt = command['click-at'] as String?;
  if (clickAt != null) {
    return ClickAtAction(
      _coordPart(clickAt, 0, '--click-at'),
      _coordPart(clickAt, 1, '--click-at'),
      button: _buttonOption(command),
      clickCount: int.tryParse(command['click-count'] as String? ?? '') ?? 1,
      modifiers: modifiers,
    );
  }
  final moveTo = command['move-to'] as String?;
  if (moveTo != null) {
    return MoveAction(_coordPart(moveTo, 0, '--move-to'), _coordPart(moveTo, 1, '--move-to'));
  }
  final drag = command['drag'] as String?;
  if (drag != null) {
    final parts = drag.split(',');
    if (parts.length != 4) {
      throw const UsageException('--drag needs x1,y1,x2,y2');
    }
    return DragAction(
      _coordPart(drag, 0, '--drag'),
      _coordPart(drag, 1, '--drag'),
      _coordPart(drag, 2, '--drag'),
      _coordPart(drag, 3, '--drag'),
      button: _buttonOption(command),
      modifiers: modifiers,
    );
  }
  final typeText = command['type-text'] as String?;
  if (typeText != null) {
    return TypeAction(
      typeText,
      css: command['type-css'] as String?,
      submit: command['submit'] == true,
    );
  }
  final key = command['key'] as String?;
  if (key != null) {
    return KeyPressAction(key, modifiers: _modifierOption(command));
  }
  final scroll = command['scroll'] as String?;
  if (scroll != null) {
    return ScrollAction(
      direction: scroll,
      distance: double.tryParse(command['distance'] as String? ?? ''),
    );
  }
  final evaluate = command['evaluate'] as String?;
  if (evaluate != null) return EvaluateAction(evaluate);
  final invoke = command['invoke'] as String?;
  if (invoke != null) {
    return InvokeAction(invoke, args: {
      for (final pair in command['arg'] as List<String>)
        if (pair.contains('=')) pair.split('=')[0]: pair.split('=')[1],
    });
  }
  throw const UsageException(
    'act needs one of --navigate, --click-name, --click-css, --click-role, '
    '--click-at, --move-to, --drag, --type-text, --key, --scroll, '
    '--evaluate, --invoke',
  );
}

List<VerifyCheck> _checksFromArgs({
  required List<String> exists,
  required List<String> absent,
  required List<String> values,
  required String? urlContains,
}) {
  CheckLocator locator(String spec) {
    final parts = {
      for (final pair in spec.split(','))
        if (pair.contains('=')) pair.split('=')[0]: pair.split('=')[1],
    };
    return CheckLocator(
      role: parts['role'],
      name: parts['name'],
      nameContains: parts['nameContains'],
    );
  }

  return [
    for (final spec in exists) ExistsCheck(locator: locator(spec)),
    for (final spec in absent) AbsentCheck(locator: locator(spec)),
    for (final spec in values)
      () {
        final parts = {
          for (final pair in spec.split(','))
            if (pair.contains('=')) pair.split('=')[0]: pair.split('=')[1],
        };
        final locatorSpec = [
          if (parts.containsKey('role')) 'role=${parts['role']}',
          if (parts.containsKey('name')) 'name=${parts['name']}',
          if (parts.containsKey('nameContains'))
            'nameContains=${parts['nameContains']}',
        ].join(',');
        return ValueCheck(
          locator: locator(locatorSpec),
          equals: parts['equals'],
          contains: parts['contains'],
        );
      }(),
    if (urlContains != null) UrlContainsCheck(urlContains),
  ];
}

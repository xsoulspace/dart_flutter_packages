import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

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

Future<ResolvedSession> _attachCdp(ArgResults options) async {
  final endpoint = _parseCdp(options['cdp'] as String?);
  if (endpoint == null) {
    throw const UsageException('--cdp <http-base> is required');
  }
  final registry = SessionRegistry(bindings: const {});
  final session = await registry.attachUri(endpoint, AutomationTransport.cdp);
  // Detach is the caller's job; ad-hoc verbs are one-shot, so detach
  // after the single operation via the registry wrapper.
  return _DetachingSession(session, registry);
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
    ..addOption('timeout', help: 'Attach timeout seconds.', defaultsTo: '10')
    ..addFlag('pretty', negatable: false, help: 'Pretty-print JSON output.');
  parser.addCommand('observe')
    ..addOption('out', help: 'Write the snapshot JSON to a file too.');
  parser.addCommand('act')
    ..addOption('navigate', help: 'Navigate to this URL.')
    ..addOption('click-name', help: 'Click by accessible name.')
    ..addOption('click-css', help: 'Click by CSS selector.')
    ..addOption('click-role', help: 'Click by semantic role (with a name).')
    ..addOption('type-text', help: 'Type this text (caret or --type-css).')
    ..addOption('type-css', help: 'CSS selector to focus before typing.')
    ..addFlag('submit', negatable: false, help: 'Press Enter after typing.')
    ..addOption('key', help: 'Press this named key.')
    ..addOption('scroll', help: 'Scroll direction (down/up/left/right).')
    ..addOption('distance', help: 'Scroll distance in logical pixels.')
    ..addOption('evaluate', help: 'Evaluate this read-only expression.')
    ..addOption('invoke', help: 'Invoke this catalog action name.')
    ..addMultiOption('arg', help: 'k=v argument for invoke (repeatable).')
    ..addOption('profile', help: "'humanPrior' or a profile JSON file path.")
    ..addOption('seed', help: 'Deterministic synthesis seed.');
  parser.addCommand('verify')
    ..addMultiOption('exists', help: 'role=,name=,nameContains= (repeatable).')
    ..addMultiOption('absent', help: 'role=,name=,nameContains= (repeatable).')
    ..addMultiOption('value', help: 'locator + equals=/contains= (repeatable).')
    ..addOption('url-contains', help: 'The surface URL must contain this.');
  parser.addCommand('screenshot')
    ..addOption('out', mandatory: true, help: 'PNG destination path.');
  parser.addCommand('validate')
    ..addOption('plan', mandatory: true, help: 'Plan document path.');
  parser.addCommand('run')
    ..addOption('plan', mandatory: true, help: 'Plan document path.')
    ..addOption('scenario', help: 'Scenario to run (default: the only one).')
    ..addOption('out', help: 'Output directory (screenshots, receipts).')
    ..addMultiOption('set', help: 'handle=uri session override (repeatable).');
  parser.addCommand('serve');

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
      await mcp.serveMcpStdio(
        defaultEndpoint: _parseCdp(options['cdp'] as String?),
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
      ).run(
        plan,
        scenarioName: command['scenario'] as String?,
        sessionOverrides: overrides,
        outDir: command['out'] as String?,
      );
      output(report.toJson());
      return report.ok ? exitOk : exitFailure;
    case 'observe':
      final session = await _attachCdp(options);
      try {
        final snapshot = await session.driver.snapshot();
        final json = jsonEncode(snapshot.toJson());
        final out = command['out'] as String?;
        if (out != null) {
          final file = File(out);
          await file.parent.create(recursive: true);
          await file.writeAsString(json);
        }
        output(snapshot.toJson());
        return exitOk;
      } finally {
        await session.detach();
      }
    case 'screenshot':
      final session = await _attachCdp(options);
      try {
        final bytes = await session.driver.screenshot();
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
      final session = await _attachCdp(options);
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
      final session = await _attachCdp(options);
      try {
        final profileName = command['profile'] as String?;
        if (profileName == null) {
          await session.driver.perform(action);
          output({'ok': true});
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
        output({'ok': true, 'behavior': outcome.toJson()});
        return exitOk;
      } finally {
        await session.detach();
      }
    default:
      throw UsageException('unknown command ${command.name}');
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
  final typeText = command['type-text'] as String?;
  if (typeText != null) {
    return TypeAction(
      typeText,
      css: command['type-css'] as String?,
      submit: command['submit'] == true,
    );
  }
  final key = command['key'] as String?;
  if (key != null) return KeyPressAction(key);
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
    '--type-text, --key, --scroll, --evaluate, --invoke',
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

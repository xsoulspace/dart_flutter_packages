import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_semantics/universal_automation_semantics.dart';

import 'checks.dart';

/// Base of one declarative scenario step.
///
/// Steps are data: parsed from the plan document, validated before the
/// run, executed in order by the runner. [session] names a session
/// binding; when `null` the runner uses the plan's only session (plans
/// with several sessions must name the session on every step — the plan
/// validator enforces that).
sealed class PlanStep {
  /// Creates a step.
  const PlanStep({this.session, this.continueOnFailure = false});

  /// Restores one step from its plan shape (the decoded YAML/JSON map of
  /// one list entry).
  factory PlanStep.fromJson(Object? json) {
    if (json is! Map<Object?, Object?>) {
      throw const FormatException('a step must be a map');
    }
    // Common keys may ride inside the step body (`- act: {click: {...},
    // session: b}`) — promote them to the step level before reading.
    final kindKeysProbe = json.keys.where((key) => const {
      'observe',
      'act',
      'verify',
      'wait',
      'screenshot',
      'intent',
      'scope',
    }.contains(key)).toList();
    if (kindKeysProbe.length == 1) {
      final probed = json[kindKeysProbe.single];
      if (probed is Map<Object?, Object?>) {
        for (final key in const [
          'session',
          'profile',
          'seed',
          'continueOnFailure',
        ]) {
          if (probed.containsKey(key) && !json.containsKey(key)) {
            json[key] = probed[key];
          }
        }
      }
    }
    final session = _optionalString(json['session'], 'session');
    final continueOnFailure = json['continueOnFailure'] == true;
    if (json.keys.contains('code')) {
      throw const FormatException(
        '"code" steps are Dart-only: they cannot be expressed in a plan '
        'document (snapshot); compose them in Dart or export a snapshot '
        'without them',
      );
    }
    final kindKeys = json.keys
        .where((key) => const {
          'observe',
          'act',
          'verify',
          'wait',
          'screenshot',
          'intent',
          'record',
          'scope',
        }.contains(key))
        .toList();
    if (kindKeys.length > 1) {
      throw FormatException(
        'a step must carry exactly one of '
        'observe/act/verify/wait/screenshot/intent '
        '(got ${json.keys.join(', ')})',
      );
    }
    if (kindKeys.isEmpty) {
      // Ergonomic shorthand: a lone action verb is an act step
      // (`- navigate: {url: ...}` ≡ `- act: {navigate: {url: ...}}`).
      final actionKey = json.keys
          .where((key) => const {
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
          }.contains(key))
          .toList();
      if (actionKey.length == 1) {
        return ActStep._(
          body: {actionKey.single: json[actionKey.single]},
          json: json,
        ).withCommon(session: session, continueOnFailure: continueOnFailure);
      }
      throw FormatException(
        'a step must carry exactly one of observe/act/verify/wait/screenshot/'
        'intent/scope or one action verb (got ${json.keys.join(', ')})',
      );
    }
    final body = json[kindKeys.single];
    return switch (kindKeys.single) {
      'observe' => ObserveStep._(body: body),
      'act' => ActStep._(body: body, json: json),
      'verify' => VerifyStep._(body: body),
      'wait' => WaitStep._(body: body),
      'screenshot' => ScreenshotStep._(body: body),
      'intent' => IntentStep._(body: body, json: json),
      'record' => RecordStep._(body: body),
      'scope' => ScopeStep._(body: body),
      _ => throw StateError('unreachable'),
    }.withCommon(session: session, continueOnFailure: continueOnFailure);
  }

  /// The session binding this step drives; `null` means "the plan's only
  /// session".
  final String? session;

  /// When true, a failure is recorded and the scenario continues instead
  /// of aborting.
  final bool continueOnFailure;

  /// The step-kind discriminator used in reports.
  String get kind;

  PlanStep withCommon({String? session, required bool continueOnFailure});

  /// Canonical plan shape (round-trippable through [PlanStep.fromJson]).
  Map<String, Object?> toJson();

  /// Violations collected after parsing (semantic checks the parser
  /// cannot express); empty means executable.
  List<String> validate() => const [];
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string when present');
  }
  return value;
}

/// Capture one semantic snapshot — optionally through a
/// [SemanticView] (ADR 0052): the report then carries the view's
/// rendered text + ref index, while `save` keeps the raw snapshot.
final class ObserveStep extends PlanStep {
  /// Creates an observe step.
  const ObserveStep({
    super.session,
    super.continueOnFailure,
    this.save,
    this.view,
    this.at,
  });

  factory ObserveStep._({required Object? body}) {
    if (body != null && body is! Map<Object?, Object?>) {
      throw const FormatException('observe must be a map when present');
    }
    final map = (body as Map<Object?, Object?>?) ?? const {};
    if (map.keys
        .any((key) => key != 'save' && key != 'view' && key != 'at')) {
      throw FormatException(
        'observe supports only `save`, `view`, and `at` '
        '(got ${map.keys.join(', ')})',
      );
    }
    return ObserveStep(
      save: _optionalString(map['save'], 'save'),
      view: map.containsKey('view')
          ? SemanticView.fromJson(map['view'])
          : null,
      at: _atPoint(map['at']),
    );
  }

  /// Report name under which the full snapshot JSON is embedded.
  final String? save;

  /// The view the observation renders through; `null` reports only
  /// counts.
  final SemanticView? view;

  /// Grounding point (ADR 0053): when present, the result names the
  /// innermost walked node whose bounds contain it.
  final (double, double)? at;

  @override
  String get kind => 'observe';

  @override
  PlanStep withCommon({String? session, required bool continueOnFailure}) =>
      ObserveStep(
        session: session,
        continueOnFailure: continueOnFailure,
        save: save,
        view: view,
        at: at,
      );

  @override
  Map<String, Object?> toJson() => {
    'observe': {
      if (save != null) 'save': save,
      if (view != null) 'view': view!.toJson(),
      if (at case (final x, final y)) 'at': {'x': x, 'y': y},
    },
    if (session != null) 'session': session,
    if (continueOnFailure) 'continueOnFailure': true,
  };
}

/// Parses an observe `at` grounding point (`{x, y}` numbers).
(double, double)? _atPoint(Object? raw) {
  if (raw == null) return null;
  if (raw is! Map<Object?, Object?>) {
    throw const FormatException('observe.at must be an {x, y} map');
  }
  final x = raw['x'];
  final y = raw['y'];
  if (x is! num || y is! num) {
    throw const FormatException('observe.at needs numeric x and y');
  }
  return (x.toDouble(), y.toDouble());
}

/// Perform one intent-level action.
final class ActStep extends PlanStep {
  /// Creates an act step.
  const ActStep({
    required this.action,
    super.session,
    super.continueOnFailure,
    this.profile,
    this.seed,
    this.returnState = false,
  });

  factory ActStep._({required Object? body, required Map<Object?, Object?> json}) {
    if (body is! Map<Object?, Object?> || body.isEmpty) {
      throw const FormatException('act must be a non-empty action map');
    }
    // Common keys may ride inside the act map (`- act: {click: {...},
    // session: b}`) — lift them instead of demanding sibling placement.
    const commonKeys = {
      'session',
      'profile',
      'seed',
      'continueOnFailure',
      'returnState',
    };
    final actionBody = {
      for (final entry in body.entries)
        if (!commonKeys.contains(entry.key)) entry.key: entry.value,
    };
    if (actionBody.isEmpty) {
      throw const FormatException('act must be a non-empty action map');
    }
    final action = ActStep.actionFromJson(actionBody);
    final profile =
        _optionalString(json['profile'] ?? body['profile'], 'profile');
    final seedValue = json['seed'] ?? body['seed'];
    if (seedValue != null && seedValue is! int) {
      throw const FormatException('seed must be an integer');
    }
    final returnState = json['returnState'] ??
        body['returnState'] ??
        // The verb shorthand keeps extra keys inside the action map
        // (`- click: {name: Go, returnState: true}`) — lift them here.
        (actionBody.values.single is Map<Object?, Object?>
            ? (actionBody.values.single as Map<Object?, Object?>)['returnState']
            : null);
    if (returnState != null && returnState is! bool) {
      throw const FormatException('returnState must be a boolean');
    }
    return ActStep(
      action: action,
      profile: profile,
      seed: seedValue as int?,
      returnState: returnState == true,
    );
  }

  /// The action to dispatch.
  final AutomationAction action;

  /// Name of the plan-level [BehaviorProfile] to dispatch under; `null`
  /// dispatches plainly (agent-immediate delivery).
  final String? profile;

  /// Deterministic synthesis seed for the profiled dispatch; `null` draws
  /// fresh entropy (production posture).
  final int? seed;

  /// When true, the step result carries the post-action state rendered
  /// through the default view — the act loop's closing read in one
  /// round trip (ADR 0052).
  final bool returnState;

  @override
  String get kind => 'act';

  @override
  PlanStep withCommon({String? session, required bool continueOnFailure}) =>
      ActStep(
        action: action,
        session: session,
        continueOnFailure: continueOnFailure,
        profile: profile,
        seed: seed,
        returnState: returnState,
      );

  @override
  Map<String, Object?> toJson() => {
    'act': actionToJson(action),
    if (profile != null) 'profile': profile,
    if (seed != null) 'seed': seed,
    if (returnState) 'returnState': true,
    if (session != null) 'session': session,
    if (continueOnFailure) 'continueOnFailure': true,
  };

  /// Encodes an action into the plan-document shape.
  static Map<String, Object?> actionToJson(AutomationAction action) =>
      switch (action) {
        NavigateAction(:final url) => {
          'navigate': {'url': url.toString()},
        },
        ClickAction(:final css, :final role, :final name) => {
          'click': {
            if (css != null) 'css': css,
            if (role != null) 'role': role,
            if (name != null) 'name': name,
          },
        },
        ClickAtAction(
          :final x,
          :final y,
          :final button,
          :final clickCount,
          :final modifiers,
        ) =>
          {
            'clickAt': {
              'x': x,
              'y': y,
              if (button != 'left') 'button': button,
              if (clickCount != 1) 'clickCount': clickCount,
              if (modifiers.isNotEmpty) 'modifiers': modifiers,
            },
          },
        MoveAction(:final x, :final y) => {
          'moveTo': {'x': x, 'y': y},
        },
        DragAction(
          :final fromX,
          :final fromY,
          :final toX,
          :final toY,
          :final button,
          :final modifiers,
        ) =>
          {
            'drag': {
              'fromX': fromX,
              'fromY': fromY,
              'toX': toX,
              'toY': toY,
              if (button != 'left') 'button': button,
              if (modifiers.isNotEmpty) 'modifiers': modifiers,
            },
          },
        TypeAction(:final text, :final css, :final submit) => {
          'type': {
            'text': text,
            if (css != null) 'css': css,
            if (submit) 'submit': true,
          },
        },
        KeyPressAction(:final key, :final modifiers) => {
          'key': key,
          if (modifiers.isNotEmpty) 'modifiers': modifiers,
        },
        ScrollAction(:final direction, :final distance) => {
          'scroll': {
            'direction': direction,
            if (distance != null) 'distance': distance,
          },
        },
        EvaluateAction(:final expression) => {'evaluate': expression},
        InvokeAction(:final name, :final args) => {
          'invoke': {'name': name, 'args': args},
        },
      };

  /// Parses an action from the plan-document shape (the `act` body map
  /// with exactly one action key). Shared by plan loading, the CLI, and
  /// the MCP server.
  static AutomationAction actionFromJson(Map<Object?, Object?> body) {
    if (body.length != 1) {
      throw FormatException(
        'an act body must carry exactly one action key '
        '(got ${body.keys.join(', ')})',
      );
    }
    final entry = body.entries.single;
    final value = entry.value;
    switch (entry.key) {
      case 'navigate':
        final params = _asMap(value, 'navigate');
        final url = _optionalString(params['url'], 'navigate.url');
        if (url == null) {
          throw const FormatException('navigate needs a url');
        }
        final uri = Uri.tryParse(url);
        if (uri == null || !uri.hasScheme) {
          throw FormatException('navigate.url must be an absolute URI: $url');
        }
        return NavigateAction(uri);
      case 'click':
        final params = _asMap(value, 'click');
        final css = _optionalString(params['css'], 'click.css');
        final role = _optionalString(params['role'], 'click.role');
        final name = _optionalString(params['name'], 'click.name');
        if (css == null && role == null && name == null) {
          throw const FormatException('click needs css, role, or name');
        }
        return ClickAction(css: css, role: role, name: name);
      case 'clickAt':
        final params = _asMap(value, 'clickAt');
        final (x, y) = _coords(params, 'clickAt');
        return ClickAtAction(
          x,
          y,
          button: _button(params),
          clickCount: _clickCount(params),
          modifiers: _modifiers(params),
        );
      case 'moveTo':
        final params = _asMap(value, 'moveTo');
        final (x, y) = _coords(params, 'moveTo');
        return MoveAction(x, y);
      case 'drag':
        final params = _asMap(value, 'drag');
        final fromX = _num(params['fromX'], 'drag.fromX');
        final fromY = _num(params['fromY'], 'drag.fromY');
        final toX = _num(params['toX'], 'drag.toX');
        final toY = _num(params['toY'], 'drag.toY');
        return DragAction(
          fromX,
          fromY,
          toX,
          toY,
          button: _button(params),
          modifiers: _modifiers(params),
        );
      case 'type':
        final params = _asMap(value, 'type');
        final text = _optionalString(params['text'], 'type.text');
        if (text == null) {
          throw const FormatException('type needs text');
        }
        return TypeAction(
          text,
          css: _optionalString(params['css'], 'type.css'),
          submit: params['submit'] == true,
        );
      case 'key':
        final params = _asMapOrString(value, 'key');
        final key = _optionalString(params['key'], 'key');
        if (key == null || key.isEmpty) {
          throw const FormatException('key needs a key name');
        }
        return KeyPressAction(key, modifiers: _modifiers(params));
      case 'scroll':
        final params = _asMap(value, 'scroll');
        final direction =
            _optionalString(params['direction'], 'scroll.direction') ?? 'down';
        final distanceValue = params['distance'];
        if (distanceValue != null && distanceValue is! num) {
          throw const FormatException('scroll.distance must be a number');
        }
        return ScrollAction(
          direction: direction,
          distance: distanceValue is num ? distanceValue.toDouble() : null,
        );
      case 'evaluate':
        final expression = value is String
            ? value
            : _optionalString(_asMap(value, 'evaluate')['expression'],
                'evaluate.expression');
        if (expression == null || expression.isEmpty) {
          throw const FormatException('evaluate needs an expression');
        }
        return EvaluateAction(expression);
      case 'invoke':
        final params = _asMap(value, 'invoke');
        final name = _optionalString(params['name'], 'invoke.name');
        if (name == null) {
          throw const FormatException('invoke needs a name');
        }
        final args = params['args'];
        return InvokeAction(
          name,
          args: args is Map<Object?, Object?>
              ? args.map((key, value) => MapEntry('$key', value))
              : const {},
        );
      default:
        throw FormatException('unknown action "${entry.key}"');
    }
  }
}

Map<Object?, Object?> _asMap(Object? value, String field) {
  if (value is! Map<Object?, Object?>) {
    throw FormatException('$field must be a map');
  }
  return value;
}

double _num(Object? value, String field) {
  if (value is! num) {
    throw FormatException('$field must be a number');
  }
  return value.toDouble();
}

(double, double) _coords(Map<Object?, Object?> params, String field) =>
    (_num(params['x'], '$field.x'), _num(params['y'], '$field.y'));

String _button(Map<Object?, Object?> params) {
  final button = params['button'];
  if (button == null) return 'left';
  if (button is! String ||
      const {'left', 'right', 'middle'}.contains(button) == false) {
    throw FormatException(
      'button must be left, right, or middle (got $button)',
    );
  }
  return button;
}

int _clickCount(Map<Object?, Object?> params) {
  final count = params['clickCount'];
  if (count == null) return 1;
  if (count is! int || count < 1 || count > 3) {
    throw const FormatException('clickCount must be an integer in 1..3');
  }
  return count;
}

/// Parses the chord modifier list (aliases normalize, unknown names
/// fail closed — a dropped modifier is a misfired chord).
List<String> _modifiers(Map<Object?, Object?> params) {
  final raw = params['modifiers'];
  if (raw == null) return const [];
  if (raw is! List) {
    throw const FormatException('modifiers must be a list of names');
  }
  return parseModifiers(raw);
}

/// Accepts either a map body or a bare string shorthand (`key: Enter`
/// means `{key: Enter}`).
Map<Object?, Object?> _asMapOrString(Object? value, String what) {
  if (value is String) return {'key': value};
  return _asMap(value, what);
}

/// Assert post-conditions against one fresh snapshot; any failed check
/// fails the step.
final class VerifyStep extends PlanStep {
  /// Creates a verify step.
  const VerifyStep({required this.checks, super.session, super.continueOnFailure});

  factory VerifyStep._({required Object? body}) {
    final list = body is List<Object?> ? body : null;
    if (list == null || list.isEmpty) {
      throw const FormatException('verify needs a non-empty list of checks');
    }
    return VerifyStep(
      checks: [
        for (final check in list) VerifyCheck.fromJson(check),
      ],
    );
  }

  /// The checks that must all hold.
  final List<VerifyCheck> checks;

  @override
  String get kind => 'verify';

  @override
  PlanStep withCommon({String? session, required bool continueOnFailure}) =>
      VerifyStep(
        checks: checks,
        session: session,
        continueOnFailure: continueOnFailure,
      );

  @override
  Map<String, Object?> toJson() => {
    'verify': [for (final check in checks) check.toJson()],
    if (session != null) 'session': session,
    if (continueOnFailure) 'continueOnFailure': true,
  };
}

/// Poll the checks until they hold or the timeout elapses — the
/// auto-wait form of [VerifyStep]. Never sleeps unconditionally: every
/// poll re-observes and re-evaluates.
final class WaitStep extends PlanStep {
  /// Creates a wait step.
  const WaitStep({
    required this.checks,
    this.timeout = const Duration(seconds: 10),
    this.pollInterval = const Duration(milliseconds: 250),
    super.session,
    super.continueOnFailure,
  });

  factory WaitStep._({required Object? body}) {
    Map<Object?, Object?> params;
    if (body is Map<Object?, Object?>) {
      params = body;
    } else {
      throw const FormatException('wait must be a map');
    }
    final checks = <VerifyCheck>[];
    final checkList = params['checks'];
    if (checkList is List<Object?>) {
      checks.addAll([
        for (final check in checkList) VerifyCheck.fromJson(check),
      ]);
    }
    final urlContains = _optionalString(params['urlContains'], 'urlContains');
    if (urlContains != null) {
      checks.add(UrlContainsCheck(urlContains));
    }
    if (checks.isEmpty) {
      throw const FormatException(
        'wait needs checks or a urlContains shorthand',
      );
    }
    final timeout = _seconds(params['timeout'], 'timeout') ??
        const Duration(seconds: 10);
    final poll = _seconds(params['poll'], 'poll') ??
        const Duration(milliseconds: 250);
    return WaitStep(
      checks: checks,
      timeout: timeout,
      pollInterval: poll,
    );
  }

  static Duration? _seconds(Object? value, String field) {
    if (value == null) return null;
    if (value is! num || value <= 0) {
      throw FormatException('$field must be a positive number of seconds');
    }
    return Duration(microseconds: (value * 1e6).round());
  }

  /// The checks that must eventually all hold.
  final List<VerifyCheck> checks;

  /// Give-up deadline.
  final Duration timeout;

  /// Poll cadence.
  final Duration pollInterval;

  @override
  String get kind => 'wait';

  @override
  PlanStep withCommon({String? session, required bool continueOnFailure}) =>
      WaitStep(
        checks: checks,
        timeout: timeout,
        pollInterval: pollInterval,
        session: session,
        continueOnFailure: continueOnFailure,
      );

  @override
  Map<String, Object?> toJson() => {
    'wait': {
      'checks': [for (final check in checks) check.toJson()],
      'timeout': timeout.inMilliseconds / 1000,
      'poll': pollInterval.inMilliseconds / 1000,
    },
    if (session != null) 'session': session,
    if (continueOnFailure) 'continueOnFailure': true,
  };

  @override
  List<String> validate() => [
    if (timeout <= Duration.zero) 'wait.timeout must be positive',
    if (pollInterval <= Duration.zero) 'wait.poll must be positive',
    if (pollInterval > timeout) 'wait.poll must not exceed wait.timeout',
  ];
}

/// Capture one PNG frame to [out].
final class ScreenshotStep extends PlanStep {
  /// Creates a screenshot step.
  const ScreenshotStep({
    required this.out,
    super.session,
    super.continueOnFailure,
  });

  factory ScreenshotStep._({required Object? body}) {
    final String out;
    if (body is String && body.isNotEmpty) {
      out = body;
    } else if (body is Map<Object?, Object?>) {
      out = _optionalString(body['out'], 'screenshot.out') ?? '';
    } else {
      out = '';
    }
    if (out.isEmpty) {
      throw const FormatException('screenshot needs an out path');
    }
    return ScreenshotStep(out: out);
  }

  /// Destination path (directories are created).
  final String out;

  @override
  String get kind => 'screenshot';

  @override
  PlanStep withCommon({String? session, required bool continueOnFailure}) =>
      ScreenshotStep(
        out: out,
        session: session,
        continueOnFailure: continueOnFailure,
      );

  @override
  Map<String, Object?> toJson() => {
    'screenshot': out,
    if (session != null) 'session': session,
    if (continueOnFailure) 'continueOnFailure': true,
  };
}

/// Invoke an app intent by name — the WHAT/HOW split of ADR 0038.
///
/// The step carries only the reference (`app`, `name`) and the
/// invocation's runtime [args]; the plan's intent registry resolves the
/// `IntentHint` (driver transport, verb, locator) and the runner lowers
/// it to a driver action. Plans reference intents, apps own their
/// locators — UI refactors do not touch plans.
final class IntentStep extends PlanStep {
  /// Creates an intent step.
  const IntentStep({
    required this.app,
    required this.name,
    this.args = const {},
    super.session,
    super.continueOnFailure,
    this.profile,
    this.seed,
  });

  factory IntentStep._({
    required Object? body,
    required Map<Object?, Object?> json,
  }) {
    final params = switch (body) {
      String reference => {'app': reference},
      Map<Object?, Object?> body => body,
      _ => throw const FormatException(
        'intent must be a map or an "app/name" string',
      ),
    };
    final (app, name) = switch (params) {
      {'app': String app, 'name': String name} => (app, name),
      {'app': String app} when app.contains('/') => (
        app.split('/')[0],
        app.split('/')[1],
      ),
      _ => throw const FormatException(
        'intent needs app and name (or an "app/name" string)',
      ),
    };
    if (app.isEmpty || name.isEmpty) {
      throw const FormatException('intent app and name must not be empty');
    }
    final argsValue = params['args'];
    final args = argsValue is Map<Object?, Object?>
        ? argsValue.map((key, value) => MapEntry('$key', value))
        : const <String, Object?>{};
    final profile = _optionalString(json['profile'], 'profile');
    final seedValue = json['seed'];
    if (seedValue != null && seedValue is! int) {
      throw const FormatException('seed must be an integer');
    }
    return IntentStep(
      app: app,
      name: name,
      args: args,
      profile: profile,
      seed: seedValue as int?,
    );
  }

  /// The app whose manifest declares the intent.
  final String app;

  /// The intent name within the app's manifest.
  final String name;

  /// The invocation's runtime arguments (intent operands — text, url,
  /// key, expression, custom-action args).
  final Map<String, Object?> args;

  /// Name of the plan-level behavior profile to dispatch under.
  final String? profile;

  /// Deterministic synthesis seed for the profiled dispatch.
  final int? seed;

  @override
  String get kind => 'intent';

  @override
  PlanStep withCommon({String? session, required bool continueOnFailure}) =>
      IntentStep(
        app: app,
        name: name,
        args: args,
        session: session,
        continueOnFailure: continueOnFailure,
        profile: profile,
        seed: seed,
      );

  @override
  Map<String, Object?> toJson() => {
    'intent': {
      'app': app,
      'name': name,
      if (args.isNotEmpty) 'args': args,
    },
    if (profile != null) 'profile': profile,
    if (seed != null) 'seed': seed,
    if (session != null) 'session': session,
    if (continueOnFailure) 'continueOnFailure': true,
  };
}


/// Run a view-scoped step tree (ADR 0052) — the calling dimension of
/// composition: the view opens with an observation, the child steps run
/// against the same session, and the closing observation's delta is
/// the scope's evidence. Composition nests the view tree AND the call
/// tree; scopes nest.
final class ScopeStep extends PlanStep {
  /// Creates a scope step.
  const ScopeStep({
    required this.view,
    required this.steps,
    super.session,
    super.continueOnFailure,
  });

  factory ScopeStep._({required Object? body}) {
    final params = switch (body) {
      Map<Object?, Object?> params => params,
      _ => throw const FormatException('scope must be a map'),
    };
    final view = SemanticView.fromJson(params['view']);
    final stepsValue = params['steps'];
    if (stepsValue is! List<Object?> || stepsValue.isEmpty) {
      throw const FormatException('scope needs a non-empty steps list');
    }
    return ScopeStep(
      view: view,
      steps: [for (final step in stepsValue) PlanStep.fromJson(step)],
    );
  }

  /// The view the scope renders its opening/closing observations
  /// through.
  final SemanticView view;

  /// The child steps (any kind except [CodeStep], which is Dart-only
  /// and cannot cross the snapshot boundary — the parser refuses it
  /// before this point).
  final List<PlanStep> steps;

  @override
  String get kind => 'scope';

  @override
  PlanStep withCommon({String? session, required bool continueOnFailure}) =>
      ScopeStep(
        view: view,
        steps: steps,
        session: session,
        continueOnFailure: continueOnFailure,
      );

  @override
  Map<String, Object?> toJson() => {
    'scope': {
      'view': view.toJson(),
      'steps': [for (final step in steps) step.toJson()],
    },
    if (session != null) 'session': session,
    if (continueOnFailure) 'continueOnFailure': true,
  };

  @override
  List<String> validate() {
    final violations = <String>[];
    if (steps.isEmpty) violations.add('scope needs a non-empty steps list');
    for (var i = 0; i < steps.length; i++) {
      final child = steps[i];
      if (child is CodeStep) {
        violations.add(
          'scope.steps[$i] is a code step: code is Dart-only and cannot '
          'cross the snapshot boundary',
        );
      }
      violations.addAll([
        for (final violation in child.validate()) 'scope.steps[$i]: $violation',
      ]);
    }
    return violations;
  }
}

/// Context handed to a [CodeStep] body: the attached driver (the full
/// observe/act surface) and the live URL when the transport exposes one.
final class CodeStepContext {
  /// Creates the context.
  const CodeStepContext({required this.driver, this.url});

  /// The attached session driver.
  final AutomationDriver driver;

  /// The surface URL, when the transport exposes one.
  final Uri? url;
}

/// A step whose body is Dart code — the first-class-code escape hatch
/// (the oka posture): terminal commands, oka calls, arbitrary checks —
/// everything a YAML document cannot express.
///
/// Code steps are **Dart-only by design**: [toJson] throws, and
/// [planDocument] refuses to export a plan containing one. Snapshots
/// are the interchange for agents; the code is the source of truth.
final class CodeStep extends PlanStep {
  /// Creates a code step.
  CodeStep({
    required this.run,
    this.label,
    super.session,
    super.continueOnFailure,
  });

  /// The body. A thrown [CodeStepException] (or any [AutomationException])
  /// fails the step; any other value returned becomes the step detail.
  final Future<Object?> Function(CodeStepContext context) run;

  /// Human-readable label used in reports and refusal messages.
  final String? label;

  @override
  String get kind => 'code';

  @override
  PlanStep withCommon({String? session, required bool continueOnFailure}) =>
      CodeStep(
        run: run,
        label: label,
        session: session,
        continueOnFailure: continueOnFailure,
      );

  @override
  Map<String, Object?> toJson() => throw UnsupportedError(
    'code steps are Dart-only and cannot cross the snapshot boundary; '
    'export snapshots with planDocument after removing them '
    '(${label ?? 'unlabeled code step'})',
  );
}

/// A [CodeStep] body reported failure.
class CodeStepException extends AutomationException {
  /// Creates the failure.
  const CodeStepException(this.stepLabel, String message, {this.details = const {}})
    : super(message);

  @override
  String get kind => 'codeStepFailed';

  /// The failing step's label, when given.
  final String? stepLabel;

  /// Structured details.
  final Map<String, Object?> details;
}

/// Record the surface's frame stream for [duration] — the screencast
/// plane (`frames != semantics`: recording, not observation) — into
/// `out/<base>.mjpeg` + `<base>.meta.jsonl` (the family's file recorder
/// sink). Linked for the CDP tier.
final class RecordStep extends PlanStep {
  /// Creates a record step.
  const RecordStep({
    required this.duration,
    required this.out,
    this.base = 'frames',
    super.session,
    super.continueOnFailure,
  });

  factory RecordStep._({required Object? body}) {
    final params = switch (body) {
      Map<Object?, Object?> params => params,
      _ => throw const FormatException('record must be a map'),
    };
    final seconds = params['seconds'];
    if (seconds is! num || seconds <= 0) {
      throw const FormatException('record needs a positive seconds');
    }
    final out = _optionalString(params['out'], 'record.out');
    if (out == null) {
      throw const FormatException('record needs an out directory');
    }
    return RecordStep(
      duration: Duration(microseconds: (seconds * 1e6).round()),
      out: out,
      base: _optionalString(params['base'], 'record.base') ?? 'frames',
    );
  }

  /// How long to record.
  final Duration duration;

  /// Output directory.
  final String out;

  /// Artifact base name.
  final String base;

  @override
  String get kind => 'record';

  @override
  PlanStep withCommon({String? session, required bool continueOnFailure}) =>
      RecordStep(
        duration: duration,
        out: out,
        base: base,
        session: session,
        continueOnFailure: continueOnFailure,
      );

  @override
  Map<String, Object?> toJson() => {
    'record': {
      'seconds': duration.inMilliseconds / 1000,
      'out': out,
      'base': base,
    },
    if (session != null) 'session': session,
    if (continueOnFailure) 'continueOnFailure': true,
  };
}

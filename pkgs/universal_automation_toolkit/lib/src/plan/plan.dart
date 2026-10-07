import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:yaml/yaml.dart';

import 'intents.dart';
import 'steps.dart';

/// One named attach-only session binding.
///
/// The toolkit never spawns or stops processes (ADR 0037 house rule 2):
/// a binding either points at a live [uri] or names a [handle]
/// (`session-<name>`-style artifact) that the caller resolves via
/// overrides. Borrowed sessions are detached from, never stopped.
@immutable
class SessionBinding {
  /// Creates a binding; exactly one of [uri] / [handle] must be set.
  const SessionBinding({
    required this.name,
    required this.transport,
    this.uri,
    this.handle,
  }) : assert(uri != null || handle != null, 'uri or handle required');

  /// Restores a binding from its plan shape.
  factory SessionBinding.fromJson(String name, Object? json) {
    if (json is! Map<Object?, Object?>) {
      throw FormatException('session "$name" must be a map');
    }
    final transportName = json['transport'];
    if (transportName is! String) {
      throw FormatException('session "$name" needs a transport');
    }
    final AutomationTransport transport;
    try {
      transport = AutomationTransport.values.byName(transportName);
    } on ArgumentError {
      throw FormatException(
        'session "$name" has unknown transport "$transportName"',
      );
    }
    final uriValue = json['uri'];
    final handleValue = json['handle'];
    if ((uriValue == null) == (handleValue == null)) {
      throw FormatException(
        'session "$name" needs exactly one of uri or handle',
      );
    }
    Uri? uri;
    if (uriValue != null) {
      if (uriValue is! String) {
        throw FormatException('session "$name" uri must be a string');
      }
      uri = Uri.tryParse(uriValue);
      if (uri == null) {
        throw FormatException('session "$name" uri does not parse: $uriValue');
      }
    }
    if (handleValue != null && handleValue is! String) {
      throw FormatException('session "$name" handle must be a string');
    }
    return SessionBinding(
      name: name,
      transport: transport,
      uri: uri,
      handle: handleValue as String?,
    );
  }

  /// Binding name (referenced by steps).
  final String name;

  /// Which protocol family speaks at the attach point.
  final AutomationTransport transport;

  /// Direct endpoint URI, when given.
  final Uri? uri;

  /// Handle-artifact name, when given (resolved by caller overrides).
  final String? handle;

  /// The effective attach URI, applying [overrides] (handle name → URI).
  Uri? resolveUri(Map<String, String> overrides) {
    if (uri != null) return uri;
    final override = overrides[handle];
    return override == null ? null : Uri.tryParse(override);
  }

  /// Canonical plan shape.
  Map<String, Object?> toJson() => {
    'transport': transport.name,
    if (uri != null) 'uri': uri.toString(),
    if (handle != null) 'handle': handle,
  };
}

/// One named, composable scenario: an ordered step list.
@immutable
class Scenario {
  /// Creates a scenario.
  const Scenario({
    required this.name,
    this.parent,
    required this.steps,
    this.parseErrors = const [],
  });

  /// Restores a scenario from its plan shape.
  factory Scenario.fromJson(String name, Object? json) {
    if (json is! Map<Object?, Object?>) {
      throw FormatException('scenario "$name" must be a map');
    }
    final parent = json['extends'];
    if (parent != null && parent is! String) {
      throw FormatException('scenario "$name" extends must be a string');
    }
    final rawSteps = json['steps'];
    if (rawSteps is! List<Object?> || rawSteps.isEmpty) {
      throw FormatException('scenario "$name" needs a non-empty steps list');
    }
    final (steps, errors) = _parseSteps(name, rawSteps);
    return Scenario(
      name: name,
      parent: parent as String?,
      steps: steps,
      parseErrors: errors,
    );
  }

  static (List<PlanStep>, List<String>) _parseSteps(
    String scenario,
    List<Object?> steps,
  ) {
    // Collect every step's violations: one bad step must not hide the
    // rest (fail closed means see everything at once). Parse errors ride
    // on the scenario and surface together with all cross-step
    // violations in [AutomationPlan.validate].
    final parsed = <PlanStep>[];
    final errors = <String>[];
    for (var i = 0; i < steps.length; i++) {
      try {
        parsed.add(PlanStep.fromJson(steps[i]));
      } on FormatException catch (error) {
        errors.add('scenario "$scenario" step ${i + 1}: ${error.message}');
      }
    }
    return (parsed, errors);
  }

  /// Scenario name.
  final String name;

  /// Parent scenario whose steps run first, when extending.
  final String? parent;

  /// This scenario's own steps (after the parent's, when extending).
  final List<PlanStep> steps;

  /// Steps that failed to parse; a scenario with parse errors never
  /// runs — the plan validator fails closed on them.
  final List<String> parseErrors;

  /// Canonical plan shape.
  Map<String, Object?> toJson() => {
    if (parent != null) 'extends': parent,
    'steps': [for (final step in steps) step.toJson()],
  };

  /// A child scenario whose steps run after this one's.
  Scenario extend(String name, {List<PlanStep> steps = const []}) =>
      Scenario(name: name, parent: this.name, steps: List.of(steps));
}

/// A declarative automation plan: sessions, behavior profiles, intents,
/// and scenarios — validated as a whole before anything runs (fail
/// closed, all violations at once).
final class AutomationPlan {
  /// Creates a plan from already-parsed parts; duplicate names throw
  /// [SpecViolationException].
  AutomationPlan({
    required List<SessionBinding> sessions,
    this.profiles = const {},
    IntentRegistry? intents,
    required List<Scenario> scenarios,
  }) : sessions = _namedMap(sessions, (session) => session.name, 'session'),
       intents = intents ?? IntentRegistry(const []),
       scenarios = _namedMap(scenarios, (scenario) => scenario.name, 'scenario');

  static Map<String, T> _namedMap<T>(
    List<T> values,
    String Function(T) nameOf,
    String label,
  ) {
    final map = <String, T>{};
    for (final value in values) {
      final name = nameOf(value);
      if (map.containsKey(name)) {
        throw SpecViolationException(['$label "$name" declared twice']);
      }
      map[name] = value;
    }
    return Map.unmodifiable(map);
  }

  /// Loads and validates a plan document (`.yaml`, `.yml`, or `.json`),
  /// resolving `include` entries relative to [path]. Throws
  /// [SpecViolationException] with every violation found.
  static Future<AutomationPlan> load(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw SpecViolationException(['plan file does not exist: $path']);
    }
    final loader = _PlanLoader(file.parent.path);
    final raw = await loader.load(file.path);
    final document = await loader.mergeIncludes(raw, file.path);
    final plan = _PlanParser(document, source: path).parse();
    final violations = plan.validate();
    if (violations.isNotEmpty) {
      throw SpecViolationException(violations);
    }
    return plan;
  }

  /// Named attach-only session bindings, in document order.
  final Map<String, SessionBinding> sessions;

  /// Named behavior profiles (ADR 0044), parsed into typed values.
  final Map<String, BehaviorProfile> profiles;

  /// The plan's intent surface (ADR 0038 hints, contract-shaped).
  final IntentRegistry intents;

  /// Named scenarios.
  final Map<String, Scenario> scenarios;

  /// The single scenario when exactly one is declared, else `null`.
  Scenario? get onlyScenario =>
      scenarios.length == 1 ? scenarios.values.single : null;

  /// Effective steps of [name]: the parent chain's steps (root first)
  /// followed by the scenario's own steps.
  List<PlanStep> effectiveSteps(String name) {
    final chain = <Scenario>[];
    var cursor = name;
    while (true) {
      if (chain.any((scenario) => scenario.name == cursor)) {
        throw SpecViolationException([
          'scenario "$name" has an extends cycle at "$cursor"',
        ]);
      }
      final scenario = scenarios[cursor];
      if (scenario == null) {
        throw SpecViolationException([
          if (chain.isEmpty)
            'scenario "$name" does not exist'
          else
            'scenario "$name" extends unknown scenario "$cursor"',
        ]);
      }
      chain.add(scenario);
      final parent = scenario.parent;
      if (parent == null) break;
      cursor = parent;
    }
    return [
      for (final scenario in chain.reversed) ...scenario.steps,
    ];
  }

  /// Collects every violation; empty means executable.
  List<String> validate() {
    final violations = <String>[];
    for (final scenario in scenarios.values) {
      violations.addAll(scenario.parseErrors);
      final parent = scenario.parent;
      if (parent != null && !scenarios.containsKey(parent)) {
        violations.add(
          'scenario "${scenario.name}" extends unknown scenario "$parent"',
        );
      }
      final steps = _safeSteps(scenario.name, violations);
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        final label = '${scenario.name} step ${i + 1} (${step.kind})';
        final session = step.session;
        if (session == null) {
          if (sessions.length != 1) {
            violations.add(
              '$label: no session named and the plan does not declare '
              'exactly one session',
            );
          }
        } else if (!sessions.containsKey(session)) {
          violations.add('$label: unknown session "$session"');
        }
        final profile = switch (step) {
          ActStep(:final profile) => profile,
          IntentStep(:final profile) => profile,
          _ => null,
        };
        if (profile != null && !profiles.containsKey(profile)) {
          violations.add('$label: unknown behavior profile "$profile"');
        }
        if (step is IntentStep) {
          violations.addAll(_intentViolations(step, label));
        }
        violations.addAll([
          for (final violation in step.validate()) '$label: $violation',
        ]);
      }
    }
    return violations;
  }

  /// Eager intent validation: the referenced intent exists, its declared
  /// parameters are satisfied, and its hint lowers to a driver action.
  List<String> _intentViolations(IntentStep step, String label) {
    final intent = intents.intent(step.app, step.name);
    if (intent == null) {
      final declared = [
        for (final manifest in intents.manifests)
          '${manifest.app}/${manifest.intents.map((i) => i.name).join(', ')}',
      ];
      return [
        '$label: unknown intent "${step.app}/${step.name}" '
        '(declared: ${declared.isEmpty ? 'none' : declared.join('; ')})',
      ];
    }
    final violations = [
      for (final missing in intent.missingParameters(step.args))
        '$label: $missing',
    ];
    try {
      intent.hint.lowerToAction(args: step.args, label: label);
    } on FormatException catch (error) {
      violations.add('$label: ${error.message}');
    }
    return violations;
  }

  List<PlanStep> _safeSteps(String name, List<String> violations) {
    try {
      return effectiveSteps(name);
    } on SpecViolationException catch (error) {
      violations.addAll(error.violations);
      return const [];
    }
  }

  /// Canonical plan shape (round-trippable through [load] via JSON).
  Map<String, Object?> toJson() => {
    'sessions': {
      for (final entry in sessions.entries) entry.key: entry.value.toJson(),
    },
    if (profiles.isNotEmpty)
      'profiles': {
        for (final entry in profiles.entries) entry.key: entry.value.toJson(),
      },
    if (intents.manifests.isNotEmpty) 'intents': intents.toJson(),
    'scenarios': {
      for (final entry in scenarios.entries) entry.key: entry.value.toJson(),
    },
  };
}

/// File loader: YAML/JSON decode, `include` merge (relative paths, cycles
/// and conflicts are violations).
class _PlanLoader {
  _PlanLoader(this.baseDir);

  final String baseDir;

  Future<Map<Object?, Object?>> load(String path) async {
    final file = File(path);
    final decoded = switch (file.uri.pathSegments.last.split('.').last) {
      'json' => jsonDecode(await file.readAsString()),
      'yaml' ||
      'yml' => loadYaml(await file.readAsString(), sourceUrl: Uri.file(path)),
      _ => throw SpecViolationException([
        'plan file must be .yaml, .yml, or .json: $path',
      ]),
    };
    if (decoded is! Map<Object?, Object?>) {
      throw SpecViolationException([
        'plan document must be a mapping: $path',
      ]);
    }
    return _plain(decoded) as Map<Object?, Object?>;
  }

  /// Converts a decoded YAML/JSON tree into plain Dart maps/lists (YAML
  /// nodes are `YamlMap`s, which fail `Map<String, Object?>` casts
  /// downstream).
  static Object? _plain(Object? value) => switch (value) {
    Map<Object?, Object?> map => {
      for (final entry in map.entries) '${entry.key}': _plain(entry.value),
    },
    List<Object?> list => [for (final item in list) _plain(item)],
    _ => value,
  };

  /// Merges `include` entries (recursively) into [document]. Same-name
  /// sessions/profiles/scenarios across files are violations, never
  /// silent overrides.
  Future<Map<Object?, Object?>> mergeIncludes(
    Map<Object?, Object?> document,
    String documentPath,
  ) async {
    final includes = document['include'];
    if (includes == null) return document;
    if (includes is! List<Object?> || includes.isEmpty) {
      throw SpecViolationException([
        'include must be a non-empty list in $documentPath',
      ]);
    }
    final merged = Map.of(document)..remove('include');
    for (final entry in includes) {
      if (entry is! String) {
        throw SpecViolationException([
          'include entries must be paths (got $entry in $documentPath)',
        ]);
      }
      final includedPath = File(entry.startsWith('/')
          ? entry
          : '${File(documentPath).parent.path}/$entry');
      final included = await load(includedPath.path);
      for (final section in const ['sessions', 'profiles', 'scenarios']) {
        final source = included[section];
        if (source == null) continue;
        if (source is! Map<Object?, Object?>) {
          throw SpecViolationException([
            'include $entry section "$section" must be a mapping',
          ]);
        }
        final target = (merged[section] as Map<Object?, Object?>? ?? const {})
            .map((key, value) => MapEntry(key, value));
        for (final key in source.keys) {
          if (target.containsKey(key)) {
            throw SpecViolationException([
              'include $entry redefines "$section.$key" (already declared)',
            ]);
          }
          target[key] = source[key];
        }
        merged[section] = target;
      }
      // Anything beyond the three sections of the included document is
      // ignored: plans compose through the sections only.
    }
    return merged;
  }
}

/// Top-level document parser: sections into typed values, collect-parse
/// errors as violations.
class _PlanParser {
  _PlanParser(this.document, {required this.source});

  final Map<Object?, Object?> document;
  final String source;

  AutomationPlan parse() {
    final violations = <String>[];
    final sessions = <String, SessionBinding>{};
    final rawSessions = _section('sessions');
    for (final entry in rawSessions.entries) {
      try {
        final binding = SessionBinding.fromJson('${entry.key}', entry.value);
        sessions[binding.name] = binding;
      } on FormatException catch (error) {
        violations.add('sessions.${entry.key}: ${error.message}');
      }
    }
    final profiles = <String, BehaviorProfile>{};
    for (final entry in _section('profiles').entries) {
      final name = '${entry.key}';
      try {
        final body = entry.value;
        if (body is! Map<Object?, Object?>) {
          throw FormatException('profile must be a mapping');
        }
        profiles[name] = BehaviorProfile.fromJson(
          body.map((key, value) => MapEntry('$key', value)),
        );
      } on FormatException catch (error) {
        violations.add('profiles.$name: ${error.message}');
      } on SpecViolationException catch (error) {
        violations.addAll([
          for (final violation in error.violations)
            'profiles.$name: $violation',
        ]);
      }
    }
    final intents = <String, IntentManifest>{};
    final rawIntents = document['intents'];
    if (rawIntents != null) {
      final manifestList = rawIntents is List<Object?>
          ? rawIntents
          : [rawIntents];
      for (var i = 0; i < manifestList.length; i++) {
        final manifest = IntentManifest.fromJson(manifestList[i]);
        if (manifest == null) {
          violations.add('intents[$i]: malformed manifest');
          continue;
        }
        if (intents.containsKey(manifest.app)) {
          violations.add('intents[$i]: manifest "${manifest.app}" redeclared');
          continue;
        }
        intents[manifest.app] = manifest;
      }
    }
    final scenarios = <String, Scenario>{};
    for (final entry in _section('scenarios').entries) {
      final name = '${entry.key}';
      try {
        final scenario = Scenario.fromJson(name, entry.value);
        scenarios[scenario.name] = scenario;
      } on FormatException catch (error) {
        violations.add('scenarios.$name: ${error.message}');
      }
    }
    if (violations.isNotEmpty) {
      throw SpecViolationException(violations);
    }
    return AutomationPlan(
      sessions: sessions.values.toList(),
      profiles: profiles,
      intents: IntentRegistry(intents.values),
      scenarios: scenarios.values.toList(),
    );
  }

  Map<Object?, Object?> _section(String name) {
    final value = document[name];
    if (value == null) return const {};
    if (value is! Map<Object?, Object?>) {
      throw SpecViolationException(['$source: section "$name" must be a map']);
    }
    return value;
  }
}

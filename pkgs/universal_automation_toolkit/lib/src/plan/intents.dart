import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';

/// Driver verb an intent hint routes to — the intentcall
/// `IntentAutomationAction` contract shape (`click`, `type`, `key`,
/// `navigate`, `evaluate`, `custom`), parsed from the manifest wire form.
enum IntentVerb {
  /// Resolve the locator and click it.
  click,

  /// Focus the locator and type the invocation's text into it.
  type,

  /// Press the key named by the locator or the invocation.
  key,

  /// Navigate the surface to the locator's route or the invocation's url.
  navigate,

  /// Evaluate the read-only expression from the invocation.
  evaluate,

  /// Invoke the named surface action from the driver's action catalog.
  custom;

  /// Parses the wire form; `null` when it names no verb.
  static IntentVerb? tryParse(Object? value) {
    for (final verb in values) {
      if (verb.name == value) return verb;
    }
    return null;
  }
}

/// How an intent is driven — the intentcall `IntentAutomationHint`
/// contract shape (ADR 0038): which driver transport family, which verb,
/// which locator. IntentCall owns intent truth; this is its read-side
/// projection, parsed verbatim from intentcall-exported manifests.
@immutable
final class IntentHint {
  /// Creates a hint after validating its invariants.
  IntentHint({
    required this.driver,
    required this.verb,
    required this.locator,
  }) {
    if (driver.trim().isEmpty) {
      throw ArgumentError.value(driver, 'driver', 'must not be empty');
    }
    final locatorDriven = switch (verb) {
      IntentVerb.click ||
      IntentVerb.type ||
      IntentVerb.key ||
      IntentVerb.custom => true,
      IntentVerb.navigate || IntentVerb.evaluate => false,
    };
    if (locatorDriven && locator.isEmpty) {
      throw ArgumentError.value(
        locator,
        'locator',
        'must not be empty for ${verb.name}',
      );
    }
    if (verb == IntentVerb.custom &&
        (locator['name'] ?? '').trim().isEmpty) {
      throw ArgumentError.value(
        locator,
        'locator',
        "custom hints must name the catalog action under locator['name']",
      );
    }
  }

  /// Restores a hint from its manifest shape; `null` when absent or
  /// malformed (tolerates pre-`action` manifests: absent verb means
  /// `click`, the historical default).
  static IntentHint? fromJson(Object? json) {
    if (json is! Map<Object?, Object?>) return null;
    final driver = json['driver'];
    if (driver is! String || driver.isEmpty) return null;
    final verb =
        IntentVerb.tryParse(json['action'] ?? json['verb']) ??
        (json['action'] == null && json['verb'] == null
            ? IntentVerb.click
            : null);
    if (verb == null) return null;
    final rawLocator = json['locator'];
    final locator = <String, String>{
      if (rawLocator is Map<Object?, Object?>)
        for (final entry in rawLocator.entries)
          if (entry.key is String && entry.value is String)
            entry.key! as String: entry.value! as String,
    };
    if (locator.isEmpty && _locatorRequired(verb)) return null;
    return IntentHint(driver: driver, verb: verb, locator: locator);
  }

  static bool _locatorRequired(IntentVerb verb) => switch (verb) {
    IntentVerb.click ||
    IntentVerb.type ||
    IntentVerb.key ||
    IntentVerb.custom => true,
    IntentVerb.navigate || IntentVerb.evaluate => false,
  };

  /// Driver transport family (`cdp`, `webdriver`, `ax`, …) — matched
  /// against session bindings' transports at run.
  final String driver;

  /// The verb an invocation layer routes to.
  final IntentVerb verb;

  /// Locator against the driver's snapshot (`css`, `role`, `name`,
  /// `key`, `route`, or the catalog action `name` for `custom`).
  final Map<String, String> locator;

  /// Lowers the hint to a driver action, feeding [args] (the invocation's
  /// runtime arguments — the operands that travel with the call, never
  /// the registration). Throws [FormatException] with a message naming
  /// [label] when the operands or locator cannot produce an action.
  AutomationAction lowerToAction({
    Map<String, Object?> args = const {},
    required String label,
  }) {
    final text = (key) => args[key] is String && (args[key] as String).isNotEmpty
        ? args[key] as String
        : (locator[key] ?? '');
    return switch (verb) {
      IntentVerb.click => ClickAction(
        css: locator['css'],
        role: locator['role'],
        name: locator['name'],
      ),
      IntentVerb.type => () {
        final value = text('text');
        if (value.isEmpty) {
          throw FormatException(
            '$label: type intent needs non-empty text (invocation args or '
            "locator['text'])",
          );
        }
        return TypeAction(
          value,
          css: locator['css'],
          submit: args['submit'] == true || locator['submit'] == 'true',
        );
      }(),
      IntentVerb.key => () {
        final value = text('key');
        if (value.isEmpty) {
          throw FormatException(
            '$label: key intent needs a key (invocation args or '
            "locator['key'])",
          );
        }
        return KeyPressAction(value);
      }(),
      IntentVerb.navigate => () {
        final value = text('url') + (text('url').isEmpty ? text('route') : '');
        final uri = Uri.tryParse(value);
        if (value.isEmpty || uri == null || !uri.hasScheme) {
          throw FormatException(
            '$label: navigate intent needs an absolute url (invocation args '
            "or locator['route'])",
          );
        }
        return NavigateAction(uri);
      }(),
      IntentVerb.evaluate => () {
        final value = text('expression');
        if (value.isEmpty) {
          throw FormatException(
            '$label: evaluate intent needs an expression (invocation args '
            "or locator['expression'])",
          );
        }
        return EvaluateAction(value);
      }(),
      IntentVerb.custom => InvokeAction(
        locator['name']!,
        args: args,
      ),
    };
  }

  /// Manifest wire shape.
  Map<String, Object?> toJson() => {
    'driver': driver,
    'action': verb.name,
    'locator': locator,
  };

  @override
  String toString() => 'IntentHint($driver, ${verb.name}, $locator)';
}

/// One intent an app declares: name, display title, optional parameter
/// descriptors, and the driving hint.
@immutable
final class AppIntent {
  /// Creates an intent.
  AppIntent({
    required this.name,
    required this.hint,
    this.title,
    this.parameters = const [],
  }) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
  }

  /// Restores an intent from its manifest shape; `null` when malformed.
  static AppIntent? fromJson(Object? json) {
    if (json is! Map<Object?, Object?>) return null;
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final hint = IntentHint.fromJson(json['hint']);
    if (hint == null) return null;
    final title = json['title'];
    final parameters = json['parameters'];
    return AppIntent(
      name: name,
      title: title is String ? title : null,
      hint: hint,
      parameters: parameters is List<Object?>
          ? [
            for (final parameter in parameters)
              if (parameter is Map<Object?, Object?>)
                parameter.map(
                  (key, value) => MapEntry('$key', value),
                ),
          ]
          : const [],
    );
  }

  /// Intent name (referenced by `intent` steps).
  final String name;

  /// Display title, when carried.
  final String? title;

  /// How the intent drives (the ADR 0038 hint).
  final IntentHint hint;

  /// Declared parameters: `{name, type?, required?, description?}` maps.
  final List<Map<String, Object?>> parameters;

  /// Whether [args] satisfy the declared required parameters.
  List<String> missingParameters(Map<String, Object?> args) => [
    for (final parameter in parameters)
      if (parameter['required'] == true &&
          (args[parameter['name']] == null))
        "missing required parameter '${parameter['name']}'",
  ];

  /// Manifest wire shape.
  Map<String, Object?> toJson() => {
    'name': name,
    if (title != null) 'title': title,
    'hint': hint.toJson(),
    if (parameters.isNotEmpty) 'parameters': parameters,
  };
}

/// All intents of one app, under the app name plans reference.
@immutable
final class IntentManifest {
  /// Creates a manifest.
  const IntentManifest({required this.app, required this.intents});

  /// Restores a manifest from its manifest-file shape; `null` when
  /// malformed.
  static IntentManifest? fromJson(Object? json) {
    if (json is! Map<Object?, Object?>) return null;
    final app = json['app'] ?? json['name'];
    if (app is! String || app.isEmpty) return null;
    final intents = json['intents'];
    if (intents is! List<Object?>) return null;
    return IntentManifest(
      app: app,
      intents: [
        for (final intent in intents)
          if (AppIntent.fromJson(intent) case final intent?) intent,
      ],
    );
  }

  /// App name.
  final String app;

  /// The app's intents.
  final List<AppIntent> intents;

  /// The intent called [name], or `null`.
  AppIntent? intent(String name) {
    for (final intent in intents) {
      if (intent.name == name) return intent;
    }
    return null;
  }

  /// Manifest wire shape.
  Map<String, Object?> toJson() => {
    'app': app,
    'intents': [for (final intent in intents) intent.toJson()],
  };
}

/// The plan's intent surface: manifests by app name, loadable in Dart or
/// from intentcall-exported manifest files.
final class IntentRegistry {
  /// Creates a registry.
  IntentRegistry(Iterable<IntentManifest> manifests)
    : _manifests = {
        for (final manifest in manifests) manifest.app: manifest,
      };

  /// Loads manifest JSON files (single manifest objects or a top-level
  /// list of them) — the intentcall export shape.
  factory IntentRegistry.fromFiles(Iterable<String> paths) {
    final manifests = <IntentManifest>[];
    for (final path in paths) {
      final decoded = jsonDecode(File(path).readAsStringSync());
      final list = decoded is List<Object?> ? decoded : [decoded];
      for (final entry in list) {
        if (IntentManifest.fromJson(entry) case final manifest?) {
          manifests.add(manifest);
        }
      }
    }
    return IntentRegistry(manifests);
  }

  final Map<String, IntentManifest> _manifests;

  /// All manifests, in registration order.
  Iterable<IntentManifest> get manifests => _manifests.values;

  /// The manifest of [app], or `null`.
  IntentManifest? manifest(String app) => _manifests[app];

  /// The intent [app] declares under [name], or `null`.
  AppIntent? intent(String app, String name) => _manifests[app]?.intent(name);

  /// Wire shape (the plan document's `intents` section is a list of
  /// manifest maps).
  List<Map<String, Object?>> toJson() => [
    for (final manifest in manifests) manifest.toJson(),
  ];
}

import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:universal_automation_interface/universal_automation_interface.dart';
import 'package:universal_automation_semantics/universal_automation_semantics.dart';

/// The MCP metadata key intentcall projects automation hints under
/// (ADR 0038 wire projection; see intentcall_mcp's publish adapter).
const intentcallAutomationMetaKey = 'dev.intentcall/automation';

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
    this.viewHint,
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
    // The view hint (ADR 0052's composition point) parses fail-closed:
    // a malformed one skips the whole hint, exactly like a malformed
    // locator — the projection upstream guarantees parseable hints.
    SemanticView? viewHint;
    if (json['view'] != null) {
      try {
        viewHint = SemanticView.fromJson(json['view']);
      } on FormatException {
        return null;
      }
    }
    return IntentHint(
      driver: driver,
      verb: verb,
      locator: locator,
      viewHint: viewHint,
    );
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

  /// The intent's perception hint — a [SemanticView] the runner
  /// observes through after dispatch, so an app declares not only WHAT
  /// it drives but HOW its effect should be read (the intent-acts /
  /// semantics-perceives composition, ADR 0052). Wire form: the `view`
  /// key in the family view grammar verbatim.
  final SemanticView? viewHint;

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
    if (viewHint != null) 'view': viewHint!.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is IntentHint &&
      other.driver == driver &&
      other.verb == verb &&
      other.locator.length == locator.length &&
      other.locator.entries.every(
        (entry) => locator[entry.key] == entry.value,
      ) &&
      _viewWire == other._viewWire;

  String? get _viewWire => viewHint == null
      ? null
      : const JsonEncoder().convert(viewHint!.toJson());

  @override
  int get hashCode => Object.hash(
    driver,
    verb,
    Object.hashAllUnordered(locator.entries),
    _viewWire,
  );
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

  /// Builds a registry from a captured MCP `tools/list` payload — the
  /// shape intentcall hints actually travel in (the ADR 0038 wire
  /// projection: each tool's `_meta['dev.intentcall/automation']` carries
  /// `IntentAutomationHint.toJson()`).
  ///
  /// Accepts the full result (`{tools: [...]}`) or a bare tool list.
  /// Tools without the hint meta are skipped (they are plain MCP tools,
  /// not automation intents); tools with an unparseable hint are skipped
  /// too — intentcall's own projection guarantees parseable hints, so a
  /// skip means the payload predates the projection. Throws
  /// [FormatException] for duplicate tool names.
  factory IntentRegistry.fromMcpToolsList(
    Object? json, {
    String app = 'app',
  }) {
    final tools = switch (json) {
      {'tools': List<Object?> tools} => tools,
      List<Object?> tools => tools,
      _ => throw const FormatException(
        'expected a tools/list payload ({tools: [...]} or a tool list)',
      ),
    };
    final intents = <AppIntent>[];
    final seen = <String>{};
    for (final tool in tools) {
      if (tool is! Map<Object?, Object?>) continue;
      final name = tool['name'];
      if (name is! String || name.isEmpty) continue;
      if (!seen.add(name)) {
        throw FormatException('duplicate tool name "$name" in capture');
      }
      final meta = tool['_meta'];
      if (meta is! Map<Object?, Object?>) continue;
      final hint = IntentHint.fromJson(meta[intentcallAutomationMetaKey]);
      if (hint == null) continue;
      final description = tool['description'];
      final inputSchema = tool['inputSchema'];
      intents.add(
        AppIntent(
          name: name,
          title: description is String && description.isNotEmpty
              ? description
              : null,
          hint: hint,
          parameters: _parametersFromSchema(inputSchema),
        ),
      );
    }
    return IntentRegistry([IntentManifest(app: app, intents: intents)]);
  }

  /// Maps a JSON-schema `inputSchema` onto the intent parameter list.
  static List<Map<String, Object?>> _parametersFromSchema(Object? schema) {
    if (schema is! Map<Object?, Object?>) return const [];
    final properties = schema['properties'];
    if (properties is! Map<Object?, Object?>) return const [];
    final required = schema['required'];
    final requiredNames = required is List<Object?>
        ? required.whereType<String>().toSet()
        : <String>{};
    return [
      for (final entry in properties.entries)
        () {
          final parameter = <String, Object?>{'name': '${entry.key}'};
          if (entry.value is Map<Object?, Object?>) {
            final property = entry.value as Map<Object?, Object?>;
            if (property['type'] is String) parameter['type'] = property['type'];
            if (property['description'] is String) {
              parameter['description'] = property['description'];
            }
          }
          if (requiredNames.contains('${entry.key}')) {
            parameter['required'] = true;
          }
          return parameter;
        }(),
    ];
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

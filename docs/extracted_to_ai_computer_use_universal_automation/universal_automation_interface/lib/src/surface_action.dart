import 'package:meta/meta.dart';

/// Describes one named action the surface under test registered for
/// automation — one entry of a driver's action catalog.
///
/// Descriptors are pure data so any tier can carry them: the instrumented
/// tier lists them from a VM service extension, the CDP tier probes the
/// page's `window.__mcpActions` registry, and any other framework (Jaspr,
/// a CLI, an OS agent) can serve the same shape over its own transport.
/// Nothing here is Flutter-specific.
@immutable
final class SurfaceActionDescriptor {
  /// Creates a descriptor after validating its invariants.
  const SurfaceActionDescriptor({
    required this.name,
    this.description = '',
    this.inputSchema,
  }) : assert(name != '', 'name must not be empty');

  /// Restores a descriptor from [toJson] output; `null` when malformed.
  static SurfaceActionDescriptor? fromJson(final Object? json) {
    if (json is! Map<Object?, Object?>) return null;
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final description = json['description'];
    final rawSchema = json['inputSchema'];
    return SurfaceActionDescriptor(
      name: name,
      description: description is String ? description : '',
      inputSchema: rawSchema is Map<Object?, Object?>
          ? Map<String, Object?>.of({
              for (final entry in rawSchema.entries)
                if (entry.key is String) entry.key! as String: entry.value,
            })
          : null,
    );
  }

  /// Catalog-unique action name (`long_press`, `app.checkout_flow`).
  ///
  /// Dotted names are the convention for app-owned namespaces; bare names
  /// stay available for surface-provided actions.
  final String name;

  /// One-line human description (agent-facing documentation).
  final String description;

  /// JSON-Schema (subset) the action's arguments must satisfy; `null`
  /// means the action accepts any JSON-encodable argument map.
  ///
  /// Carried as plain data on purpose: the family depends on no schema
  /// library. Consumers that want pre-dispatch validation (the mcp_flutter
  /// harness validates against `intentcall_schema`) read this map.
  final Map<String, Object?>? inputSchema;

  /// Serializes the descriptor (JSON-encodable).
  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    if (inputSchema != null) 'inputSchema': inputSchema,
  };

  @override
  String toString() =>
      'SurfaceActionDescriptor('
      '$name${description.isEmpty ? '' : ': $description'})';
}

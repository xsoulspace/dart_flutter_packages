// ignore_for_file: lines_longer_than_80_chars

/// ADR 0035 §1/§3 — the MATERIALIZER BINDING: the registry IS the format
/// seam. The informal contract that already fit a 4th class
/// (`perform({action, anchor, body}) → outcome.toJson()` + declared
/// actions + a map parser) is promoted to ONE tiny record — the proven
/// shape, made mechanical. Adding a format = registering a binding here
/// (+ the materializer file), never a new switch, never a new verb.
///
/// NOT a fat interface: no nullable knobs for packs/consent/coverage/
/// baseline (dart-only machinery stays on the dart path the router
/// already maintains — `sym_*` nodes never route through a binding).
///
/// ADR 0035 §3 — registration-time honesty: the registry is validated at
/// init (machine-checked, named errors); a wiring error is a startup
/// failure, never a silent misattribution ("class has no actions").
///
/// FILE CREATION is a BINDING property (build order item 7): creating a
/// file = creating meaning — a file node + content sub-nodes under its
/// binding, the path projecting from the ADDRESSED DIR NODE. There is no
/// raw `file_bootstrap` verb (fs-thinking relapse) and no per-format
/// create verb: the ONE edit verb serves the declared creation action
/// ([fileCreationAction]) when — and only when — the binding declares
/// the [FileCreation] capability. A class whose binding does not declare
/// it has NO creation route: the router bounces NAMING the binding and
/// the field to register — never a silent fallback to a raw write.
library;

import 'package:xsoulspace_agentic_harness/src/tools/fs_tools.dart'
    show FileLockTable, FsToolsRoot;

import 'file_class_spec.dart' show FileClassSpec, MapParser, fileClassSpecs;
import 'md_materializer.dart' show mdMapParser, mdMaterializerPerform;
import 'ts_materializer.dart'
    show tsMapParser, tsMaterializerPerform;
import 'cs_materializer.dart'
    show csMapParser, csMaterializerPerform;
import 'yaml_json_materializer.dart'
    show jsonMapParser, keypathMaterializerPerform, yamlMapParser;

/// The create-file action name served through the ONE edit verb when the
/// binding declares the [FileCreation] capability. One name for every
/// creation-capable class (the semantics are class-agnostic: whole-file
/// meaning creation); the class teaches its anchor currency through the
/// capability's declared fields, never through a per-format verb.
const fileCreationAction = 'create_document';

/// The FILE-CREATION capability, declared as binding data (build order
/// item 7): the binding declares WHETHER the class supports creation and
/// in which anchor currency — not a per-format verb, not a raw write.
///
/// The router addresses creation at a DIR node (the parent in the
/// map-graph); the anchor names the new file (workspace-relative), so
/// the path PROJECTS from meaning and the jail never sees a model-named
/// absolute path. The class's initial-content semantics (heading-bearing
/// body for heading classes; empty map document + first key at the
/// anchor keypath for keypath classes) live in the class's materializer
/// — the capability declares the CONTRACT (action + currency), the
/// materializer realizes it, and the registry linter keeps them honest.
class FileCreation {
  const FileCreation({required this.action, required this.anchorCurrency});

  /// The create-file action name (one of the ONE verb's servable
  /// actions for this class). Use [fileCreationAction].
  final String action;

  /// The creation anchor's declared currency:
  /// - `new_file_path` — the anchor is the new file's workspace-relative
  ///   path; the initial content rides the body whole (heading classes:
  ///   the body must carry the initial heading structure);
  /// - `new_file_path#keypath` — the anchor is the path plus an optional
  ///   `#keypath` suffix; the suffix sets the FIRST key into the created
  ///   empty map document (keypath classes), the body being its value.
  final String anchorCurrency;
}



/// One node edit routed to a binding's materializer — the arg envelope of
/// the proven `perform` shape (the router resolves the node and the
/// anchor; the materializer plans, splices, oracles, auto-reverts).
class NodeEditRequest {
  const NodeEditRequest({
    required this.root,
    required this.path,
    required this.action,
    required this.anchor,
    this.locks,
    this.owner = 'edit_node_router',
    this.body,
  });

  /// The jailed workspace root.
  final FsToolsRoot root;

  /// The shared single-writer lock table (md/keypath/span editors claim
  /// the same one).
  final FileLockTable? locks;

  /// Lock owner tag.
  final Object owner;

  /// Workspace-relative path (resolved by the router from the node — the
  /// model never names it).
  final String path;

  /// The action name (one of the binding's declared `actions`).
  final String action;

  /// The anchor in the binding's DECLARED currency (already resolved —
  /// see [MaterializerBinding.resolveAnchor]).
  final String anchor;

  /// The body-as-data (prose/fragment), when supplied.
  final String? body;
}

/// The proven perform shape, promoted to a type (ADR 0035 §1): plan →
/// splice → oracle → auto-revert, surfacing bounces as structured data.
typedef NodeMaterializer = Map<String, dynamic> Function(NodeEditRequest r);

/// The binding's map half (ADR 0035 §2): parse [content] into sub-node
/// DATA — the fs tier stamps the nodes (ids, budget caps and green-screen
/// facts stay engine-owned; the id prefix is binding-declared). The type
/// is `file_class_spec.dart`'s [MapParser].

/// Resolves the materializer's anchor slot from the model's literal anchor
/// arg + the node's props. The binding declares its anchor currency here
/// (ADR 0035 §3d — keypath, never a path; node-id, never a label guess).
typedef AnchorResolver = String Function(
  String nodeId,
  Map<String, dynamic> props,
  String? literalAnchor,
);

/// The node-id currency: the node itself is the anchor.
String _nodeIdAnchor(String nodeId, Map<String, dynamic> props,
        String? literalAnchor) =>
    nodeId;

/// The keypath currency: the literal creation keypath wins; the node's
/// stamped keypath prop is the truth; the node id is only the handle.
String _keypathAnchor(String nodeId, Map<String, dynamic> props,
        String? literalAnchor) =>
    literalAnchor ?? '${props['keypath'] ?? nodeId}';

/// ADR 0035 §1 — the tiny binding record (~20 lines): one file class's
/// EDIT + MAP registration. The metadata view the old spec folded into
/// (span currency, map format, emitter, oracle, anchor currency) plus the
/// realizations the old spec only named as dead strings (the perform fn,
/// the map parser, the sub-node id prefix).
class MaterializerBinding {
  const MaterializerBinding({
    required this.fileClass,
    required this.extensions,
    required this.actions,
    required this.materializer,
    required this.oracle,
    required this.anchors,
    required this.spanCurrency,
    required this.mapFormat,
    required this.emitter,
    this.mapParser,
    this.subNodePrefix,
    this.resolveAnchor = _nodeIdAnchor,
    this.fileCreation,
  });

  /// The registry key — the node's stamped `class` prop. MUST equal a
  /// [FileClassSpec.fileClass] (§3a: a binding for an unregistered class
  /// is a wiring error today).
  final String fileClass;

  /// Lowercase extensions WITH the dot — must agree with the file-class
  /// spec (§3a) and be disjoint across bindings (§3b).
  final Set<String> extensions;

  /// The class's legal EDIT ACTION names (the closed union served by the
  /// ONE edit verb, class-scoped — ADR 0034 §2). Non-empty ⇒ a named
  /// oracle must exist (§3c).
  final List<String> actions;

  /// The perform fn — the realization behind the old dead `emitter`/
  /// `oracle` strings.
  final NodeMaterializer materializer;

  /// The named mechanical oracle (`zero_broken_links`,
  /// `parse_semantic_diff`). A class with NO oracle has NO edit actions —
  /// its writes route through the review gate (ADR 0024 §6).
  final String oracle;

  /// The required anchor slot's currency (§3d — declared, never implied).
  final String anchors;

  /// The span currency the emitter splices (`section`, `keypath`).
  final String spanCurrency;

  /// The tree sub-structure the map half builds (`heading_tree`,
  /// `keypath_tree`).
  final String mapFormat;

  /// The host-spliced emitter realization (`section_splice`,
  /// `keypath_splice`).
  final String emitter;

  /// The map parser (§2): null → mapless class (no text read,
  /// structurally — node facts + the named bounce; ADR 0024 §6).
  final MapParser? mapParser;

  /// The sub-node id prefix (`sec_`, `key_`) — the STALE-MAP DROP
  /// ownership: the fs tier derives which sub-nodes belong to (and die
  /// with) a file from the binding, never a hardcoded prefix list (§2).
  /// Required whenever [mapParser] is set.
  final String? subNodePrefix;

  /// The anchor resolver (§3d).
  final AnchorResolver resolveAnchor;

  /// The FILE-CREATION capability (build order item 7): null → the class
  /// has NO creation route (the router bounces NAMING this binding and
  /// field — never a silent raw-write fallback). Declared, never implied.
  final FileCreation? fileCreation;
}

/// THE REGISTRY — DATA (ADR 0035 §1). One entry per file class with edit
/// actions. Routing keys on the node's stamped `class` prop; yaml+json
/// share ONE keypath materializer across two bindings (class-routing,
/// never kind-routing). The engine, router, fs tier and model surface are
/// closed code; a new format lands here as data + one materializer file.
const materializerBindings = <String, MaterializerBinding>{
  'md': MaterializerBinding(
    fileClass: 'md',
    extensions: {'.md', '.mdx'},
    spanCurrency: 'section',
    mapFormat: 'heading_tree',
    emitter: 'section_splice',
    oracle: 'zero_broken_links',
    anchors: 'heading_path',
    actions: ['replace_section', 'insert_section', 'append_to_section'],
    materializer: mdMaterializerPerform,
    mapParser: mdMapParser,
    subNodePrefix: 'sec_',
    fileCreation: FileCreation(
      action: fileCreationAction,
      anchorCurrency: 'new_file_path',
    ),
  ),
  'yaml': MaterializerBinding(
    fileClass: 'yaml',
    extensions: {'.yaml', '.yml'},
    spanCurrency: 'keypath',
    mapFormat: 'keypath_tree',
    emitter: 'keypath_splice',
    oracle: 'parse_semantic_diff',
    anchors: 'keypath',
    actions: ['set_key', 'replace_value', 'delete_key', 'append_list_item'],
    materializer: keypathMaterializerPerform,
    mapParser: yamlMapParser,
    subNodePrefix: 'key_',
    resolveAnchor: _keypathAnchor,
    // Creation: the anchor is the new file's path; the `#keypath` suffix
    // sets the FIRST key into the created empty map document.
    fileCreation: FileCreation(
      action: fileCreationAction,
      anchorCurrency: 'new_file_path#keypath',
    ),
  ),
  'json': MaterializerBinding(
    fileClass: 'json',
    extensions: {'.json'},
    spanCurrency: 'keypath',
    mapFormat: 'keypath_tree',
    emitter: 'keypath_splice',
    oracle: 'parse_semantic_diff',
    anchors: 'keypath',
    actions: ['set_key', 'replace_value', 'delete_key', 'append_list_item'],
    materializer: keypathMaterializerPerform,
    mapParser: jsonMapParser,
    subNodePrefix: 'key_',
    resolveAnchor: _keypathAnchor,
    // Creation: same keypath currency as the yaml binding — ONE shared
    // materializer realizes BOTH classes' creation (class-routing).
    fileCreation: FileCreation(
      action: fileCreationAction,
      anchorCurrency: 'new_file_path#keypath',
    ),
  ),
  // ADR 0035 §6 — the ts family (Tier C v1): symbol map via the
  // dependency-light scanner (tsScanSymbols), member-body edits via PACK
  // EXECUTABLES only (apply_executable — replace_member_body is
  // deliberately OMITTED from the declared union: the v1 limitation IS
  // registry data, never prose, §5). Anchor currency = the node id (the
  // default [_nodeIdAnchor]); the named oracle tsc_no_emit bounces
  // BEFORE bytes when unavailable.
  'ts': MaterializerBinding(
    fileClass: 'ts',
    extensions: {'.ts', '.tsx'},
    spanCurrency: 'member_span',
    mapFormat: 'symbol_tree',
    emitter: 'member_splice',
    oracle: 'tsc_no_emit',
    anchors: 'node_id',
    actions: ['insert_member', 'remove_member', 'apply_executable'],
    materializer: tsMaterializerPerform,
    mapParser: tsMapParser,
    subNodePrefix: 'tsym_',
  ),
  // ADR 0035 §6 — the cs family (Tier C v1, mirrors the ts family):
  // symbol map via the dependency-light scanner (csScanSymbols),
  // member-body edits via PACK EXECUTABLES only (apply_executable —
  // replace_member_body is deliberately OMITTED from the declared union:
  // the v1 limitation IS registry data, never prose, §5). Anchor
  // currency = the node id (the default [_nodeIdAnchor]); the named
  // oracle dotnet_build bounces BEFORE bytes when unavailable. The
  // *.csproj Tier B xml binding is the named-not-built disposition
  // (PLAN ledger — csproj stays class `other`, review-gate writes).
  'cs': MaterializerBinding(
    fileClass: 'cs',
    extensions: {'.cs'},
    spanCurrency: 'member_span',
    mapFormat: 'symbol_tree',
    emitter: 'member_splice',
    oracle: 'dotnet_build',
    anchors: 'node_id',
    actions: ['insert_member', 'remove_member', 'apply_executable'],
    materializer: csMaterializerPerform,
    mapParser: csMapParser,
    subNodePrefix: 'csym_',
  ),
};

/// ADR 0035 §3 — the registry-linter: named registration errors, empty
/// list = valid. Machine-checked at registry init; each violation class
/// is unit-tested with its own named error.
///
/// - `binding_without_file_class` (§3a): a binding for a class the file
///   spec registry never registered — a wiring error TODAY (it would
///   misattribute as "class has no actions").
/// - `binding_extensions_mismatch` (§3a): the binding's extension set
///   disagrees with its file-class spec — one of the two is a lie.
/// - `extension_collision` (§3b): one extension claimed by two bindings —
///   path → class resolution must be a total, once-stamped function.
/// - `actions_without_oracle` (§3c): actions declared with no named
///   oracle — the honesty law (ADR 0024 §6) as assertion, not convention.
/// - `anchor_currency_undeclared` (§3d): actions declared with no anchor
///   currency — the ADR 0034 disposition-1 pattern as assertion.
/// - `map_without_sub_node_prefix` (§2): a map parser without the
///   stale-map drop ownership (the sub-node id prefix).
/// - `creation_without_map` (build order item 7): a creation capability
///   without a map parser — creation promises the file node + content
///   sub-nodes under the binding; a mapless creation would create bytes
///   the tree cannot see.
/// - `creation_declaration_incomplete`: a creation capability without
///   its action name or anchor currency — an undeclared currency is the
///   fs-shaped relapse the capability exists to prevent.
List<String> validateMaterializerBindings(
  List<MaterializerBinding> bindings, {
  List<FileClassSpec> classes = fileClassSpecs,
}) {
  final errors = <String>[];
  final known = {for (final c in classes) c.fileClass: c};
  final extOwner = <String, String>{};
  for (final b in bindings) {
    final spec = known[b.fileClass];
    if (spec == null) {
      errors.add(
        'binding_without_file_class: binding "${b.fileClass}" has no '
        'registered FileClassSpec — wire the spec first (§3a: a binding '
        'for an unregistered class misattributes as "class has no '
        'actions")',
      );
      continue;
    }
    if (b.extensions.length != spec.extensions.length ||
        !b.extensions.containsAll(spec.extensions)) {
      errors.add(
        'binding_extensions_mismatch: binding "${b.fileClass}" declares '
        '${b.extensions.toList()..sort()} but the file-class spec '
        'declares ${spec.extensions.toList()..sort()} — exactly one of '
        'them is the truth (§3a)',
      );
    }
    for (final ext in b.extensions) {
      final owner = extOwner[ext];
      if (owner != null && owner != b.fileClass) {
        errors.add(
          'extension_collision: "$ext" is claimed by BOTH "$owner" and '
          '"${b.fileClass}" — path → class must resolve total and '
          'once-stamped; declare precedence or fix the sets (§3b)',
        );
      }
      extOwner[ext] = b.fileClass;
    }
    if (b.actions.isNotEmpty && b.oracle.isEmpty) {
      errors.add(
        'actions_without_oracle: binding "${b.fileClass}" declares '
        '${b.actions.length} action(s) but no named oracle — the honesty '
        'law (ADR 0024 §6) is an assertion, not a convention (§3c)',
      );
    }
    if (b.actions.isNotEmpty && b.anchors.isEmpty) {
      errors.add(
        'anchor_currency_undeclared: binding "${b.fileClass}" declares '
        'actions but no anchor currency — declare it (§3d)',
      );
    }
    if (b.mapParser != null && (b.subNodePrefix == null || b.subNodePrefix!.isEmpty)) {
      errors.add(
        'map_without_sub_node_prefix: binding "${b.fileClass}" builds a '
        'map but owns no sub-node id prefix — stale map drops would lie '
        'about the tree (§2)',
      );
    }
    final creation = b.fileCreation;
    if (creation != null && b.mapParser == null) {
      errors.add(
        'creation_without_map: binding "${b.fileClass}" declares file '
        'creation but builds no map — creation promises the file node + '
        'content sub-nodes under its binding; register mapParser + '
        'subNodePrefix (build order item 7)',
      );
    }
    if (creation != null &&
        (creation.action.isEmpty || creation.anchorCurrency.isEmpty)) {
      errors.add(
        'creation_declaration_incomplete: binding "${b.fileClass}" '
        'declares file creation without its action name or anchor '
        'currency — declare both (an undeclared creation currency is '
        'the fs-shaped relapse the capability exists to prevent)',
      );
    }
  }
  return errors;
}

/// The validated registry view. First touch runs the §3 linter — a named
/// wiring error is a startup failure, never a silent misattribution.
class MaterializerRegistry {
  MaterializerRegistry() {
    final errors =
        validateMaterializerBindings(materializerBindings.values.toList());
    if (errors.isNotEmpty) {
      throw StateError(
        'materializer registry INVALID (ADR 0035 §3):\n'
        '${errors.join('\n')}',
      );
    }
    _byClass = {
      for (final b in materializerBindings.values) b.fileClass: b,
    };
  }

  late final Map<String, MaterializerBinding> _byClass;

  /// The binding for a stamped `class` prop; null → the class has no edit
  /// actions (its writes route through the review gate — named, never
  /// silent; absence of registration IS the enforcement).
  MaterializerBinding? bindingFor(String fileClass) => _byClass[fileClass];

  /// The sub-node id prefixes of every MAPPED binding — the fs tier's
  /// stale-map drop ownership, derived from the registry (no hardcoded
  /// prefix list, §2). Deduped (several keypath classes share a prefix).
  List<String> get mapSubNodePrefixes {
    final prefixes = <String>{
      for (final b in _byClass.values)
        if (b.mapParser != null) b.subNodePrefix!,
    };
    return prefixes.toList()..sort();
  }
}

final MaterializerRegistry materializerRegistry = MaterializerRegistry();

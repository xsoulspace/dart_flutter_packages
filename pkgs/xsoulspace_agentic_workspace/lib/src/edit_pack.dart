// ignore_for_file: lines_longer_than_80_chars

/// The edit-pack registry (ADR 0035 §4 extraction from span_editor.dart):
/// the built-in pack tables, pack-declared executable registration with
/// `EditExecutableWire` validation, and the trusted-author (authored-body)
/// pack machinery. `SpanEditMaterializer` keeps its public API and
/// delegates here; behavior is byte-identical to the pre-extraction
/// members.
library;

import 'package:agentic_executables_wire/agentic_executables_wire.dart'
    show EditExecutableKind, EditExecutableWire;

import 'span_editor.dart' show SpanEditBounce;

/// The default (built-in) edit executables. Growth is pack/data-driven
/// (ADR 0019 §4 / ADR 0023 §3): never a hand-added core verb. The rename
/// executable lives HERE, as data, exactly so it cannot become a hardcoded
/// core sub-action again (the B4 hard cut).
const defaultEditExecutables = <String, Map<String, dynamic>>{
  'rename_symbol': {
    'scope': 'lexical',
    'atomic': true,
    'args': ['newName'],
    'description':
        'Lexical rename across the refs frontier (whole-identifier '
        'replacement in files that reference the symbol). Bounces on '
        'getters/setters, operators, named constructors and same-name '
        'ambiguity (scope: lexical; analyzer-grade is P4/J3).',
  },
};

/// The pack registry: the pack-declared executables a span editor knows,
/// the op-chains the body-kind executables carry, and the consented
/// authored bodies of trusted-author executables. All state is DATA, per
/// pack — registration is the only write path and it validates the wire.
///
/// Structural class-shape kinds (`add_constructor_param`,
/// `add_enum_case` — trusted-author tier, build order item 8) ride the
/// SAME registry: registration is free (the spec — param name/type/
/// optionality/constructor, case name/args — declares the shape), and
/// CONSENT is separate from the pack: application refuses without a
/// wired consent approver, then the host splices the signature/field/
/// initializer/case byte-precisely with the free-oracle + auto-revert
/// family (realization lives in span_editor.dart).
class EditPackRegistry {
  EditPackRegistry({
    List<EditExecutableWire>? initial,
    bool Function(EditExecutableWire wire, String authoredBodyDiff)? consent,
  }) : _consent = consent {
    for (final e in initial ?? const <EditExecutableWire>[]) {
      executables[e.id] = e;
    }
  }

  /// Registered pack executables, by id (the wire is the declared shape).
  final Map<String, EditExecutableWire> executables = {};

  /// The op-chains a pack's body-kind executables carry (data, per pack —
  /// this is the R7d zero-authored-tokens seam; the wire shape carries the
  /// verification + scope, the chain rides on the same pack entry).
  final Map<String, List<Map<String, String?>>> opChains = {};

  /// The CONSENTED authored bodies of trusted-author pack executables
  /// (data, per pack — registered only through the pack-write consent
  /// gate; the model never sees or authors this text).
  final Map<String, String> authoredBodies = {};

  final bool Function(EditExecutableWire wire, String authoredBodyDiff)?
  _consent;

  /// R7d — registers a pack-declared executable with its (optional) body
  /// op-chain. The chain travels with the PACK as data; the model never
  /// authors it (zero authored tokens for known classes).
  ///
  /// P1 trusted-author tier: [authoredBody] registers an `authored_body`
  /// executable. The registration REQUIRES the pack-write consent gate
  /// (deny-by-default) and the body is presented to it as a unified diff.
  void register(
    EditExecutableWire wire, {
    List<Map<String, String?>>? opChain,
    String? authoredBody,
  }) {
    if (authoredBody != null) {
      if (wire.kind != EditExecutableKind.authoredBody) {
        throw SpanEditBounce(
          'authoredBody given for "${wire.id}" whose kind is '
              '${wire.kind.wire} — only authored_body executables carry '
              'authored bodies',
          'declare the pack entry with kind: authored_body',
        );
      }
      final consent = _consent;
      if (consent == null) {
        throw SpanEditBounce(
          'authored-body executable "${wire.id}" REFUSED: no pack-write '
              'consent gate wired (deny-by-default)',
          'wire SpanEditMaterializer(packConsent:) — a trusted-author body '
              'enters the world only through a consented pack write',
        );
      }
      final diff = authoredBodyDiff(wire.id, authoredBody);
      if (!consent(wire, diff)) {
        throw SpanEditBounce(
          'pack-write consent DENIED for authored-body executable '
              '"${wire.id}" — it was never registered',
          'fix the pack (or re-consent) before applying it',
        );
      }
      authoredBodies[wire.id] = authoredBody;
    }
    executables[wire.id] = wire;
    if (opChain != null) opChains[wire.id] = opChain;
  }

  /// The unified-diff rendering the pack-write consent gate sees: every
  /// line of the authored body as an addition (the body replaces a
  /// member's body span at apply time; the target symbol is per-move and
  /// deliberately NOT part of the consented text).
  String authoredBodyDiff(String id, String body) {
    final lines = body.split('\n');
    return '--- a/pack:$id (authored body)\n'
        '+++ b/pack:$id (authored body)\n'
        '${[for (final l in lines) '+$l'].join("\n")}';
  }
}

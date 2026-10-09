# universal_automation_semantics

The semantic view grammar for the universal automation family
([ADR 0052](../../docs/decisions/0052_semantic_view_grammar.md)): what an
agent's observe/act loop actually reads. Pure Dart over the family
`Snapshot` — no Flutter, no protocol clients. Every tier projects its
native tree (Flutter semantics, macOS AX, AT-SPI, UIA, CDP a11y) into
`AxNode`s and shares this layer, so refs, diffs, and renders mean the
same thing everywhere.

## The layered composition API

One layer per concern, all of them values — the same decomposition
Flutter uses, one level up:

| Layer | Type | Composition |
| --- | --- | --- |
| Declaration | `SemanticView` | const-built, nested (`panes`), builder-refinable |
| Instance | `Observation` | `Observation.of(snapshot, view)` — refs issued, selection applied |
| Read-out | `render()` / `diff()` | text and JSON, managed here |

Both construction directions work everywhere — declare a whole tree in
one expression, or refine iteratively; call a single terminal
observation, or compose views into step trees (in the toolkit:
`observe(view: …)`, `act(..., returnState: true)`, `scope(view, [...])`).

```dart
// Declarative: one const tree, panes nesting views nesting views.
const view = SemanticView(
  maxNodes: 200,
  panes: {'toolbar': SemanticView(subtreeOf: 's_1')},
);

// Iterative: builder refinement of the same value.
final tuned = view.trimmed(50).withPane('list', SemanticView(maxNodes: 40));

// Terminal: one observation, one call.
final observation = Observation.of(await driver.snapshot(), tuned);
final text = observation.render();   // numbered compact text
final delta = observation.diff(last); // +/-/~ rows with stable refs
observation.resolve('s_3');           // fail-closed ref resolution
```

## Invariants

1. **Refs number the full walk** in document order (`s_N`; each pane
   renumbers its own subtree as `<pane>.s_N`). Views, filters, and
   trimming decide what is *shown*, never what is *numbered* — a ref
   read off a filtered or trimmed observation stays valid.
2. **Resolution is not display**: every walked ref resolves; a ref no
   walk issued fails closed with `SemanticRefUnavailableException`
   (reobserve, never guess).
3. **Diffs match by structural signature**, so reflows report no change
   and value changes report as `~` rows carrying the new refs.

## Wire form

`SemanticView.toJson()`/`fromJson()` speak mcp_flutter's
`semantic_snapshot` filter keys (`identifierPrefix`/`subtreeOf`/
`fields`) plus family extensions (`maxNodes`, `panes`) — the same keys
work in plan documents and MCP `automation_observe` arguments.

```json
{"subtreeOf": "s_1", "fields": ["role", "name", "value"], "maxNodes": 120,
 "panes": {"header": {"maxNodes": 5}}}
```

## Producers: projecting a native walk (ADR 0052 full cutover)

A producer's walk stays native; this package owns everything after the
tree exists. For tiers that emit Flutter-shaped node maps
(`type`/`label`/`value`/`bounds`, children as ref lists — mcp_flutter's
`semantic_snapshot` today):

- `snapshotRef(i)` — the one ref dialect (`s_N`, document order);
- `familySnapshotFromNodes(nodes, snapshotId:, capturedAt:)` — the
  projection into the family `Snapshot` (role/name/value/bounds on the
  shared axis, the producer's vocabulary in `attributes`);
- `projectSnapshotNodes(nodes, keep:, fields:)` — the envelope-side
  selection policy (fields projection with `ref` always kept, children
  pruned to kept refs, emptied children dropped).

```dart
final observation = Observation.of(
  familySnapshotFromNodes(emitted, snapshotId: id, capturedAt: now),
  view,
);
```

## Grounding: `nodeAt` (ADR 0053)

`observation.nodeAt(x, y)` answers "which element is at this point"
from the tree's own bounds — the walked node containing the point,
smallest area first (innermost wins), fail-closed with
`SemanticRefUnavailableException` when nothing covers it. Bounds
grounding needs no screenshots; pixel grounding stays client-side.

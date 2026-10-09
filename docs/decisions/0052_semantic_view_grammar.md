# ADR 0052: `universal_automation_semantics` — the family's semantic view grammar

- Status: Accepted (amended 2026-10-08, same day: full mcp_flutter
  cutover; bounds grounding via `nodeAt`; intent view hints)
- Date: 2026-10-08
- North Star impact: `applies`
- Builds on: [ADR 0037](0037_universal_automation_family.md) (family,
  house rules), [ADR 0038](0038_automation_kernel_unification.md)
  (transport-from-engine), [ADR 0046](0046_universal_automation_toolkit.md)
  (the agent surface), and the mcp_flutter `semantic_snapshot` design
  (refs number the full walk; filters only decide what is returned)

## Context

The family's computer-use posture is **semantic-first**: the
accessibility tree is the primary perception channel (text observations,
ref-addressed elements, diffs); screenshots are opt-in enrichment — not
every coding agent renders images, and some route them through vision
services. Two implementations of that posture's core now exist or are
about to:

- mcp_flutter's `SemanticSnapshotService` walks Flutter's semantics tree
  and owns the policy: `s_N` ref issuance, ref-stability under
  filtering, staleness refusal, filter semantics
  (`identifierPrefix`/`subtreeOf`/`fields`), compact envelope.
- `universal_automation_toolkit` needs the same loop economics (refs,
  diffs, `returnState`, trimming) across the CDP/WebDriver/OS tiers.

Writing the second implementation independently forks ref semantics —
two subtly different dialects break agent loops that cross tiers. The
policy layer is pure (no Flutter, no protocol): it consumes the family
`Snapshot` (`AxNode`), which every tier already produces. The pain is
repeated (two consumers now, oka/harness next), and the wire keys are
already a de facto contract with a real consumer (mcp_flutter's filter
JSON). Cross-repo sharing in this ecosystem happens through packages
(mcp_flutter depends on hosted pub deps), so "share the code" requires
a real package.

## Decision

New package `pkgs/universal_automation_semantics` — pure Dart, depends
only on `universal_automation_interface` (+meta). No Flutter, no
protocol clients. **Producers stay native** (Flutter semantics walks in
mcp_flutter, macOS AX, AT-SPI, UIA, CDP a11y); this package owns
everything after the tree exists.

### The layered composition API (values all the way down)

The API mirrors Flutter's own decomposition — declaration, managed
instance, rendering — one layer per concern, all of them values:

| Layer | Type | Flutter analogue | Composition |
| --- | --- | --- | --- |
| Declaration | `SemanticView` | Widget | const-built, nested (`panes`), builder-refinable |
| Instance | `Observation` | Element | `Observation.of(snapshot, view)` — refs issued, selection applied |
| Read-out | `render()` / `diff()` | RenderObject output | text/JSON managed here, never by callers |

Both construction directions work everywhere (the oka terminal-call
posture: every verb is callable alone AND composes into trees):

```dart
// Declarative: one const tree, panes nesting views nesting views.
const view = SemanticView(
  fields: {SemanticField.role, SemanticField.name, SemanticField.value},
  maxNodes: 200,
  panes: {'toolbar': SemanticView(subtreeOf: 's_1')},
);

// Iterative: builder refinement of the same value.
final tuned = view.trimmed(50).withPane('list', SemanticView(maxNodes: 40));

// Terminal: one observation, one call.
final observation = Observation.of(snapshot, tuned);
final text = observation.render();       // numbered compact text
final delta = observation.diff(last);    // +/-/~ rows with stable refs
observation.resolve('s_3');              // fail-closed ref resolution
```

The wire form is one schema across all three faces (Dart composition,
plan documents, MCP arguments) and its selection keys are mcp_flutter's
existing ones (`identifierPrefix`/`subtreeOf`/`fields`), so adoption
there is a dependency bump, not a migration. Family extensions:
`maxNodes`, `panes`.

### Invariants (the contract that makes agent loops portable)

1. **Refs number the full walk** in document order (`s_N`; each pane
   renumbers its own subtree as `<pane>.s_N`). Views, filters, and
   trimming decide what is *shown*, never what is *numbered*.
2. **Resolution is not display**: a ref read off any filtered or
   trimmed observation of a session resolves against that observation's
   full walk; a ref no walk issued fails closed with
   `SemanticRefUnavailableException` — reobserve, never guess.
3. **Diffs match by structural signature** (pane + positional ancestor
   chain + role/name), so reflows report no change and value changes
   report as `~` rows carrying the new refs.

### Toolkit surface (the calling dimension)

The toolkit's plan grammar grows the calling face of the same values —
composition nests the tree AND the call:

- `observe(view: …)` — the report carries the rendered text + ref
  index; `save` stays raw snapshot.
- `act(..., returnState: true)` — the act loop's closing read: state
  rendered into the step result (act + observe in one round trip).
- `scope(view, [steps])` — a view-scoped step tree: opening
  observation, child steps, closing observation with the delta as the
  step's evidence. Declarative and serializable; nested scopes allowed.

MCP mirrors the same keys (`view` object on `automation_observe`,
`returnState` on `automation_act`, per-session last observation for
`diff`), so agents get the whole loop over the existing six-tool
surface.

## Consequences

- One ref dialect family-wide; conformance-grade goldens
  (`test/semantics_test.dart`) travel with the package, and every tier
  inherits the loop economics without touching its driver.
- `universal_automation_interface` stays contracts-only; rendering and
  diffing change at product speed without republishing the contracts.
- intentcall stays the WHAT (declared intents); this package is the HOW
  of perception. The composition point landed: intent hints carry
  **view hints** — an optional `view` key in the family grammar
  verbatim on `IntentHint`; the runner observes through it after
  dispatch, so an app declares how its effect should be read. The
  dependency points this way (hints reference the grammar), never the
  reverse.

## Non-claims

- Diff matching is identifier-keyed where tiers expose identifiers
  (reordering identified siblings reports no change); the positional
  chain remains the fallback for identifier-less nodes, where reordered
  identical siblings can still alias.
- mcp_flutter adoption completed the same day: the **full cutover**
  landed — [familySnapshotFromNodes], the ref dialect ([snapshotRef]),
  and the node-map selection policy ([projectSnapshotNodes]) live in
  this package; mcp_toolkit keeps only the Flutter mechanism (the
  semantics walk, visibility metadata, the staleness contract, and the
  gesture caches). Its published envelope keys are unchanged — the
  cutover is internal, proven by their untouched contract tests. The
  dependency stays a local path dep until the package publishes (an
  owner-gated step); the `fields` dimension's node keys stay
  Flutter-shaped (`label`, `hint`) by the same producer-stays-native
  rule — the policy is shared, the vocabulary is the producer's.
- No coordinate actions here (ADR-first, family-wide verb growth —
  landed as ADR 0053).
- Bounds-based coordinate grounding **landed** as
  `Observation.nodeAt(x, y)`: the walked node whose bounds contain the
  point, smallest area first, fail-closed on a miss. This reads the
  tree's own geometry — no screenshots. Pixel grounding (screenshot →
  coordinates) stays a client-side concern.
- Screenshots ride as **opt-in image content blocks**
  (`automation_screenshot` with `image: true`; `maxPx` caps the long
  side, window-scoped capture on the OS tier). The semantic channel
  stays primary; agents that do not render images never receive them
  unprompted.

## Falsifier

If within a quarter only the toolkit adopts the package (mcp_flutter
never bumps), and the layer stabilizes into two or three pure
functions, demote it back into the toolkit or the interface package —
one package fewer. The demotion stays cheap precisely because the
package is small, Flutter-free, and has no plugin seams. (The full
cutover — mcp_toolkit building its envelope through this package —
resets that clock: two repos now ship on it.)

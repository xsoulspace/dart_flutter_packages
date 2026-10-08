# ADR 0053: Coordinate pointer verbs — `clickAt`/`moveTo`/`drag`, MoE-lowered from day one

- Status: Accepted
- Date: 2026-10-08
- North Star impact: `applies`
- Builds on: [ADR 0037](0037_universal_automation_family.md) (family,
  house rules), [ADR 0044](0044_behavior_dynamics_contract.md) (behavior
  profiles and receipts — the MoE layer),
  [ADR 0045](0045_flutter_web_driving_primitives.md) (real-Chromium
  driving primitives), [ADR 0052](0052_semantic_view_grammar.md) (the
  semantic-first ordering these verbs sit at the bottom of)

## Context

The semantic-first computer-use posture (ADR 0052) keeps coordinates as
the **last** fallback tier: the accessibility tree is the primary
channel, and coordinates exist for surfaces no tree can see — canvas,
games, Electron content — and for pixel-grounded agents. Until now the
family had no coordinate verbs: `ClickAction` is locator-only, so those
surfaces dead-ended.

The universal verbs are a family-wide release by design (every driver's
`perform` switch, the behavior synthesizer, plan documents, MCP, CLI,
and conformance all compile against the sealed set) — the growth
decision needs an ADR, not a patch. The one already-proven coordinate
primitive, `CdpPage.clickAt`, was private to the CDP tier's semantic
clicks; the MoE layer (ADR 0044) lowered only locator clicks.

## Decision

Three actions enter the sealed `AutomationAction` set, capability-gated
under a new `DriverCapabilities.pointerCoordinates` (default **false**;
drivers without the capability refuse loudly with
`DriverUnsupportedException`):

- `ClickAtAction(x, y, {button: 'left', clickCount: 1})` — click at
  surface coordinates; `clickCount` 2 = double-click, 3 = triple.
- `MoveAction(x, y)` — pointer move without pressing (hover
  affordances, drag pre-positioning).
- `DragAction(fromX, fromY, toX, toY, {button})` — press, carried move,
  release.

**MoE lowering from day one** (the core of this decision): the ADR 0044
synthesizer lowers the new verbs through the same humanized pipeline as
locator clicks — lead dwell, bezier approach (curvature allowed to
depart near the from-point; the landing point is exact), button-hold
timing, multi-press cadence. A drag is a *gesture*, not a teleport with
the button held: the carried path animates through the profile's
segments, and receipts cover the whole dispatch. `PointerDownStep`/
`PointerUpStep` gain `clickCount` so double-clicks survive profiled
delivery. A plain (agent-immediate) dispatch is the degenerate profile:
one move, one press, one release.

Tier coverage in this wave: **CDP implemented** (`Input.dispatchMouseEvent`
primitives `clickAt`/`movePointerTo`/`dragAt` — the same primitive the
live-proven semantic clicks already used, now public). macOS (CGEvent
pointer extension in the native bridge), WebDriver (W3C pointer
actions), Linux AT-SPI and Windows UIA (synthetic input) **refuse
loudly** until wired — the capability flag makes that checkable before
attach.

Surfacing mirrors ADR 0046/0052: plan verbs `clickAt`/`moveTo`/`drag`
(round-trippable documents), MCP `automation_act` actions + parameters,
CLI `--click-at x,y` / `--move-to x,y` / `--drag x1,y1,x2,y2` with
`--button`/`--click-count`.

## Consequences

- Canvas/game/pixel-grounded surfaces are reachable on the browser tier
  today; OS tiers light up as their native extensions land.
- Every profile applies to coordinate dispatch for free — no retrofit:
  `humanPrior` drags carry bezier paths, and behavior receipts record
  the full gesture (predicted-vs-observed for pixel-tier automation).
- The sealed-set release forced all drivers, the synthesizer, and the
  toolkit to decide loudly — no silent degradation anywhere.

## Non-claims

- macOS/WebDriver/AT-SPI/UIA implementations are future waves (the
  capability flag is the contract; the refusals are loud today).
- Keyboard modifier chords (`Cmd+click`) are not in this wave; the
  `button` axis is pointer-only. Modifier composition is its own
  decision once key coverage grows.
- No pixel *grounding* here: these verbs take coordinates from the
  caller (a vision model or a view's bounds). Turning screenshots into
  coordinates stays a client-side concern.
- `clickCount > 3` is clamped to 3 (the transport's triple-click).

## Falsifier

If canvas/game surfaces keep being driven through `invoke` actions and
evaluate-expressions instead of the coordinate verbs (agents prefer
in-page handlers), the verbs are demotable — remove them before the
closed set ossifies. The usage signal to watch: coordinate-verb share
in runs where the surface advertises no accessibility tree.

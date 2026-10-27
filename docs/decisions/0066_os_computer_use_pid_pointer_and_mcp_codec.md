# ADR 0066: OS computer-use pid pointer and MCP codec

Date: 2026-10-27
Status: Accepted and implemented (2026-10-27)
Related: 0065 (window-local semantic pointer), 0064 (background actuation),
0053 (coordinates), UA ADR 0003 (tier routing), UA ADR 0005 (consent)

## Context

Models trained on OpenAI-style computer use emit screenshot →
`click(x,y)` / `type` / `scroll` in **image pixel space** against a bound
surface. Universal Automation already captured window PNGs and preview
streams (ADR 0065) but delivered pointer through global HID or semantic
`AXPress`. Keyboard already used `CGEvent.postToPid`; pointer and scroll
needed the same shape for background, non-activating actuation.

## Decision

1. **Pid-scoped pointer and scroll (macOS).** Window-local coordinates map
   to screen space, then mouse and scroll events post to the anchored pid
   (`postToPid`). Global HID pointer remains for foreground screen
   coordinates only.
2. **Semantic vs pixel paths.** `ClickAtAction` with `windowId` defaults to
   semantic hit-test (`AXPress`, ADR 0065). `pixelInjection: true` selects
   the computer-use lane.
3. **MCP `automation_computer`.** Single tool with `action` discriminant
   matching the trained computer vocabulary plus `bind`/`unbind`. Screenshots
   return `width`, `height`, `scale`, and an image block by default.
4. **Consent.** Screen Recording and Accessibility use the existing
   `xsoulspace_permission_core` / `automation_request_consent` stack; typed
   refusals include a remedy, not a second consent product.
5. **Gates.** Dart `dart test`, compose/plan steps, and a live
   `computer_use_parity_probe.dart` — no new shell `gate_*.sh` wrappers.
6. **Non-claims.** Built-in vision/OCR to locate widgets in PNGs; Windows/Linux
   pid pointer; silent HID fallback when pid delivery fails; CDP required for
   computer use.

## Consequences

- Swift: `xs_axdrv_pointer_{move,button}_pid`, `xs_axdrv_scroll_pid`.
- Dart: `pixelInjection` on `ClickAtAction`; `windowCaptureFrame` scale meta.
- MCP: `automation_computer`; `computerUse` in `automation_capabilities`.
- UA local ADR 0008 records package-level wiring.

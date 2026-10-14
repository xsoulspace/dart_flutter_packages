# intentshow — the intentcall verification matrix

What works, what breaks, and how this file proves it. Re-run:

```bash
# Chrome headless with a debug port:
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
  --remote-debugging-port=9333 --user-data-dir=/tmp/uat-chrome about:blank &
cd pkgs/universal_automation_toolkit && dart run example/intentshow_plan.dart
```

## The chain under test

```
intentcall_mcp publish adapter          universal_automation_toolkit
{driver, action, locator} under  ─────►  IntentRegistry.fromMcpToolsList
_meta['dev.intentcall/automation']       → intent: steps → driver → surface
```

- **Layer 1 (contract goldens)** — `test/intentcall_contract_test.dart`:
  the toolkit parser against intentcall's own serialization cases
  (round-trip, pre-action→click, unknown-action→null, string coercion,
  custom-requires-`locator.name`) plus the `mcp_publish_adapter`
  projection golden (`app_buy_item`). 8/8 green.
- **Layer 2 (real producer payload)** — the projection shape is taken
  from intentcall_mcp's own adapter test, and the REAL server payload
  is captured and ingested: `showcase/fmt-tools.capture.json` —
  flutter_mcp_toolkit_server's live `tools/list` (34 tools, static
  catalog, zero hints — hints flow on dynamic client tools registered
  by an instrumented app). `test/intentcall_contract_test.dart`
  ingests the real file end-to-end.
  Investigated dead end (recorded so nobody re-chases it): the built
  fmt server appears to never answer `initialize` — but that is an
  artifact of a `printf | server` harness: printf exits, stdin hits
  EOF, `StreamChannel.withCloseGuarantee` fires shutdown mid-handshake,
  and json_rpc_2 drops the response (`if (!isClosed)`). With stdin held
  open — what every real MCP client does — the server handshakes
  normally. Verified with a minimal dart_mcp server (answers fine) and
  a held-open-stdin python client (full handshake + capture).
- **Layer 3 (semantic, live over real Chrome)** —
  `example/intentshow_plan.dart` drives the matrix below and
  self-verifies: works steps must pass, known-breaks must fail with the
  expected error kind; mismatch exits 1.

## The matrix (from `showcase/last-run.json`)

| # | Step (intent) | Verdict | Detail |
| --- | --- | --- | --- |
| 0–1 | navigate + wait heading | ✓ works | CDP tier |
| 2–3 | `page_fill_email` (type + invocation text) → value check | ✓ works | runtime args carry the operand |
| 4–5 | `page_buy` (semantic click by accessible name) → status | ✓ works | snapshot + live-DOM click ladder |
| 6–7 | `page_checkout` (custom → `window.__mcpActions.checkout`) | ✓ works | catalog invoke with args (`checked-out:SKU-1` observed) |
| 8–9 | `page_stamp` (evaluate) → verify | ✓ works | expression from locator |
| 10–12 | re-fill + `page_submit_email` (key Enter) → verify | ✓ works | OS-focus-safe caret path + key |
| 13 | `page_ghost_click` (no such button) | ✗ breaks **as designed** | `elementNotFound` — locator refuses loudly |
| 14 | `page_ghost_invoke` (no such catalog action) | ✗ breaks **as designed** | `protocol` — page-level rejection surfaced |
| validate | `page_fill_email` without args | ✗ refused **as designed** | `missing required parameter 'text'` — before anything runs |

Data files: `intentshow.capture.json` (captured-shape tools payload),
`intentshow.snapshot.json` (exported plan snapshot via `planDocument`),
`last-run.json` (the runner report = this matrix, machine-checked).

## Non-claims

- The capture file is projection-**shaped** (mirroring the adapter's
  tested output); a capture from a live intentcall-instrumented Flutter
  app is pending on the fmt-server initialize issue above.
- The Flutter JIT tier's `ToolkitDriver` (driver `toolkit` hints) binds
  via composition-root injection — not exercised in this Chrome-only
  matrix.

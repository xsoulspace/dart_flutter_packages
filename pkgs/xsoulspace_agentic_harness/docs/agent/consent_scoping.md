# Consent Scoping — actor-scoped consent plans (spec + law)

- Status: Accepted (build order item 4; prerequisite for ALL multi-actor work)
- Date: 2026-09-08
- Code: [lib/src/tooling/consent_scoping.dart](../../lib/src/tooling/consent_scoping.dart)
  · Gate: [test/consent_scoping_test.dart](../../test/consent_scoping_test.dart)
- Builds on: R9.1 workspace consent (`.harnessd/consent.json`), ADR 0009
  (monotonic budgets), ADR 0027 (reads are not builds; consent plans as the
  ADR 0027 amendment), pipeline_coding.md § The mechanical tier.

## The law

1. **Consent is a WRITING property.** It answers exactly one question —
   *may this actor apply this verb to this path?* — and nothing else.
2. **Tier profiles are READING properties.** Orthogonal, by construction:
   a consent plan never widens what an actor can READ (zoom/scan/impact
   are governed by the meaning profile, not consent), and a tier profile
   never grants a WRITE (the trusted-author tier still routes every pack
   write through consent).
3. **Deny-by-default, always NAMED.** Every non-grant returns one of
   `noPlan / wrongActor / scopeMiss / verbMiss / exhausted / expired` —
   never a silent refusal, never a silent fallback. Malformed schema
   raises `ConsentPlanError` with a stable machine-readable `code`.
4. **A plan is bounded.** `maxUses` is a hard cap (monotonic budgets,
   ADR 0009) and `ttl` lapses against an injected clock. Consent is a
   grant, never an capability upgrade.
5. **Actor isolation.** One actor's grant never covers another. Each
   actor sees only its own audit rows.

## Schema

### v2 (actor-scoped)

```json
{
  "planId": "p-a",
  "actor": "actor-a",
  "scopePathGlob": "^pkgs/a/",
  "verbs": ["write", "edit"],
  "maxUses": 50,
  "ttlSeconds": 3600,
  "grantedAt": "2026-09-08T10:00:00Z"
}
```

| field           | required | meaning                                                                 |
|-----------------|----------|-------------------------------------------------------------------------|
| `planId`        | yes      | unique within a ledger; duplicate registration is a named error          |
| `actor`         | yes      | grant owner; `*` is the documented workspace fallback (see precedence)   |
| `scopePathGlob` | yes      | REGEX over workspace-relative paths (`hasMatch` — v1 semantics kept; the name `pathGlob` survives only in v1 documents) |
| `verbs`         | no       | default `{write, edit}`; also `pack_write` (trusted-author tier)         |
| `maxUses`       | no       | default `50`; non-negative; the ledger decrements on each grant          |
| `ttlSeconds`    | no       | omit = never expires; positive integer                                   |
| `grantedAt`     | yes      | ISO-8601; `ttl` is enforced against `grantedAt + ttl` vs the supplied clock |

### v1 (legacy, workspace-scoped) — backward compatible

```json
{ "pathGlob": "^(pkgs|docs)/", "verbs": ["write", "edit"], "maxUses": 50 }
```

A v1 object (NO `actor` field) parses as the **documented legacy
workspace fallback**: `actor = '*'`, no ttl, `grantedAt` = the caller's
`legacyGrantedAt` (or the wall clock). This is a named, tested path — not
a heuristic: any v2 key present but incomplete is a NAMED error
(`missing_planId` etc.), never a v1 fallback.

### Named error codes

`not_an_object`, `missing_<field>` (non-empty string required),
`missing_scope` (neither `scopePathGlob` nor `pathGlob`), `bad_verbs`,
`bad_max_uses`, `bad_ttl`, `bad_granted_at`, `bad_scope_regex`
(malformed regex at registration), `bad_plans` (document `plans` not an
array), `duplicate_plan_id`.

### Document shape

`parseConsentPlanDocument` accepts a single plan object (v1 or v2) or
`{"plans": [...]}` — the v2 document carries the workspace `*` fallback
and per-actor plans **side by side**.

## Precedence (the routing law)

Evaluated per (actor, verb, path) by `ConsentLedger.matches`:

1. **Explicit actor plans first**, in registration order; the first
   GRANT wins and decrements that plan's use counter.
2. **The `*` fallback never widens an explicit actor's deny.** If the
   actor has explicit plans and none grants, the deny stands — the
   fallback is not consulted.
3. **Only an actor with no explicit plan falls through** to the `*`
   workspace tier (legacy v1 semantics; the fallback plan's id IS `*`,
   so its use counter is the shared workspace budget).
4. No plan at all → `noPlan`. Denies consume nothing; grants decrement
   exactly one counter.

## Evaluation contract (pure)

`ConsentPlan.evaluate({actor, verb, path, remainingUses, now})` is a pure
function — no mutation, no clock access, no I/O. The ledger supplies
`remainingUses` and `now`, making the stateful surface (counters, audit
append) testable with an injected `ConsentClock`.

Check order per plan: `wrongActor` → `scopeMiss` → `verbMiss` →
`exhausted` → `expired` → `granted`.

## Audit

`ConsentAuditEntry {actor, verb, path, decision, timestamp}` — keyed by
actor, append-only, never rewritten or removed. `ledger.auditFor(actor)`
projects one actor's rows; `auditFor` never leaks another actor's rows
(gate-tested). Out-of-band outcomes (a human approver's answer) land in
the SAME log via `ledger.auditAppend`.

## Integration hooks (where the backend calls in, once lanes merge)

The model is wired to nothing today. The backend (host lane's
`harness_acp_backend.dart`) already consults a workspace plan at these
exact points; each becomes a one-line `ledger.matches(...)` call with the
session's actor id:

| host site today | hook |
|---|---|
| `ConsentPlan.forWorkspace(workspace)` — loads `<ws>/.harnessd/consent.json` at session creation (`setConsentPlan`) | `parseConsentPlanDocument(jsonDecode(...))` + `ledger.addPlan` per plan; the per-session actor id replaces `session.consentPlan`/`consentPlanUses` |
| write_review approver (R9.1 consent inheritance, `harness_acp_backend.dart` ~L689) | `ledger.matches(actor: sessionActor, verb: 'write', path: write.relativePath)` |
| `planAllows(path, kind)` — span-edit approver (~L1017) | `ledger.matches(actor: ..., verb: 'edit', path: ...)` |
| `packConsent(wire, diff)` — trusted-author pack tier (~L1043) | `ledger.matches(actor: ..., verb: 'pack_write', path: '.dart_tool/harnessd/edit_pack.json')` |
| `session.consentLog.add(...)` lines | superseded by the structured `ConsentAuditEntry` rows (`ledger.audit`); `auditAppend` carries human approver answers |

A single `ConsentLedger` per daemon process (or per world) gives all
workers in that world shared budgets and one audit log; per-session
ledgers keep today's isolation — both work unchanged.

## Non-claims

- ~~Not wired~~ **WIRED 2026-09-09** (the consent-integration lane): the
  daemon's consent paths (write_review approver, `planAllows`,
  `packConsent`, the mechanical-edit approver) route through
  `ConsentLedger.matches(actor: session.consentActor, verb, path)`; every
  answer lands as an actor-keyed `ConsentAuditEntry` (structured
  `consent-row {…}` JSON in `consentLog`, legacy phrases preserved). The
  actor id is `sessionConsentActor(cwd)` = `harnessd@<workspace-path>`
  (stable per workspace, distinct across workspaces). Mechanical actors
  source their deny-by-default callback via `consentFromLedger`.
  Gates: `consent_integration_gate_test.dart` (8) +
  `harnessd_consent_scoping_test.dart` (4). STILL OPEN: v2 document
  auto-load at session creation (v1 auto-apply unchanged; v2 loads via
  the explicit `setSessionConsentDocument`), audit persistence (the
  ledger stays in-memory per session).
- No reading-side effect: consent never widens reads (law §2) — tier
  profiles are untouched.
- `scopePathGlob` is regex, not glob syntax, despite the historical name
  (v1 wire compatibility; semantics unchanged from the host's
  `RegExp(pathGlob).hasMatch`).

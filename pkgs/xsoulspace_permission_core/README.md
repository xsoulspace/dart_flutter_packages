# xsoulspace_permission_core

Composable permission contract shared across products — the typed
vocabulary and decision algebra, transport-free by design.

## Why

Every product in the ecosystem was growing its own permission dialect:
Last Answer's chat stance policy, the agentic host's deny-by-default
consent gate, future OS-consent and model-gate rungs. The concepts were
the same; the words were not. This package is the shared contract:

- **Requests** — one record (`PermissionRequest`) every transport
  adapts to at its edge.
- **Decisions** — `allow` / `deny` / **`escalate`**. The third verb is
  the unifying addition: a decider that holds no authority says so,
  and the request moves UP (user, paired peer, OS dialog, model gate)
  instead of being silently answered.
- **Composition** — policies are total, pure functions; chains are
  first-match; the `PermissionGate` runner denies anything still
  escalated when no consent authority exists. Deny-by-default is
  structural, not a policy someone must remember to install.

## Shape

```dart
final gate = PermissionGate(
  policies: [
    GrantPolicy(store),                            // recorded allowances first
    PermissionStance.workspaceEdits.policy(),      // the working set
  ],
  onEscalate: (request) => myConsentSurface(request), // user, peer, OS, model
);

final decision = await gate.resolve(request);
```

## Consumers

- **Last Answer** — `ChatPermissionPolicy` (ask / WS-edits / full)
  delegates its decision to `PermissionStance.policy()`; the doc
  router and ACP round-trip stay product-side.
- **agentic host** — the consent gate names its request kinds through
  `PermissionKind` and projects the pending kind to the fleet.
- The **model gate** rung (a local decision model answering
  escalations) composes as one more policy — an authority question its
  own ADR settles first.

## Laws

1. Deny-by-default: silence denies; only an explicit allow grants.
2. Escalate is not a soft deny — it carries no verdict.
3. `once` grants are single-use, by store law, not discipline.
4. Kinds are a closed, growing vocabulary — parse by name, never
   exhaustive-switch without a default.

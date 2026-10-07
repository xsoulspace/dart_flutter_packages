# Changelog

## 0.1.0

- Initial release: `PermissionKind`, `PermissionRequest`, `PermissionDecision`
  (allow / deny / **escalate**), `PermissionStance`, `PermissionPolicy`,
  composable policies (`AllowAllPolicy`, `KindAllowlistPolicy`,
  `GrantPolicy`, `FirstMatchPolicy`), `PermissionGrantStore` +
  `InMemoryPermissionGrantStore`, and the `PermissionGate` runner whose
  missing escalation sink denies by default.

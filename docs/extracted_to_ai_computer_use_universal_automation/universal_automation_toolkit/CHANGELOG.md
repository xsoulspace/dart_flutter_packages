# Changelog

## 0.1.0

- Initial release: declarative plans (sessions/profiles/intents/
  scenarios, `extends` + `include` composition, fail-closed validation),
  the plan runner with structured reports and ADR 0044 behavior
  receipts, the `universal-automation` CLI (observe/act/verify/
  screenshot/validate/run/serve), and the MCP stdio server
  (`automation_observe/act/verify/screenshot/validate_plan/run_plan`).
- v1 links the CDP tier; other transports fail loudly until linked
  (ADR 0046).

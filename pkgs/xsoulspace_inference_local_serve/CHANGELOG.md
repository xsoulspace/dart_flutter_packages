# Changelog

## 0.1.0

- Initial version: shared local-provider serve core extracted from the laya
  serve runtime — `LocalServeRuntime` (health-gated loopback, attach-only or
  spawnOnMiss, honest readiness, health deadlines, content-free diagnostics),
  `ManagedServeProcess`/`ServeProcessStarter` lifecycle, `LocalHealthProbe`
  one-shot probe, and the `LoopbackJsonServer` pure-Dart wire skeleton.

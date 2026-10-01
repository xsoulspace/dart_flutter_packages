# Changelog

## 0.1.1

- interface constraint bump to ^0.2.0.
- `KeyPressAction` actually presses keys (the wire-key mapping was dead
  code after an unconditional throw); unknown keys refuse with the
  supported set named.
- `no such element` envelopes map to `ElementNotFoundException`
  (surface state) instead of `DriverUnsupportedException`.

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.0 - 2026-09-27

### Added
- feat: WebDriver BiDi — `WebDriverBidiConnection`/`WebDriverBidiSession`
  (subscribe, context tree, navigate, evaluate, live events) over the
  `webSocketUrl` a new-session response advertises, plus fake-server
  BiDi coverage.

- feat: `WebDriverClient` — W3C classic sessions, navigation, elements,
  clicks, typing, key actions, screenshots.
- feat: `WebDriverDriver` adapter with honest `a11yTree: false`.
- feat: `SafariDriverEndpoint` — `safaridriver` spawn + `/status` wait.
- feat: `FakeWebDriverServer` test double
  (`package:universal_browser_webdriver/testing.dart`).

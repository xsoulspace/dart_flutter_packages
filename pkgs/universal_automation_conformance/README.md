# universal_automation_conformance

Conformance suites proving `AutomationDriver`, `FrameSource`, and
`FrameSink` implementations are swappable. Adoption is one call, exactly
like `universal_storage_conformance`:

```dart
void main() {
  automationDriverConformanceTests(
    'CdpDriver over FakeCdpServer',
    createDriver: () async {
      final server = FakeCdpServer();
      final base = await server.start();
      final session = await CdpBrowserSession.attach(base);
      return session.driver;
    },
  );

  frameSourceConformanceTests(
    'PollingFrameSource',
    createSource: () async => PollingFrameSource(grab),
  );

  frameSinkConformanceTests(
    'WebSocketFrameServer',
    createSink: () async {
      final sink = WebSocketFrameServer();
      await sink.start();
      return sink;
    },
  );
}
```

A backend that does not pass its suite is not swappable; fix the backend
before shipping an adapter.

## Non-claims

- The suites exercise contracts, not protocol conformance: CDP wire
  semantics are covered by `universal_browser_cdp`'s own tests.

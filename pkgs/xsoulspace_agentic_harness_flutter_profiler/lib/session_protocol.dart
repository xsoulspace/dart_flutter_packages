/// ADR 0009 (D3) — the PURE-DART entry point of the profiler protocol
/// layer: the headless reader over the session registry.
///
/// This sub-barrel exists so a headless consumer (daemon driver, agent,
/// test) imports the protocol WITHOUT the Flutter widget barrel — the
/// import graph of this library contains no Flutter at all. Flutter panes
/// may import it through the main barrel instead.
library;

export 'src/session_protocol.dart';

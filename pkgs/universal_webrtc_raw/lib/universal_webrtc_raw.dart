/// Raw client for the `xs-webrtc-sidecar/1` wire protocol.
///
/// The sidecar (see `rust/webrtc_sidecar/` in this package) wraps the
/// webrtc-rs engine behind JSON-lines stdio: one handshake line, then
/// correlated requests/responses plus asynchronous events. This package
/// is deliberately *raw* — it speaks the wire and supervises the process;
/// session-level meaning (signaling, frame semantics) lives in
/// `universal_webrtc`.
library;

export 'src/sidecar_client.dart';
export 'src/sidecar_exceptions.dart';
export 'src/sidecar_transport.dart';

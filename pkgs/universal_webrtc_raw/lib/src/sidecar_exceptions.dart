import 'package:meta/meta.dart';

/// The sidecar answered with an error response or broke the protocol.
@immutable
class SidecarException implements Exception {
  /// Creates the exception.
  const SidecarException(this.message, {this.details = const {}});

  final String message;
  final Map<String, Object?> details;

  @override
  String toString() => details.isEmpty
      ? 'SidecarException: $message'
      : 'SidecarException: $message $details';
}

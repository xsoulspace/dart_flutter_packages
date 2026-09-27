import 'package:meta/meta.dart';

/// Base class of all family exceptions: a stable message, a machine-readable
/// [kind], and structured details agents can classify without parsing prose.
@immutable
class AutomationException implements Exception {
  /// Creates the exception.
  const AutomationException(this.message, {this.details = const {}});

  /// Machine-readable category (`automation`, `specViolation`, …).
  String get kind => 'automation';

  /// Human-readable message.
  final String message;

  /// Structured details; never contains payload bytes.
  final Map<String, Object?> details;

  @override
  String toString() {
    if (details.isEmpty) return '$kind: $message';
    return '$kind: $message $details';
  }
}

/// A typed spec failed fail-closed validation before anything ran.
@immutable
class SpecViolationException extends AutomationException {
  /// Creates the exception from the collected violations.
  SpecViolationException(this.violations)
    : super(
        'spec rejected: ${violations.join('; ')}',
        details: {'violations': violations},
      );

  @override
  String get kind => 'specViolation';

  /// Every violation found; the composition did not start.
  final List<String> violations;
}

/// A driver was asked to perform something its capability set excludes.
@immutable
class DriverUnsupportedException extends AutomationException {
  /// Creates the exception.
  const DriverUnsupportedException(super.message);

  @override
  String get kind => 'driverUnsupported';
}

/// The endpoint did not answer or answered with an unexpected identity.
@immutable
class EndpointUnreachableException extends AutomationException {
  /// Creates the exception.
  const EndpointUnreachableException(super.message, {super.details});

  @override
  String get kind => 'endpointUnreachable';
}

/// A protocol-level error response came back from the endpoint.
@immutable
class ProtocolException extends AutomationException {
  /// Creates the exception.
  const ProtocolException(super.message, {this.code, super.details});

  @override
  String get kind => 'protocol';

  /// Protocol error code, when the protocol numbers its errors.
  final int? code;
}

/// A frame sink was used after close — always a programming error.
@immutable
class SinkClosedException extends AutomationException {
  /// Creates the exception for sink [sinkId].
  const SinkClosedException(this.sinkId)
    : super('sink "$sinkId" was used after close');

  @override
  String get kind => 'sinkClosed';

  /// Identifier of the closed sink.
  final String sinkId;
}

/// A locator matched no node in the driver's latest observation.
///
/// Distinct from [DriverUnsupportedException]: the operation is supported,
/// the surface just does not contain the requested element right now.
/// Retrying after a fresh [AutomationDriver.snapshot] is meaningful.
@immutable
class ElementNotFoundException extends AutomationException {
  /// Creates the exception for [locatorValue] under [locator].
  const ElementNotFoundException(this.locator, this.locatorValue)
    : super('no node matches $locator "$locatorValue"');

  @override
  String get kind => 'elementNotFound';

  /// Locator kind that did not match (`ref`, `name`, `role`, `css`).
  final String locator;

  /// Locator value that did not match.
  final String locatorValue;
}

import 'package:universal_automation_interface/universal_automation_interface.dart';

/// The native bridge failed with an error code.
class CaptureBridgeException extends AutomationException {
  /// Creates the exception.
  CaptureBridgeException(super.message, {this.code, super.details});

  @override
  String get kind => 'captureBridge';

  /// Native error code (see the Swift bridge docs for the table).
  final int? code;
}

/// Screen recording is not yet permitted for this process.
class CapturePermissionDeniedException extends AutomationException {
  /// Creates the exception with a remediation path in the message.
  CapturePermissionDeniedException()
      : super(
          'screen recording permission missing; call '
          'CaptureBridge.requestScreenPermission() as an explicit '
          'user action, or grant it in System Settings',
        );

  @override
  String get kind => 'capturePermissionDenied';
}

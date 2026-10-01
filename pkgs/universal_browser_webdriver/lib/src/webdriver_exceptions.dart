import 'package:universal_automation_interface/universal_automation_interface.dart';

/// A WebDriver error envelope came back (`value.error`).
class WebDriverException extends ProtocolException {
  /// Creates the exception from an error envelope.
  WebDriverException({
    required String error,
    required String message,
    int? httpStatus,
  }) : super(
         message,
         code: httpStatus,
         details: {
           'error': error,
           'status': ?httpStatus,
         },
       );

  /// Maps a W3C error string onto the family exception hierarchy.
  static Object fromEnvelope(String error, String message, int httpStatus) {
    switch (error) {
      case 'no such element':
        // A missing element is a surface state, not an unsupported
        // operation; the wire envelope carries no locator context.
        return ElementNotFoundException('unspecified', message);
      case 'no such window':
      case 'no such alert':
        return DriverUnsupportedException('$error: $message');
      case 'session not created':
      case 'invalid session id':
        return EndpointUnreachableException(
          '$error: $message',
          details: {'error': error},
        );
      default:
        return WebDriverException(
          error: error,
          message: message,
          httpStatus: httpStatus,
        );
    }
  }
}

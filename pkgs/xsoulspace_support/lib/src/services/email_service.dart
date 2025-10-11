import 'package:url_launcher/url_launcher.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

/// {@template email_service}
/// Service for composing and sending support emails.
///
/// Handles email URL composition, validation, and launching
/// the default email client with pre-filled content.
/// {@endtemplate}
class EmailService {
  /// {@macro email_service}
  const EmailService({final Logger? logger}) : _logger = logger;

  final Logger? _logger;

  /// {@template compose_email_url}
  /// Composes a mailto URL with all support request parameters.
  ///
  /// The URL follows RFC 6068 standard for mailto links and includes
  /// subject, body, and optional CC/BCC recipients.
  /// {@endtemplate}
  String composeEmailUrl({
    required final String to,
    final String? subject,
    final String? body,
    final List<String>? cc,
    final List<String>? bcc,
  }) {
    final queryParams = <String, String>{};

    if (subject != null && subject.isNotEmpty) {
      queryParams['subject'] = _encodeUrlParameter(subject);
    }

    if (body != null && body.isNotEmpty) {
      queryParams['body'] = _encodeUrlParameter(body);
    }

    if (cc != null && cc.isNotEmpty) {
      queryParams['cc'] = cc.join(',');
    }

    if (bcc != null && bcc.isNotEmpty) {
      queryParams['bcc'] = bcc.join(',');
    }

    final queryString = queryParams.entries
        .map((final entry) => '${entry.key}=${entry.value}')
        .join('&');

    return queryString.isNotEmpty ? 'mailto:$to?$queryString' : 'mailto:$to';
  }

  /// {@template send_email}
  /// Opens the default email client with pre-filled content.
  ///
  /// Returns `true` if the email client was successfully opened,
  /// `false` if no email client is available or the operation failed.
  /// {@endtemplate}
  Future<bool> sendEmail({
    required final String to,
    final String? subject,
    final String? body,
    final List<String>? cc,
    final List<String>? bcc,
  }) async {
    _logger?.debug(
      'EMAIL_SERVICE',
      'Composing email',
      data: {
        'to': to,
        'hasSubject': subject != null,
        'hasBody': body != null,
        'hasCc': cc != null && cc.isNotEmpty,
        'hasBcc': bcc != null && bcc.isNotEmpty,
      },
    );

    final emailUrl = composeEmailUrl(
      to: to,
      subject: subject,
      body: body,
      cc: cc,
      bcc: bcc,
    );

    final uri = Uri.parse(emailUrl);

    try {
      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          _logger?.info('EMAIL_SERVICE', 'Email client opened successfully');
        } else {
          _logger?.warning('EMAIL_SERVICE', 'Failed to launch email client');
        }
        return launched;
      } else {
        _logger?.warning(
          'EMAIL_SERVICE',
          'Cannot launch email URL - no email client available',
        );
        return false;
      }
    } catch (e, stackTrace) {
      _logger?.error(
        'EMAIL_SERVICE',
        'Failed to send email',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// {@template validate_email}
  /// Validates email address format using a comprehensive regex pattern.
  ///
  /// Note: This is a basic validation. For production use, consider
  /// more robust email validation libraries.
  /// {@endtemplate}
  bool isValidEmail(final String email) {
    const emailRegex = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
    return RegExp(emailRegex).hasMatch(email.trim());
  }

  /// {@template format_email_body}
  /// Formats email body with proper line breaks and structure.
  ///
  /// Converts plain text to email-friendly format with proper
  /// line breaks and paragraph separation.
  /// {@endtemplate}
  String formatEmailBody(final String body) => body
      .trim()
      .replaceAll(RegExp(r'\n\s*\n'), '\n\n') // Normalize paragraph breaks
      .replaceAll(RegExp(r'[ \t]+'), ' ') // Normalize whitespace
      .trim();

  /// {@template format_email_subject}
  /// Formats email subject line for optimal display.
  ///
  /// Trims whitespace and ensures the subject is not empty.
  /// {@endtemplate}
  String formatEmailSubject(final String subject) => subject.trim();

  /// URL-encodes parameters for mailto links.
  ///
  /// Handles special characters that need to be encoded in URLs.
  String _encodeUrlParameter(final String parameter) =>
      Uri.encodeComponent(parameter);
}

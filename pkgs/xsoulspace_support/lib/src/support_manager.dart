// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/foundation.dart';
import 'package:is_dart_empty_or_not/is_dart_empty_or_not.dart';

import 'models/models.dart';
import 'services/services.dart';

/// {@template support_manager}
/// Main class for managing support requests and email functionality.
///
/// Provides high-level methods for creating and sending support
/// requests with automatic context collection.
/// {@endtemplate}
class SupportManager {
  /// {@macro support_manager}
  factory SupportManager() => instance;
  SupportManager._();

  /// {@macro support_manager}
  static final instance = SupportManager._();

  final _appInfoService = AppInfoService();
  final _deviceInfoService = DeviceInfoService();
  final _emailService = EmailService();

  /// {@template send_support_email}
  /// Sends a comprehensive support email with automatic context collection.
  ///
  /// Automatically collects app and device information, formats the email,
  /// and opens the default email client with pre-filled content.
  ///
  /// Returns `true` if the email client was opened successfully,
  /// `false` if no email client is available or the operation failed.
  /// {@endtemplate}
  Future<bool> sendSupportEmail({
    required final SupportConfig config,
    required final String subject,
    required final String description,
    final String? userEmail,
    final String? userName,
    final Map<String, String>? additionalContext,
  }) async {
    try {
      final supportRequest = await _createSupportRequest(
        config: config,
        subject: subject,
        description: description,
        userEmail: userEmail,
        userName: userName,
        additionalContext: additionalContext,
      );

      final emailBody = _composeEmailBody(supportRequest, config);
      final emailSubject = '${config.emailSubjectPrefix}: $subject';

      return await _emailService.sendEmail(
        to: config.supportEmail,
        subject: emailSubject,
        body: emailBody,
      );
      // ignore: avoid_catches_without_on_clauses
    } catch (e, stackTrace) {
      debugPrint('Failed to send support email: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  /// {@template send_simple_support_email}
  /// Sends a simplified support email for quick feedback or bug reports.
  ///
  /// Uses default subject and minimal user input required.
  /// {@endtemplate}
  Future<bool> sendSimpleSupportEmail({
    required final SupportConfig config,
    final String? userEmail,
    final String? additionalInfo,
  }) => sendSupportEmail(
    config: config,
    subject: _getLocalizedString(
      config,
      SupportLocalization.appFeedback,
      'App Feedback',
    ),
    description:
        additionalInfo ??
        _getLocalizedString(
          config,
          SupportLocalization.userFeedbackOrBugReport,
          'User feedback or bug report',
        ),
    userEmail: userEmail,
  );

  /// {@template create_support_request}
  /// Creates a complete support request with all available context.
  ///
  /// Collects app and device information automatically and combines
  /// it with user-provided information.
  /// {@endtemplate}
  Future<SupportRequest> createSupportRequest({
    required final SupportConfig config,
    required final String subject,
    required final String description,
    final String? userEmail,
    final String? userName,
    final Map<String, String>? additionalContext,
  }) => _createSupportRequest(
    config: config,
    subject: subject,
    description: description,
    userEmail: userEmail,
    userName: userName,
    additionalContext: additionalContext,
  );

  /// Creates a support request with automatic context collection.
  Future<SupportRequest> _createSupportRequest({
    required final SupportConfig config,
    required final String subject,
    required final String description,
    final String? userEmail,
    final String? userName,
    final Map<String, String>? additionalContext,
  }) async {
    AppInfo? appInfo;
    DeviceInfo? deviceInfo;

    if (config.includeAppInfo) {
      appInfo = await _appInfoService.getAppInfo();
    }

    if (config.includeDeviceInfo) {
      deviceInfo = await _deviceInfoService.getDeviceInfo();
    }

    // Merge additional context
    final mergedContext = <String, String>{...config.additionalContext};

    return SupportRequest(
      subject: subject,
      description: description,
      appInfo: appInfo ?? _getDefaultAppInfo(config),
      deviceInfo: deviceInfo ?? _getDefaultDeviceInfo(config),
      userEmail: userEmail,
      userName: userName,
      additionalContext: mergedContext.isNotEmpty ? mergedContext : null,
    );
  }

  /// Composes the email body from a support request and configuration.
  static String _composeEmailBody(
    final SupportRequest request,
    final SupportConfig config,
  ) {
    if (config.emailTemplate.isNotEmpty) {
      return _applyTemplate(config.emailTemplate, request, config);
    }

    return _getDefaultEmailTemplate(request, config);
  }

  /// Applies a custom email template with support request data.
  static String _applyTemplate(
    final String template,
    final SupportRequest request,
    final SupportConfig config,
  ) => template
      .replaceAll('{{subject}}', request.subject)
      .replaceAll('{{description}}', request.description)
      .replaceAll(
        '{{userEmail}}',
        request.userEmail.whenEmptyUse(
          _getLocalizedString(
            config,
            SupportLocalization.notProvided,
            'Not provided',
          ),
        ),
      )
      .replaceAll(
        '{{userName}}',
        request.userName.whenEmptyUse(
          _getLocalizedString(
            config,
            SupportLocalization.notProvided,
            'Not provided',
          ),
        ),
      )
      .replaceAll('{{appVersion}}', request.appInfo.version)
      .replaceAll('{{appBuild}}', request.appInfo.buildNumber)
      .replaceAll(
        '{{appName}}',
        request.appInfo.appName ??
            _getLocalizedString(config, SupportLocalization.unknown, 'Unknown'),
      )
      .replaceAll('{{platform}}', request.deviceInfo.platform)
      .replaceAll('{{deviceModel}}', request.deviceInfo.model)
      .replaceAll('{{osVersion}}', request.deviceInfo.osVersion);

  /// Gets the default email template.
  static String _getDefaultEmailTemplate(
    final SupportRequest request,
    final SupportConfig config,
  ) {
    final buffer = StringBuffer()
      ..writeln(
        _getLocalizedString(
          config,
          SupportLocalization.helloSupportTeam,
          'Hello Support Team,',
        ),
      )
      ..writeln()
      ..writeln(
        _getLocalizedString(
          config,
          SupportLocalization.experiencingIssue,
          "I'm experiencing an issue with the ${config.appName} app.",
        ),
      )
      ..writeln()
      ..writeln(
        _getLocalizedString(
          config,
          SupportLocalization.issueDescription,
          '**Issue Description:**',
        ),
      )
      ..writeln(request.description)
      ..writeln();

    if (request.appInfo.version !=
        _getLocalizedString(config, SupportLocalization.unknown, 'Unknown')) {
      buffer
        ..writeln(
          _getLocalizedString(
            config,
            SupportLocalization.appInformation,
            '**App Information:**',
          ),
        )
        ..writeln(
          '- ${_getLocalizedString(config, SupportLocalization.version, 'Version')}: ${request.appInfo.version} (${request.appInfo.buildNumber})',
        )
        ..writeln(
          '- ${_getLocalizedString(config, SupportLocalization.package, 'Package')}: ${request.appInfo.packageName}',
        );
      if (request.appInfo.appName != null) {
        buffer.writeln(
          '- ${_getLocalizedString(config, SupportLocalization.appName, 'App Name')}: ${request.appInfo.appName}',
        );
      }
      buffer.writeln();
    }

    if (request.deviceInfo.platform !=
        _getLocalizedString(config, SupportLocalization.unknown, 'Unknown')) {
      buffer
        ..writeln(
          _getLocalizedString(
            config,
            SupportLocalization.deviceInformation,
            '**Device Information:**',
          ),
        )
        ..writeln(
          '- ${_getLocalizedString(config, SupportLocalization.platform, 'Platform')}: ${request.deviceInfo.platform}',
        )
        ..writeln(
          '- ${_getLocalizedString(config, SupportLocalization.model, 'Model')}: ${request.deviceInfo.model}',
        )
        ..writeln(
          '- ${_getLocalizedString(config, SupportLocalization.osVersion, 'OS Version')}: ${request.deviceInfo.osVersion}',
        );
      if (request.deviceInfo.manufacturer != null) {
        buffer.writeln(
          '- ${_getLocalizedString(config, SupportLocalization.manufacturer, 'Manufacturer')}: ${request.deviceInfo.manufacturer}',
        );
      }
      buffer.writeln();
    }

    if (request.userEmail.isNotEmpty) {
      buffer
        ..writeln(
          '${_getLocalizedString(config, SupportLocalization.contactEmail, '**Contact Email:**')} ${request.userEmail}',
        )
        ..writeln();
    }

    if (request.userName.isNotEmpty) {
      buffer
        ..writeln(
          '${_getLocalizedString(config, SupportLocalization.userName, '**User Name:**')} ${request.userName}',
        )
        ..writeln();
    }

    if (request.additionalContext.isNotEmpty) {
      buffer.writeln(
        _getLocalizedString(
          config,
          SupportLocalization.additionalContext,
          '**Additional Context:**',
        ),
      );
      for (final entry in request.additionalContext.entries) {
        buffer.writeln('- ${entry.key}: ${entry.value}');
      }
      buffer.writeln();
    }

    buffer
      ..writeln(
        _getLocalizedString(
          config,
          SupportLocalization.additionalDetails,
          '**Additional Details:**',
        ),
      )
      ..writeln(
        _getLocalizedString(
          config,
          SupportLocalization.provideAdditionalContext,
          'Please provide any additional context about your issue below:',
        ),
      )
      ..writeln()
      ..writeln()
      ..writeln()
      ..writeln()
      ..writeln('---')
      ..writeln(
        _getLocalizedString(
          config,
          SupportLocalization.sentFromApp,
          'Sent from ${config.appName} app',
        ),
      );

    return buffer.toString();
  }

  /// Gets default app info when collection fails.
  static AppInfo _getDefaultAppInfo(final SupportConfig config) => AppInfo(
    version: _getLocalizedString(
      config,
      SupportLocalization.unknown,
      'Unknown',
    ),
    buildNumber: _getLocalizedString(
      config,
      SupportLocalization.unknown,
      'Unknown',
    ),
    packageName: 'unknown.package',
    appName: config.appName,
  );

  /// Gets default device info when collection fails.
  static DeviceInfo _getDefaultDeviceInfo(final SupportConfig config) =>
      DeviceInfo(
        platform: _getLocalizedString(
          config,
          SupportLocalization.unknown,
          'Unknown',
        ),
        model: _getLocalizedString(
          config,
          SupportLocalization.unknown,
          'Unknown',
        ),
        osVersion: _getLocalizedString(
          config,
          SupportLocalization.unknown,
          'Unknown',
        ),
      );

  /// Gets a localized string from the config or falls back to default
  static String _getLocalizedString(
    final SupportConfig config,
    final String key,
    final String fallback,
  ) => SupportLocalization.getLocalizedString(
    config.localization,
    key,
    fallback,
  );
}

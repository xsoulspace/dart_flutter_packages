// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/foundation.dart';
import 'package:is_dart_empty_or_not/is_dart_empty_or_not.dart';
import 'package:xsoulspace_locale/xsoulspace_locale.dart';

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
    final UiLanguage? language,
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

      final emailBody = _composeEmailBody(supportRequest, config, language);
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
    final UiLanguage? language,
  }) => sendSupportEmail(
    config: config,
    subject: _getLocalizedString(
      config,
      SupportLocalization.appFeedback,
      'App Feedback',
      language,
    ),
    description:
        additionalInfo ??
        _getLocalizedString(
          config,
          SupportLocalization.userFeedbackOrBugReport,
          'User feedback or bug report',
          language,
        ),
    userEmail: userEmail,
    language: language,
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
    final UiLanguage? language,
  ) {
    if (config.emailTemplate.isNotEmpty) {
      return _applyTemplate(config.emailTemplate, request, config, language);
    }

    return _getDefaultEmailTemplate(request, config, language);
  }

  /// Applies a custom email template with support request data.
  static String _applyTemplate(
    final String template,
    final SupportRequest request,
    final SupportConfig config,
    final UiLanguage? language,
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
            language,
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
            language,
          ),
        ),
      )
      .replaceAll('{{appVersion}}', request.appInfo.version)
      .replaceAll('{{appBuild}}', request.appInfo.buildNumber)
      .replaceAll(
        '{{appName}}',
        request.appInfo.appName ??
            _getLocalizedString(config, SupportLocalization.unknown, 'Unknown', language),
      )
      .replaceAll('{{platform}}', request.deviceInfo.platform)
      .replaceAll('{{deviceModel}}', request.deviceInfo.model)
      .replaceAll('{{osVersion}}', request.deviceInfo.osVersion);

  /// Gets the default email template.
  static String _getDefaultEmailTemplate(
    final SupportRequest request,
    final SupportConfig config,
    final UiLanguage? language,
  ) {
    final buffer = StringBuffer()
      ..writeln(
        _getLocalizedString(
          config,
          SupportLocalization.helloSupportTeam,
          'Hello Support Team,',
          language,
        ),
      )
      ..writeln()
      ..writeln(
        _getLocalizedString(
          config,
          SupportLocalization.experiencingIssue,
          "I'm experiencing an issue with the ${config.appName} app.",
          language,
        ),
      )
      ..writeln()
      ..writeln(
        _getLocalizedString(
          config,
          SupportLocalization.issueDescription,
          '**Issue Description:**',
          language,
        ),
      )
      ..writeln(request.description)
      ..writeln();

    if (request.appInfo.version !=
        _getLocalizedString(config, SupportLocalization.unknown, 'Unknown', language)) {
      buffer
        ..writeln(
          _getLocalizedString(
            config,
            SupportLocalization.appInformation,
            '**App Information:**',
            language,
          ),
        )
        ..writeln(
          '- ${_getLocalizedString(config, SupportLocalization.version, 'Version', language)}: ${request.appInfo.version} (${request.appInfo.buildNumber})',
        )
        ..writeln(
          '- ${_getLocalizedString(config, SupportLocalization.package, 'Package', language)}: ${request.appInfo.packageName}',
        );
      if (request.appInfo.appName != null) {
        buffer.writeln(
          '- ${_getLocalizedString(config, SupportLocalization.appName, 'App Name', language)}: ${request.appInfo.appName}',
        );
      }
      buffer.writeln();
    }

    if (request.deviceInfo.platform !=
        _getLocalizedString(config, SupportLocalization.unknown, 'Unknown', language)) {
      buffer
        ..writeln(
          _getLocalizedString(
            config,
            SupportLocalization.deviceInformation,
            '**Device Information:**',
            language,
          ),
        )
        ..writeln(
          '- ${_getLocalizedString(config, SupportLocalization.platform, 'Platform', language)}: ${request.deviceInfo.platform}',
        )
        ..writeln(
          '- ${_getLocalizedString(config, SupportLocalization.model, 'Model', language)}: ${request.deviceInfo.model}',
        )
        ..writeln(
          '- ${_getLocalizedString(config, SupportLocalization.osVersion, 'OS Version', language)}: ${request.deviceInfo.osVersion}',
        );
      if (request.deviceInfo.manufacturer != null) {
        buffer.writeln(
          '- ${_getLocalizedString(config, SupportLocalization.manufacturer, 'Manufacturer', language)}: ${request.deviceInfo.manufacturer}',
        );
      }
      buffer.writeln();
    }

    if (request.userEmail.isNotEmpty) {
      buffer
        ..writeln(
          '${_getLocalizedString(config, SupportLocalization.contactEmail, '**Contact Email:**', language)} ${request.userEmail}',
        )
        ..writeln();
    }

    if (request.userName.isNotEmpty) {
      buffer
        ..writeln(
          '${_getLocalizedString(config, SupportLocalization.userName, '**User Name:**', language)} ${request.userName}',
        )
        ..writeln();
    }

    if (request.additionalContext.isNotEmpty) {
      buffer.writeln(
        _getLocalizedString(
          config,
          SupportLocalization.additionalContext,
          '**Additional Context:**',
          language,
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
          language,
        ),
      )
      ..writeln(
        _getLocalizedString(
          config,
          SupportLocalization.provideAdditionalContext,
          'Please provide any additional context about your issue below:',
          language,
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
          language,
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
      null,
    ),
    buildNumber: _getLocalizedString(
      config,
      SupportLocalization.unknown,
      'Unknown',
      null,
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
          null,
        ),
        model: _getLocalizedString(
          config,
          SupportLocalization.unknown,
          'Unknown',
          null,
        ),
        osVersion: _getLocalizedString(
          config,
          SupportLocalization.unknown,
          'Unknown',
          null,
        ),
      );

  /// Gets a localized string from the config or falls back to default
  static String _getLocalizedString(
    final SupportConfig config,
    final String key,
    final String fallback,
    final UiLanguage? language,
  ) {
    final targetLanguage = language ?? SupportLocalization.defaultLanguage;
    return config.getLocalizedString(key, targetLanguage, fallback);
  }
}

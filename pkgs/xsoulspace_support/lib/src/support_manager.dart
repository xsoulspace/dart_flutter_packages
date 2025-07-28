// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/foundation.dart';

import 'models/models.dart';
import 'models/support_config.dart';
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
    subject: 'App Feedback',
    description: additionalInfo ?? 'User feedback or bug report',
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
    final mergedContext = <String, String>{};
    if (config.additionalContext != null) {
      mergedContext.addAll(config.additionalContext!);
    }
    if (additionalContext != null) {
      mergedContext.addAll(additionalContext);
    }

    return SupportRequest(
      subject: subject,
      description: description,
      appInfo: appInfo ?? _getDefaultAppInfo(config),
      deviceInfo: deviceInfo ?? _getDefaultDeviceInfo(),
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
    if (config.emailTemplate != null) {
      return _applyTemplate(config.emailTemplate!, request);
    }

    return _getDefaultEmailTemplate(request, config);
  }

  /// Applies a custom email template with support request data.
  static String _applyTemplate(
    final String template,
    final SupportRequest request,
  ) => template
      .replaceAll('{{subject}}', request.subject)
      .replaceAll('{{description}}', request.description)
      .replaceAll('{{userEmail}}', request.userEmail ?? 'Not provided')
      .replaceAll('{{userName}}', request.userName ?? 'Not provided')
      .replaceAll('{{appVersion}}', request.appInfo.version)
      .replaceAll('{{appBuild}}', request.appInfo.buildNumber)
      .replaceAll('{{appName}}', request.appInfo.appName ?? 'Unknown')
      .replaceAll('{{platform}}', request.deviceInfo.platform)
      .replaceAll('{{deviceModel}}', request.deviceInfo.model)
      .replaceAll('{{osVersion}}', request.deviceInfo.osVersion);

  /// Gets the default email template.
  static String _getDefaultEmailTemplate(
    final SupportRequest request,
    final SupportConfig config,
  ) {
    final buffer = StringBuffer()
      ..writeln('Hello Support Team,')
      ..writeln()
      ..writeln("I'm experiencing an issue with the ${config.appName} app.")
      ..writeln()
      ..writeln('**Issue Description:**')
      ..writeln(request.description)
      ..writeln();

    if (request.appInfo.version != 'Unknown') {
      buffer
        ..writeln('**App Information:**')
        ..writeln(
          '- Version: ${request.appInfo.version} (${request.appInfo.buildNumber})',
        )
        ..writeln('- Package: ${request.appInfo.packageName}');
      if (request.appInfo.appName != null) {
        buffer.writeln('- App Name: ${request.appInfo.appName}');
      }
      buffer.writeln();
    }

    if (request.deviceInfo.platform != 'Unknown') {
      buffer
        ..writeln('**Device Information:**')
        ..writeln('- Platform: ${request.deviceInfo.platform}')
        ..writeln('- Model: ${request.deviceInfo.model}')
        ..writeln('- OS Version: ${request.deviceInfo.osVersion}');
      if (request.deviceInfo.manufacturer != null) {
        buffer.writeln('- Manufacturer: ${request.deviceInfo.manufacturer}');
      }
      buffer.writeln();
    }

    if (request.userEmail != null) {
      buffer
        ..writeln('**Contact Email:** ${request.userEmail}')
        ..writeln();
    }

    if (request.userName != null) {
      buffer
        ..writeln('**User Name:** ${request.userName}')
        ..writeln();
    }

    if (request.additionalContext != null &&
        request.additionalContext!.isNotEmpty) {
      buffer.writeln('**Additional Context:**');
      for (final entry in request.additionalContext!.entries) {
        buffer.writeln('- ${entry.key}: ${entry.value}');
      }
      buffer.writeln();
    }

    buffer
      ..writeln('**Additional Details:**')
      ..writeln('Please provide any additional context about your issue below:')
      ..writeln()
      ..writeln()
      ..writeln()
      ..writeln()
      ..writeln('---')
      ..writeln('Sent from ${config.appName} app');

    return buffer.toString();
  }

  /// Gets default app info when collection fails.
  static AppInfo _getDefaultAppInfo(final SupportConfig config) => AppInfo(
    version: 'Unknown',
    buildNumber: 'Unknown',
    packageName: 'unknown.package',
    appName: config.appName,
  );

  /// Gets default device info when collection fails.
  static DeviceInfo _getDefaultDeviceInfo() => const DeviceInfo(
    platform: 'Unknown',
    model: 'Unknown',
    osVersion: 'Unknown',
  );
}

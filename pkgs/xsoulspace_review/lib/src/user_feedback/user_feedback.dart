import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wiredash/wiredash.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

export 'wiredash_custom_delegate.dart';

/// {@template user_feedback_wiredash_dto}
/// Configuration data transfer object for Wiredash integration.
///
/// Contains all necessary configuration for initializing Wiredash
/// user feedback system.
/// {@endtemplate}
class UserFeedbackWiredashDto {
  /// {@macro user_feedback_wiredash_dto}
  const UserFeedbackWiredashDto({
    required this.projectId,
    required this.secret,
    this.collectMetaData,
    this.feedbackOptions,
    this.psOptions,
    this.theme,
    this.options,
    this.padding,
  });

  /// Wiredash project ID
  final String projectId;

  /// Wiredash secret key
  final String secret;

  /// Callback to collect custom metadata
  final FutureOr<CustomizableWiredashMetaData> Function(
    CustomizableWiredashMetaData metaData,
  )?
  collectMetaData;

  /// Feedback form options
  final WiredashFeedbackOptions? feedbackOptions;

  /// Promoter score options
  final PsOptions? psOptions;

  /// Custom theme for Wiredash UI
  final WiredashThemeData? theme;

  /// General Wiredash options
  final WiredashOptionsData? options;

  /// Padding for Wiredash UI
  final EdgeInsets? padding;
}

/// {@template user_feedback}
/// Widget wrapper for user feedback functionality using Wiredash.
///
/// Wraps the application with Wiredash feedback system for collecting
/// user feedback, bug reports, and feature requests.
///
/// ## Usage
/// ```dart
/// UserFeedback.wiredash(
///   dto: UserFeedbackWiredashDto(
///     projectId: 'your-project-id',
///     secret: 'your-secret',
///   ),
///   logger: myLogger, // Optional
///   child: MyApp(),
/// );
/// ```
/// {@endtemplate}
class UserFeedback extends StatelessWidget {
  /// {@macro user_feedback}
  const UserFeedback.wiredash({
    required this.child,
    required final UserFeedbackWiredashDto dto,
    this.logger,
    super.key,
  }) : wiredashDto = dto;

  /// The child widget to wrap
  final Widget child;

  /// Wiredash configuration
  final UserFeedbackWiredashDto wiredashDto;

  /// Optional logger for debugging and monitoring
  final Logger? logger;

  /// Shows the feedback form.
  ///
  /// Call this method to manually trigger the feedback form.
  ///
  /// [context] - Build context for accessing Wiredash
  /// [logger] - Optional logger for debugging
  static Future<void> show(final BuildContext context, {final Logger? logger}) {
    logger?.debug('FEEDBACK', 'Opening feedback form');
    return Wiredash.of(context).show();
  }

  @override
  Widget build(final BuildContext context) {
    logger?.debug(
      'FEEDBACK',
      'Initializing Wiredash feedback system',
      data: {'projectId': wiredashDto.projectId},
    );

    return Wiredash(
      projectId: wiredashDto.projectId,
      secret: wiredashDto.secret,
      collectMetaData: wiredashDto.collectMetaData,
      feedbackOptions: wiredashDto.feedbackOptions,
      psOptions: wiredashDto.psOptions,
      theme: wiredashDto.theme,
      options: wiredashDto.options,
      padding: wiredashDto.padding,
      child: child,
    );
  }
}

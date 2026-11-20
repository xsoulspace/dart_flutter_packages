// ignore_for_file: avoid_annotating_with_dynamic
import 'package:flutter/foundation.dart';
import 'package:xsoulspace_foundation/xsoulspace_foundation.dart';

enum AnalyticEvents { usedInAndroid, usedInIOS, usedInWeb }

abstract class AnalyticsService extends AnalyticsServicePlugin {
  void upsertPlugin<T extends AnalyticsServicePlugin>(T plugin);
}

abstract class AnalyticsServicePlugin implements Loadable, Disposable {
  void reportIntededException([dynamic value]) {}
  Future<void> logAnalyticEvent(AnalyticEvents event);
  Future<void> onDelayedLoad();
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    Iterable<DiagnosticsNode> information = const [],
    bool fatal = false,
    bool? printDetails,
  });

  Future<void> recordFlutterError(
    FlutterErrorDetails flutterErrorDetails, {
    bool fatal = false,
  });

  @override
  Future<void> onLoad();

  /// noop implementation
  void dynamicLog(
    dynamic value, {
    String message = '',
    StackTrace? stackTrace,
  }) {}
  void dynamicWarningLog(
    dynamic value, {
    String message = '',
    StackTrace? stackTrace,
  }) {}

  /// noop implementation
  void dynamicInfoLog(
    dynamic value, {
    String message = '',
    StackTrace? stackTrace,
  }) {}

  /// noop implementation
  void dynamicErrorLog(
    dynamic value, {
    String message = '',
    StackTrace? stackTrace,
  }) {}

  @override
  @mustCallSuper
  void dispose() {}
}

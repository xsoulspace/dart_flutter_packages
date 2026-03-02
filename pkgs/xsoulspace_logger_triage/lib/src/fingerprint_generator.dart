library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

/// Generates deterministic issue fingerprints from log records.
final class FingerprintGenerator {
  const FingerprintGenerator();

  static final RegExp _uuidPattern = RegExp(
    r'\b[0-9a-fA-F]{8}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}\b',
  );
  static final RegExp _hexPattern = RegExp(r'\b(?:0x)?[0-9a-fA-F]{8,}\b');
  static final RegExp _numberPattern = RegExp(r'\b\d+\b');
  static final RegExp _lineNumberPattern = RegExp(r':\d+(?::\d+)?');
  static final RegExp _whitespacePattern = RegExp(r'\s+');

  String fingerprint(final LogRecord record, {final int topFrames = 5}) {
    final errorType = _resolveErrorType(record.error);
    final messageTemplate = normalizeMessage(record.message);
    final appFrames = extractNormalizedFrames(record.stackTrace, topFrames);

    final payload = StringBuffer()
      ..write(errorType)
      ..write('|')
      ..write(messageTemplate)
      ..write('|')
      ..write(appFrames.join('|'))
      ..write('|')
      ..write(record.category);

    return sha1.convert(utf8.encode(payload.toString())).toString();
  }

  String normalizeMessage(final String message) {
    var normalized = message;
    normalized = normalized.replaceAll(_uuidPattern, '<uuid>');
    normalized = normalized.replaceAll(_hexPattern, '<hex>');
    normalized = normalized.replaceAll(_numberPattern, '<num>');
    normalized = normalized.replaceAll(_whitespacePattern, ' ').trim();
    return normalized;
  }

  List<String> extractNormalizedFrames(
    final StackTrace? stackTrace,
    final int topFrames,
  ) {
    if (stackTrace == null || topFrames <= 0) {
      return const <String>[];
    }

    final lines = stackTrace
        .toString()
        .split('\n')
        .map((final line) => line.trim())
        .where((final line) => line.isNotEmpty)
        .where((final line) => !_isSdkFrame(line));

    return lines.take(topFrames).map(_normalizeFrame).toList(growable: false);
  }

  bool _isSdkFrame(final String line) =>
      line.contains('dart:') ||
      line.contains('package:test') ||
      line.contains('package:flutter_test');

  String _normalizeFrame(final String frame) {
    var normalized = frame;
    normalized = normalized.replaceAll(_lineNumberPattern, '');
    normalized = normalized.replaceAll(_hexPattern, '<hex>');
    normalized = normalized.replaceAll(_whitespacePattern, ' ').trim();
    return normalized;
  }

  String _resolveErrorType(final Object? error) {
    if (error == null) {
      return 'none';
    }

    final runtimeTypeName = error.runtimeType.toString();
    if (runtimeTypeName != 'String') {
      return runtimeTypeName;
    }

    final text = error.toString();
    final separator = text.indexOf(':');
    if (separator > 0) {
      return text.substring(0, separator).trim();
    }

    return runtimeTypeName;
  }
}

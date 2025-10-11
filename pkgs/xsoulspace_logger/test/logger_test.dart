/// Tests for xsoulspace_logger package
library;

import 'package:test/test.dart';
import 'package:xsoulspace_logger/xsoulspace_logger.dart';

void main() {
  group('LogLevel', () {
    test('should have correct ordering', () {
      expect(LogLevel.verbose.value, lessThan(LogLevel.debug.value));
      expect(LogLevel.debug.value, lessThan(LogLevel.info.value));
      expect(LogLevel.info.value, lessThan(LogLevel.warning.value));
      expect(LogLevel.warning.value, lessThan(LogLevel.error.value));
    });

    test('isEnabled should work correctly', () {
      expect(LogLevel.verbose.isEnabled(LogLevel.verbose), isTrue);
      expect(LogLevel.debug.isEnabled(LogLevel.verbose), isTrue);
      expect(LogLevel.verbose.isEnabled(LogLevel.debug), isFalse);
      expect(LogLevel.error.isEnabled(LogLevel.info), isTrue);
    });
  });

  group('LoggerConfig', () {
    test('debug preset should have correct settings', () {
      final config = LoggerConfig.debug();
      expect(config.minLevel, LogLevel.verbose);
      expect(config.enableConsole, isTrue);
      expect(config.enableFile, isTrue);
    });

    test('production preset should have correct settings', () {
      final config = LoggerConfig.production();
      expect(config.minLevel, LogLevel.info);
      expect(config.enableConsole, isFalse);
      expect(config.enableFile, isTrue);
    });

    test('consoleOnly preset should have correct settings', () {
      final config = LoggerConfig.consoleOnly();
      expect(config.enableConsole, isTrue);
      expect(config.enableFile, isFalse);
    });
  });

  group('Logger', () {
    setUp(() async {
      // Reset logger before each test
      await Logger.reset();
    });

    tearDown(() async {
      // Clean up
      await Logger.reset();
    });

    test('should initialize with console-only config', () {
      final config = LoggerConfig.consoleOnly(level: LogLevel.info);
      final logger = Logger(config);
      expect(logger.config.enableConsole, isTrue);
      expect(logger.config.enableFile, isFalse);
    });

    test('should respect minimum log level', () {
      final config = LoggerConfig.consoleOnly(level: LogLevel.warning);
      final logger = Logger(config);

      // These should not throw
      logger.verbose('TEST', 'Verbose message');
      logger.debug('TEST', 'Debug message');
      logger.info('TEST', 'Info message');
      logger.warning('TEST', 'Warning message');
      logger.error('TEST', 'Error message');
    });

    test('should log with data', () {
      final config = LoggerConfig.consoleOnly();
      final logger = Logger(config);

      logger.info(
        'TEST',
        'Message with data',
        data: {'key1': 'value1', 'key2': 42},
      );
    });

    test('should log errors with stack trace', () {
      final config = LoggerConfig.consoleOnly();
      final logger = Logger(config);

      try {
        throw Exception('Test error');
      } catch (e, stack) {
        logger.error('TEST', 'Error occurred', error: e, stackTrace: stack);
      }
    });

    test('should be singleton', () {
      final config = LoggerConfig.consoleOnly();
      final logger1 = Logger(config);
      final logger2 = Logger();
      expect(identical(logger1, logger2), isTrue);
    });
  });

  group('FileWriter', () {
    test('should create FileWriter with config', () {
      const config = LoggerConfig(
        minLevel: LogLevel.info,
        enableConsole: false,
        enableFile: true,
      );

      final writer = FileWriter(config);
      expect(writer.config.enableFile, isTrue);
    });

    test('should handle writes without errors', () {
      const config = LoggerConfig(
        minLevel: LogLevel.info,
        enableConsole: false,
        enableFile: true,
      );

      final writer = FileWriter(config);
      // These should not throw
      writer.write('Message 1');
      writer.write('Message 2');
      writer.write('Message 3');
    });
  });
}

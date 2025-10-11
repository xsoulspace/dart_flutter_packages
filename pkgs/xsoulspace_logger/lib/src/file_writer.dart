/// Async file writer with rotation support
library;

import 'dart:async';
import 'dart:io';

import 'logger_config.dart';

/// Handles writing log messages to files with rotation support
class FileWriter {
  final LoggerConfig config;
  final List<String> _buffer = [];
  File? _currentFile;
  Timer? _flushTimer;
  bool _disposed = false;

  FileWriter(this.config) {
    _initializeFile();
    _startPeriodicFlush();
  }

  /// Initialize log file with timestamp
  Future<void> _initializeFile() async {
    if (!config.enableFile) return;

    final directory = await _getLogDirectory();
    await directory.create(recursive: true);

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final filename = 'log_$timestamp.log';
    _currentFile = File('${directory.path}/$filename');

    // Clean old files if rotation is enabled
    if (config.enableRotation) {
      await _cleanOldFiles(directory);
    }
  }

  /// Get log directory
  Future<Directory> _getLogDirectory() async {
    if (config.logDirectory != null) {
      return Directory(config.logDirectory!);
    }
    // Use system temp directory
    final tempDir = Directory.systemTemp;
    return Directory('${tempDir.path}/xsoulspace_logger');
  }

  /// Write log message to buffer
  void write(String message) {
    if (_disposed || !config.enableFile) return;

    _buffer.add(message);

    // Flush if buffer is large
    if (_buffer.length >= 100) {
      _flush();
    }
  }

  /// Flush buffer to file
  Future<void> _flush() async {
    if (_buffer.isEmpty || _currentFile == null || _disposed) return;

    try {
      final messages = List<String>.from(_buffer);
      _buffer.clear();

      final content = '${messages.join('\n')}\n';
      await _currentFile!.writeAsString(content, mode: FileMode.append);

      // Check file size and rotate if needed
      if (config.enableRotation) {
        final stat = await _currentFile!.stat();
        final sizeMB = stat.size / (1024 * 1024);
        if (sizeMB >= config.maxFileSizeMB) {
          await _rotateFile();
        }
      }
    } catch (e) {
      // Ignore file write errors
      print('FileWriter error: $e');
    }
  }

  /// Rotate to new file
  Future<void> _rotateFile() async {
    // File will be flushed on next write
    await _initializeFile();
  }

  /// Clean old log files
  Future<void> _cleanOldFiles(Directory directory) async {
    try {
      final files = await directory
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.log'))
          .cast<File>()
          .toList();

      if (files.length <= config.maxFileCount) return;

      // Sort by modification time
      files.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return aStat.modified.compareTo(bStat.modified);
      });

      // Delete oldest files
      final toDelete = files.length - config.maxFileCount;
      for (var i = 0; i < toDelete; i++) {
        await files[i].delete();
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  /// Start periodic flush timer
  void _startPeriodicFlush() {
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _flush();
    });
  }

  /// Dispose and flush remaining buffer
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _flushTimer?.cancel();
    await _flush();
  }
}

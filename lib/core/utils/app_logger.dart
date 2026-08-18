import 'dart:collection';

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  LogEntry(this.level, this.tag, this.message, this.timestamp);

  final LogLevel level;
  final String tag;
  final String message;
  final DateTime timestamp;

  @override
  String toString() {
    final ts = timestamp.toIso8601String();
    final lvl = level.name.toUpperCase().padRight(7);
    return '$ts $lvl [$tag] $message';
  }
}

/// Structured, in-memory ring-buffer logger (see spec section 36).
///
/// Deliberately does not log fare/distance-adjacent free text at INFO level in
/// release builds beyond what's needed for the job history — and never logs
/// credentials, tokens, or anything resembling a password. See docs/architecture.md.
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const int _maxEntries = 500;
  final Queue<LogEntry> _buffer = ListQueue<LogEntry>(_maxEntries);

  List<LogEntry> get recentEntries => List.unmodifiable(_buffer);

  void debug(String tag, String message) => _log(LogLevel.debug, tag, message);
  void info(String tag, String message) => _log(LogLevel.info, tag, message);
  void warning(String tag, String message) => _log(LogLevel.warning, tag, message);
  void error(String tag, String message) => _log(LogLevel.error, tag, message);

  void _log(LogLevel level, String tag, String message) {
    final entry = LogEntry(level, tag, message, DateTime.now());
    if (_buffer.length >= _maxEntries) {
      _buffer.removeFirst();
    }
    _buffer.add(entry);
    if (kDebugMode) {
      debugPrint(entry.toString());
    }
  }

  void clear() => _buffer.clear();
}

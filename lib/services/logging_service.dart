import 'package:flutter/foundation.dart';

enum LogLevel {
  debug,
  info,
  warning,
  error
}

class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  
  factory LoggingService() {
    return _instance;
  }

  LoggingService._internal();

  void log(String message, {LogLevel level = LogLevel.info, Object? error, StackTrace? stackTrace}) {
    if (!kReleaseMode) {
      final timestamp = DateTime.now().toIso8601String();
      final prefix = '[${level.toString().split('.').last.toUpperCase()}]';
      
      debugPrint('$timestamp $prefix $message');
      
      if (error != null) {
        debugPrint('Error: $error');
      }
      
      if (stackTrace != null) {
        debugPrint('StackTrace: $stackTrace');
      }
    }
  }

  void debug(String message) {
    log(message, level: LogLevel.debug);
  }

  void info(String message) {
    log(message, level: LogLevel.info);
  }

  void warning(String message, {Object? error, StackTrace? stackTrace}) {
    log(message, level: LogLevel.warning, error: error, stackTrace: stackTrace);
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    log(message, level: LogLevel.error, error: error, stackTrace: stackTrace);
  }
} 
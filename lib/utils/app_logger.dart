import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized logging manager for Aerion AeroSense.
///
/// By default, verbose debug logs and operational prints are disabled to keep
/// the console clean. Logging can be enabled dynamically via Executive Settings
/// or programmatically for hardware diagnostics.
class AppLogger {
  static const String _prefKey = 'aerosense_enable_logging';

  /// Master switch for logging. Defaults to false.
  static bool enableLogging = false;

  /// Load persisted logging preference from SharedPreferences
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enableLogging = prefs.getBool(_prefKey) ?? false;
    } catch (_) {
      // Ignored during unit tests or early init
    }
  }

  /// Toggle logging and persist preference
  static Future<void> setLoggingEnabled(bool enabled) async {
    enableLogging = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, enabled);
    } catch (_) {}
  }

  /// Debug level log (e.g. detailed BLE packets, WiFi polling, mode switches)
  static void debug(String tag, String message) {
    if (enableLogging && kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }

  /// Short alias for debug
  static void d(String tag, String message) => debug(tag, message);

  /// Informational log
  static void info(String tag, String message) {
    if (enableLogging && kDebugMode) {
      debugPrint('[$tag] $message');
    }
  }

  /// Short alias for info
  static void i(String tag, String message) => info(tag, message);

  /// Warning level log (e.g. retries, graceful fallbacks)
  static void warning(String tag, String message) {
    if (enableLogging && kDebugMode) {
      debugPrint('[$tag] ⚠️ $message');
    }
  }

  /// Short alias for warning
  static void w(String tag, String message) => warning(tag, message);

  /// Error level log (e.g. caught exceptions)
  static void error(String tag, String message, [Object? err, StackTrace? stackTrace]) {
    if (enableLogging && kDebugMode) {
      debugPrint('[$tag] ❌ $message${err != null ? ': $err' : ''}');
      if (stackTrace != null) {
        debugPrint(stackTrace.toString());
      }
    }
  }

  /// Short alias for error
  static void e(String tag, String message, [Object? err, StackTrace? stackTrace]) =>
      AppLogger.error(tag, message, err, stackTrace);
}

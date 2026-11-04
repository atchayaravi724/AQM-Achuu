import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

enum MetricStatus { normal, warning, critical }

/// Manages configurable environmental alert thresholds and notification preferences.
/// Persists values in SharedPreferences and applies updates in real-time.
class ThresholdProvider extends ChangeNotifier {
  // SharedPreferences Keys
  static const String _keyTempNormalMax = 'thresh_temp_normal_max';
  static const String _keyTempWarningMax = 'thresh_temp_warning_max';
  static const String _keyHumMin = 'thresh_hum_min';
  static const String _keyHumNormalMin = 'thresh_hum_normal_min';
  static const String _keyHumNormalMax = 'thresh_hum_normal_max';
  static const String _keyHumMax = 'thresh_hum_max';
  static const String _keyAqNormalMax = 'thresh_aq_normal_max';
  static const String _keyAqWarningMax = 'thresh_aq_warning_max';
  static const String _keyAlertTemp = 'thresh_alert_temp';
  static const String _keyAlertHum = 'thresh_alert_hum';
  static const String _keyAlertAq = 'thresh_alert_aq';
  static const String _keyAlertSound = 'thresh_alert_sound';
  static const String _keyAlertVibration = 'thresh_alert_vibration';

  // Default Values
  static const double defaultTempNormalMax = 30.0;
  static const double defaultTempWarningMax = 35.0;
  static const double defaultHumMin = 20.0;
  static const double defaultHumNormalMin = 30.0;
  static const double defaultHumNormalMax = 70.0;
  static const double defaultHumMax = 85.0;
  static const int defaultAqNormalMax = 1500;
  static const int defaultAqWarningMax = 2500;

  // Temperature Thresholds (°C)
  double _tempNormalMax = defaultTempNormalMax;
  double _tempWarningMax = defaultTempWarningMax;

  // Humidity Thresholds (%)
  double _humidityMin = defaultHumMin;
  double _humidityNormalMin = defaultHumNormalMin;
  double _humidityNormalMax = defaultHumNormalMax;
  double _humidityMax = defaultHumMax;

  // Air Quality Thresholds (MQ-135 Raw ADC readings)
  int _aqNormalMax = defaultAqNormalMax;
  int _aqWarningMax = defaultAqWarningMax;

  // Alert Preferences
  bool _enableTempAlerts = true;
  bool _enableHumidityAlerts = true;
  bool _enableAirQualityAlerts = true;
  bool _enableSound = true;
  bool _enableVibration = true;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  // Getters
  double get tempNormalMax => _tempNormalMax;
  double get tempWarningMax => _tempWarningMax;
  double get humidityMin => _humidityMin;
  double get humidityNormalMin => _humidityNormalMin;
  double get humidityNormalMax => _humidityNormalMax;
  double get humidityMax => _humidityMax;
  int get aqNormalMax => _aqNormalMax;
  int get aqWarningMax => _aqWarningMax;

  bool get enableTempAlerts => _enableTempAlerts;
  bool get enableHumidityAlerts => _enableHumidityAlerts;
  bool get enableAirQualityAlerts => _enableAirQualityAlerts;
  bool get enableSound => _enableSound;
  bool get enableVibration => _enableVibration;

  Future<void>? _loadFuture;

  ThresholdProvider() {
    loadFromPrefs();
  }

  Future<void> loadFromPrefs() {
    _loadFuture ??= _doLoadFromPrefs();
    return _loadFuture!;
  }

  Future<void> _doLoadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _tempNormalMax = prefs.getDouble(_keyTempNormalMax) ?? defaultTempNormalMax;
      _tempWarningMax = prefs.getDouble(_keyTempWarningMax) ?? defaultTempWarningMax;
      _humidityMin = prefs.getDouble(_keyHumMin) ?? defaultHumMin;
      _humidityNormalMin = prefs.getDouble(_keyHumNormalMin) ?? defaultHumNormalMin;
      _humidityNormalMax = prefs.getDouble(_keyHumNormalMax) ?? defaultHumNormalMax;
      _humidityMax = prefs.getDouble(_keyHumMax) ?? defaultHumMax;
      _aqNormalMax = prefs.getInt(_keyAqNormalMax) ?? defaultAqNormalMax;
      _aqWarningMax = prefs.getInt(_keyAqWarningMax) ?? defaultAqWarningMax;

      _enableTempAlerts = prefs.getBool(_keyAlertTemp) ?? true;
      _enableHumidityAlerts = prefs.getBool(_keyAlertHum) ?? true;
      _enableAirQualityAlerts = prefs.getBool(_keyAlertAq) ?? true;
      _enableSound = prefs.getBool(_keyAlertSound) ?? true;
      _enableVibration = prefs.getBool(_keyAlertVibration) ?? true;

      _isLoaded = true;
      notifyListeners();
    } catch (_) {
      _isLoaded = true;
    }
  }

  /// Validates threshold configuration before saving
  static String? validateThresholds({
    required double tempNormalMax,
    required double tempWarningMax,
    required double humMin,
    required double humNormalMin,
    required double humNormalMax,
    required double humMax,
    required int aqNormalMax,
    required int aqWarningMax,
  }) {
    if (tempNormalMax <= 0 || tempWarningMax <= 0) {
      return 'Temperature thresholds must be positive values.';
    }
    if (tempNormalMax >= tempWarningMax) {
      return 'Normal temperature limit ($tempNormalMax°C) must be less than warning threshold ($tempWarningMax°C).';
    }
    if (humMin < 0 || humMax > 100) {
      return 'Humidity values must be between 0% and 100%.';
    }
    if (humMin >= humNormalMin || humNormalMin >= humNormalMax || humNormalMax >= humMax) {
      return 'Humidity bounds must satisfy: Min ($humMin%) < Normal Range ($humNormalMin% - $humNormalMax%) < Max ($humMax%).';
    }
    if (aqNormalMax <= 0 || aqWarningMax <= 0) {
      return 'Raw MQ-135 ADC thresholds must be positive integers.';
    }
    if (aqNormalMax >= aqWarningMax) {
      return 'Normal air quality limit ($aqNormalMax ADC) must be less than warning threshold ($aqWarningMax ADC).';
    }
    return null;
  }

  /// Updates and persists all threshold parameters simultaneously with validation
  Future<bool> updateThresholds({
    required double tempNormalMax,
    required double tempWarningMax,
    required double humMin,
    required double humNormalMin,
    required double humNormalMax,
    required double humMax,
    required int aqNormalMax,
    required int aqWarningMax,
  }) async {
    await loadFromPrefs();
    final error = validateThresholds(
      tempNormalMax: tempNormalMax,
      tempWarningMax: tempWarningMax,
      humMin: humMin,
      humNormalMin: humNormalMin,
      humNormalMax: humNormalMax,
      humMax: humMax,
      aqNormalMax: aqNormalMax,
      aqWarningMax: aqWarningMax,
    );
    if (error != null) return false;

    _tempNormalMax = tempNormalMax;
    _tempWarningMax = tempWarningMax;
    _humidityMin = humMin;
    _humidityNormalMin = humNormalMin;
    _humidityNormalMax = humNormalMax;
    _humidityMax = humMax;
    _aqNormalMax = aqNormalMax;
    _aqWarningMax = aqWarningMax;

    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyTempNormalMax, _tempNormalMax);
      await prefs.setDouble(_keyTempWarningMax, _tempWarningMax);
      await prefs.setDouble(_keyHumMin, _humidityMin);
      await prefs.setDouble(_keyHumNormalMin, _humidityNormalMin);
      await prefs.setDouble(_keyHumNormalMax, _humidityNormalMax);
      await prefs.setDouble(_keyHumMax, _humidityMax);
      await prefs.setInt(_keyAqNormalMax, _aqNormalMax);
      await prefs.setInt(_keyAqWarningMax, _aqWarningMax);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Toggles alert preference settings
  Future<void> setAlertPreferences({
    bool? tempAlerts,
    bool? humidityAlerts,
    bool? aqAlerts,
    bool? sound,
    bool? vibration,
  }) async {
    await loadFromPrefs();
    if (tempAlerts != null) _enableTempAlerts = tempAlerts;
    if (humidityAlerts != null) _enableHumidityAlerts = humidityAlerts;
    if (aqAlerts != null) _enableAirQualityAlerts = aqAlerts;
    if (sound != null) _enableSound = sound;
    if (vibration != null) _enableVibration = vibration;

    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      if (tempAlerts != null) await prefs.setBool(_keyAlertTemp, tempAlerts);
      if (humidityAlerts != null) await prefs.setBool(_keyAlertHum, humidityAlerts);
      if (aqAlerts != null) await prefs.setBool(_keyAlertAq, aqAlerts);
      if (sound != null) await prefs.setBool(_keyAlertSound, sound);
      if (vibration != null) await prefs.setBool(_keyAlertVibration, vibration);
    } catch (_) {}
  }

  /// Restores all thresholds and alert preferences to factory defaults
  Future<void> restoreDefaults() async {
    await loadFromPrefs();
    _tempNormalMax = defaultTempNormalMax;
    _tempWarningMax = defaultTempWarningMax;
    _humidityMin = defaultHumMin;
    _humidityNormalMin = defaultHumNormalMin;
    _humidityNormalMax = defaultHumNormalMax;
    _humidityMax = defaultHumMax;
    _aqNormalMax = defaultAqNormalMax;
    _aqWarningMax = defaultAqWarningMax;
    _enableTempAlerts = true;
    _enableHumidityAlerts = true;
    _enableAirQualityAlerts = true;
    _enableSound = true;
    _enableVibration = true;

    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyTempNormalMax);
      await prefs.remove(_keyTempWarningMax);
      await prefs.remove(_keyHumMin);
      await prefs.remove(_keyHumNormalMin);
      await prefs.remove(_keyHumNormalMax);
      await prefs.remove(_keyHumMax);
      await prefs.remove(_keyAqNormalMax);
      await prefs.remove(_keyAqWarningMax);
      await prefs.remove(_keyAlertTemp);
      await prefs.remove(_keyAlertHum);
      await prefs.remove(_keyAlertAq);
      await prefs.remove(_keyAlertSound);
      await prefs.remove(_keyAlertVibration);
    } catch (_) {}
  }

  Future<void> resetToDefaults() => restoreDefaults();
  Future<void> setEnableTempAlerts(bool v) => setAlertPreferences(tempAlerts: v);
  Future<void> setEnableHumidityAlerts(bool v) => setAlertPreferences(humidityAlerts: v);
  Future<void> setEnableAirQualityAlerts(bool v) => setAlertPreferences(aqAlerts: v);
  Future<void> setEnableSound(bool v) => setAlertPreferences(sound: v);
  Future<void> setEnableVibration(bool v) => setAlertPreferences(vibration: v);

  // ── Status Evaluators ──────────────────────────────────────────────────────

  MetricStatus getTemperatureStatus(double temp) {
    if (temp < _tempNormalMax) return MetricStatus.normal;
    if (temp <= _tempWarningMax) return MetricStatus.warning;
    return MetricStatus.critical;
  }

  MetricStatus getHumidityStatus(double humidity) {
    if (humidity >= _humidityNormalMin && humidity <= _humidityNormalMax) {
      return MetricStatus.normal;
    }
    if ((humidity >= _humidityMin && humidity < _humidityNormalMin) ||
        (humidity > _humidityNormalMax && humidity <= _humidityMax)) {
      return MetricStatus.warning;
    }
    return MetricStatus.critical;
  }

  MetricStatus getAirQualityStatus(int rawAdc) {
    if (rawAdc < _aqNormalMax) return MetricStatus.normal;
    if (rawAdc <= _aqWarningMax) return MetricStatus.warning;
    return MetricStatus.critical;
  }

  static String getStatusLabel(MetricStatus status) {
    switch (status) {
      case MetricStatus.normal:
        return 'NORMAL';
      case MetricStatus.warning:
        return 'WARNING';
      case MetricStatus.critical:
        return 'CRITICAL';
    }
  }

  static Color getStatusColor(MetricStatus status, bool isDark) {
    switch (status) {
      case MetricStatus.normal:
        return isDark ? AppColors.neonEmerald : AppColors.lightSecondary;
      case MetricStatus.warning:
        return AppColors.criticalRed; // Vivid red for warning as requested
      case MetricStatus.critical:
        return AppColors.crimsonNeon; // High-intensity crimson red for critical
    }
  }
}

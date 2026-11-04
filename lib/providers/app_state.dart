import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sensor_data.dart';
import '../models/incident_record.dart';
import '../ble/ble_manager.dart';
import '../connectivity/connectivity_manager.dart';
import '../utils/alert_service.dart';
import '../utils/app_logger.dart';
import 'threshold_provider.dart';

/// Type alias allowing AppState to be referenced as TelemetryProvider
typedef TelemetryProvider = AppState;

class AppState extends ChangeNotifier {
  final BleManager bleManager;
  final ConnectivityManager connectivityManager;
  final ThresholdProvider thresholdProvider;
  final AlertService _alertService = AlertService();

  AppState({
    required this.bleManager,
    required this.connectivityManager,
    ThresholdProvider? thresholdProvider,
  }) : thresholdProvider = thresholdProvider ?? ThresholdProvider() {
    _alertService.initialize();
    _listenToConnectivityManager();
    _alertSub = bleManager.alertFlagStream.listen(_onAlertFlag);
    _loadSavedTheme();
    _loadSavedIncidents();
    this.thresholdProvider.addListener(_onThresholdsChanged);
  }

  void _onThresholdsChanged() {
    if (hasReceivedTelemetry) {
      _checkTemperatureHazard(_lastTemperature);
      _checkHumidityAlert(_lastHumidity);
      _checkAirQualityAlert(_lastAirQuality);
    }
    notifyListeners();
  }

  Future<void> _loadSavedIncidents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('aerosense_saved_incidents');
      if (raw != null && raw.isNotEmpty) {
        final List decoded = jsonDecode(raw);
        final loaded = decoded
            .map((item) => IncidentRecord.fromMap(item as Map))
            .whereType<IncidentRecord>()
            .toList();
        if (loaded.isNotEmpty) {
          _incidents.clear();
          _incidents.addAll(loaded);
          notifyListeners();
        }
      }
    } catch (e) {
      AppLogger.w('AppState', 'Error loading saved incidents: $e');
    }
  }

  Future<void> _persistIncidents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _incidents.map((i) => i.toJson()).toList();
      await prefs.setString('aerosense_saved_incidents', jsonEncode(jsonList));
    } catch (e) {
      AppLogger.w('AppState', 'Error persisting incidents: $e');
    }
  }

  // ── Theme System ───────────────────────────────────────────────────────────
  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  bool _themeLoaded = false;

  Future<void> _loadSavedTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_themeLoaded) {
        final modeStr = prefs.getString('app_theme_mode');
        if (modeStr != null) {
          _themeMode = ThemeMode.values.firstWhere(
            (m) => m.name == modeStr,
            orElse: () => ThemeMode.dark,
          );
        } else {
          final isDark = prefs.getBool('is_dark_theme') ?? true;
          _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
        }
        _themeLoaded = true;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeLoaded = true;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_theme_mode', mode.name);
      await prefs.setBool('is_dark_theme', mode == ThemeMode.dark);
    } catch (_) {}
  }

  Future<void> toggleTheme() async {
    _themeLoaded = true;
    _themeMode = (_themeMode == ThemeMode.dark) ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_dark_theme', _themeMode == ThemeMode.dark);
    } catch (_) {}
  }

  // ── Incident management ────────────────────────────────────────────────────
  final List<IncidentRecord> _incidents = [];
  List<IncidentRecord> get incidents => List.unmodifiable(_incidents);

  IncidentRecord? _activeIncident;
  IncidentRecord? _activeTempIncident;
  IncidentRecord? _activeHumidityIncident;
  IncidentRecord? _activeAqIncident;

  IncidentRecord? get activeIncident => _activeIncident ?? _activeTempIncident ?? _activeHumidityIncident ?? _activeAqIncident;

  bool _hazardActive = false;
  bool get hazardActive => _hazardActive;

  bool _hazardSilenced = false;
  bool get hazardSilenced => _hazardSilenced;

  AlertType _currentAlertType = AlertType.temperature;
  AlertType get currentAlertType => _currentAlertType;

  // ── Sensor data ────────────────────────────────────────────────────────────
  double _lastTemperature = 0.0;
  double get lastTemperature => _lastTemperature;

  double _lastHumidity = 0.0;
  double get lastHumidity => _lastHumidity;

  int _lastAirQuality = 0;
  int get lastAirQuality => _lastAirQuality;

  // ── Temperature unit ───────────────────────────────────────────────────────
  bool _showFahrenheit = false;
  bool get showFahrenheit => _showFahrenheit;

  // ── Sampling interval ──────────────────────────────────────────────────────
  int _samplingIntervalSeconds = 2;
  int get samplingIntervalSeconds => _samplingIntervalSeconds;

  // ── History for charts ────────────────────────────────────────────────────
  final List<SensorData> _sensorHistory = [];
  List<SensorData> get sensorHistory => List.unmodifiable(_sensorHistory);

  /// Air quality trend over the last recorded samples (no simulation)
  String get airQualityTrend {
    if (_sensorHistory.length < 2) return 'AWAITING READINGS';
    final recent = _sensorHistory.length > 5
        ? _sensorHistory.sublist(_sensorHistory.length - 5)
        : _sensorHistory;
    final diff = recent.last.airQuality - recent.first.airQuality;
    if (diff > 50) return 'RISING (DETERIORATING)';
    if (diff < -50) return 'FALLING (IMPROVING)';
    return 'STABLE';
  }

  // ── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription<SensorData>? _dataSub;
  StreamSubscription<int>? _alertSub;

  bool get isBleConnected => bleManager.isConnected;
  BleConnectionState get bleState => bleManager.bleState;
  String? get connectedDeviceName => bleManager.connectedDeviceName;

  SensorData? _latestSensorData;
  SensorData? get latestSensorData => _latestSensorData;
  bool get hasReceivedTelemetry => _lastTemperature != 0.0 || _lastHumidity != 0.0 || _lastAirQuality != 0;

  // ── MPU-6050 Motion Getters ────────────────────────────────────────────────
  bool get isMpuConnected => _latestSensorData?.mpuConnected ?? bleManager.mpuDetected;
  double? get accelX => _latestSensorData?.accelX;
  double? get accelY => _latestSensorData?.accelY;
  double? get accelZ => _latestSensorData?.accelZ;
  double? get gyroX => _latestSensorData?.gyroX;
  double? get gyroY => _latestSensorData?.gyroY;
  double? get gyroZ => _latestSensorData?.gyroZ;

  /// Determines motion state without generating simulated readings
  String get motionStateLabel {
    if (!isMpuConnected) return 'SENSOR NOT CONNECTED';
    final ax = accelX ?? 0.0;
    final ay = accelY ?? 0.0;
    final az = accelZ ?? 1.0;
    final magnitude = (ax * ax + ay * ay + az * az);
    // When resting under 1g gravity (~9.8 m/s² or 1.0g), delta from 1g indicates active motion
    final deltaFromGravity = (magnitude - 1.0).abs();
    return deltaFromGravity > 0.2 ? 'IN MOTION' : 'STATIONARY';
  }

  void _listenToConnectivityManager() {
    _dataSub = connectivityManager.dataStream.listen(_onSensorData);
  }

  void _onSensorData(SensorData data) {
    _latestSensorData = data;
    _lastTemperature = data.temperature;
    _lastHumidity = data.humidity;
    _lastAirQuality = data.airQuality;

    _sensorHistory.add(data);
    if (_sensorHistory.length > 500) _sensorHistory.removeAt(0);

    _checkTemperatureHazard(data.temperature);
    _checkHumidityAlert(data.humidity);
    _checkAirQualityAlert(data.airQuality);

    notifyListeners();
  }

  void _checkTemperatureHazard(double temp) {
    // Data integrity: Do not trigger alerts when temperature data is unavailable or uninitialized
    if (temp <= 0.0 || temp.isNaN || temp.isInfinite || !hasReceivedTelemetry) return;
    if (!thresholdProvider.enableTempAlerts) return;

    final isCritical = temp > thresholdProvider.tempWarningMax;
    final isWarning = temp > thresholdProvider.tempNormalMax;

    if (isCritical || isWarning) {
      if (_activeTempIncident == null) {
        final incidentId = 'INC-${DateTime.now().millisecondsSinceEpoch}';
        final incident = IncidentRecord(
          id: incidentId,
          startTime: DateTime.now(),
          alertType: AlertType.temperature,
          peakTemperature: temp,
        );
        _activeTempIncident = incident;
        _activeIncident = incident;
        _incidents.insert(0, incident);
        _persistIncidents();

        if (isCritical) {
          _hazardActive = true;
          _hazardSilenced = false;
          _currentAlertType = AlertType.temperature;
          if (thresholdProvider.enableSound || thresholdProvider.enableVibration) {
            _alertService.showTemperatureAlert(temp);
          }
        }
        connectivityManager.firebaseService.logIncident(incident);
      } else {
        // Continuous thermal breach: update peak temperature without creating duplicate incidents
        if (temp > _activeTempIncident!.peakTemperature) {
          _activeTempIncident!.peakTemperature = temp;
          _persistIncidents();
          connectivityManager.firebaseService.updateIncident(_activeTempIncident!);
        }
        if (isCritical && !_hazardActive) {
          _hazardActive = true;
          _hazardSilenced = false;
          _currentAlertType = AlertType.temperature;
          if (thresholdProvider.enableSound || thresholdProvider.enableVibration) {
            _alertService.showTemperatureAlert(temp);
          }
        }
      }
    } else if (_activeTempIncident != null) {
      // Temperature has safely returned below normal threshold
      _activeTempIncident!.endTime = DateTime.now();
      connectivityManager.firebaseService.updateIncident(_activeTempIncident!);
      _persistIncidents();
      if (_activeIncident == _activeTempIncident) {
        _activeIncident = null;
      }
      _activeTempIncident = null;
      if (_hazardActive && _currentAlertType == AlertType.temperature) {
        _hazardActive = false;
        _hazardSilenced = false;
      }
    }
  }

  void _checkHumidityAlert(double humidity) {
    if (humidity <= 0.0 || humidity.isNaN || !hasReceivedTelemetry) return;
    if (!thresholdProvider.enableHumidityAlerts) return;

    final isCritical = humidity > thresholdProvider.humidityMax || (humidity > 0 && humidity < thresholdProvider.humidityMin);
    final isWarning = humidity > thresholdProvider.humidityNormalMax || (humidity > 0 && humidity < thresholdProvider.humidityNormalMin);

    if (isCritical || isWarning) {
      if (_activeHumidityIncident == null) {
        final incidentId = 'INC-${DateTime.now().millisecondsSinceEpoch}';
        final incident = IncidentRecord(
          id: incidentId,
          startTime: DateTime.now(),
          alertType: AlertType.humidity,
          peakTemperature: _lastTemperature,
          peakHumidity: humidity,
        );
        _activeHumidityIncident = incident;
        _incidents.insert(0, incident);
        _persistIncidents();

        if (isCritical && !_hazardActive) {
          _hazardActive = true;
          _hazardSilenced = false;
          _currentAlertType = AlertType.humidity;
          if (thresholdProvider.enableSound || thresholdProvider.enableVibration) {
            _alertService.showHumidityAlert(humidity);
          }
        }
        connectivityManager.firebaseService.logIncident(incident);
      } else if (humidity > _activeHumidityIncident!.peakHumidity) {
        _activeHumidityIncident!.peakHumidity = humidity;
        _persistIncidents();
        connectivityManager.firebaseService.updateIncident(_activeHumidityIncident!);
      }
    } else if (_activeHumidityIncident != null) {
      _activeHumidityIncident!.endTime = DateTime.now();
      connectivityManager.firebaseService.updateIncident(_activeHumidityIncident!);
      _persistIncidents();
      _activeHumidityIncident = null;
      if (_hazardActive && _currentAlertType == AlertType.humidity) {
        _hazardActive = false;
        _hazardSilenced = false;
      }
    }
  }

  void _checkAirQualityAlert(int aq) {
    if (aq <= 0 || !hasReceivedTelemetry) return;
    if (!thresholdProvider.enableAirQualityAlerts) return;

    final isCritical = aq > thresholdProvider.aqWarningMax;
    final isWarning = aq > thresholdProvider.aqNormalMax;

    if (isCritical || isWarning) {
      if (_activeAqIncident == null) {
        final incidentId = 'INC-${DateTime.now().millisecondsSinceEpoch}';
        final incident = IncidentRecord(
          id: incidentId,
          startTime: DateTime.now(),
          alertType: AlertType.airQuality,
          peakTemperature: _lastTemperature,
          peakAirQuality: aq,
        );
        _activeAqIncident = incident;
        _incidents.insert(0, incident);
        _persistIncidents();

        if (isCritical && !_hazardActive) {
          _hazardActive = true;
          _hazardSilenced = false;
          _currentAlertType = AlertType.airQuality;
          if (thresholdProvider.enableSound || thresholdProvider.enableVibration) {
            _alertService.showAirQualityAlert(aq);
          }
        }
        connectivityManager.firebaseService.logIncident(incident);
      } else if (aq > _activeAqIncident!.peakAirQuality) {
        _activeAqIncident!.peakAirQuality = aq;
        _persistIncidents();
        connectivityManager.firebaseService.updateIncident(_activeAqIncident!);
      }
    } else if (_activeAqIncident != null) {
      _activeAqIncident!.endTime = DateTime.now();
      connectivityManager.firebaseService.updateIncident(_activeAqIncident!);
      _persistIncidents();
      _activeAqIncident = null;
      if (_hazardActive && _currentAlertType == AlertType.airQuality) {
        _hazardActive = false;
        _hazardSilenced = false;
      }
    }
  }

  /// Manually refreshes live sensor telemetry from all available streams
  Future<void> refreshTelemetry() async {
    await connectivityManager.refresh();
    notifyListeners();
  }

  void _onAlertFlag(int flag) {
    if (flag > 0 && !_hazardActive) {
      _hazardActive = true;
      _hazardSilenced = false;
      notifyListeners();
    }
  }

  /// Acknowledges and silences active hazard haptics/modal without marking temperature safe.
  /// Continuous monitoring remains active until actual DHT22 reading returns below 35.0°C.
  void silenceHazard() => acknowledgeHazard();

  void acknowledgeHazard() {
    _hazardSilenced = true;
    final inc = _activeIncident ?? _activeTempIncident;
    if (inc != null) {
      inc.acknowledged = true;
      inc.acknowledgedAt = DateTime.now();
      _persistIncidents();
      connectivityManager.firebaseService.writeAcknowledgement(
        inc.id,
        ackedAt: inc.acknowledgedAt,
      );
      connectivityManager.firebaseService.updateIncident(inc);
    }
    // IMPORTANT: _hazardActive remains TRUE until temperature returns below threshold
    notifyListeners();
  }

  void acknowledgeIncident(String id) {
    final idx = _incidents.indexWhere((i) => i.id == id);
    if (idx != -1) {
      _incidents[idx].acknowledged = !_incidents[idx].acknowledged;
      _incidents[idx].acknowledgedAt = _incidents[idx].acknowledged ? DateTime.now() : null;
      _persistIncidents();
      connectivityManager.firebaseService.updateIncident(_incidents[idx]);
      notifyListeners();
    }
  }

  void markAllIncidentsRead() {
    final now = DateTime.now();
    for (final inc in _incidents) {
      if (!inc.acknowledged) {
        inc.acknowledged = true;
        inc.acknowledgedAt = now;
        connectivityManager.firebaseService.updateIncident(inc);
      }
    }
    _persistIncidents();
    notifyListeners();
  }

  int get unreadIncidentsCount => _incidents.where((i) => !i.acknowledged).length;

  void toggleTemperatureUnit() {
    _showFahrenheit = !_showFahrenheit;
    notifyListeners();
  }

  Future<void> setSamplingInterval(int seconds) async {
    _samplingIntervalSeconds = seconds;
    await bleManager.writeSamplingInterval(seconds);
    notifyListeners();
  }

  // ── Stats ──────────────────────────────────────────────────────────────────
  int get totalIncidentsToday {
    final now = DateTime.now();
    return _incidents.where((i) =>
      i.startTime.year == now.year &&
      i.startTime.month == now.month &&
      i.startTime.day == now.day
    ).length;
  }

  int get totalIncidentsCount => _incidents.length;

  Duration get totalHazardDuration {
    return _incidents.fold(Duration.zero, (prev, i) => prev + i.duration);
  }

  double get maxPeakTemp => maxRecordedTemperature;

  double get maxRecordedTemperature {
    if (_incidents.isEmpty) return 0.0;
    return _incidents
        .where((i) => i.alertType == AlertType.temperature)
        .map((i) => i.peakTemperature)
        .fold(0.0, (a, b) => a > b ? a : b);
  }

  // Daily/weekly grouped history
  List<SensorData> getHistoryForLastHours(int hours) {
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    return _sensorHistory.where((d) => d.timestamp.isAfter(cutoff)).toList();
  }

  @override
  void dispose() {
    thresholdProvider.removeListener(_onThresholdsChanged);
    _dataSub?.cancel();
    _alertSub?.cancel();
    super.dispose();
  }
}

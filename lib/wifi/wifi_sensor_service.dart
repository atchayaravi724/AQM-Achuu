import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/sensor_data.dart';
import '../utils/app_logger.dart';

/// Polls the ESP32 HTTP server for sensor data over Wi-Fi.
/// The ESP32 exposes: GET http://<ip>/sensors
/// Response JSON: {"temperature":28.4,"humidity":62.1,"air_quality":145,"uptime":3600}
class WiFiSensorService extends ChangeNotifier {
  String _espIpAddress = '';
  String get espIpAddress => _espIpAddress;

  String _connectedSsid = '';
  String get connectedSsid => _connectedSsid;

  void setConnectedSsid(String ssid) {
    _connectedSsid = ssid;
    notifyListeners();
  }

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _isPolling = false;
  bool get isPolling => _isPolling;

  SensorData? _lastReading;
  SensorData? get lastReading => _lastReading;

  String _lastError = '';
  String get lastError => _lastError;

  int _failureCount = 0;
  static const int _maxFailures = 5;

  Timer? _pollTimer;
  int _pollIntervalSeconds = 2;

  final _sensorController = StreamController<SensorData>.broadcast();
  Stream<SensorData> get sensorStream => _sensorController.stream;

  final _connectionController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStream => _connectionController.stream;

  void setIpAddress(String ip) {
    _espIpAddress = ip.trim();
    notifyListeners();
  }

  void setPollInterval(int seconds) {
    _pollIntervalSeconds = seconds.clamp(1, 60);
    if (_isPolling) {
      stopPolling();
      startPolling();
    }
  }

  Future<bool> testConnection() async {
    if (_espIpAddress.isEmpty) return false;
    try {
      final response = await http
          .get(Uri.parse('http://$_espIpAddress/sensors'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void startPolling() {
    if (_isPolling) return;
    _isPolling = true;
    _failureCount = 0;
    notifyListeners();
    _pollTimer = Timer.periodic(
      Duration(seconds: _pollIntervalSeconds),
      (_) => _fetchSensorData(),
    );
    _fetchSensorData(); // immediate first fetch
  }

  void stopPolling() {
    _isPolling = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _setConnected(false);
    notifyListeners();
  }

  Future<void> _fetchSensorData() async {
    if (_espIpAddress.isEmpty) return;
    try {
      final response = await http
          .get(Uri.parse('http://$_espIpAddress/sensors'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = SensorData(
          temperature: (json['temperature'] as num).toDouble(),
          humidity: (json['humidity'] as num).toDouble(),
          airQuality: (json['air_quality'] as num?)?.toInt() ?? 0,
          source: DataSource.wifi,
          timestamp: DateTime.now(),
        );
        _lastReading = data;
        _lastError = '';
        _failureCount = 0;
        _sensorController.add(data);
        _setConnected(true);
      } else {
        _onFetchError('HTTP ${response.statusCode}');
      }
    } on TimeoutException {
      _onFetchError('Timeout — ESP32 not responding');
    } catch (e) {
      _onFetchError(e.toString());
    }
  }

  void _onFetchError(String error) {
    _lastError = error;
    _failureCount++;
    AppLogger.d('WiFi', 'Fetch error ($_failureCount/$_maxFailures): $error');
    if (_failureCount >= _maxFailures) {
      _setConnected(false);
    }
    notifyListeners();
  }

  void _setConnected(bool connected) {
    if (_isConnected == connected) return;
    _isConnected = connected;
    _connectionController.add(connected);
    notifyListeners();
  }

  @visibleForTesting
  void injectDataForTesting(SensorData data) {
    _lastReading = data;
    _sensorController.add(data);
    _setConnected(true);
    notifyListeners();
  }

  @override
  void dispose() {
    stopPolling();
    _sensorController.close();
    _connectionController.close();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../ble/ble_constants.dart';
import '../models/sensor_data.dart';
import '../utils/app_logger.dart';

/// Standard BLE connection states for AERION – AeroSense lifecycle management
enum BleConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  reconnecting,
  connectionFailed,
}

enum ConnectionStep {
  idle,
  connecting,
  bonding,
  discoveringServices,
  subscribingGatt,
  connected,
  reconnecting,
  disconnected,
}

class BleManager extends ChangeNotifier {
  // Stream controllers
  final _scanResultsController = StreamController<List<ScanResult>>.broadcast();
  final _connectionStepController = StreamController<ConnectionStep>.broadcast();
  final _bleStateController = StreamController<BleConnectionState>.broadcast();
  final _temperatureController = StreamController<double>.broadcast();
  final _humidityController = StreamController<double>.broadcast();
  final _airQualityController = StreamController<int>.broadcast();
  final _alertFlagController = StreamController<int>.broadcast();
  final _rssiController = StreamController<int>.broadcast();

  Stream<List<ScanResult>> get scanResultsStream => _scanResultsController.stream;
  Stream<ConnectionStep> get connectionStepStream => _connectionStepController.stream;
  Stream<BleConnectionState> get bleStateStream => _bleStateController.stream;
  Stream<double> get temperatureStream => _temperatureController.stream;
  Stream<double> get humidityStream => _humidityController.stream;
  Stream<int> get airQualityStream => _airQualityController.stream;
  Stream<int> get alertFlagStream => _alertFlagController.stream;
  Stream<int> get rssiStream => _rssiController.stream;

  // State
  BleConnectionState _bleState = BleConnectionState.disconnected;
  BleConnectionState get bleState => _bleState;

  bool get isConnected => _bleState == BleConnectionState.connected;
  bool get isReconnecting => _bleState == BleConnectionState.reconnecting;
  bool get isFailed => _bleState == BleConnectionState.connectionFailed;

  ConnectionStep _connectionStep = ConnectionStep.idle;
  ConnectionStep get connectionStep => _connectionStep;

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  BluetoothCharacteristic? _tempChar;
  BluetoothCharacteristic? _humidityChar;
  BluetoothCharacteristic? _airQualityChar;
  BluetoothCharacteristic? _samplingIntervalChar;
  BluetoothCharacteristic? _alertChar;

  double _lastTemperature = 0.0;
  double _lastHumidity = 0.0;
  int _lastAirQuality = 0;
  int _lastRssi = 0;
  int get lastRssi => _lastRssi;
  int? get rssi => _connectedDevice != null ? _lastRssi : null;
  double get lastTemperature => _lastTemperature;
  double get lastHumidity => _lastHumidity;
  int get lastAirQuality => _lastAirQuality;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  List<ScanResult> _scanResults = [];
  List<ScanResult> get scanResults => List.unmodifiable(_scanResults);

  String? get connectedDeviceName {
    if (_connectedDevice == null) return null;
    if (_connectedDevice!.platformName.isNotEmpty) return _connectedDevice!.platformName;
    if (_connectedDevice!.advName.isNotEmpty) return _connectedDevice!.advName;
    return _connectedDevice!.remoteId.str;
  }

  // Moving average buffers
  final List<double> _tempBuffer = [];
  final List<double> _humidityBuffer = [];
  final List<int> _airQualityBuffer = [];
  static const int _filterSize = 5;

  // Subscriptions
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanningSub;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  StreamSubscription<List<int>>? _tempSub;
  StreamSubscription<List<int>>? _humiditySub;
  StreamSubscription<List<int>>? _airQualitySub;
  StreamSubscription<List<int>>? _alertSub;
  Timer? _rssiTimer;
  Timer? _reconnectTimer;

  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;
  bool _intentionalDisconnect = false;

  BleManager() {
    _initScannerListener();
  }

  void _initScannerListener() {
    if (kIsWeb) return;
    try {
      _isScanningSub = FlutterBluePlus.isScanning.listen((scanning) {
        if (_isScanning != scanning) {
          _isScanning = scanning;
          notifyListeners();
        }
      });
    } catch (e) {
      AppLogger.w('BLE', 'isScanning listener init error: $e');
    }
  }

  /// Deterministic exponential backoff calculation for BLE reconnection:
  /// Attempt 0: 2s
  /// Attempt 1: 4s
  /// Attempt 2: 8s
  /// Attempt 3: 16s
  /// Attempt 4: 32s
  /// Max capped at 60s
  static Duration calculateBackoffDelay(int attempt) {
    if (attempt < 0) attempt = 0;
    final seconds = (2 * (1 << attempt)).clamp(2, 60);
    return Duration(seconds: seconds);
  }

  void _setState(BleConnectionState state) {
    if (_bleState == state) return;
    _bleState = state;
    _bleStateController.add(state);
    notifyListeners();
  }

  /// Hardware state of MPU6050 motion sensor.
  /// Remains false until physical hardware is wired and detected by firmware.
  /// Absolutely NO simulated readings are generated.
  bool get mpuDetected => false;

  /// Decodes motion telemetry payload when physically present.
  /// Expects either ASCII comma-separated values ("ax,ay,az,gx,gy,gz")
  /// or 24-byte binary (6 x 4-byte IEEE 754 float32: ax, ay, az, gx, gy, gz in little-endian).
  /// Returns null if payload is invalid or sensor is disconnected (no fake data).
  static Map<String, double>? parseMotionTelemetry(List<int> bytes) {
    if (bytes.isEmpty) return null;

    // 1. ASCII CSV payload ("ax,ay,az,gx,gy,gz")
    try {
      final str = utf8.decode(bytes).trim();
      if (str.contains(',')) {
        final parts = str.split(',');
        if (parts.length == 6) {
          final parsed = parts.map((p) => double.tryParse(p.trim())).toList();
          if (!parsed.contains(null)) {
            return {
              'accelX': parsed[0]!,
              'accelY': parsed[1]!,
              'accelZ': parsed[2]!,
              'gyroX': parsed[3]!,
              'gyroY': parsed[4]!,
              'gyroZ': parsed[5]!,
            };
          }
        }
      }
    } catch (_) {}

    // 2. Binary payload (exactly 24 bytes for 6 x float32 in little-endian)
    if (bytes.length == 24) {
      final bd = ByteData.sublistView(Uint8List.fromList(bytes));
      final ax = bd.getFloat32(0, Endian.little);
      final ay = bd.getFloat32(4, Endian.little);
      final az = bd.getFloat32(8, Endian.little);
      final gx = bd.getFloat32(12, Endian.little);
      final gy = bd.getFloat32(16, Endian.little);
      final gz = bd.getFloat32(20, Endian.little);
      if (!ax.isNaN && !ay.isNaN && !az.isNaN &&
          !gx.isNaN && !gy.isNaN && !gz.isNaN) {
        return {
          'accelX': ax,
          'accelY': ay,
          'accelZ': az,
          'gyroX': gx,
          'gyroY': gy,
          'gyroZ': gz,
        };
      }
    }

    return null;
  }

  /// Checks if device name begins with the AeroSense target prefix AQM-
  static bool isTargetDeviceName(String name) {
    return name.trim().toUpperCase().startsWith(BleConstants.targetDevicePrefix.toUpperCase());
  }

  /// Robust helper to extract the best human-readable device name
  /// from BLE advertisement or cached platform name.
  static String getDeviceName(ScanResult r) {
    final advName = r.advertisementData.advName.trim();
    if (advName.isNotEmpty) return advName;

    final platformName = r.device.platformName.trim();
    if (platformName.isNotEmpty) return platformName;

    return 'Unknown Device';
  }

  /// Returns true if the device matches the AeroSense target prefix (AQM-*)
  /// or advertises the AeroSense custom GATT service UUID.
  static bool isAeroSenseDevice(ScanResult r) {
    final name = getDeviceName(r);
    if (isTargetDeviceName(name)) {
      return true;
    }
    return r.advertisementData.serviceUuids.contains(BleConstants.serviceGuid);
  }

  void _setStep(ConnectionStep step) {
    _connectionStep = step;
    _connectionStepController.add(step);
    notifyListeners();
  }

  Future<void> connectToDevice(BluetoothDevice device) => connectTo(device);

  Future<void> startScan() async {
    if (kIsWeb) {
      AppLogger.i('BLE', 'Scanning not supported on Web (Chrome).');
      return;
    }

    _isScanning = true;
    _setState(BleConnectionState.scanning);
    notifyListeners();
    _scanResults = [];
    _scanResultsController.add([]);

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      // Deduplicate by remote ID and sort: target devices (AQM-*) on top, then highest RSSI
      final Map<String, ScanResult> seen = {};
      for (final r in results) {
        seen[r.device.remoteId.str] = r;
      }
      final list = seen.values.toList();
      list.sort((a, b) {
        final aIsTarget = isAeroSenseDevice(a);
        final bIsTarget = isAeroSenseDevice(b);
        if (aIsTarget && !bIsTarget) return -1;
        if (!aIsTarget && bIsTarget) return 1;
        return b.rssi.compareTo(a.rssi);
      });
      _scanResults = list;
      _scanResultsController.add(list);
      notifyListeners();
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      AppLogger.e('BLE', 'Scan error', e);
      _isScanning = false;
      _setState(BleConnectionState.disconnected);
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    _isScanning = false;
    if (_bleState == BleConnectionState.scanning) {
      _setState(BleConnectionState.disconnected);
    }
    notifyListeners();
    if (!kIsWeb) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
    _scanSub?.cancel();
  }

  Future<void> connectTo(BluetoothDevice device) async {
    _intentionalDisconnect = false;
    _reconnectAttempts = 0;
    await _doConnect(device);
  }

  Future<void> _doConnect(BluetoothDevice device) async {
    try {
      _setState(BleConnectionState.connecting);
      _setStep(ConnectionStep.connecting);
      await device.connect(timeout: const Duration(seconds: 15), autoConnect: false);

      // On Android, request MTU 512 for optimal sensor telemetry throughput
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
          await device.requestMtu(512);
        } catch (e) {
          AppLogger.d('BLE', 'MTU request notice: $e');
        }
      }

      _setStep(ConnectionStep.bonding);
      await Future.delayed(const Duration(milliseconds: 500));

      _setStep(ConnectionStep.discoveringServices);
      final services = await device.discoverServices();

      // Find our service
      BluetoothService? targetService;
      for (final s in services) {
        if (s.uuid == BleConstants.serviceGuid) {
          targetService = s;
          break;
        }
      }
      if (targetService == null) {
        throw Exception('AeroSense BLE Service not found on device');
      }

      // Find characteristics
      for (final c in targetService.characteristics) {
        if (c.uuid == BleConstants.temperatureGuid) _tempChar = c;
        if (c.uuid == BleConstants.humidityGuid) _humidityChar = c;
        if (c.uuid == BleConstants.airQualityGuid) _airQualityChar = c;
        if (c.uuid == BleConstants.samplingIntervalGuid) _samplingIntervalChar = c;
        if (c.uuid == BleConstants.alertGuid) _alertChar = c;
      }

      // Read initial values
      if (_tempChar != null) {
        final val = await _tempChar!.read();
        final t = SensorData.parseFloat(val);
        _applyTempFilter(t);
      }
      if (_humidityChar != null) {
        final val = await _humidityChar!.read();
        final h = SensorData.parseFloat(val);
        _applyHumidityFilter(h);
      }
      if (_airQualityChar != null) {
        final val = await _airQualityChar!.read();
        final aq = SensorData.parseAirQuality(val);
        _applyAirQualityFilter(aq);
      }

      _setStep(ConnectionStep.subscribingGatt);

      // Subscribe temp
      if (_tempChar != null && _tempChar!.properties.notify) {
        await _tempChar!.setNotifyValue(true);
        _tempSub?.cancel();
        _tempSub = _tempChar!.onValueReceived.listen((val) {
          final t = SensorData.parseFloat(val);
          if (t > -40 && t < 150) _applyTempFilter(t);
        });
      }

      // Subscribe humidity
      if (_humidityChar != null && _humidityChar!.properties.notify) {
        await _humidityChar!.setNotifyValue(true);
        _humiditySub?.cancel();
        _humiditySub = _humidityChar!.onValueReceived.listen((val) {
          final h = SensorData.parseFloat(val);
          if (h >= 0 && h <= 100) _applyHumidityFilter(h);
        });
      }

      // Subscribe air quality (MQ-135)
      if (_airQualityChar != null && _airQualityChar!.properties.notify) {
        await _airQualityChar!.setNotifyValue(true);
        _airQualitySub?.cancel();
        _airQualitySub = _airQualityChar!.onValueReceived.listen((val) {
          final aq = SensorData.parseAirQuality(val);
          _applyAirQualityFilter(aq);
        });
      }

      // Subscribe alert
      if (_alertChar != null && _alertChar!.properties.notify) {
        await _alertChar!.setNotifyValue(true);
        _alertSub?.cancel();
        _alertSub = _alertChar!.onValueReceived.listen((val) {
          if (val.isNotEmpty) _alertFlagController.add(val[0]);
        });
      }

      _connectedDevice = device;
      _isScanning = false;
      _reconnectAttempts = 0;
      _setState(BleConnectionState.connected);
      _setStep(ConnectionStep.connected);

      // RSSI polling
      _rssiTimer?.cancel();
      _rssiTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          final rssi = await device.readRssi();
          _lastRssi = rssi;
          _rssiController.add(rssi);
        } catch (_) {}
      });

      // Listen for disconnection
      _connectionStateSub?.cancel();
      _connectionStateSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && !_intentionalDisconnect) {
          _handleDisconnect(device);
        }
      });
    } catch (e) {
      AppLogger.e('BLE', 'Connect error', e);
      _handleDisconnect(device);
    }
  }

  void _handleDisconnect(BluetoothDevice device) {
    _rssiTimer?.cancel();
    _tempSub?.cancel();
    _humiditySub?.cancel();
    _airQualitySub?.cancel();
    _alertSub?.cancel();
    _tempChar = null;
    _humidityChar = null;
    _airQualityChar = null;
    _samplingIntervalChar = null;
    _alertChar = null;

    if (_reconnectAttempts < _maxReconnectAttempts) {
      _setState(BleConnectionState.reconnecting);
      _setStep(ConnectionStep.reconnecting);
      final delay = calculateBackoffDelay(_reconnectAttempts);
      _reconnectAttempts++;
      AppLogger.d('BLE', 'Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)');
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(delay, () => _doConnect(device));
    } else {
      _setState(BleConnectionState.connectionFailed);
      _setStep(ConnectionStep.disconnected);
      _connectedDevice = null;
      AppLogger.w('BLE', 'Reconnection attempts exhausted ($_maxReconnectAttempts/$_maxReconnectAttempts). Connection failed.');
    }
  }

  /// Cancels any active reconnection backoff timer and resets state to disconnected
  void cancelReconnection() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _connectedDevice = null;
    _setState(BleConnectionState.disconnected);
    _setStep(ConnectionStep.disconnected);
    notifyListeners();
  }

  void _applyTempFilter(double value) {
    _tempBuffer.add(value);
    if (_tempBuffer.length > _filterSize) _tempBuffer.removeAt(0);
    final avg = _tempBuffer.reduce((a, b) => a + b) / _tempBuffer.length;
    _lastTemperature = avg;
    _temperatureController.add(avg);
    notifyListeners();
  }

  void _applyHumidityFilter(double value) {
    _humidityBuffer.add(value);
    if (_humidityBuffer.length > _filterSize) _humidityBuffer.removeAt(0);
    final avg = _humidityBuffer.reduce((a, b) => a + b) / _humidityBuffer.length;
    _lastHumidity = avg;
    _humidityController.add(avg);
    notifyListeners();
  }

  void _applyAirQualityFilter(int value) {
    _airQualityBuffer.add(value);
    if (_airQualityBuffer.length > _filterSize) _airQualityBuffer.removeAt(0);
    final avg = (_airQualityBuffer.reduce((a, b) => a + b) / _airQualityBuffer.length).round();
    _lastAirQuality = avg;
    _airQualityController.add(avg);
    notifyListeners();
  }

  Future<void> writeSamplingInterval(int seconds) async {
    if (_samplingIntervalChar == null) return;
    try {
      final data = ByteData(2);
      data.setUint16(0, seconds, Endian.little);
      await _samplingIntervalChar!.write(data.buffer.asUint8List(), withoutResponse: false);
    } catch (e) {
      AppLogger.e('BLE', 'Write sampling interval error', e);
    }
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _rssiTimer?.cancel();
    _tempSub?.cancel();
    _humiditySub?.cancel();
    _airQualitySub?.cancel();
    _alertSub?.cancel();
    _connectionStateSub?.cancel();
    try {
      await _connectedDevice?.disconnect();
    } catch (_) {}
    _connectedDevice = null;
    _tempChar = null;
    _humidityChar = null;
    _airQualityChar = null;
    _samplingIntervalChar = null;
    _alertChar = null;
    _tempBuffer.clear();
    _humidityBuffer.clear();
    _airQualityBuffer.clear();
    _setState(BleConnectionState.disconnected);
    _setStep(ConnectionStep.idle);
  }

  @override
  void dispose() {
    disconnect();
    _isScanningSub?.cancel();
    _scanSub?.cancel();
    _scanResultsController.close();
    _connectionStepController.close();
    _bleStateController.close();
    _temperatureController.close();
    _humidityController.close();
    _airQualityController.close();
    _alertFlagController.close();
    _rssiController.close();
    super.dispose();
  }
}

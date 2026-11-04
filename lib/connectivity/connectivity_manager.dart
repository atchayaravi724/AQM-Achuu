import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../wifi/wifi_sensor_service.dart';
import '../firebase/firebase_service.dart';
import '../ble/ble_manager.dart';
import '../models/sensor_data.dart';
import '../utils/app_logger.dart';

enum ConnectivityMode { none, ble, wifi, firebase }

/// Orchestrates automatic switching between BLE, Wi-Fi HTTP, and Firebase.
/// Priority: Firebase (most reliable) > WiFi HTTP > BLE (fallback)
/// Auto-reconnects when a higher-priority channel becomes available.
class ConnectivityManager extends ChangeNotifier {
  final WiFiSensorService wifiService;
  final FirebaseService firebaseService;
  final BleManager bleManager;

  ConnectivityManager({
    required this.wifiService,
    required this.firebaseService,
    required this.bleManager,
  }) {
    _init();
  }

  ConnectivityMode _activeMode = ConnectivityMode.none;
  ConnectivityMode get activeMode => _activeMode;

  bool _hasInternetAccess = false;
  bool get hasInternetAccess => _hasInternetAccess;

  SensorData? _latestData;
  SensorData? get latestData => _latestData;

  final _dataController = StreamController<SensorData>.broadcast();
  Stream<SensorData> get dataStream => _dataController.stream;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<SensorData>? _wifiDataSub;
  StreamSubscription<SensorData>? _firebaseDataSub;
  StreamSubscription<double>? _bleTempSub;
  StreamSubscription<int>? _bleAqSub;
  StreamSubscription<BleConnectionState>? _bleStateSub;
  StreamSubscription<bool>? _wifiConnSub;

  void _init() {
    // Monitor network connectivity
    try {
      _connectivitySub = Connectivity()
          .onConnectivityChanged
          .listen(_onConnectivityChanged);

      // Check initial connectivity
      Connectivity().checkConnectivity().then(_onConnectivityChanged).catchError((e) {
        AppLogger.d('Connectivity', 'Initial connectivity check skipped: $e');
      });
    } catch (e) {
      AppLogger.d('Connectivity', 'Connectivity listener skipped: $e');
    }

    // Listen to all data sources — highest priority wins
    _firebaseDataSub = firebaseService.sensorStream.listen(_onFirebaseData);
    _wifiDataSub = wifiService.sensorStream.listen(_onWifiData);

    // BLE telemetry streams
    _bleTempSub = bleManager.temperatureStream.listen((_) => _onBleData());
    _bleAqSub = bleManager.airQualityStream.listen((_) => _onBleData());

    // Monitor BLE connection lifecycle
    _bleStateSub = bleManager.bleStateStream.listen(_onBleStateChanged);
  }

  void _onBleStateChanged(BleConnectionState state) {
    if (state == BleConnectionState.disconnected ||
        state == BleConnectionState.connectionFailed) {
      if (_activeMode == ConnectivityMode.ble) {
        _setMode(ConnectivityMode.none);
      }
      if (firebaseService.isAvailable && _hasInternetAccess) {
        firebaseService.updateDeviceStatus('DISCONNECTED', connectionMode: 'NONE');
      }
    } else if (state == BleConnectionState.connected) {
      if (_activeMode == ConnectivityMode.none) {
        _setMode(ConnectivityMode.ble);
      }
      if (firebaseService.isAvailable && _hasInternetAccess) {
        firebaseService.updateDeviceStatus('CONNECTED', connectionMode: 'BLE');
      }
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final hasNetwork = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);

    final wasConnected = _hasInternetAccess;
    _hasInternetAccess = hasNetwork;

    if (hasNetwork && !wasConnected) {
      // Network restored — try Firebase/WiFi first
      AppLogger.i('Connectivity', 'Network restored — switching from BLE');
      if (firebaseService.isAvailable) {
        firebaseService.startListening();
        firebaseService.flushOfflineBuffer();
      }
      if (wifiService.espIpAddress.isNotEmpty) {
        wifiService.startPolling();
      }
    } else if (!hasNetwork && wasConnected) {
      // Network lost — fall back to BLE
      AppLogger.i('Connectivity', 'Network lost — falling back to BLE');
      wifiService.stopPolling();
      _setMode(ConnectivityMode.ble);
    }
    notifyListeners();
  }

  void _onFirebaseData(SensorData data) {
    if (_hasInternetAccess && firebaseService.isConnected) {
      _setMode(ConnectivityMode.firebase);
      _emit(data);
    }
  }

  void _onWifiData(SensorData data) {
    // Use WiFi only if Firebase is not connected
    if (_activeMode != ConnectivityMode.firebase) {
      _setMode(ConnectivityMode.wifi);
      _emit(data);
    }
  }

  void _onBleData() {
    final temp = bleManager.lastTemperature;
    final hum = bleManager.lastHumidity;
    final aq = bleManager.lastAirQuality;

    // Discard zero/dummy uninitialized readings
    if (temp == 0.0 && hum == 0.0 && aq == 0) return;

    final data = SensorData(
      temperature: temp,
      humidity: hum,
      airQuality: aq,
      source: DataSource.ble,
      timestamp: DateTime.now(),
      mpuConnected: bleManager.mpuDetected,
    );

    // Use BLE only if no higher-priority channel is active
    if (_activeMode == ConnectivityMode.none ||
        _activeMode == ConnectivityMode.ble) {
      _setMode(ConnectivityMode.ble);
      _emit(data);
    }

    // IoT Edge Gateway: Relay actual BLE telemetry to Firebase RTDB if online
    if (firebaseService.isAvailable && _hasInternetAccess) {
      firebaseService.syncBleTelemetry(
        data,
        deviceName: bleManager.connectedDeviceName,
        deviceId: bleManager.connectedDevice?.remoteId.str,
      );
    }
  }

  void _emit(SensorData data) {
    _latestData = data;
    _dataController.add(data);
    notifyListeners();
  }

  void _setMode(ConnectivityMode mode) {
    if (_activeMode == mode) return;
    _activeMode = mode;
    AppLogger.d('Connectivity', 'Mode → $mode');
    notifyListeners();
  }

  /// Call this when user enters ESP32 IP address in WiFi Monitor screen
  void connectWifi(String ipAddress) {
    wifiService.setIpAddress(ipAddress);
    wifiService.startPolling();
  }

  void disconnectWifi() {
    wifiService.stopPolling();
    if (_activeMode == ConnectivityMode.wifi) {
      _setMode(ConnectivityMode.ble);
    }
  }

  /// Manually triggers a re-fetch across all active connectivity channels
  Future<void> refresh() async {
    if (firebaseService.isAvailable) {
      await firebaseService.fetchLatest();
    }
    if (bleManager.isConnected) {
      _onBleData();
    }
    notifyListeners();
  }

  String get modeLabel {
    switch (_activeMode) {
      case ConnectivityMode.firebase: return 'FIREBASE';
      case ConnectivityMode.wifi:     return 'WI-FI';
      case ConnectivityMode.ble:      return 'BLUETOOTH';
      case ConnectivityMode.none:     return 'NO SIGNAL';
    }
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _wifiDataSub?.cancel();
    _firebaseDataSub?.cancel();
    _bleTempSub?.cancel();
    _bleAqSub?.cancel();
    _bleStateSub?.cancel();
    _wifiConnSub?.cancel();
    _dataController.close();
    super.dispose();
  }
}


import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/sensor_data.dart';
import '../models/incident_record.dart';
import '../utils/app_logger.dart';

/// Offline queued telemetry record for store-and-forward resilience
class QueuedTelemetry {
  final SensorData data;
  final String recordId;
  final int timestamp;
  final String? deviceName;
  final String? deviceId;

  const QueuedTelemetry({
    required this.data,
    required this.recordId,
    required this.timestamp,
    this.deviceName,
    this.deviceId,
  });

  Map<String, dynamic> toMap() {
    final dName = deviceName;
    final dId = deviceId;
    return {
      'temperature': data.temperature,
      'humidity': data.humidity,
      'air_quality': data.airQuality,
      'timestamp': timestamp,
      'source': 'OFFLINE_BUFFER_SYNC',
      'mpu_connected': data.mpuConnected,
      if (data.mpuConnected && data.accelX != null) 'motion': {
        'accel_x': data.accelX,
        'accel_y': data.accelY,
        'accel_z': data.accelZ,
        'gyro_x': data.gyroX,
        'gyro_y': data.gyroY,
        'gyro_z': data.gyroZ,
      },
      if (dName != null && dName.isNotEmpty) 'device_name': dName,
      if (dId != null && dId.isNotEmpty) 'device_id': dId,
    };
  }
}

/// Manages Firebase Authentication and Realtime Database stream
/// for the AERION – AeroSense environmental monitoring platform.
///
/// Target Database:
///   URL:  https://aerion-aerosense-default-rtdb.asia-southeast1.firebasedatabase.app
///   Path: /aerosense
class FirebaseService extends ChangeNotifier {
  static const String databaseUrl =
      'https://aerion-aerosense-default-rtdb.asia-southeast1.firebasedatabase.app';
  static const String basePath = 'aerosense';

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Whether Firebase is configured and ready to be used
  bool get isConfigured => _isInitialized;

  /// Whether Firebase App instance exists
  bool get isAvailable {
    try {
      return _isInitialized && Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  String _statusMessage = 'Uninitialized';
  String get statusMessage => _statusMessage;

  bool _persistenceConfigured = false;

  /// Gets the regional Firebase Realtime Database instance
  FirebaseDatabase? get _db {
    if (!isAvailable) return null;
    try {
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: databaseUrl,
      );

      // Enable offline disk persistence on mobile platforms
      if (!kIsWeb && !_persistenceConfigured) {
        try {
          db.setPersistenceEnabled(true);
          db.setPersistenceCacheSizeBytes(10000000); // 10MB offline cache
          _persistenceConfigured = true;
          AppLogger.i('FirebaseService', 'Offline disk persistence enabled (10MB cache)');
        } catch (e) {
          AppLogger.d('FirebaseService', 'Persistence already set or notice: $e');
        }
      }
      return db;
    } catch (e) {
      AppLogger.w('FirebaseService', 'Error getting database: $e');
      return null;
    }
  }

  /// Gets the Firebase Authentication instance
  FirebaseAuth? get _auth {
    if (!isAvailable) return null;
    try {
      return FirebaseAuth.instance;
    } catch (e) {
      AppLogger.w('FirebaseService', 'Error getting FirebaseAuth: $e');
      return null;
    }
  }

  // ── Authentication State ───────────────────────────────────────────────────
  User? get currentUser => _auth?.currentUser;
  bool get isAuthenticated => currentUser != null;

  String get authUserLabel {
    final user = currentUser;
    if (user == null) return 'Unauthenticated';
    if (user.isAnonymous) return 'Anonymous (${user.uid.substring(0, 6)})';
    return user.email ?? user.uid;
  }

  StreamSubscription<User?>? _authSub;

  // ── Realtime Stream State ──────────────────────────────────────────────────
  bool _isListening = false;
  bool get isListening => _isListening;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  SensorData? _lastReading;
  SensorData? get lastReading => _lastReading;

  DateTime? _lastPacketTime;
  DateTime? get lastPacketTime => _lastPacketTime;

  String _lastError = '';
  String get lastError => _lastError;

  String _deviceStatus = 'UNKNOWN';
  String get deviceStatus => _deviceStatus;

  String _connectionMode = 'UNKNOWN';
  String get connectionMode => _connectionMode;

  final List<QueuedTelemetry> _offlineBuffer = [];
  List<QueuedTelemetry> get offlineBuffer => List.unmodifiable(_offlineBuffer);
  int get pendingBufferCount => _offlineBuffer.length;
  int get offlineBufferCount => _offlineBuffer.length;
  bool get hasPendingBuffer => _offlineBuffer.isNotEmpty;

  static const int maxBufferSize = 100;
  final Set<String> _syncedRecordIds = {};

  DateTime? _lastSyncTime;
  SensorData? _lastSyncedData;

  /// Evaluates whether the ESP32 is actively streaming.
  /// Considered ONLINE if a packet arrived within the last 30 seconds.
  bool get isEsp32Online {
    if (_lastPacketTime == null) return false;
    final diff = DateTime.now().difference(_lastPacketTime!);
    return diff.inSeconds < 30;
  }

  StreamSubscription<DatabaseEvent>? _dataSub;
  StreamSubscription<DatabaseEvent>? _connSub;

  final _sensorController = StreamController<SensorData>.broadcast();
  Stream<SensorData> get sensorStream => _sensorController.stream;

  // ── Lifecycle & Setup ──────────────────────────────────────────────────────

  void markInitialized(bool success, [String? message]) {
    _isInitialized = success;
    _statusMessage = message ?? (success ? 'Configured & Ready' : 'Initialization Failed');
    _lastError = success ? '' : _statusMessage;

    if (success) {
      _listenToAuthChanges();
    }
    notifyListeners();
  }

  void markUnconfigured(String message) {
    _isInitialized = false;
    _statusMessage = message;
    _lastError = message;
    notifyListeners();
  }

  void _listenToAuthChanges() {
    _authSub?.cancel();
    _authSub = _auth?.authStateChanges().listen((user) {
      AppLogger.d('FirebaseAuth', 'Auth state changed: ${user?.uid}');
      notifyListeners();
      // If user became authenticated and sync wasn't active, start sync
      if (user != null && !_isListening) {
        startListening();
      }
    });
  }

  // ── Authentication Actions ─────────────────────────────────────────────────

  /// Signs in anonymously to satisfy secure database rules (`auth != null`)
  Future<bool> signInAnonymously() async {
    final auth = _auth;
    if (auth == null) {
      _lastError = 'Firebase Auth not available. Configure Firebase first.';
      notifyListeners();
      return false;
    }
    try {
      await auth.signInAnonymously();
      AppLogger.i('FirebaseAuth', 'Anonymous sign-in success: ${auth.currentUser?.uid}');
      _lastError = '';
      notifyListeners();
      if (!_isListening) {
        startListening();
      }
      return true;
    } catch (e) {
      _lastError = 'Auth failed: $e';
      AppLogger.w('FirebaseAuth', 'Anonymous sign-in error: $e');
      notifyListeners();
      return false;
    }
  }

  /// Signs in with Email and Password
  Future<bool> signInWithEmailPassword(String email, String password) async {
    final auth = _auth;
    if (auth == null) return false;
    try {
      await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      AppLogger.i('FirebaseAuth', 'Email sign-in success: $email');
      _lastError = '';
      notifyListeners();
      if (!_isListening) {
        startListening();
      }
      return true;
    } catch (e) {
      _lastError = 'Auth failed: $e';
      AppLogger.w('FirebaseAuth', 'Email sign-in error: $e');
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _auth?.signOut();
    } catch (_) {}
    stopListening();
    notifyListeners();
  }

  // ── Database Sync & Subscriptions ──────────────────────────────────────────

  void startListening() {
    if (!isAvailable) {
      _lastError = _statusMessage.isNotEmpty
          ? _statusMessage
          : 'Firebase is not configured for this platform.';
      AppLogger.d('Firebase', 'Cannot start sync: $_lastError');
      notifyListeners();
      return;
    }

    if (_isListening) return;
    _isListening = true;
    _lastError = '';
    notifyListeners();

    final db = _db;
    if (db == null) {
      _isListening = false;
      _lastError = 'FirebaseDatabase instance not available';
      notifyListeners();
      return;
    }

    try {
      // 1. Monitor Firebase connection state (.info/connected)
      _connSub?.cancel();
      _connSub = db.ref('.info/connected').onValue.listen(
        (event) {
          final connected = event.snapshot.value as bool? ?? false;
          final wasDisconnected = !_isConnected && connected;
          _isConnected = connected;
          notifyListeners();

          if (wasDisconnected) {
            AppLogger.i('FirebaseService', 'Realtime Database connection active');
            if (_offlineBuffer.isNotEmpty) {
              flushOfflineBuffer();
            }
          }
        },
        onError: (e) {
          _isConnected = false;
          _lastError = e.toString();
          notifyListeners();
        },
      );

      // 2. Keep /aerosense path synced offline and listen for real-time updates
      final sensorRef = db.ref(basePath);
      if (!kIsWeb) {
        try {
          sensorRef.keepSynced(true);
        } catch (e) {
          AppLogger.d('Firebase', 'keepSynced notice: $e');
        }
      }

      _dataSub?.cancel();
      _dataSub = sensorRef.onValue.listen(_onData, onError: _onError);
    } catch (e) {
      _isListening = false;
      _isConnected = false;
      _lastError = e.toString();
      AppLogger.w('Firebase', 'Stream setup error: $e');
      notifyListeners();
    }
  }

  void stopListening() {
    _isListening = false;
    _dataSub?.cancel();
    _connSub?.cancel();
    _isConnected = false;
    notifyListeners();
  }

  void _onData(DatabaseEvent event) {
    try {
      final value = event.snapshot.value;
      if (value == null) return;
      final map = Map<String, dynamic>.from(value as Map);

      _deviceStatus = map['device_status']?.toString() ?? 'ONLINE';
      _connectionMode = map['connection_mode']?.toString() ?? 'FIREBASE';

      // Parse and validate using SensorData.fromFirebaseMap
      final data = SensorData.fromFirebaseMap(map);
      if (data == null) {
        AppLogger.d('Firebase', 'Ignored uninitialized or invalid sensor reading');
        return;
      }

      _lastReading = data;
      _lastPacketTime = DateTime.now();
      _lastError = '';
      _sensorController.add(data);
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      AppLogger.w('Firebase', 'Parse error: $e');
    }
  }

  void _onError(Object error) {
    _lastError = error.toString();
    _isConnected = false;
    AppLogger.d('Firebase', 'Stream error: $error');
    notifyListeners();
  }

  /// Manually polls the latest telemetry snapshot from Firebase Realtime Database
  Future<void> fetchLatest() async {
    if (!isAvailable) return;
    try {
      final db = _db;
      if (db == null) return;
      final snap = await db.ref(basePath).get();
      if (snap.exists && snap.value != null) {
        final map = Map<String, dynamic>.from(snap.value as Map);
        final data = SensorData.fromFirebaseMap(map);
        if (data != null && data.isValid) {
          _lastReading = data;
          _lastPacketTime = DateTime.now();
          _sensorController.add(data);
          notifyListeners();
        }
      }
    } catch (e) {
      AppLogger.w('FirebaseService', 'fetchLatest error: $e');
    }
  }

  /// Synchronizes real telemetry received from ESP32 via BLE to Firebase RTDB (/aerosense).
  ///
  /// The mobile application functions as an IoT edge gateway, relaying authenticated
  /// hardware telemetry to Firebase Realtime Database when connected over BLE.
  ///
  /// Never uploads fabricated, uninitialized, or simulated sensor data.
  Future<bool> syncBleTelemetry(
    SensorData data, {
    String? deviceName,
    String? deviceId,
  }) async {
    // 1. Validate incoming sensor values (reject NaN, infinite, extreme out-of-range, and empty dummy data)
    if (!data.isValid) {
      AppLogger.d('FirebaseService', 'Rejected invalid sensor reading: T=${data.temperature}, H=${data.humidity}, AQ=${data.airQuality}');
      return false;
    }

    // 2. Prevent duplicate database writes if values haven't changed meaningfully within 500ms
    if (_lastSyncTime != null && _lastSyncedData != null) {
      final elapsed = DateTime.now().difference(_lastSyncTime!).inMilliseconds;
      if (elapsed < 500 &&
          _lastSyncedData!.temperature == data.temperature &&
          _lastSyncedData!.humidity == data.humidity &&
          _lastSyncedData!.airQuality == data.airQuality &&
          _lastSyncedData!.mpuConnected == data.mpuConnected) {
        return true; // Already up-to-date
      }
    }

    final recordId = data.timestamp.millisecondsSinceEpoch.toString();
    final queueItem = QueuedTelemetry(
      data: data,
      recordId: recordId,
      timestamp: data.timestamp.millisecondsSinceEpoch,
      deviceName: deviceName,
      deviceId: deviceId,
    );

    // If Firebase is uninitialized or disconnected, store locally in offline buffer
    if (!isAvailable || !_isConnected) {
      _bufferReading(queueItem);
      return true;
    }

    final db = _db;
    if (db == null) {
      _bufferReading(queueItem);
      return true;
    }

    try {
      final payload = data.toFirebaseMap(
        connectionMode: 'BLE_GATEWAY',
        deviceStatus: 'CONNECTED',
        deviceName: deviceName,
        deviceId: deviceId,
      );

      // 1. Update live /aerosense state
      final liveRef = db.ref(basePath);
      await liveRef.update(payload);

      // 2. Append to historical telemetry series at /aerosense/history/<timestamp>
      if (!_syncedRecordIds.contains(recordId)) {
        await db.ref('$basePath/history/$recordId').set({
          'temperature': data.temperature,
          'humidity': data.humidity,
          'air_quality': data.airQuality,
          'timestamp': ServerValue.timestamp,
          'source': 'BLE',
          'mpu_connected': data.mpuConnected,
          if (data.mpuConnected && data.accelX != null) 'motion': {
            'accel_x': data.accelX,
            'accel_y': data.accelY,
            'accel_z': data.accelZ,
            'gyro_x': data.gyroX,
            'gyro_y': data.gyroY,
            'gyro_z': data.gyroZ,
          },
        });
        _syncedRecordIds.add(recordId);
        if (_syncedRecordIds.length > 500) {
          _syncedRecordIds.remove(_syncedRecordIds.first);
        }
      }

      _lastSyncTime = DateTime.now();
      _lastSyncedData = data;
      return true;
    } catch (e) {
      AppLogger.w('FirebaseService', 'Write failed, buffering offline: $e');
      _bufferReading(queueItem);
      return true;
    }
  }

  void _bufferReading(QueuedTelemetry item) {
    if (_offlineBuffer.any((b) => b.recordId == item.recordId)) return;
    if (_offlineBuffer.length >= maxBufferSize) {
      _offlineBuffer.removeAt(0); // FIFO eviction
    }
    _offlineBuffer.add(item);
    AppLogger.d('FirebaseService', 'Telemetry buffered offline (pending: ${_offlineBuffer.length})');
    notifyListeners();
  }

  /// Flushes all pending offline telemetry to Firebase RTDB upon network reconnection
  Future<int> flushOfflineBuffer() async {
    if (_offlineBuffer.isEmpty || !isAvailable || !_isConnected) return 0;
    final db = _db;
    if (db == null) return 0;

    int flushedCount = 0;
    final itemsToFlush = List<QueuedTelemetry>.from(_offlineBuffer);

    for (final item in itemsToFlush) {
      try {
        if (!_syncedRecordIds.contains(item.recordId)) {
          await db.ref('$basePath/history/${item.recordId}').set(item.toMap());
          _syncedRecordIds.add(item.recordId);
        }
        _offlineBuffer.removeWhere((b) => b.recordId == item.recordId);
        flushedCount++;
      } catch (e) {
        AppLogger.w('FirebaseService', 'Error flushing item ${item.recordId}: $e');
        break; // Stop and retry later if network dropped
      }
    }

    if (flushedCount > 0) {
      AppLogger.i('FirebaseService', 'Successfully synced $flushedCount offline buffered readings to RTDB ✓');
      notifyListeners();
    }
    return flushedCount;
  }

  /// Updates hardware connection status in Firebase RTDB
  Future<void> updateDeviceStatus(String status, {String? connectionMode}) async {
    final db = _db;
    if (db == null || !isAvailable) return;
    try {
      await db.ref(basePath).update({
        'device_status': status,
        if (connectionMode != null) 'connection_mode': connectionMode,
        'timestamp': ServerValue.timestamp,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      AppLogger.w('FirebaseService', 'Update status error: $e');
    }
  }

  /// Writes user acknowledgment back to the database (/aerosense/ack)
  Future<void> writeAcknowledgement(String incidentId, {DateTime? ackedAt}) async {
    final db = _db;
    if (db == null || !isAvailable) return;
    try {
      await db.ref('$basePath/ack').set({
        'incident_id': incidentId,
        'acked_at': ackedAt?.millisecondsSinceEpoch ?? ServerValue.timestamp,
        'acked_by': currentUser?.uid ?? 'anonymous',
      });
      AppLogger.i('FirebaseService', 'Acknowledgement for $incidentId written to RTDB');
    } catch (e) {
      AppLogger.w('Firebase', 'Write ack error: $e');
    }
  }

  /// Logs a critical incident to /aerosense/incidents/$id
  Future<bool> logIncident(IncidentRecord incident) async {
    final db = _db;
    if (db == null || !isAvailable) {
      AppLogger.w('FirebaseService', 'Cannot log incident: database unavailable');
      return false;
    }
    try {
      await db.ref('$basePath/incidents/${incident.id}').set(incident.toFirebaseMap());
      AppLogger.i('FirebaseService', 'Incident ${incident.id} logged to RTDB');
      return true;
    } catch (e) {
      AppLogger.e('FirebaseService', 'Error logging incident', e);
      return false;
    }
  }

  /// Updates an active or resolved incident in /aerosense/incidents/$id
  Future<bool> updateIncident(IncidentRecord incident) async {
    final db = _db;
    if (db == null || !isAvailable) return false;
    try {
      await db.ref('$basePath/incidents/${incident.id}').update(incident.toFirebaseMap());
      AppLogger.i('FirebaseService', 'Incident ${incident.id} updated in RTDB');
      return true;
    } catch (e) {
      AppLogger.e('FirebaseService', 'Error updating incident', e);
      return false;
    }
  }

  @override
  void dispose() {
    stopListening();
    _authSub?.cancel();
    _sensorController.close();
    super.dispose();
  }
}

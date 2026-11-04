import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aerion_aerosense/firebase_options.dart';
import 'package:aerion_aerosense/firebase/firebase_service.dart';
import 'package:aerion_aerosense/models/sensor_data.dart';
import 'package:aerion_aerosense/ble/ble_constants.dart';
import 'package:aerion_aerosense/ble/ble_manager.dart';
import 'package:aerion_aerosense/wifi/wifi_sensor_service.dart';
import 'package:aerion_aerosense/connectivity/connectivity_manager.dart';
import 'package:aerion_aerosense/utils/data_decoder.dart';
import 'package:aerion_aerosense/utils/permissions_helper.dart';
import 'package:aerion_aerosense/providers/app_state.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:aerion_aerosense/models/incident_record.dart';
import 'package:aerion_aerosense/widgets/hazard_modal.dart';
import 'package:aerion_aerosense/widgets/dual_arc_gauge.dart';
import 'package:aerion_aerosense/theme/app_theme.dart';
import 'package:aerion_aerosense/screens/settings_screen.dart';
import 'package:aerion_aerosense/providers/threshold_provider.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (methodCall) async {
        if (methodCall.method == 'check') {
          return ['wifi'];
        }
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (methodCall) async => true,
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AERION AeroSense Core Unit Tests', () {
    test('DefaultFirebaseOptions is properly configured with genuine project credentials', () {
      expect(DefaultFirebaseOptions.isConfigured, isTrue);
      expect(DefaultFirebaseOptions.currentPlatform?.projectId, 'aerion-aerosense');
      expect(DefaultFirebaseOptions.currentPlatform?.databaseURL,
          'https://aerion-aerosense-default-rtdb.asia-southeast1.firebasedatabase.app');
    });

    test('FirebaseService starts in unconfigured/uninitialized state without crashing', () {
      final service = FirebaseService();
      expect(service.isInitialized, isFalse);
      expect(service.isConfigured, isFalse);
      expect(service.isConnected, isFalse);
      expect(service.isListening, isFalse);

      // Calling startListening when unconfigured should not throw
      service.startListening();
      expect(service.isListening, isFalse);
      expect(service.lastError, isNotEmpty);
    });

    test('SensorData parses floats and assigns labels correctly', () {
      final data = SensorData(
        temperature: 28.5,
        humidity: 65.0,
        airQuality: 650,
        source: DataSource.wifi,
        timestamp: DateTime.now(),
      );

      expect(data.temperature, 28.5);
      expect(data.humidity, 65.0);
      expect(data.airQuality, 650);
      expect(data.airQualityLabel, 'GOOD');
      expect(data.airQualityLevel, 0);
      expect(data.temperatureFahrenheit, closeTo(83.3, 0.1));
    });

    test('BleConstants has correct target prefix and GATT service UUID', () {
      expect(BleConstants.targetDevicePrefix, 'AQM-');
      expect(BleConstants.serviceUuid, '4fafc201-1fb5-459e-8fcc-c5c9c331914b');
      expect(BleConstants.temperatureCharUuid, 'beb5483e-36e1-4688-b7f5-ea07361b26a8');
      expect(BleConstants.humidityCharUuid, 'cba1d466-344c-4be3-ab3f-189f80dd7518');
      expect(BleConstants.airQualityCharUuid, 'f0de3a41-2b5e-4c6f-9d7a-1e8b3c4d5e6f');
      expect(BleConstants.samplingIntervalCharUuid, 'd8e3b210-9b48-4b92-9654-e75b2b2a60a4');
      expect(BleConstants.alertCharUuid, 'e7f2a1b0-4a3d-4c5e-8f6b-9c1d2e3f4a5b');
    });

    test('SensorData dual-mode parser decodes both ASCII string and IEEE 754 float bytes', () {
      // 1. ASCII decimal string test
      final asciiBytes = '28.75'.codeUnits;
      expect(SensorData.parseFloat(asciiBytes), closeTo(28.75, 0.01));

      // 2. IEEE 754 float32 little-endian bytes test (28.75f = 0x41E60000 -> LE: [0x00, 0x00, 0xE6, 0x41])
      final ieeeBytes = [0x00, 0x00, 0xE6, 0x41];
      expect(SensorData.parseFloat(ieeeBytes), closeTo(28.75, 0.01));

      // 3. Air quality parsing (ASCII string)
      final aqAscii = '680'.codeUnits;
      expect(SensorData.parseAirQuality(aqAscii), 680);

      // 4. Air quality parsing (IEEE 754 float 680.0f = 0x442A0000 -> LE: [0x00, 0x00, 0x2A, 0x44])
      final aqFloatBytes = [0x00, 0x00, 0x2A, 0x44];
      expect(SensorData.parseAirQuality(aqFloatBytes), 680);

      // 5. Air quality parsing (uint16 little endian 680 = 0x02A8 -> [0xA8, 0x02])
      final aqUint16Bytes = [0xA8, 0x02];
      expect(SensorData.parseAirQuality(aqUint16Bytes), 680);
    });

    test('SensorData handles MPU6050 physical disconnection without fake data', () {
      final data = SensorData(
        temperature: 25.0,
        humidity: 50.0,
        timestamp: DateTime.now(),
      );
      expect(data.mpuConnected, isFalse);
      expect(data.accelX, isNull);
      expect(data.gyroX, isNull);
    });

    test('PermissionsHelper detects web and platform correctly', () {
      expect(PermissionsHelper.isWeb, isFalse); // in test VM
    });

    // ── Phase 3: BLE Pipeline, Connection States & Backoff Unit Tests ───────
    test('BleConnectionState has all required lifecycle states', () {
      expect(BleConnectionState.values, contains(BleConnectionState.disconnected));
      expect(BleConnectionState.values, contains(BleConnectionState.scanning));
      expect(BleConnectionState.values, contains(BleConnectionState.connecting));
      expect(BleConnectionState.values, contains(BleConnectionState.connected));
      expect(BleConnectionState.values, contains(BleConnectionState.reconnecting));
      expect(BleConnectionState.values, contains(BleConnectionState.connectionFailed));
      expect(BleConnectionState.values.length, 6);
    });

    test('BleManager exponential backoff delays are calculated deterministically', () {
      expect(BleManager.calculateBackoffDelay(0), const Duration(seconds: 2));
      expect(BleManager.calculateBackoffDelay(1), const Duration(seconds: 4));
      expect(BleManager.calculateBackoffDelay(2), const Duration(seconds: 8));
      expect(BleManager.calculateBackoffDelay(3), const Duration(seconds: 16));
      expect(BleManager.calculateBackoffDelay(4), const Duration(seconds: 32));
      // Attempts >= 5 are capped at 60s
      expect(BleManager.calculateBackoffDelay(5), const Duration(seconds: 60));
      expect(BleManager.calculateBackoffDelay(10), const Duration(seconds: 60));
      // Negative attempt clamped to 2s
      expect(BleManager.calculateBackoffDelay(-1), const Duration(seconds: 2));
    });

    test('BleManager target device name filtering accurately detects AQM- prefix', () {
      expect(BleManager.isTargetDeviceName('AQM-Atchaya'), isTrue);
      expect(BleManager.isTargetDeviceName('AQM-Node-01'), isTrue);
      expect(BleManager.isTargetDeviceName('aqm-lab-sensor'), isTrue);
      expect(BleManager.isTargetDeviceName('  AQM-ESP32S3  '), isTrue);
      expect(BleManager.isTargetDeviceName('ESP32-Sensors'), isFalse);
      expect(BleManager.isTargetDeviceName('SmartBand-45'), isFalse);
      expect(BleManager.isTargetDeviceName(''), isFalse);
    });

    test('DataDecoder decodes sampling intervals and alert flags correctly', () {
      // Sampling interval: ASCII
      expect(DataDecoder.decodeSamplingInterval('5'.codeUnits), 5);
      // Sampling interval: 2-byte uint16 little-endian (15 seconds -> [0x0F, 0x00])
      expect(DataDecoder.decodeSamplingInterval([0x0F, 0x00]), 15);
      // Sampling interval: 1-byte uint8 (30 seconds)
      expect(DataDecoder.decodeSamplingInterval([30]), 30);
      // Sampling interval: Out of bounds (> 60s) defaults to 2
      expect(DataDecoder.decodeSamplingInterval('999'.codeUnits), 2);
      // Encode sampling interval to 2-byte uint16 little-endian
      final encoded = DataDecoder.encodeSamplingInterval(10);
      expect(encoded.length, 2);
      expect(encoded[0], 10);
      expect(encoded[1], 0);

      // Alert flag: 1 = hazard, 0 = normal, empty = 0
      expect(DataDecoder.decodeAlertFlag([1]), 1);
      expect(DataDecoder.decodeAlertFlag([0]), 0);
      expect(DataDecoder.decodeAlertFlag([]), 0);
    });

    test('MPU6050 motion parser returns null when disconnected and decodes when present without fake data', () {
      // When empty or invalid, must return null (no fake data generated)
      expect(BleManager.parseMotionTelemetry([]), isNull);
      expect(BleManager.parseMotionTelemetry([0x00, 0x01]), isNull);

      // When ASCII CSV motion payload arrives: "0.05,-0.02,9.81,0.01,0.02,-0.01"
      final csvBytes = '0.05,-0.02,9.81,0.01,0.02,-0.01'.codeUnits;
      final csvResult = BleManager.parseMotionTelemetry(csvBytes);
      expect(csvResult, isNotNull);
      expect(csvResult!['accelZ'], closeTo(9.81, 0.01));
      expect(csvResult['accelX'], closeTo(0.05, 0.01));

      // When 24-byte IEEE 754 little-endian binary arrives
      final bd = ByteData(24);
      bd.setFloat32(0, 0.12, Endian.little);
      bd.setFloat32(4, -0.34, Endian.little);
      bd.setFloat32(8, 9.80, Endian.little);
      bd.setFloat32(12, 0.01, Endian.little);
      bd.setFloat32(16, 0.02, Endian.little);
      bd.setFloat32(20, -0.03, Endian.little);
      final binResult = BleManager.parseMotionTelemetry(bd.buffer.asUint8List());
      expect(binResult, isNotNull);
      expect(binResult!['accelX'], closeTo(0.12, 0.01));
      expect(binResult['accelY'], closeTo(-0.34, 0.01));
      expect(binResult['accelZ'], closeTo(9.80, 0.01));
    });

    test('TelemetryProvider type alias and FirebaseService sync guards against empty fake data', () async {
      // TelemetryProvider alias matches AppState
      expect(TelemetryProvider, equals(AppState));

      final service = FirebaseService();
      // syncBleTelemetry must reject zero/uninitialized dummy readings
      final rejected = await service.syncBleTelemetry(
        SensorData(
          temperature: 0.0,
          humidity: 0.0,
          airQuality: 0,
          timestamp: DateTime.now(),
        ),
      );
      expect(rejected, isFalse);
    });

    // ── Phase 4: Firebase RTDB Telemetry Synchronization Unit Tests ─────────
    test('SensorData.fromFirebaseMap accurately validates DHT22, MQ135 and rejects corrupted data', () {
      // 1. Valid DHT22 + MQ135 packet
      final validMap = {
        'temperature': 24.5,
        'humidity': 55.0,
        'air_quality': 420,
        'timestamp': 1700000000000,
        'device_status': 'ONLINE',
        'connection_mode': 'WIFI',
        'mpu_connected': false,
      };
      final parsed = SensorData.fromFirebaseMap(validMap);
      expect(parsed, isNotNull);
      expect(parsed!.temperature, 24.5);
      expect(parsed.humidity, 55.0);
      expect(parsed.airQuality, 420);
      expect(parsed.mpuConnected, isFalse);
      expect(parsed.source, DataSource.firebase);

      // 2. Reject out-of-range corrupted temperature (> 125°C for DHT22)
      final corruptTemp = Map<dynamic, dynamic>.from(validMap);
      corruptTemp['temperature'] = 199.9;
      expect(SensorData.fromFirebaseMap(corruptTemp), isNull);

      // 3. Reject negative out-of-range temperature (< -40°C)
      final extremeCold = Map<dynamic, dynamic>.from(validMap);
      extremeCold['temperature'] = -55.0;
      expect(SensorData.fromFirebaseMap(extremeCold), isNull);

      // 4. Reject out-of-range humidity (> 100%)
      final corruptHum = Map<dynamic, dynamic>.from(validMap);
      corruptHum['humidity'] = 105.0;
      expect(SensorData.fromFirebaseMap(corruptHum), isNull);

      // 5. Reject missing temperature
      final missingTemp = Map<dynamic, dynamic>.from(validMap);
      missingTemp.remove('temperature');
      expect(SensorData.fromFirebaseMap(missingTemp), isNull);

      // 6. Reject uninitialized all-zero dummy hardware reading
      final dummyPacket = {
        'temperature': 0.0,
        'humidity': 0.0,
        'air_quality': 0,
        'timestamp': 1700000000000,
      };
      expect(SensorData.fromFirebaseMap(dummyPacket), isNull);
    });

    test('SensorData.fromFirebaseMap decodes MPU6050 physical motion data without fake defaults', () {
      final motionMap = {
        'temperature': 22.0,
        'humidity': 48.0,
        'air_quality': 300,
        'timestamp': 1700000000000,
        'mpu_connected': true,
        'motion': {
          'accel_x': 0.08,
          'accel_y': -0.15,
          'accel_z': 9.79,
          'gyro_x': 0.01,
          'gyro_y': -0.02,
          'gyro_z': 0.05,
        }
      };
      final parsed = SensorData.fromFirebaseMap(motionMap);
      expect(parsed, isNotNull);
      expect(parsed!.mpuConnected, isTrue);
      expect(parsed.accelZ, closeTo(9.79, 0.01));
      expect(parsed.gyroZ, closeTo(0.05, 0.01));

      // When mpu_connected is false, motion fields must be null (no fake data)
      final noMotionMap = Map<dynamic, dynamic>.from(motionMap);
      noMotionMap['mpu_connected'] = false;
      final parsedNoMotion = SensorData.fromFirebaseMap(noMotionMap);
      expect(parsedNoMotion, isNotNull);
      expect(parsedNoMotion!.mpuConnected, isFalse);
      expect(parsedNoMotion.accelX, isNull);
      expect(parsedNoMotion.gyroX, isNull);
    });

    test('SensorData.toFirebaseMap serializes valid payload cleanly', () {
      final data = SensorData(
        temperature: 26.8,
        humidity: 62.4,
        airQuality: 512,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        source: DataSource.ble,
        mpuConnected: false,
      );
      final map = data.toFirebaseMap(connectionMode: 'BLE_GATEWAY', deviceStatus: 'CONNECTED');
      expect(map['temperature'], 26.8);
      expect(map['humidity'], 62.4);
      expect(map['air_quality'], 512);
      expect(map['timestamp'], 1700000000000);
      expect(map['connection_mode'], 'BLE_GATEWAY');
      expect(map['device_status'], 'CONNECTED');
      expect(map['mpu_connected'], isFalse);
      expect(map.containsKey('motion'), isFalse);
    });

    test('FirebaseService local offline buffering and queue management operates correctly', () async {
      final service = FirebaseService();
      expect(service.pendingBufferCount, 0);
      expect(service.hasPendingBuffer, isFalse);

      final validTelemetry = SensorData(
        temperature: 27.2,
        humidity: 58.1,
        airQuality: 490,
        timestamp: DateTime.now(),
        source: DataSource.ble,
      );

      // In uninitialized/offline test environment, valid telemetry is buffered locally
      final handled = await service.syncBleTelemetry(validTelemetry, deviceName: 'AQM-Node');
      expect(handled, isTrue);
      expect(service.pendingBufferCount, 1);
      expect(service.hasPendingBuffer, isTrue);

      // Attempting to buffer the same timestamp recordId is deduplicated
      await service.syncBleTelemetry(validTelemetry, deviceName: 'AQM-Node');
      expect(service.pendingBufferCount, 1); // No duplicate added
    });

    // ── Phase 5: Executive Dashboard, Dual Arc Gauge & UI/UX Tests ───────────
    test('DualArcGauge threshold color accurately applies Blue, Amber, Crimson', () {
      // Normal (< 30°C): Dark -> Electric Cyan (#00F2FE), Light -> Royal Blue (#2563EB)
      expect(DualArcGauge.getTemperatureColor(24.0, isDark: true), AppColors.electricCyan);
      expect(DualArcGauge.getTemperatureColor(24.0, isDark: false), AppColors.lightPrimary);

      // Warning (30°C - 35°C): Radiant Amber (#FFAB00)
      expect(DualArcGauge.getTemperatureColor(30.0), AppColors.radiantAmber);
      expect(DualArcGauge.getTemperatureColor(32.5), AppColors.radiantAmber);
      expect(DualArcGauge.getTemperatureColor(35.0), AppColors.radiantAmber);

      // Critical (> 35°C): Crimson Neon (#FF1744)
      expect(DualArcGauge.getTemperatureColor(35.1), AppColors.crimsonNeon);
      expect(DualArcGauge.getTemperatureColor(42.0), AppColors.crimsonNeon);
    });

    test('DualArcGauge threshold labels are accurate', () {
      expect(DualArcGauge.getThresholdLabel(25.0), 'NORMAL (<30°C)');
      expect(DualArcGauge.getThresholdLabel(30.0), 'WARNING (30–35°C)');
      expect(DualArcGauge.getThresholdLabel(35.0), 'WARNING (30–35°C)');
      expect(DualArcGauge.getThresholdLabel(36.0), 'CRITICAL (>35°C)');
    });

    testWidgets('DualArcGauge renders placeholder when hasData is false without fake values', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DualArcGauge(
              temperature: 0.0,
              humidity: 0.0,
              hasData: false,
            ),
          ),
        ),
      );

      // Must display '--' instead of '0.0'
      expect(find.text('--'), findsNWidgets(2)); // Temperature & Humidity
      expect(find.text('NO SENSOR DATA'), findsOneWidget);
    });

    testWidgets('DualArcGauge renders real values and threshold badge when hasData is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DualArcGauge(
              temperature: 28.5,
              humidity: 62.0,
              hasData: true,
            ),
          ),
        ),
      );

      expect(find.text('28.5'), findsOneWidget);
      expect(find.text('62.0'), findsOneWidget);
      expect(find.text('NORMAL (<30°C)'), findsOneWidget);
    });

    test('AppState MPU-6050 getters report SENSOR NOT CONNECTED when physically absent', () {
      final ble = BleManager();
      final wifi = WiFiSensorService();
      final fb = FirebaseService();
      final cm = ConnectivityManager(wifiService: wifi, firebaseService: fb, bleManager: ble);
      final appState = AppState(bleManager: ble, connectivityManager: cm);

      // When physical MPU-6050 is not detected, getters must return null and disconnected status
      expect(appState.isMpuConnected, isFalse);
      expect(appState.accelX, isNull);
      expect(appState.accelY, isNull);
      expect(appState.accelZ, isNull);
      expect(appState.gyroX, isNull);
      expect(appState.gyroY, isNull);
      expect(appState.gyroZ, isNull);
      expect(appState.motionStateLabel, 'SENSOR NOT CONNECTED');

      // Zero fake data
      expect(appState.latestSensorData, isNull);
      expect(appState.hasReceivedTelemetry, isFalse);
    });

    test('AppState ThemeMode toggles between Light and Dark mode seamlessly', () async {
      final ble = BleManager();
      final wifi = WiFiSensorService();
      final fb = FirebaseService();
      final cm = ConnectivityManager(wifiService: wifi, firebaseService: fb, bleManager: ble);
      final appState = AppState(bleManager: ble, connectivityManager: cm);

      expect(appState.isDarkMode, isTrue);
      expect(appState.themeMode, ThemeMode.dark);

      await appState.toggleTheme();
      expect(appState.isDarkMode, isFalse);
      expect(appState.themeMode, ThemeMode.light);

      await appState.toggleTheme();
      expect(appState.isDarkMode, isTrue);
      expect(appState.themeMode, ThemeMode.dark);
    });

    // ── Phase 6: Critical Hazard Alerts, Incident Management & Audit Tests ────
    test('IncidentRecord serialization preserves all audit fields accurately', () {
      final now = DateTime.now();
      final incident = IncidentRecord(
        id: 'INC-1730000000000',
        startTime: now,
        alertType: AlertType.temperature,
        peakTemperature: 37.8,
        peakHumidity: 65.0,
        peakAirQuality: 450,
        acknowledged: true,
        acknowledgedAt: now.add(const Duration(seconds: 45)),
        endTime: now.add(const Duration(minutes: 5)),
      );

      expect(incident.isResolved, isTrue);
      expect(incident.isActive, isFalse);
      expect(incident.duration.inMinutes, 5);

      final map = incident.toFirebaseMap();
      expect(map['id'], 'INC-1730000000000');
      expect(map['alert_type'], 'temperature');
      expect(map['peak_temperature'], 37.8);
      expect(map['acknowledged'], isTrue);
      expect(map['is_resolved'], isTrue);

      final restored = IncidentRecord.fromMap(map);
      expect(restored, isNotNull);
      expect(restored!.id, incident.id);
      expect(restored.alertType, AlertType.temperature);
      expect(restored.peakTemperature, 37.8);
      expect(restored.acknowledged, isTrue);
      expect(restored.isResolved, isTrue);
    });

    test('AppState triggers thermal hazard alert when DHT22 temperature > 35.0°C and does not create duplicates', () async {
      final ble = BleManager();
      final wifi = WiFiSensorService();
      final fb = FirebaseService();
      final cm = ConnectivityManager(wifiService: wifi, firebaseService: fb, bleManager: ble);
      final appState = AppState(bleManager: ble, connectivityManager: cm);

      // 1. Normal temperature (28.5°C) -> No hazard
      wifi.injectDataForTesting(SensorData(
        temperature: 28.5,
        humidity: 50.0,
        timestamp: DateTime.now(),
        source: DataSource.wifi,
      ));
      await pumpEventQueue();
      expect(appState.hazardActive, isFalse);
      expect(appState.activeIncident, isNull);
      expect(appState.incidents.length, 0);

      // 2. Critical breach (36.2°C > 35.0°C) -> Triggers hazard incident
      wifi.injectDataForTesting(SensorData(
        temperature: 36.2,
        humidity: 52.0,
        timestamp: DateTime.now(),
        source: DataSource.wifi,
      ));
      await pumpEventQueue();
      expect(appState.hazardActive, isTrue);
      expect(appState.hazardSilenced, isFalse);
      expect(appState.activeIncident, isNotNull);
      expect(appState.activeIncident!.peakTemperature, 36.2);
      expect(appState.activeIncident!.alertType, AlertType.temperature);
      expect(appState.incidents.length, 1);
      final firstIncidentId = appState.activeIncident!.id;

      // 3. Higher breach in continuous incident (38.4°C) -> Updates peak, NO DUPLICATE incident
      wifi.injectDataForTesting(SensorData(
        temperature: 38.4,
        humidity: 53.0,
        timestamp: DateTime.now(),
        source: DataSource.wifi,
      ));
      await pumpEventQueue();
      expect(appState.hazardActive, isTrue);
      expect(appState.incidents.length, 1); // Strictly no duplicate
      expect(appState.activeIncident!.id, firstIncidentId);
      expect(appState.activeIncident!.peakTemperature, 38.4);

      // 4. User acknowledges/silences alert -> marks acknowledged, stops alarm, but DOES NOT mark temperature safe
      appState.acknowledgeHazard();
      expect(appState.hazardSilenced, isTrue);
      expect(appState.hazardActive, isTrue); // STILL ACTIVE: Monitoring continues!
      expect(appState.activeIncident!.acknowledged, isTrue);
      expect(appState.activeIncident!.acknowledgedAt, isNotNull);
      expect(appState.activeIncident!.isResolved, isFalse);

      // 5. Temperature remains > 35.0°C (36.0°C) -> Monitoring continues without creating new incident
      wifi.injectDataForTesting(SensorData(
        temperature: 36.0,
        humidity: 50.0,
        timestamp: DateTime.now(),
        source: DataSource.wifi,
      ));
      await pumpEventQueue();
      expect(appState.hazardActive, isTrue);
      expect(appState.incidents.length, 1);

      // 6. Temperature drops safely <= 35.0°C (29.5°C) -> Resolves incident!
      wifi.injectDataForTesting(SensorData(
        temperature: 29.5,
        humidity: 50.0,
        timestamp: DateTime.now(),
        source: DataSource.wifi,
      ));
      await pumpEventQueue();
      expect(appState.hazardActive, isFalse);
      expect(appState.hazardSilenced, isFalse);
      expect(appState.activeIncident, isNull);
      expect(appState.incidents.length, 1);
      expect(appState.incidents.first.isResolved, isTrue);
      expect(appState.incidents.first.endTime, isNotNull);
    });

    test('AppState does not trigger alert on uninitialized/empty dummy data (0.0°C)', () async {
      final ble = BleManager();
      final wifi = WiFiSensorService();
      final fb = FirebaseService();
      final cm = ConnectivityManager(wifiService: wifi, firebaseService: fb, bleManager: ble);
      final appState = AppState(bleManager: ble, connectivityManager: cm);

      wifi.injectDataForTesting(SensorData(
        temperature: 0.0,
        humidity: 0.0,
        airQuality: 0,
        timestamp: DateTime.now(),
      ));
      await pumpEventQueue();
      expect(appState.hazardActive, isFalse);
      expect(appState.incidents.isEmpty, isTrue);
    });

    testWidgets('HazardModal displays emergency warning, temperature, and acknowledges cleanly', (tester) async {
      final ble = BleManager();
      final wifi = WiFiSensorService();
      final fb = FirebaseService();
      final cm = ConnectivityManager(wifiService: wifi, firebaseService: fb, bleManager: ble);
      final appState = AppState(bleManager: ble, connectivityManager: cm);

      bool ackCalled = false;
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: HazardModal(
                temperature: 38.5,
                alertType: AlertType.temperature,
                onAcknowledge: () => ackCalled = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Verify UI elements
      expect(find.text('CRITICAL THERMAL HAZARD'), findsOneWidget);
      expect(find.text('38.5'), findsOneWidget);
      expect(find.text('SAFETY LIMIT: 35.0°C'), findsOneWidget);
      expect(find.text('SILENCE & ACKNOWLEDGE'), findsOneWidget);

      // Tap SILENCE & ACKNOWLEDGE button
      await tester.tap(find.text('SILENCE & ACKNOWLEDGE'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(ackCalled, isTrue);
    });

    test('AppColors resolvers return exact palette values for Light and Dark modes', () {
      // Dark Mode palette checks
      expect(AppColors.getBackground(true), const Color(0xFF0B0F17));
      expect(AppColors.getCardBg(true), const Color(0xFF151B26));
      expect(AppColors.getBorder(true), const Color(0xFF212C3D));
      expect(AppColors.getPrimary(true), const Color(0xFF00F2FE));
      expect(AppColors.getSecondary(true), const Color(0xFF00E676));
      expect(AppColors.getTextPrimary(true), const Color(0xFFE6EDF3));
      expect(AppColors.getTextSecondary(true), const Color(0xFF8B949E));

      // Light Mode palette checks
      expect(AppColors.getBackground(false), const Color(0xFFF8FAFC));
      expect(AppColors.getCardBg(false), const Color(0xFFFFFFFF));
      expect(AppColors.getBorder(false), const Color(0xFFE2E8F0));
      expect(AppColors.getPrimary(false), const Color(0xFF2563EB));
      expect(AppColors.getSecondary(false), const Color(0xFF10B981));
      expect(AppColors.getTextPrimary(false), const Color(0xFF0F172A));
      expect(AppColors.getTextSecondary(false), const Color(0xFF64748B));
    });

    testWidgets('SettingsScreen displays appearance options and switches themes smoothly', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ble = BleManager();
      final wifi = WiFiSensorService();
      final fb = FirebaseService();
      final cm = ConnectivityManager(wifiService: wifi, firebaseService: fb, bleManager: ble);
      final appState = AppState(bleManager: ble, connectivityManager: cm);
      final threshold = ThresholdProvider();
      await threshold.loadFromPrefs();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: appState),
            ChangeNotifierProvider<FirebaseService>.value(value: fb),
            ChangeNotifierProvider<ThresholdProvider>.value(value: threshold),
          ],
          child: Consumer<AppState>(
            builder: (context, state, _) {
              return MaterialApp(
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: state.themeMode,
                home: const SettingsScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify sections and options exist
      expect(find.text('SETTINGS & THRESHOLDS'), findsOneWidget);
      expect(find.text('ENVIRONMENTAL ALERT THRESHOLDS'), findsOneWidget);
      expect(find.text('Stealth Midnight Cyber'), findsOneWidget);
      expect(find.text('Executive Porcelain Light'), findsOneWidget);

      // Initially Dark Mode
      expect(appState.isDarkMode, isTrue);

      // Tap Executive Porcelain Light to switch to light mode
      await tester.tap(find.text('Executive Porcelain Light'));
      await tester.pumpAndSettle();
      expect(appState.isDarkMode, isFalse);

      // Tap Stealth Midnight Cyber to switch back to dark mode
      await tester.tap(find.text('Stealth Midnight Cyber'));
      await tester.pumpAndSettle();
      expect(appState.isDarkMode, isTrue);
    });

    // ── Phase 7: Environmental Alert Thresholds & Persistence Unit Tests ───────
    test('ThresholdProvider initializes with correct default IoT thresholds', () async {
      final provider = ThresholdProvider();
      await provider.loadFromPrefs();

      // Default Temperature: Normal < 30°C, Warning 30-35°C, Critical > 35°C
      expect(provider.tempNormalMax, 30.0);
      expect(provider.tempWarningMax, 35.0);

      // Default Humidity: Min 20%, Normal 30-70%, Max 85%
      expect(provider.humidityMin, 20.0);
      expect(provider.humidityNormalMin, 30.0);
      expect(provider.humidityNormalMax, 70.0);
      expect(provider.humidityMax, 85.0);

      // Default MQ-135 Raw ADC: Normal < 1500, Warning 1500-2500, Critical > 2500
      expect(provider.aqNormalMax, 1500);
      expect(provider.aqWarningMax, 2500);

      // Default Alert Preferences
      expect(provider.enableTempAlerts, isTrue);
      expect(provider.enableHumidityAlerts, isTrue);
      expect(provider.enableAirQualityAlerts, isTrue);
      expect(provider.enableSound, isTrue);
      expect(provider.enableVibration, isTrue);
    });

    test('ThresholdProvider validates thresholds and rejects invalid bounds', () {
      // Valid defaults
      expect(
        ThresholdProvider.validateThresholds(
          tempNormalMax: 30.0,
          tempWarningMax: 35.0,
          humMin: 20.0,
          humNormalMin: 30.0,
          humNormalMax: 70.0,
          humMax: 85.0,
          aqNormalMax: 1500,
          aqWarningMax: 2500,
        ),
        isNull,
      );

      // Invalid: normal temp >= warning temp
      expect(
        ThresholdProvider.validateThresholds(
          tempNormalMax: 36.0,
          tempWarningMax: 35.0,
          humMin: 20.0,
          humNormalMin: 30.0,
          humNormalMax: 70.0,
          humMax: 85.0,
          aqNormalMax: 1500,
          aqWarningMax: 2500,
        ),
        contains('must be less than warning threshold'),
      );

      // Invalid: humidity min >= humidity normal min
      expect(
        ThresholdProvider.validateThresholds(
          tempNormalMax: 30.0,
          tempWarningMax: 35.0,
          humMin: 80.0,
          humNormalMin: 30.0,
          humNormalMax: 70.0,
          humMax: 85.0,
          aqNormalMax: 1500,
          aqWarningMax: 2500,
        ),
        contains('Humidity bounds must satisfy'),
      );

      // Invalid: air quality raw normal >= warning
      expect(
        ThresholdProvider.validateThresholds(
          tempNormalMax: 30.0,
          tempWarningMax: 35.0,
          humMin: 20.0,
          humNormalMin: 30.0,
          humNormalMax: 70.0,
          humMax: 85.0,
          aqNormalMax: 3000,
          aqWarningMax: 2000,
        ),
        contains('must be less than warning threshold'),
      );
    });

    test('ThresholdProvider evaluates status correctly against custom thresholds', () async {
      final provider = ThresholdProvider();
      await provider.loadFromPrefs();

      // Custom thresholds: temp normal < 28, warning 28-32, critical > 32
      await provider.updateThresholds(
        tempNormalMax: 28.0,
        tempWarningMax: 32.0,
        humMin: 25.0,
        humNormalMin: 35.0,
        humNormalMax: 65.0,
        humMax: 80.0,
        aqNormalMax: 1200,
        aqWarningMax: 2200,
      );

      // Temperature evaluations
      expect(provider.getTemperatureStatus(25.0), MetricStatus.normal);
      expect(provider.getTemperatureStatus(30.0), MetricStatus.warning);
      expect(provider.getTemperatureStatus(33.5), MetricStatus.critical);

      // Humidity evaluations
      expect(provider.getHumidityStatus(50.0), MetricStatus.normal);
      expect(provider.getHumidityStatus(28.0), MetricStatus.warning); // between 25 and 35
      expect(provider.getHumidityStatus(18.0), MetricStatus.critical); // below 25
      expect(provider.getHumidityStatus(82.0), MetricStatus.critical); // above 80

      // Air Quality evaluations
      expect(provider.getAirQualityStatus(800), MetricStatus.normal);
      expect(provider.getAirQualityStatus(1800), MetricStatus.warning);
      expect(provider.getAirQualityStatus(2600), MetricStatus.critical);
    });

    test('ThresholdProvider restores defaults and persists via SharedPreferences', () async {
      final provider = ThresholdProvider();
      await provider.loadFromPrefs();

      // Update to custom values
      await provider.updateThresholds(
        tempNormalMax: 25.0,
        tempWarningMax: 29.0,
        humMin: 20.0,
        humNormalMin: 30.0,
        humNormalMax: 70.0,
        humMax: 85.0,
        aqNormalMax: 1500,
        aqWarningMax: 2500,
      );
      expect(provider.tempNormalMax, 25.0);
      expect(provider.tempWarningMax, 29.0);

      // Restore defaults
      await provider.restoreDefaults();
      expect(provider.tempNormalMax, 30.0);
      expect(provider.tempWarningMax, 35.0);
      expect(provider.humidityMin, 20.0);
      expect(provider.aqNormalMax, 1500);
    });
  });
}

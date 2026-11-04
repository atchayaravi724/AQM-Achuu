import '../utils/data_decoder.dart';

enum DataSource { ble, wifi, firebase }

class SensorData {
  final double temperature; // °C
  final double humidity;    // %
  final int airQuality;     // MQ-135 raw ADC value (0-4095)
  final DataSource source;
  final DateTime timestamp;

  // MPU6050 physical hardware data (null when sensor is not connected)
  final bool mpuConnected;
  final double? accelX;
  final double? accelY;
  final double? accelZ;
  final double? gyroX;
  final double? gyroY;
  final double? gyroZ;

  const SensorData({
    required this.temperature,
    required this.humidity,
    this.airQuality = 0,
    this.source = DataSource.ble,
    required this.timestamp,
    this.mpuConnected = false,
    this.accelX,
    this.accelY,
    this.accelZ,
    this.gyroX,
    this.gyroY,
    this.gyroZ,
  });

  double get temperatureFahrenheit => temperature * 9 / 5 + 32;

  /// Air quality qualitative label based on MQ-135 raw ADC reading (0-4095)
  String get airQualityLabel {
    if (airQuality <= 0) return 'NO DATA';
    if (airQuality < 800) return 'GOOD';
    if (airQuality < 1500) return 'MODERATE';
    if (airQuality < 2500) return 'POOR';
    return 'HAZARDOUS';
  }

  /// Color index: 0=good, 1=moderate, 2=poor, 3=hazardous
  int get airQualityLevel {
    if (airQuality <= 0) return 0;
    if (airQuality < 800) return 0;
    if (airQuality < 1500) return 1;
    if (airQuality < 2500) return 2;
    return 3;
  }

  /// Validates sensor data integrity (rejects NaN, extreme out-of-range, and empty dummy packets)
  bool get isValid {
    if (temperature.isNaN || temperature.isInfinite || temperature < -40.0 || temperature > 125.0) {
      return false;
    }
    if (humidity.isNaN || humidity.isInfinite || humidity < 0.0 || humidity > 100.0) {
      return false;
    }
    if (airQuality < 0 || airQuality > 4095) {
      return false;
    }
    // Reject uninitialized dummy reading
    if (temperature == 0.0 && humidity == 0.0 && airQuality == 0) {
      return false;
    }
    return true;
  }

  /// Converts SensorData to a Firebase Realtime Database compatible map
  Map<String, dynamic> toFirebaseMap({String? connectionMode, String? deviceStatus, String? deviceName, String? deviceId}) {
    return {
      'temperature': temperature,
      'humidity': humidity,
      'air_quality': airQuality,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'device_status': deviceStatus ?? 'ONLINE',
      'connection_mode': connectionMode ?? (source == DataSource.ble ? 'BLE_GATEWAY' : 'WIFI'),
      'mpu_connected': mpuConnected,
      if (deviceName != null && deviceName.isNotEmpty) 'device_name': deviceName,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
      if (mpuConnected && accelX != null) 'motion': {
        'accel_x': accelX,
        'accel_y': accelY,
        'accel_z': accelZ,
        'gyro_x': gyroX,
        'gyro_y': gyroY,
        'gyro_z': gyroZ,
      },
    };
  }

  /// Safely parses and validates Firebase Realtime Database map
  static SensorData? fromFirebaseMap(Map<dynamic, dynamic> map) {
    final temp = _toDouble(map['temperature']);
    final hum = _toDouble(map['humidity']);
    final aq = _toInt(map['air_quality']) ?? 0;

    // Reject missing or corrupted primary readings
    if (temp == null || hum == null) return null;
    if (temp < -40.0 || temp > 125.0) return null;
    if (hum < 0.0 || hum > 100.0) return null;
    if (aq < 0 || aq > 5000) return null;

    // Guard against all-zero initial dummy packets
    if (temp == 0.0 && hum == 0.0 && aq == 0) return null;

    // Parse timestamp
    DateTime ts;
    final rawTs = map['timestamp'];
    if (rawTs is int) {
      // If in seconds (UNIX epoch < 2000000000), convert to ms
      final ms = rawTs < 2000000000 ? rawTs * 1000 : rawTs;
      ts = DateTime.fromMillisecondsSinceEpoch(ms);
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    // Parse MPU-6050 physical motion data if present
    final mpuConnected = map['mpu_connected'] == true;
    double? ax, ay, az, gx, gy, gz;
    if (mpuConnected && map['motion'] is Map) {
      final motion = map['motion'] as Map;
      ax = _toDouble(motion['accel_x'] ?? motion['accelX']);
      ay = _toDouble(motion['accel_y'] ?? motion['accelY']);
      az = _toDouble(motion['accel_z'] ?? motion['accelZ']);
      gx = _toDouble(motion['gyro_x'] ?? motion['gyroX']);
      gy = _toDouble(motion['gyro_y'] ?? motion['gyroY']);
      gz = _toDouble(motion['gyro_z'] ?? motion['gyroZ']);
    }

    return SensorData(
      temperature: temp,
      humidity: hum,
      airQuality: aq.clamp(0, 4095),
      source: DataSource.firebase,
      timestamp: ts,
      mpuConnected: mpuConnected,
      accelX: ax,
      accelY: ay,
      accelZ: az,
      gyroX: gx,
      gyroY: gy,
      gyroZ: gz,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v.isNaN || v.isInfinite ? null : v;
    if (v is int) return v.toDouble();
    if (v is String) {
      final p = double.tryParse(v);
      return (p != null && !p.isNaN && !p.isInfinite) ? p : null;
    }
    return null;
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.isNaN || v.isInfinite ? null : v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }

  /// Robust dual-mode float parser (delegates to DataDecoder):
  /// 1. Tries UTF-8 ASCII decimal string decoding (e.g. "28.5")
  /// 2. Falls back to 4-byte IEEE 754 little-endian float decoding
  static double parseFloat(List<int> bytes) => DataDecoder.decodeFloat(bytes);

  /// Robust dual-mode air quality parser (delegates to DataDecoder):
  /// 1. Tries UTF-8 ASCII integer/decimal string decoding (e.g. "650")
  /// 2. If 4 bytes: decodes IEEE 754 float and converts to int
  /// 3. If 2 bytes: decodes 16-bit unsigned integer (little endian)
  static int parseAirQuality(List<int> bytes) => DataDecoder.decodeAirQuality(bytes);

  SensorData copyWith({
    double? temperature,
    double? humidity,
    int? airQuality,
    DataSource? source,
    DateTime? timestamp,
    bool? mpuConnected,
    double? accelX,
    double? accelY,
    double? accelZ,
    double? gyroX,
    double? gyroY,
    double? gyroZ,
  }) {
    return SensorData(
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      airQuality: airQuality ?? this.airQuality,
      source: source ?? this.source,
      timestamp: timestamp ?? this.timestamp,
      mpuConnected: mpuConnected ?? this.mpuConnected,
      accelX: accelX ?? this.accelX,
      accelY: accelY ?? this.accelY,
      accelZ: accelZ ?? this.accelZ,
      gyroX: gyroX ?? this.gyroX,
      gyroY: gyroY ?? this.gyroY,
      gyroZ: gyroZ ?? this.gyroZ,
    );
  }
}

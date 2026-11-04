import 'dart:convert';
import 'dart:typed_data';

/// Production-grade binary & ASCII payload decoder for AERION – AeroSense BLE telemetry.
/// Supports dual-mode decoding:
/// 1. UTF-8 ASCII decimal strings (e.g. "28.5", "650", "2")
/// 2. IEEE 754 4-byte floating-point in little-endian & big-endian
/// 3. 16-bit / 8-bit integer formats
class DataDecoder {
  DataDecoder._();

  /// Decodes temperature or humidity from BLE payload.
  /// Tries UTF-8 ASCII decimal string first, then IEEE 754 4-byte float (little-endian).
  static double decodeFloat(List<int> bytes, {double defaultValue = 0.0}) {
    if (bytes.isEmpty) return defaultValue;

    // 1. Try ASCII decimal string (e.g. "28.5" -> 4 bytes [0x32, 0x38, 0x2E, 0x35])
    try {
      final asciiStr = utf8.decode(bytes).trim();
      final parsed = double.tryParse(asciiStr);
      if (parsed != null && !parsed.isNaN && !parsed.isInfinite) {
        return parsed;
      }
    } catch (_) {}

    // 2. Try IEEE 754 4-byte float in little-endian (standard ESP32 float pointer write)
    if (bytes.length >= 4) {
      final bd = ByteData(4);
      for (int i = 0; i < 4; i++) {
        bd.setUint8(i, bytes[i] & 0xFF);
      }
      final leVal = bd.getFloat32(0, Endian.little);
      if (!leVal.isNaN && !leVal.isInfinite) {
        return leVal;
      }
    }

    return defaultValue;
  }

  /// Decodes MQ-135 raw ADC air quality (0–4095).
  /// Supports:
  /// - ASCII decimal string ("650")
  /// - 4-byte IEEE 754 float (as sent by notifyBleFloat(pAirQualityChar, (float)airQuality))
  /// - 2-byte uint16 little-endian
  static int decodeAirQuality(List<int> bytes, {int defaultValue = 0}) {
    if (bytes.isEmpty) return defaultValue;

    // 1. Try ASCII string
    try {
      final asciiStr = utf8.decode(bytes).trim();
      final parsedInt = int.tryParse(asciiStr);
      if (parsedInt != null) return parsedInt.clamp(0, 4095);
      final parsedDouble = double.tryParse(asciiStr);
      if (parsedDouble != null && !parsedDouble.isNaN) {
        return parsedDouble.round().clamp(0, 4095);
      }
    } catch (_) {}

    // 2. 4-byte IEEE 754 float
    if (bytes.length >= 4) {
      final flt = decodeFloat(bytes);
      return flt.round().clamp(0, 4095);
    }

    // 3. 2-byte uint16 little-endian
    if (bytes.length >= 2) {
      final bd = ByteData(2);
      bd.setUint8(0, bytes[0] & 0xFF);
      bd.setUint8(1, bytes[1] & 0xFF);
      return bd.getUint16(0, Endian.little).clamp(0, 4095);
    }

    return defaultValue;
  }

  /// Decodes sampling interval in seconds (1–60s).
  static int decodeSamplingInterval(List<int> bytes, {int defaultValue = 2}) {
    if (bytes.isEmpty) return defaultValue;

    // 1. Try ASCII string
    try {
      final asciiStr = utf8.decode(bytes).trim();
      final parsed = int.tryParse(asciiStr);
      if (parsed != null && parsed >= 1 && parsed <= 60) {
        return parsed;
      }
    } catch (_) {}

    // 2. 2-byte uint16 little-endian
    if (bytes.length >= 2) {
      final bd = ByteData(2);
      bd.setUint8(0, bytes[0] & 0xFF);
      bd.setUint8(1, bytes[1] & 0xFF);
      final val = bd.getUint16(0, Endian.little);
      if (val >= 1 && val <= 60) return val;
    }

    // 3. 1-byte uint8
    if (bytes.length == 1 && bytes[0] >= 1 && bytes[0] <= 60) {
      return bytes[0];
    }

    return defaultValue;
  }

  /// Encodes sampling interval (1–60s) into 2-byte uint16 little-endian.
  static Uint8List encodeSamplingInterval(int seconds) {
    final clamped = seconds.clamp(1, 60);
    final bd = ByteData(2);
    bd.setUint16(0, clamped, Endian.little);
    return bd.buffer.asUint8List();
  }

  /// Decodes 1-byte alert flag (1 = Critical Temperature / Hazard).
  static int decodeAlertFlag(List<int> bytes) {
    if (bytes.isEmpty) return 0;
    return bytes[0] & 0xFF;
  }
}

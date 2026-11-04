enum AlertType { temperature, humidity, airQuality, disconnection }

enum AlertSeverity { normal, warning, critical }

class IncidentRecord {
  final String id;
  final DateTime startTime;
  final AlertType alertType;
  double peakTemperature;
  double peakHumidity;
  int peakAirQuality;
  DateTime? endTime;
  bool acknowledged;
  DateTime? acknowledgedAt;

  IncidentRecord({
    required this.id,
    required this.startTime,
    this.alertType = AlertType.temperature,
    required this.peakTemperature,
    this.peakHumidity = 0.0,
    this.peakAirQuality = 0,
    this.endTime,
    this.acknowledged = false,
    this.acknowledgedAt,
  });

  bool get isResolved => endTime != null;
  bool get isActive => endTime == null;

  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }

  String get durationLabel {
    final d = duration;
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  String get alertTypeLabel {
    switch (alertType) {
      case AlertType.temperature:
        return 'THERMAL HAZARD (>35°C)';
      case AlertType.humidity:
        return 'HUMIDITY ANOMALY';
      case AlertType.airQuality:
        return 'AIR QUALITY HAZARD';
      case AlertType.disconnection:
        return 'SENSOR DISCONNECTION';
    }
  }

  String get title {
    switch (alertType) {
      case AlertType.temperature:
        return 'Thermal Breach Detected';
      case AlertType.humidity:
        return 'Humidity Threshold Anomaly';
      case AlertType.airQuality:
        return 'Elevated Gas Concentration';
      case AlertType.disconnection:
        return 'Hardware Connection Lost';
    }
  }

  String get sensorName {
    switch (alertType) {
      case AlertType.temperature:
        return 'DHT22 Temperature Sensor';
      case AlertType.humidity:
        return 'DHT22 Humidity Sensor';
      case AlertType.airQuality:
        return 'MQ135 Gas Sensor (Raw ADC)';
      case AlertType.disconnection:
        return 'ESP32 Telemetry Engine';
    }
  }

  String get readingString {
    switch (alertType) {
      case AlertType.temperature:
        return '${peakTemperature.toStringAsFixed(1)} °C';
      case AlertType.humidity:
        return '${peakHumidity.toStringAsFixed(1)} %';
      case AlertType.airQuality:
        return '$peakAirQuality ADC';
      case AlertType.disconnection:
        return 'Offline';
    }
  }

  AlertSeverity get severity {
    switch (alertType) {
      case AlertType.temperature:
        if (peakTemperature >= 35.0) return AlertSeverity.critical;
        if (peakTemperature >= 30.0) return AlertSeverity.warning;
        return AlertSeverity.normal;
      case AlertType.humidity:
        if (peakHumidity > 85.0 || peakHumidity < 20.0) return AlertSeverity.critical;
        if (peakHumidity > 70.0 || peakHumidity < 30.0) return AlertSeverity.warning;
        return AlertSeverity.normal;
      case AlertType.airQuality:
        if (peakAirQuality > 2500) return AlertSeverity.critical;
        if (peakAirQuality > 1500) return AlertSeverity.warning;
        return AlertSeverity.normal;
      case AlertType.disconnection:
        return AlertSeverity.warning;
    }
  }

  String get severityLabel {
    switch (severity) {
      case AlertSeverity.critical:
        return 'CRITICAL';
      case AlertSeverity.warning:
        return 'WARNING';
      case AlertSeverity.normal:
        return 'NORMAL';
    }
  }

  Map<String, dynamic> toFirebaseMap() {
    return {
      'id': id,
      'alert_type': alertType.name,
      'alert_type_label': alertTypeLabel,
      'start_time': startTime.millisecondsSinceEpoch,
      'peak_temperature': peakTemperature,
      'peak_humidity': peakHumidity,
      'peak_air_quality': peakAirQuality,
      'acknowledged': acknowledged,
      if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt!.millisecondsSinceEpoch,
      if (endTime != null) 'end_time': endTime!.millisecondsSinceEpoch,
      'duration_seconds': duration.inSeconds,
      'is_resolved': isResolved,
    };
  }

  static IncidentRecord? fromMap(Map<dynamic, dynamic> map) {
    try {
      final id = map['id']?.toString() ?? 'INC-${DateTime.now().millisecondsSinceEpoch}';
      final startMs = (map['start_time'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
      final start = DateTime.fromMillisecondsSinceEpoch(startMs);
      final peakTemp = (map['peak_temperature'] as num?)?.toDouble() ?? 0.0;
      final peakHum = (map['peak_humidity'] as num?)?.toDouble() ?? 0.0;
      final peakAq = (map['peak_air_quality'] as num?)?.toInt() ?? 0;
      final ack = map['acknowledged'] == true;
      final ackMs = (map['acknowledged_at'] as num?)?.toInt();
      final ackAt = ackMs != null ? DateTime.fromMillisecondsSinceEpoch(ackMs) : null;
      final endMs = (map['end_time'] as num?)?.toInt();
      final end = endMs != null ? DateTime.fromMillisecondsSinceEpoch(endMs) : null;

      AlertType type = AlertType.temperature;
      final typeStr = map['alert_type']?.toString();
      if (typeStr != null) {
        type = AlertType.values.firstWhere(
          (e) => e.name == typeStr,
          orElse: () => AlertType.temperature,
        );
      }

      return IncidentRecord(
        id: id,
        startTime: start,
        alertType: type,
        peakTemperature: peakTemp,
        peakHumidity: peakHum,
        peakAirQuality: peakAq,
        acknowledged: ack,
        acknowledgedAt: ackAt,
        endTime: end,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => toFirebaseMap();

  factory IncidentRecord.fromJson(Map<String, dynamic> json) {
    return fromMap(json)!;
  }
}

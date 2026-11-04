import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleConstants {
  static const String targetDevicePrefix = 'AQM-';
  static const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String temperatureCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const String humidityCharUuid = 'cba1d466-344c-4be3-ab3f-189f80dd7518';
  static const String samplingIntervalCharUuid = 'd8e3b210-9b48-4b92-9654-e75b2b2a60a4';
  static const String alertCharUuid = 'e7f2a1b0-4a3d-4c5e-8f6b-9c1d2e3f4a5b';
  static const String airQualityCharUuid = 'f0de3a41-2b5e-4c6f-9d7a-1e8b3c4d5e6f';

  static const double warningTempThreshold = 30.0;
  static const double criticalTempThreshold = 35.0;

  static Guid get serviceGuid => Guid(serviceUuid);
  static Guid get temperatureGuid => Guid(temperatureCharUuid);
  static Guid get humidityGuid => Guid(humidityCharUuid);
  static Guid get samplingIntervalGuid => Guid(samplingIntervalCharUuid);
  static Guid get alertGuid => Guid(alertCharUuid);
  static Guid get airQualityGuid => Guid(airQualityCharUuid);
}

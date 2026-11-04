import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'app_logger.dart';

/// Manages local push notifications for sensor hazard alerts.
class AlertService {
  static final AlertService _instance = AlertService._internal();
  factory AlertService() => _instance;
  AlertService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      await _notifications.initialize(
        const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
      );
      _initialized = true;
    } catch (e) {
      AppLogger.w('AlertService', 'Initialization error: $e');
    }
  }

  Future<void> showTemperatureAlert(double temperature) async {
    if (!_initialized || kIsWeb) return;
    try {
      await _notifications.show(
        1001,
        '⚠️ CRITICAL THERMAL HAZARD',
        'Temperature: ${temperature.toStringAsFixed(1)}°C exceeds 35°C limit!',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'aerosense_hazard',
            'Thermal Hazard Alerts',
            channelDescription: 'Critical temperature threshold alerts',
            importance: Importance.max,
            priority: Priority.high,
            color: Color(0xFFFF1744),
            enableVibration: true,
            playSound: true,
          ),
          iOS: DarwinNotificationDetails(
            sound: 'default',
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      AppLogger.e('Alert', 'Notification error', e);
    }
  }

  Future<void> showHumidityAlert(double humidity) async {
    if (!_initialized || kIsWeb) return;
    try {
      await _notifications.show(
        1002,
        '💧 Abnormal Humidity Detected',
        'Humidity: ${humidity.toStringAsFixed(1)}% is outside normal range',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'aerosense_humidity',
            'Humidity Alerts',
            channelDescription: 'Humidity threshold alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      AppLogger.e('Alert', 'Notification error', e);
    }
  }

  Future<void> showDisconnectionAlert(String source) async {
    if (!_initialized || kIsWeb) return;
    try {
      await _notifications.show(
        1003,
        '📡 Sensor Disconnected',
        '$source connection lost — attempting reconnect',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'aerosense_connection',
            'Connection Alerts',
            channelDescription: 'Sensor connection status alerts',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
          ),
        ),
      );
    } catch (e) {
      AppLogger.e('Alert', 'Notification error', e);
    }
  }

  Future<void> showAirQualityAlert(int aqiValue) async {
    if (!_initialized || kIsWeb) return;
    try {
      await _notifications.show(
        1004,
        '🌫️ Poor Air Quality Detected',
        'Air Quality Index: $aqiValue — Ventilate the area immediately',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'aerosense_air',
            'Air Quality Alerts',
            channelDescription: 'Air quality threshold alerts',
            importance: Importance.high,
            priority: Priority.high,
            color: Color(0xFFFFAB00),
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      AppLogger.e('Alert', 'Notification error', e);
    }
  }
}

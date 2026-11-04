import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'app_logger.dart';

enum BlePermissionStatus {
  granted,
  denied,
  permanentlyDenied,
  locationServiceDisabled,
  bluetoothOff,
  webUnsupported,
}

class PermissionsHelper {
  /// Returns whether the app is currently running on the Web (e.g. Chrome).
  static bool get isWeb => kIsWeb;

  /// Check and request required BLE permissions based on platform and OS version.
  /// - Web: Unsupported for passive broadcast BLE scanning.
  /// - Android 12+ (API 31+): BLUETOOTH_SCAN, BLUETOOTH_CONNECT, ACCESS_FINE_LOCATION.
  /// - Android ≤ 11 (API ≤ 30): ACCESS_FINE_LOCATION. (BLUETOOTH and BLUETOOTH_ADMIN are install-time).
  /// - iOS: NSBluetoothAlwaysUsageDescription / Permission.bluetooth.
  static Future<BlePermissionStatus> checkAndRequestBlePermissions() async {
    if (kIsWeb) {
      return BlePermissionStatus.webUnsupported;
    }

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      if (sdkInt >= 31) {
        // Android 12+ (API 31+) runtime permissions
        final Map<Permission, PermissionStatus> statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();

        final scanStatus = statuses[Permission.bluetoothScan];
        final connectStatus = statuses[Permission.bluetoothConnect];

        if (scanStatus == PermissionStatus.permanentlyDenied ||
            connectStatus == PermissionStatus.permanentlyDenied) {
          return BlePermissionStatus.permanentlyDenied;
        }

        final scanGranted = scanStatus?.isGranted == true || scanStatus?.isLimited == true;
        final connectGranted = connectStatus?.isGranted == true || connectStatus?.isLimited == true;

        if (!scanGranted || !connectGranted) {
          return BlePermissionStatus.denied;
        }
      } else {
        // Android 11 and below (API <= 30)
        // BLUETOOTH_SCAN does not exist on API <= 30. Only location is a runtime permission.
        final locStatus = await Permission.locationWhenInUse.request();
        if (locStatus == PermissionStatus.permanentlyDenied) {
          return BlePermissionStatus.permanentlyDenied;
        }
        if (!locStatus.isGranted && !locStatus.isLimited) {
          return BlePermissionStatus.denied;
        }

        // On Android <= 11, GPS Location Service MUST be enabled for BLE scanning
        final isGpsOn = await isLocationServiceEnabled();
        if (!isGpsOn) {
          return BlePermissionStatus.locationServiceDisabled;
        }
      }

      return BlePermissionStatus.granted;
    } else if (Platform.isIOS) {
      final status = await Permission.bluetooth.request();
      if (status == PermissionStatus.permanentlyDenied) {
        return BlePermissionStatus.permanentlyDenied;
      }
      return status.isGranted || status.isLimited
          ? BlePermissionStatus.granted
          : BlePermissionStatus.denied;
    }

    // macOS, Windows, Linux
    return BlePermissionStatus.granted;
  }

  /// Check if GPS/Location services are enabled on Android devices.
  static Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      try {
        return await Permission.locationWhenInUse.serviceStatus.isEnabled;
      } catch (_) {
        return true;
      }
    }
    return true;
  }

  /// Check whether the Bluetooth hardware adapter is turned ON.
  /// Safely guarded with a 2-second timeout so it never hangs.
  static Future<bool> isBluetoothOn() async {
    if (kIsWeb) return false;
    try {
      final state = await FlutterBluePlus.adapterState
          .first
          .timeout(const Duration(seconds: 2), onTimeout: () => BluetoothAdapterState.unknown);
      return state == BluetoothAdapterState.on;
    } catch (e) {
      AppLogger.w('PermissionsHelper', 'isBluetoothOn check error: $e');
      return false;
    }
  }

  /// Show dialog when running in Chrome / Web.
  static Future<void> showWebUnsupportedDialog(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00F2FE).withOpacity(0.12),
                border: Border.all(color: const Color(0xFF00F2FE), width: 1.5),
              ),
              child: const Icon(Icons.language, color: Color(0xFF00F2FE), size: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'Web Bluetooth Scanning Unsupported',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Google Chrome and Web Bluetooth API do not support background/passive BLE discovery scans for advertising peripherals.\n\nTo discover and connect to physical ESP32 BLE hardware (AQM-*), please run AERION on a native Android or iOS device.\n\nTip: You can still monitor ESP32 sensor telemetry in Chrome via the Wi-Fi Monitor & Firebase Realtime Database!',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 13, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF8B949E),
                      side: const BorderSide(color: Color(0xFF30363D)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Dismiss'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F2FE),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Understood', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Show modal bottom sheet when Bluetooth adapter is powered off.
  static Future<void> showBluetoothOffDialog(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF1744).withOpacity(0.12),
                border: Border.all(color: const Color(0xFFFF1744), width: 1.5),
              ),
              child: const Icon(Icons.bluetooth_disabled, color: Color(0xFFFF1744), size: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'Bluetooth is Powered Off',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Please turn on Bluetooth to scan for nearby AeroSense (AQM-*) sensor nodes.',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F2FE),
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  if (!kIsWeb && Platform.isAndroid) {
                    await FlutterBluePlus.turnOn();
                  } else {
                    await openAppSettings();
                  }
                } catch (_) {}
              },
              child: const Text('Turn On Bluetooth', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  /// Show modal when GPS Location Services are turned off on Android.
  static Future<void> showLocationServiceDisabledDialog(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFFAB00).withOpacity(0.12),
                border: Border.all(color: const Color(0xFFFFAB00), width: 1.5),
              ),
              child: const Icon(Icons.location_off, color: Color(0xFFFFAB00), size: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'Location Services (GPS) Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Android requires device Location Services (GPS) to be turned ON in order to scan for BLE beacons and peripheral advertisements.',
              style: TextStyle(color: Color(0xFF8B949E), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFAB00),
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings();
              },
              child: const Text('Open Settings', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  /// Show modal when Bluetooth or Location permissions are denied.
  static Future<void> showPermissionsDeniedSheet(BuildContext context, {bool isPermanent = false}) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF1744).withOpacity(0.12),
                border: Border.all(color: const Color(0xFFFF1744), width: 1.5),
              ),
              child: const Icon(Icons.security, color: Color(0xFFFF1744), size: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'BLE Permissions Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isPermanent
                  ? 'Bluetooth and Location permissions are permanently denied. Please grant them in system settings to discover ESP32 hardware.'
                  : 'AERION requires Bluetooth Scan, Bluetooth Connect, and Location permissions to communicate with your ESP32 sensor node.',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00F2FE),
                foregroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings();
              },
              child: const Text('Open App Settings', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

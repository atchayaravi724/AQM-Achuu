// File generated for FlutterFire configuration.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Connected to Firebase project: AERION-AeroSense
/// Database URL: https://aerion-aerosense-default-rtdb.asia-southeast1.firebasedatabase.app
class DefaultFirebaseOptions {
  /// Whether Firebase options have been configured for the current platform.
  static bool get isConfigured => currentPlatform != null;

  /// Returns [FirebaseOptions] for the current platform if configured, otherwise null.
  static FirebaseOptions? get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return null;
      case TargetPlatform.linux:
        return null;
      default:
        return null;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBM0eHoK7YG_N0NnkLbcLVGvCgSdtTtqBg',
    appId: '1:688104346207:web:aa2cea70e8f5c3859241ea',
    messagingSenderId: '688104346207',
    projectId: 'aerion-aerosense',
    databaseURL: 'https://aerion-aerosense-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'aerion-aerosense.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBM0eHoK7YG_N0NnkLbcLVGvCgSdtTtqBg',
    appId: '1:688104346207:android:aa2cea70e8f5c3859241ea',
    messagingSenderId: '688104346207',
    projectId: 'aerion-aerosense',
    databaseURL: 'https://aerion-aerosense-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'aerion-aerosense.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAjJomN5Q1DMQZBI-UlkVtdFJJcOblQ6lQ',
    appId: '1:688104346207:ios:59782367b8ec0da09241ea',
    messagingSenderId: '688104346207',
    projectId: 'aerion-aerosense',
    databaseURL: 'https://aerion-aerosense-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'aerion-aerosense.firebasestorage.app',
    iosBundleId: 'com.aerion.aeriona',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAjJomN5Q1DMQZBI-UlkVtdFJJcOblQ6lQ',
    appId: '1:688104346207:ios:59782367b8ec0da09241ea',
    messagingSenderId: '688104346207',
    projectId: 'aerion-aerosense',
    databaseURL: 'https://aerion-aerosense-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'aerion-aerosense.firebasestorage.app',
    iosBundleId: 'com.aerion.aeriona',
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'ble/ble_manager.dart';
import 'wifi/wifi_sensor_service.dart';
import 'firebase/firebase_service.dart';
import 'connectivity/connectivity_manager.dart';
import 'providers/app_state.dart';
import 'providers/threshold_provider.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'utils/app_logger.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.init();

  // Force portrait mode on mobile platforms
  if (!kIsWeb) {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (e) {
      AppLogger.w('SystemChrome', 'Orientation error: $e');
    }
  }

  // System UI overlay style — matches the dark AeroSense theme
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D1117),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Initialize Firebase gracefully without crashing
  final firebaseService = FirebaseService();
  await _initFirebase(firebaseService);

  runApp(AerionAeroSenseApp(firebaseService: firebaseService));
}

/// Attempts to initialize Firebase gracefully for Web, Android, and iOS.
/// If configuration is not yet available, marks [FirebaseService] as unconfigured
/// and allows the application UI to load cleanly without crashing.
Future<void> _initFirebase(FirebaseService firebaseService) async {
  try {
    FirebaseOptions? options;
    try {
      options = DefaultFirebaseOptions.currentPlatform;
    } catch (e) {
      AppLogger.w('Firebase', 'DefaultFirebaseOptions platform error: $e');
      options = null;
    }

    if (kIsWeb && options == null) {
      AppLogger.i('Firebase', 'Web options not configured yet. Running in unconfigured mode.');
      firebaseService.markUnconfigured(
        'Firebase Web configuration missing. Run "flutterfire configure" to enable live cloud sync.',
      );
      return;
    }

    if (options != null) {
      await Firebase.initializeApp(options: options);
      firebaseService.markInitialized(true, 'Connected to Firebase');
      AppLogger.i('Firebase', 'Initialized with platform options');
    } else {
      // Mobile platforms (Android/iOS): try native configuration files
      try {
        await Firebase.initializeApp();
        firebaseService.markInitialized(true, 'Connected to Firebase');
        AppLogger.i('Firebase', 'Initialized with native configuration');
      } catch (nativeError) {
        AppLogger.w('Firebase', 'Native initialization skipped/failed: $nativeError');
        firebaseService.markUnconfigured(
          'Firebase configuration not found. Add google-services.json or run "flutterfire configure".',
        );
      }
    }
  } catch (e) {
    AppLogger.e('Firebase', 'Initialization error', e);
    firebaseService.markUnconfigured('Firebase initialization failed: $e');
  }
}

class AerionAeroSenseApp extends StatelessWidget {
  final FirebaseService firebaseService;

  const AerionAeroSenseApp({
    super.key,
    required this.firebaseService,
  });

  @override
  Widget build(BuildContext context) {
    final bleManager = BleManager();
    final wifiService = WiFiSensorService();
    final thresholdProvider = ThresholdProvider();
    final connectivityManager = ConnectivityManager(
      wifiService: wifiService,
      firebaseService: firebaseService,
      bleManager: bleManager,
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<BleManager>.value(value: bleManager),
        ChangeNotifierProvider<WiFiSensorService>.value(value: wifiService),
        ChangeNotifierProvider<FirebaseService>.value(value: firebaseService),
        ChangeNotifierProvider<ConnectivityManager>.value(value: connectivityManager),
        ChangeNotifierProvider<ThresholdProvider>.value(value: thresholdProvider),
        ChangeNotifierProvider<AppState>(
          create: (_) => AppState(
            bleManager: bleManager,
            connectivityManager: connectivityManager,
            thresholdProvider: thresholdProvider,
          ),
        ),
      ],
      child: Consumer<AppState>(
        builder: (context, appState, _) {
          final isDark = appState.isDarkMode;
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            systemNavigationBarColor: isDark ? const Color(0xFF0B0F17) : const Color(0xFFF8FAFC),
            systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          ));

          return MaterialApp(
            title: 'Aerion AeroSense',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: appState.themeMode,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}

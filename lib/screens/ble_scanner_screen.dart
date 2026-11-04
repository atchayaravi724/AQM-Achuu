import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../ble/ble_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/rssi_bars.dart';
import '../utils/permissions_helper.dart';
import 'home_shell.dart';

// ---------------------------------------------------------------------------
// BLE Scanner Screen
// ---------------------------------------------------------------------------

class BleScannerScreen extends StatefulWidget {
  const BleScannerScreen({super.key});

  @override
  State<BleScannerScreen> createState() => _BleScannerScreenState();
}

class _BleScannerScreenState extends State<BleScannerScreen>
    with TickerProviderStateMixin {
  // ── Radar animation controllers ──────────────────────────────────────────
  late final AnimationController _radarSweepController;
  late final AnimationController _blipController;
  late final AnimationController _pulseTitleController;
  late final AnimationController _scanProgressController;

  late final Animation<double> _sweepAnimation;
  late final Animation<double> _pulseTitleAnimation;
  late final Animation<double> _scanProgressAnimation;

  // ── Radar blip state ─────────────────────────────────────────────────────
  final List<_RadarBlip> _blips = [];
  final Random _rng = Random();

  // ── Connection-step overlay ───────────────────────────────────────────────
  bool _showConnectionOverlay = false;
  ConnectionStep _currentConnectionStep = ConnectionStep.idle;

  // ── Scan results (local copy) ───────────────────────────────────────────
  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<ConnectionStep>? _connSub;

  @override
  void initState() {
    super.initState();

    // Radar sweep: full 360° rotation, 3 s per revolution.
    _radarSweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _sweepAnimation = Tween<double>(begin: 0, end: 2 * pi)
        .animate(_radarSweepController);

    // Blip fade controller: drives opacity 1 → 0 on each tick.
    _blipController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _blipController.reset();
        }
      });

    // Title pulse when scanning.
    _pulseTitleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseTitleAnimation = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(
            parent: _pulseTitleController, curve: Curves.easeInOut));

    // 15-second scanning progress timer animation
    _scanProgressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );
    _scanProgressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanProgressController, curve: Curves.linear),
    );

    // Periodically spawn new blips while scanning.
    _radarSweepController.addListener(_maybeSpawnBlip);

    // Listen to scan results and connection state streams.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ble = context.read<BleManager>();
      setState(() {
        _scanResults = ble.scanResults;
      });

      if (ble.isScanning && !_radarSweepController.isAnimating) {
        _startRadarAnimation();
      }

      _scanSub = ble.scanResultsStream.listen((results) {
        if (mounted) setState(() => _scanResults = results);
      });

      _connSub = ble.connectionStepStream.listen((step) {
        if (!mounted) return;
        setState(() {
          _currentConnectionStep = step;
          _showConnectionOverlay =
              step != ConnectionStep.idle &&
              step != ConnectionStep.connected &&
              step != ConnectionStep.disconnected;
        });
        if (step == ConnectionStep.connected) {
          setState(() {
            _showConnectionOverlay = false;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _radarSweepController.removeListener(_maybeSpawnBlip);
    _radarSweepController.dispose();
    _blipController.dispose();
    _pulseTitleController.dispose();
    _scanProgressController.dispose();
    _scanSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  void _maybeSpawnBlip() {
    if (!mounted) return;
    final ble = context.read<BleManager>();
    if (!ble.isScanning) return;

    if (_rng.nextDouble() < 0.07 && _blips.length < 12) {
      setState(() {
        _blips.add(_RadarBlip(
          angle: _rng.nextDouble() * 2 * pi,
          radius: 0.2 + _rng.nextDouble() * 0.75,
          createdAt: DateTime.now(),
          ttl: 2000 + _rng.nextInt(2000),
        ));
        _blips.removeWhere((b) =>
            DateTime.now().difference(b.createdAt).inMilliseconds > b.ttl);
      });
    }
  }

  Future<void> _onScanToggle(BleManager ble) async {
    // If running in Web (Chrome), explain that background broadcast scanning is unsupported
    if (kIsWeb) {
      await PermissionsHelper.showWebUnsupportedDialog(context);
      return;
    }

    if (ble.isScanning) {
      await ble.stopScan();
      _stopRadarAnimation();
    } else {
      final status = await PermissionsHelper.checkAndRequestBlePermissions();
      if (!mounted) return;

      switch (status) {
        case BlePermissionStatus.webUnsupported:
          await PermissionsHelper.showWebUnsupportedDialog(context);
          return;
        case BlePermissionStatus.denied:
          await PermissionsHelper.showPermissionsDeniedSheet(context, isPermanent: false);
          return;
        case BlePermissionStatus.permanentlyDenied:
          await PermissionsHelper.showPermissionsDeniedSheet(context, isPermanent: true);
          return;
        case BlePermissionStatus.locationServiceDisabled:
          await PermissionsHelper.showLocationServiceDisabledDialog(context);
          return;
        case BlePermissionStatus.bluetoothOff:
          await PermissionsHelper.showBluetoothOffDialog(context);
          return;
        case BlePermissionStatus.granted:
          break;
      }

      final btOn = await PermissionsHelper.isBluetoothOn();
      if (!btOn) {
        if (mounted) await PermissionsHelper.showBluetoothOffDialog(context);
        return;
      }

      await ble.startScan();
      _startRadarAnimation();
    }
  }

  void _startRadarAnimation() {
    _radarSweepController.repeat();
    _pulseTitleController.repeat(reverse: true);
    _scanProgressController.forward(from: 0.0);
  }

  void _stopRadarAnimation() {
    _radarSweepController.stop();
    _pulseTitleController.stop();
    _scanProgressController.reset();
    setState(() => _blips.clear());
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.electricCyan : AppColors.lightPrimary;
    final successColor = isDark ? AppColors.neonEmerald : AppColors.lightSecondary;

    return Consumer<BleManager>(
      builder: (context, ble, _) {
        // Automatically synchronize radar sweep when BLE scan timeout fires
        if (!ble.isScanning && _radarSweepController.isAnimating) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _stopRadarAnimation();
          });
        }

        // Sort: AeroSense target devices (AQM-*) first, then highest RSSI
        final sorted = List<ScanResult>.from(_scanResults)
          ..sort((a, b) {
            final aIsTarget = BleManager.isAeroSenseDevice(a);
            final bIsTarget = BleManager.isAeroSenseDevice(b);
            if (aIsTarget && !bIsTarget) return -1;
            if (!aIsTarget && bIsTarget) return 1;
            return b.rssi.compareTo(a.rssi);
          });

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Stack(
            children: [
              // ── Main content ──────────────────────────────────────────────
              SafeArea(
                child: Column(
                  children: [
                    _buildHeader(ble, isDark, primaryColor, successColor),
                    if (kIsWeb) _buildWebUnsupportedBanner(isDark, primaryColor),
                    if (ble.isConnected) ...[
                      _buildConnectedDeviceCard(ble, isDark, primaryColor, successColor),
                      const SizedBox(height: 8),
                    ] else ...[
                      _buildRadarSection(ble, isDark, primaryColor, successColor),
                      _buildScanButton(ble, isDark, primaryColor),
                      if (ble.isScanning) _buildScanProgressBar(isDark, primaryColor, successColor),
                      const SizedBox(height: 8),
                    ],
                    Expanded(child: _buildDeviceList(sorted, ble, isDark, primaryColor, successColor)),
                  ],
                ),
              ),

              // ── Connection overlay ────────────────────────────────────────
              if (_showConnectionOverlay)
                _ConnectionOverlay(
                  currentStep: _currentConnectionStep,
                  isDark: isDark,
                  primaryColor: primaryColor,
                  successColor: successColor,
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Section builders ──────────────────────────────────────────────────────

  Widget _buildConnectedDeviceCard(BleManager ble, bool isDark, Color primaryColor, Color successColor) {
    final devName = ble.connectedDeviceName ?? 'AeroSense Node';
    final devId = ble.connectedDevice?.remoteId.str ?? 'Unknown ID';
    final rssi = ble.lastRssi;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: successColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: successColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: successColor.withValues(alpha: 0.15),
                ),
                child: Icon(Icons.bluetooth_connected_rounded, color: successColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      devName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      devId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (rssi != 0) ...[
                RssiBars(rssi: rssi),
                const SizedBox(width: 6),
                Text(
                  '$rssi dBm',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => HomeShell.switchTab(context, 0),
                  icon: const Icon(Icons.dashboard_rounded, size: 16),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'VIEW DASHBOARD',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: isDark ? AppColors.background : Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => ble.disconnect(),
                icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.crimsonNeon),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'DISCONNECT',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.crimsonNeon),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.crimsonNeon, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BleManager ble, bool isDark, Color primaryColor, Color successColor) {
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          // Aerion logo mark
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: primaryColor, width: 1.5),
              color: primaryColor.withValues(alpha: 0.10),
            ),
            child: Center(
              child: Text(
                'A',
                style: TextStyle(
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AERION',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  letterSpacing: 3,
                ),
              ),
              Text(
                'AeroSense BLE Terminal',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 11,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: ble.isScanning
                  ? successColor.withValues(alpha: 0.12)
                  : (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: ble.isScanning
                    ? successColor
                    : (isDark ? AppColors.border : AppColors.lightBorder),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ble.isScanning ? successColor : textSecondary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  ble.isScanning ? 'SCANNING' : 'IDLE',
                  style: TextStyle(
                    color: ble.isScanning ? successColor : textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.2, end: 0);
  }

  Widget _buildWebUnsupportedBanner(bool isDark, Color primaryColor) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primaryColor.withValues(alpha: 0.15),
            ),
            child: Icon(
              Icons.info_outline_rounded,
              color: primaryColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Web Bluetooth scanning is unsupported in Chrome',
                  style: TextStyle(
                    color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Chrome does not support background BLE scanning. To discover ESP32 nodes (AQM-*), run on Android/iOS or use Wi-Fi & Firebase.',
                  style: TextStyle(
                    color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarSection(BleManager ble, bool isDark, Color primaryColor, Color successColor) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.34,
      child: AnimatedBuilder(
        animation: _sweepAnimation,
        builder: (_, __) {
          final blipData = _blips.map((b) {
            final age = DateTime.now()
                .difference(b.createdAt)
                .inMilliseconds;
            final opacity =
                (1.0 - age / b.ttl).clamp(0.0, 1.0);
            return _BlipRenderData(
                angle: b.angle, radius: b.radius, opacity: opacity);
          }).toList();

          return CustomPaint(
            painter: _RadarPainter(
              sweepAngle: ble.isScanning ? _sweepAnimation.value : 0,
              blips: blipData,
              isActive: ble.isScanning,
              isDark: isDark,
              primaryColor: primaryColor,
              successColor: successColor,
            ),
            child: Container(),
          );
        },
      ),
    );
  }

  Widget _buildScanProgressBar(bool isDark, Color primaryColor, Color successColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'SCANNING (15s WINDOW)',
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              Text(
                '${_scanResults.length} FOUND',
                style: TextStyle(
                  color: successColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: AnimatedBuilder(
              animation: _scanProgressAnimation,
              builder: (context, _) {
                return LinearProgressIndicator(
                  value: _scanProgressAnimation.value,
                  backgroundColor: isDark ? AppColors.cardBg : AppColors.lightBorder,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  minHeight: 3,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanButton(BleManager ble, bool isDark, Color primaryColor) {
    final textSecondary = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          // Title
          AnimatedBuilder(
            animation: _pulseTitleAnimation,
            builder: (_, __) => Opacity(
              opacity: ble.isScanning ? _pulseTitleAnimation.value : 1.0,
              child: Text(
                ble.isScanning
                    ? 'SCANNING FOR BLE HARDWARE…'
                    : 'TAP TO SCAN',
                style: TextStyle(
                  color: ble.isScanning ? primaryColor : textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Button
          GestureDetector(
            onTap: () => _onScanToggle(ble),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ble.isScanning
                    ? AppColors.crimsonNeon.withValues(alpha: 0.15)
                    : primaryColor.withValues(alpha: 0.12),
                border: Border.all(
                  color: ble.isScanning ? AppColors.crimsonNeon : primaryColor,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: ble.isScanning
                        ? AppColors.crimsonNeon.withValues(alpha: 0.3)
                        : primaryColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                ble.isScanning ? Icons.stop_rounded : Icons.bluetooth_searching,
                color: ble.isScanning ? AppColors.crimsonNeon : primaryColor,
                size: 26,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(
    List<ScanResult> results,
    BleManager ble,
    bool isDark,
    Color primaryColor,
    Color successColor,
  ) {
    if (results.isEmpty) {
      return _buildEmptyState(ble, isDark, primaryColor, successColor);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: results.length,
      itemBuilder: (_, index) {
        final result = results[index];
        return _DeviceListItem(
          result: result,
          index: index,
          isDark: isDark,
          primaryColor: primaryColor,
          successColor: successColor,
          onConnect: () => ble.connectToDevice(result.device),
        );
      },
    );
  }

  Widget _buildEmptyState(BleManager ble, bool isDark, Color primaryColor, Color successColor) {
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    if (ble.isScanning) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Listening for ESP32 BLE advertisement packets…',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Searching for "AQM-*" prefixes and 4fafc201 service UUID',
                style: TextStyle(color: textSecondary, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    // Idle empty state with hardware checklist
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? AppColors.cardBg : AppColors.lightBackground,
                border: Border.all(color: isDark ? AppColors.border : AppColors.lightBorder, width: 1.5),
              ),
              child: Icon(Icons.bluetooth_searching, color: textSecondary, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              'No AeroSense Nodes Discovered',
              style: TextStyle(
                color: textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap the radar button above to scan for nearby hardware.',
              style: TextStyle(color: textSecondary, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardBg : AppColors.lightCardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isDark ? AppColors.border : AppColors.lightBorder, width: 1),
                boxShadow: isDark
                    ? null
                    : const [
                        BoxShadow(
                          color: Color(0x060F172A),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        )
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.checklist_rounded, color: primaryColor, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'HARDWARE CHECKLIST',
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _checklistRow('ESP32 Dev Module powered ON with DHT22 (GPIO 4) & MQ-135 (GPIO 34)', isDark, successColor),
                  _checklistRow('Firmware broadcasting with "AQM-*" (e.g. AQM-Atchaya)', isDark, successColor),
                  _checklistRow('Bluetooth and Location (GPS) turned ON on this phone', isDark, successColor),
                  _checklistRow('Device within line-of-sight range (< 10 meters)', isDark, successColor),
                  _checklistRow('No other phone currently connected (1 active connection)', isDark, successColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _checklistRow(String text, bool isDark, Color successColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: successColor, fontSize: 12, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Device list item
// ---------------------------------------------------------------------------

class _DeviceListItem extends StatelessWidget {
  final ScanResult result;
  final int index;
  final bool isDark;
  final Color primaryColor;
  final Color successColor;
  final VoidCallback onConnect;

  const _DeviceListItem({
    required this.result,
    required this.index,
    required this.isDark,
    required this.primaryColor,
    required this.successColor,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final name = BleManager.getDeviceName(result);
    final mac = result.device.remoteId.str;
    final rssi = result.rssi;
    final isTarget = BleManager.isAeroSenseDevice(result);
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Device name + badge
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                style: TextStyle(
                                  color: isTarget ? primaryColor : textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isTarget) ...[
                              const SizedBox(width: 8),
                              _TargetBadge(successColor: successColor),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        // MAC address + GATT Service indicator
                        Row(
                          children: [
                            Text(
                              mac,
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 11,
                                fontFamily: AppTextStyles.fontFamily,
                                letterSpacing: 0.8,
                              ),
                            ),
                            if (isTarget) ...[
                              const SizedBox(width: 8),
                              Text('•', style: TextStyle(color: isDark ? AppColors.border : AppColors.lightBorder, fontSize: 11)),
                              const SizedBox(width: 8),
                              Text(
                                'AeroSense GATT',
                                style: TextStyle(
                                  color: successColor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // RSSI bars
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      RssiBars(rssi: rssi),
                      const SizedBox(height: 2),
                      Text(
                        '$rssi dBm',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Connect button
              SizedBox(
                width: double.infinity,
                height: 38,
                child: OutlinedButton(
                  onPressed: onConnect,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: isTarget
                        ? primaryColor.withValues(alpha: 0.08)
                        : Colors.transparent,
                    foregroundColor: isTarget ? primaryColor : textSecondary,
                    side: BorderSide(
                      color: isTarget ? primaryColor : (isDark ? AppColors.border : AppColors.lightBorder),
                      width: isTarget ? 1.5 : 1.0,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.bluetooth_connected,
                        size: 15,
                        color: isTarget ? primaryColor : textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'CONNECT TO HARDWARE',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                          color: isTarget ? primaryColor : textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate(delay: (index * 60).ms)
        .fadeIn(duration: 350.ms)
        .slideX(begin: 0.15, end: 0, curve: Curves.easeOut);
  }
}

// ---------------------------------------------------------------------------
// Target badge
// ---------------------------------------------------------------------------

class _TargetBadge extends StatelessWidget {
  final Color successColor;
  const _TargetBadge({required this.successColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: successColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: successColor.withValues(alpha: 0.8),
          width: 1,
        ),
      ),
      child: Text(
        'AEROSENSE NODE',
        style: TextStyle(
          color: successColor,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).shimmer(
          duration: 2000.ms,
          color: successColor.withValues(alpha: 0.4),
        );
  }
}

// ---------------------------------------------------------------------------
// Connection Overlay
// ---------------------------------------------------------------------------

class _ConnectionOverlay extends StatelessWidget {
  final ConnectionStep currentStep;
  final bool isDark;
  final Color primaryColor;
  final Color successColor;

  static const List<String> _stepLabels = [
    'Connecting...',
    'Bonding...',
    'Discovering Services...',
    'Subscribing to GATT Streams...',
    'Ready!',
  ];

  static const List<ConnectionStep> _stepEnums = [
    ConnectionStep.connecting,
    ConnectionStep.bonding,
    ConnectionStep.discoveringServices,
    ConnectionStep.subscribingGatt,
    ConnectionStep.connected,
  ];

  const _ConnectionOverlay({
    required this.currentStep,
    required this.isDark,
    required this.primaryColor,
    required this.successColor,
  });

  @override
  Widget build(BuildContext context) {
    final currentIndex = _stepEnums.indexOf(currentStep);
    final cardBg = isDark ? AppColors.cardBg : AppColors.lightCardBg;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;

    return Container(
      color: Colors.black.withValues(alpha: isDark ? 0.85 : 0.65),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withValues(alpha: 0.15),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulsingBluetoothIcon(primaryColor: primaryColor),
              const SizedBox(height: 24),
              Text(
                'ESTABLISHING CONNECTION',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              ..._stepLabels.asMap().entries.map((entry) {
                final idx = entry.key;
                final label = entry.value;
                final isDone = currentIndex > idx;
                final isCurrent = currentIndex == idx;
                return _StepRow(
                  label: label,
                  isDone: isDone,
                  isCurrent: isCurrent,
                  isDark: isDark,
                  primaryColor: primaryColor,
                  successColor: successColor,
                );
              }),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _PulsingBluetoothIcon extends StatefulWidget {
  final Color primaryColor;
  const _PulsingBluetoothIcon({required this.primaryColor});

  @override
  State<_PulsingBluetoothIcon> createState() => _PulsingBluetoothIconState();
}

class _PulsingBluetoothIconState extends State<_PulsingBluetoothIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final glow = _ctrl.value;
        return Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.primaryColor.withValues(alpha: 0.08 + glow * 0.08),
            boxShadow: [
              BoxShadow(
                color: widget.primaryColor.withValues(alpha: 0.2 + glow * 0.3),
                blurRadius: 20 + glow * 20,
                spreadRadius: 2 + glow * 4,
              ),
            ],
          ),
          child: Icon(Icons.bluetooth,
              color: widget.primaryColor, size: 32),
        );
      },
    );
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final bool isDone;
  final bool isCurrent;
  final bool isDark;
  final Color primaryColor;
  final Color successColor;

  const _StepRow({
    required this.label,
    required this.isDone,
    required this.isCurrent,
    required this.isDark,
    required this.primaryColor,
    required this.successColor,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    Widget leading;

    if (isDone) {
      color = successColor;
      leading = Icon(Icons.check_circle_rounded,
              color: successColor, size: 18)
          .animate()
          .scale(
              begin: const Offset(0.4, 0.4),
              end: const Offset(1, 1),
              duration: 300.ms,
              curve: Curves.elasticOut);
    } else if (isCurrent) {
      color = primaryColor;
      leading = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
        ),
      );
    } else {
      color = isDark ? AppColors.textMuted : AppColors.lightTextMuted;
      leading = Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark ? AppColors.border : AppColors.lightBorder,
            width: 2,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: EdgeInsets.symmetric(
            horizontal: isCurrent ? 12 : 0,
            vertical: isCurrent ? 8 : 0),
        decoration: BoxDecoration(
          color: isCurrent
              ? primaryColor.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isCurrent
                ? primaryColor.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight:
                      isCurrent ? FontWeight.w700 : FontWeight.w400,
                  letterSpacing: isCurrent ? 0.5 : 0,
                ),
                child: Text(label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Radar CustomPainter
// ---------------------------------------------------------------------------

class _RadarBlip {
  final double angle;
  final double radius;
  final DateTime createdAt;
  final int ttl; // milliseconds

  const _RadarBlip({
    required this.angle,
    required this.radius,
    required this.createdAt,
    required this.ttl,
  });
}

class _BlipRenderData {
  final double angle;
  final double radius; // 0..1 (fraction of radar radius)
  final double opacity;

  const _BlipRenderData({
    required this.angle,
    required this.radius,
    required this.opacity,
  });
}

class _RadarPainter extends CustomPainter {
  final double sweepAngle;
  final List<_BlipRenderData> blips;
  final bool isActive;
  final bool isDark;
  final Color primaryColor;
  final Color successColor;

  _RadarPainter({
    required this.sweepAngle,
    required this.blips,
    required this.isActive,
    required this.isDark,
    required this.primaryColor,
    required this.successColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radarRadius = min(size.width, size.height) / 2 - 8;

    // ── 1. Clip to the radar circle ───────────────────────────────────────
    canvas.save();
    canvas.clipPath(Path()
      ..addOval(
          Rect.fromCircle(center: center, radius: radarRadius)));

    // ── 2. Tinted background ───────────────────────────────────────────
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: isDark
            ? const [
                Color(0xFF001A1F),
                Color(0xFF0B0F17),
              ]
            : const [
                Color(0xFFEFF6FF),
                Color(0xFFF8FAFC),
              ],
      ).createShader(
          Rect.fromCircle(center: center, radius: radarRadius));
    canvas.drawCircle(center, radarRadius, bgPaint);

    if (isActive) {
      // ── 3. Sweep sector ───────────────────────────────────────────────────
      const sweepWidth = pi / 4; // 45° sector
      final sectorPath = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radarRadius),
          sweepAngle - sweepWidth,
          sweepWidth,
          false,
        )
        ..close();

      final sweepPaint = Paint()
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: sweepAngle - sweepWidth,
          endAngle: sweepAngle,
          colors: [
            primaryColor.withValues(alpha: 0.0),
            primaryColor.withValues(alpha: isDark ? 0.18 : 0.22),
          ],
        ).createShader(
            Rect.fromCircle(center: center, radius: radarRadius));
      canvas.drawPath(sectorPath, sweepPaint);

      // Leading edge line
      final armPaint = Paint()
        ..color = primaryColor.withValues(alpha: isDark ? 0.70 : 0.85)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        center,
        Offset(
          center.dx + radarRadius * cos(sweepAngle),
          center.dy + radarRadius * sin(sweepAngle),
        ),
        armPaint,
      );
    }

    // ── 4. Concentric circles ───────────────────────────────────────────────
    final circlePaint = Paint()
      ..color = primaryColor.withValues(alpha: isDark ? 0.12 : 0.16)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radarRadius * i / 4, circlePaint);
    }

    // ── 5. Crosshair grid lines ─────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = primaryColor.withValues(alpha: isDark ? 0.10 : 0.14)
      ..strokeWidth = 0.7;
    canvas.drawLine(Offset(center.dx - radarRadius, center.dy),
        Offset(center.dx + radarRadius, center.dy), gridPaint);
    canvas.drawLine(Offset(center.dx, center.dy - radarRadius),
        Offset(center.dx, center.dy + radarRadius), gridPaint);
    final d = radarRadius / sqrt2;
    canvas.drawLine(Offset(center.dx - d, center.dy - d),
        Offset(center.dx + d, center.dy + d), gridPaint);
    canvas.drawLine(Offset(center.dx + d, center.dy - d),
        Offset(center.dx - d, center.dy + d), gridPaint);

    // ── 6. Blips ─────────────────────────────────────────────────────────────
    for (final blip in blips) {
      final bx = center.dx + blip.radius * radarRadius * cos(blip.angle);
      final by = center.dy + blip.radius * radarRadius * sin(blip.angle);
      final blipPaint = Paint()
        ..color =
            successColor.withValues(alpha: blip.opacity * 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(Offset(bx, by), 3.5 * blip.opacity, blipPaint);
      final corePaint = Paint()
        ..color = (isDark ? Colors.white : primaryColor).withValues(alpha: blip.opacity * 0.8);
      canvas.drawCircle(Offset(bx, by), 1.2 * blip.opacity, corePaint);
    }

    canvas.restore();

    // ── 7. Outer ring ─────────────────────────────────────────────────────
    final ringPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radarRadius, ringPaint);

    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: isDark ? 0.08 : 0.05)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, radarRadius, glowPaint);

    // ── 8. Center dot ────────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      4,
      Paint()
        ..color = primaryColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(center, 2, Paint()..color = isDark ? Colors.white : primaryColor);
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.sweepAngle != sweepAngle ||
      oldDelegate.blips.length != blips.length ||
      oldDelegate.isActive != isActive ||
      oldDelegate.isDark != isDark ||
      oldDelegate.primaryColor != primaryColor;
}

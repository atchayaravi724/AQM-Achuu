import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../providers/threshold_provider.dart';
import '../ble/ble_manager.dart';
import '../connectivity/connectivity_manager.dart';
import '../firebase/firebase_service.dart';
import '../models/sensor_data.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/hazard_modal.dart';
import 'home_shell.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Selected graph time-range filter (1, 6, 24 hours)
  int _selectedHours = 1;

  double _temp = 0.0;
  double _humidity = 0.0;
  int _airQuality = 0;
  bool _hasReceivedData = false;
  DateTime? _lastUpdated;
  bool _isRefreshing = false;

  final List<StreamSubscription> _subs = [];

  Future<void> _handleManualRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    HapticFeedback.mediumImpact();
    try {
      final appState = context.read<AppState>();
      await appState.refreshTelemetry();
      if (mounted) {
        setState(() {
          _lastUpdated = DateTime.now();
          if (appState.hasReceivedTelemetry) {
            _temp = appState.lastTemperature;
            _humidity = appState.lastHumidity;
            _airQuality = appState.lastAirQuality;
            _hasReceivedData = true;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Telemetry Refreshed • Live sensor reading synced at ${DateFormat('HH:mm:ss').format(DateTime.now())}',
              style: const TextStyle(fontFamily: AppTextStyles.fontFamily, color: Colors.white),
            ),
            backgroundColor: const Color(0xFF131A26),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  void _subscribe() {
    if (!mounted) return;
    final cm = context.read<ConnectivityManager>();
    final appState = context.read<AppState>();

    if (appState.hasReceivedTelemetry) {
      setState(() {
        _temp = appState.lastTemperature;
        _humidity = appState.lastHumidity;
        _airQuality = appState.lastAirQuality;
        _hasReceivedData = true;
        _lastUpdated = appState.latestSensorData?.timestamp ?? DateTime.now();
      });
    }

    _subs.add(cm.dataStream.listen((data) {
      if (mounted) {
        setState(() {
          _temp = data.temperature;
          _humidity = data.humidity;
          _airQuality = data.airQuality;
          _hasReceivedData = true;
          _lastUpdated = data.timestamp;
        });
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final threshold = context.watch<ThresholdProvider>();
    final ble = context.watch<BleManager>();
    final cm = context.watch<ConnectivityManager>();
    final firebase = context.watch<FirebaseService>();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.electricCyan : AppColors.lightPrimary;

    final showF = appState.showFahrenheit;
    final displayTemp = showF ? _temp * 9 / 5 + 32 : _temp;
    final tempUnit = showF ? '°F' : '°C';

    final isConnected = ble.isConnected || cm.activeMode != ConnectivityMode.none;
    final hasData = _hasReceivedData && appState.hasReceivedTelemetry;

    // Filter historical points by selected time-range
    final history = appState.getHistoryForLastHours(_selectedHours);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _handleManualRefresh,
            color: primaryColor,
            backgroundColor: isDark ? const Color(0xFF131A26) : Colors.white,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _buildAppBar(context, appState, isConnected, primaryColor, isDark),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // 1. Overall Device Status Card
                      _buildDeviceStatusBanner(ble, cm, firebase, isConnected, isDark),
                      const SizedBox(height: 16),

                    // 2. Section Title
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ENVIRONMENTAL METRICS',
                          style: AppTextStyles.themedSectionHeader(isDark).copyWith(
                            fontSize: 13,
                            letterSpacing: 1.2,
                          ),
                        ),
                        if (_lastUpdated != null)
                          Text(
                            'Updated ${DateFormat('HH:mm:ss').format(_lastUpdated!)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 3. Environmental Monitoring Cards (4 Cards)
                    _buildEnvironmentalCards(
                      temp: _temp,
                      displayTemp: displayTemp,
                      tempUnit: tempUnit,
                      humidity: _humidity,
                      airQuality: _airQuality,
                      isConnected: isConnected,
                      hasData: hasData,
                      lastUpdated: _lastUpdated,
                      threshold: threshold,
                      cm: cm,
                      isDark: isDark,
                      primaryColor: primaryColor,
                    ),
                    const SizedBox(height: 24),

                    // 4. Live Graphs Header & Time-Range Selector
                    _buildGraphsHeader(isDark, primaryColor),
                    const SizedBox(height: 14),

                    // 5. Temperature Trend Line Chart
                    _buildTrendChartCard(
                      title: 'TEMPERATURE TREND ($tempUnit)',
                      unit: tempUnit,
                      lineColor: isDark ? AppColors.electricCyan : AppColors.lightPrimary,
                      history: history,
                      getValue: (d) => showF ? d.temperature * 9 / 5 + 32 : d.temperature,
                      minY: showF ? 50 : 15,
                      maxY: showF ? 115 : 45,
                      isDark: isDark,
                      primaryColor: primaryColor,
                    ),
                    const SizedBox(height: 16),

                    // 6. Humidity Trend Line Chart
                    _buildTrendChartCard(
                      title: 'HUMIDITY TREND (%)',
                      unit: '%',
                      lineColor: isDark ? AppColors.neonEmerald : AppColors.lightSecondary,
                      history: history,
                      getValue: (d) => d.humidity,
                      minY: 0,
                      maxY: 100,
                      isDark: isDark,
                      primaryColor: primaryColor,
                    ),
                    const SizedBox(height: 16),

                    // 7. Air Quality Trend Line Chart (MQ135 Raw ADC)
                    _buildTrendChartCard(
                      title: 'AIR QUALITY (MQ135 RAW ADC)',
                      subtitle: 'Raw 12-bit ADC readings (0 – 4095). Higher values denote rising gas concentration.',
                      unit: 'ADC',
                      lineColor: AppColors.radiantAmber,
                      history: history,
                      getValue: (d) => d.airQuality.toDouble(),
                      minY: 0,
                      maxY: 4095,
                      isDark: isDark,
                      primaryColor: primaryColor,
                    ),
                    const SizedBox(height: 24),

                    // 8. Recent Alerts Summary
                    _buildAlertsSummaryCard(appState, isDark, primaryColor),
                    const SizedBox(height: 32),
                  ]),
                ),
              ),
            ],
          ),
        ),

          // Critical Hazard Modal overlay
          if (appState.hazardActive && !appState.hazardSilenced)
            HazardModal(
              temperature: _temp,
              alertType: appState.currentAlertType,
              onAcknowledge: () => appState.silenceHazard(),
            ),
        ],
      ),
    );
  }

  // ── Header App Bar ──────────────────────────────────────────────────────────

  Widget _buildAppBar(
    BuildContext context,
    AppState appState,
    bool isConnected,
    Color primaryColor,
    bool isDark,
  ) {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
            ),
            child: Icon(Icons.blur_on_rounded, color: primaryColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AERION • AEROSENSE',
                  style: TextStyle(
                    color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  'Environmental IoT Monitoring',
                  style: TextStyle(
                    color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Temperature Unit Toggle (°C / °F)
        IconButton(
          tooltip: 'Toggle °C / °F',
          icon: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              appState.showFahrenheit ? '°F' : '°C',
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            appState.toggleTemperatureUnit();
          },
        ),
        // Theme switch
        IconButton(
          tooltip: appState.isDarkMode ? 'Light Mode' : 'Dark Mode',
          icon: Icon(
            appState.isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            color: primaryColor,
            size: 20,
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            appState.toggleTheme();
          },
        ),
        // Manual Telemetry Refresh Button
        IconButton(
          tooltip: 'Refresh Telemetry',
          icon: _isRefreshing
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primaryColor,
                  ),
                )
              : Icon(
                  Icons.refresh_rounded,
                  color: primaryColor,
                  size: 22,
                ),
          onPressed: _isRefreshing ? null : _handleManualRefresh,
        ),
        // Settings Action
        IconButton(
          tooltip: 'Settings',
          icon: Icon(
            Icons.tune_rounded,
            color: primaryColor,
            size: 20,
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            HomeShell.switchTab(context, 5);
          },
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── Overall Device Status Banner ──────────────────────────────────────────

  Widget _buildDeviceStatusBanner(
    BleManager ble,
    ConnectivityManager cm,
    FirebaseService firebase,
    bool isConnected,
    bool isDark,
  ) {
    final statusColor = isConnected
        ? (isDark ? AppColors.neonEmerald : AppColors.lightSecondary)
        : AppColors.radiantAmber;

    String modeName;
    String modeDetail;
    IconData modeIcon;

    if (cm.activeMode == ConnectivityMode.firebase && firebase.isConnected) {
      modeName = 'CLOUD SYNCHRONIZED';
      modeDetail = 'Firebase RTDB (/aerosense) • Low Latency Stream';
      modeIcon = Icons.cloud_done_rounded;
    } else if (cm.activeMode == ConnectivityMode.wifi) {
      modeName = 'LOCAL WI-FI ACTIVE';
      modeDetail = 'ESP32 HTTP Polling (${cm.wifiService.espIpAddress})';
      modeIcon = Icons.wifi_rounded;
    } else if (ble.isConnected) {
      modeName = 'BLE HARDWARE CONNECTED';
      modeDetail = '${ble.connectedDeviceName ?? "AeroSense"} • 2.4GHz GATT Stream';
      modeIcon = Icons.bluetooth_connected_rounded;
    } else {
      modeName = 'DEVICE OFFLINE / STANDBY';
      modeDetail = 'No active telemetry stream • Connect via BLE or Wi-Fi';
      modeIcon = Icons.sensors_off_rounded;
    }

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Icon(modeIcon, color: statusColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          modeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    modeDetail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 4 Environmental Monitoring Cards ──────────────────────────────────────

  Widget _buildEnvironmentalCards({
    required double temp,
    required double displayTemp,
    required String tempUnit,
    required double humidity,
    required int airQuality,
    required bool isConnected,
    required bool hasData,
    required DateTime? lastUpdated,
    required ThresholdProvider threshold,
    required ConnectivityManager cm,
    required bool isDark,
    required Color primaryColor,
  }) {
    final tempStatus = threshold.getTemperatureStatus(temp);
    final humStatus = threshold.getHumidityStatus(humidity);
    final aqStatus = threshold.getAirQualityStatus(airQuality);

    final timestampStr = lastUpdated != null
        ? DateFormat('HH:mm:ss').format(lastUpdated)
        : 'Awaiting';

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'TEMPERATURE',
                value: hasData ? '${displayTemp.toStringAsFixed(1)} $tempUnit' : '--',
                icon: Icons.thermostat_rounded,
                status: hasData ? tempStatus : MetricStatus.normal,
                statusLabel: hasData ? ThresholdProvider.getStatusLabel(tempStatus) : 'STANDBY',
                statusColor: hasData
                    ? ThresholdProvider.getStatusColor(tempStatus, isDark)
                    : (isDark ? AppColors.textMuted : AppColors.lightTextMuted),
                timestamp: timestampStr,
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'HUMIDITY',
                value: hasData ? '${humidity.toStringAsFixed(1)} %' : '--',
                icon: Icons.water_drop_rounded,
                status: hasData ? humStatus : MetricStatus.normal,
                statusLabel: hasData ? ThresholdProvider.getStatusLabel(humStatus) : 'STANDBY',
                statusColor: hasData
                    ? ThresholdProvider.getStatusColor(humStatus, isDark)
                    : (isDark ? AppColors.textMuted : AppColors.lightTextMuted),
                timestamp: timestampStr,
                isDark: isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'MQ135 RAW SENSOR',
                value: hasData ? '$airQuality ADC' : '--',
                icon: Icons.air_rounded,
                status: hasData ? aqStatus : MetricStatus.normal,
                statusLabel: hasData ? ThresholdProvider.getStatusLabel(aqStatus) : 'STANDBY',
                statusColor: hasData
                    ? ThresholdProvider.getStatusColor(aqStatus, isDark)
                    : (isDark ? AppColors.textMuted : AppColors.lightTextMuted),
                timestamp: timestampStr,
                subtitle: 'Raw ADC Reading',
                isDark: isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                title: 'CONNECTION',
                value: isConnected ? cm.modeLabel : 'OFFLINE',
                icon: isConnected ? Icons.cell_tower_rounded : Icons.link_off_rounded,
                status: isConnected ? MetricStatus.normal : MetricStatus.warning,
                statusLabel: isConnected ? 'CONNECTED' : 'DISCONNECTED',
                statusColor: isConnected
                    ? (isDark ? AppColors.neonEmerald : AppColors.lightSecondary)
                    : AppColors.radiantAmber,
                timestamp: timestampStr,
                subtitle: isConnected ? 'Live Channel' : 'Standby',
                isDark: isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required MetricStatus status,
    required String statusLabel,
    required Color statusColor,
    required String timestamp,
    String? subtitle,
    required bool isDark,
  }) {
    final isAbnormal = status == MetricStatus.warning || status == MetricStatus.critical;
    final effectiveColor = isAbnormal ? AppColors.criticalRed : statusColor;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: isAbnormal
            ? Border.all(color: AppColors.criticalRed.withValues(alpha: 0.65), width: 1.5)
            : null,
      ),
      child: GlassCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Title and Icon
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.themedLabel(isDark).copyWith(
                        fontSize: 10.5,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w700,
                        color: isAbnormal ? AppColors.criticalRed : null,
                      ),
                    ),
                  ),
                  Icon(
                    isAbnormal ? Icons.warning_amber_rounded : icon,
                    color: effectiveColor,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Large Value
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: TextStyle(
                    color: isAbnormal
                        ? AppColors.criticalRed
                        : (isDark ? AppColors.textPrimary : AppColors.lightTextPrimary),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    fontFamily: AppTextStyles.fontFamily,
                  ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                    fontSize: 9.5,
                  ),
                ),
              ],
              const SizedBox(height: 8),

              // Bottom row: Status badge and Timestamp
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: effectiveColor.withValues(alpha: isAbnormal ? 0.20 : 0.12),
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: effectiveColor.withValues(alpha: isAbnormal ? 0.8 : 0.3),
                          width: isAbnormal ? 1.2 : 1.0,
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: effectiveColor,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      timestamp,
                      style: TextStyle(
                        color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                        fontSize: 9.5,
                        fontFamily: AppTextStyles.fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Live Graphs Header & Range Selector ────────────────────────────────────

  Widget _buildGraphsHeader(bool isDark, Color primaryColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(Icons.show_chart_rounded, color: primaryColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LIVE TELEMETRY GRAPHS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.themedSectionHeader(isDark).copyWith(
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Time-range pills: 1h, 6h, 24h
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardBg : AppColors.lightCardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? AppColors.border : AppColors.lightBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildRangePill(1, '1H', isDark, primaryColor),
              _buildRangePill(6, '6H', isDark, primaryColor),
              _buildRangePill(24, '24H', isDark, primaryColor),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRangePill(int hours, String label, bool isDark, Color primaryColor) {
    final isSelected = _selectedHours == hours;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedHours = hours);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: isSelected
                ? (isDark ? AppColors.background : Colors.white)
                : (isDark ? AppColors.textMuted : AppColors.lightTextMuted),
          ),
        ),
      ),
    );
  }

  // ── Generic Trend Line Chart Card ──────────────────────────────────────────

  Widget _buildTrendChartCard({
    required String title,
    String? subtitle,
    required String unit,
    required Color lineColor,
    required List<SensorData> history,
    required double Function(SensorData) getValue,
    required double minY,
    required double maxY,
    required bool isDark,
    required Color primaryColor,
  }) {
    final textMuted = isDark ? AppColors.textMuted : AppColors.lightTextMuted;
    final gridColor = isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);

    // Prepare chart spots
    final List<FlSpot> spots = [];
    if (history.isNotEmpty) {
      final baseTime = history.first.timestamp.millisecondsSinceEpoch.toDouble();
      for (int i = 0; i < history.length; i++) {
        final d = history[i];
        final val = getValue(d);
        // Normalize X to elapsed minutes from earliest data point
        final xMin = (d.timestamp.millisecondsSinceEpoch - baseTime) / 60000.0;
        spots.add(FlSpot(xMin, val));
      }
    }

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                if (history.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: lineColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${history.length} pts',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: lineColor,
                      ),
                    ),
                  ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  color: textMuted,
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Line Chart or Empty State
            if (spots.isEmpty)
              Container(
                height: 160,
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timeline_rounded, color: textMuted, size: 36),
                    const SizedBox(height: 8),
                    Text(
                      'Awaiting live readings...',
                      style: TextStyle(color: textMuted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Connect via BLE, Wi-Fi, or Firebase to plot real-time trend',
                      style: TextStyle(color: textMuted.withValues(alpha: 0.7), fontSize: 10),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                height: 180,
                child: LineChart(
                  LineChartData(
                    lineTouchData: LineTouchData(
                      handleBuiltInTouches: true,
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => isDark ? const Color(0xFF1E293B) : Colors.white,
                        tooltipRoundedRadius: 8,
                        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        getTooltipItems: (touchedSpots) {
                          return touchedSpots.map((spot) {
                            final idx = spot.spotIndex;
                            String timeLabel = '';
                            if (idx >= 0 && idx < history.length) {
                              timeLabel = DateFormat('HH:mm:ss').format(history[idx].timestamp);
                            }
                            return LineTooltipItem(
                              '$timeLabel\n${spot.y.toStringAsFixed(1)} $unit',
                              TextStyle(
                                color: lineColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            );
                          }).toList();
                        },
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: (maxY - minY) / 4 > 0 ? (maxY - minY) / 4 : 10,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: gridColor,
                        strokeWidth: 0.8,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 38,
                          getTitlesWidget: (val, _) {
                            return Text(
                              val.toInt().toString(),
                              style: TextStyle(
                                color: textMuted,
                                fontSize: 9.5,
                                fontFamily: AppTextStyles.fontFamily,
                              ),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: spots.last.x > 0 ? spots.last.x / 3 : 1,
                          getTitlesWidget: (val, _) {
                            // Find closest data point to display time
                            final closest = history.isNotEmpty
                                ? history[(val / (spots.last.x > 0 ? spots.last.x : 1) * (history.length - 1))
                                    .clamp(0, history.length - 1)
                                    .toInt()]
                                : null;
                            if (closest == null) return const SizedBox.shrink();
                            return Text(
                              DateFormat('HH:mm').format(closest.timestamp),
                              style: TextStyle(
                                color: textMuted,
                                fontSize: 9.5,
                                fontFamily: AppTextStyles.fontFamily,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    minY: minY,
                    maxY: maxY,
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        isCurved: true,
                        curveSmoothness: 0.25,
                        color: lineColor,
                        barWidth: 2.5,
                        isStrokeCapRound: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: lineColor.withValues(alpha: 0.10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Recent Alerts Summary Card ─────────────────────────────────────────────

  Widget _buildAlertsSummaryCard(AppState appState, bool isDark, Color primaryColor) {
    final recentIncidents = appState.incidents.take(3).toList();
    final emerald = isDark ? AppColors.neonEmerald : AppColors.lightSecondary;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: primaryColor, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'RECENT ALERTS SUMMARY',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    HomeShell.switchTab(context, 4);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'VIEW ALL (${appState.totalIncidentsCount})',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10.5,
                      color: primaryColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recentIncidents.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline_rounded, color: emerald, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'All environmental parameters nominal. No active hazards detected.',
                        style: TextStyle(
                          color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: recentIncidents.map((inc) {
                  const alertColor = AppColors.criticalRed;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: alertColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: alertColor.withValues(alpha: 0.5), width: 1.2),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: alertColor,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${inc.title}: ${inc.readingString}',
                            style: TextStyle(
                              color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: alertColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: alertColor.withValues(alpha: 0.6)),
                          ),
                          child: Text(
                            inc.severityLabel,
                            style: TextStyle(
                              color: alertColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 9,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('HH:mm').format(inc.startTime),
                          style: TextStyle(
                            color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                            fontSize: 10.5,
                            fontFamily: AppTextStyles.fontFamily,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

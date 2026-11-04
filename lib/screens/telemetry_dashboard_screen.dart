import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../ble/ble_manager.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';
import '../widgets/dual_arc_gauge.dart';
import '../widgets/rssi_bars.dart';
import '../widgets/neon_glow_border.dart';
import '../widgets/hazard_modal.dart';
import 'audit_report_screen.dart';
import 'ble_scanner_screen.dart';

class TelemetryDashboardScreen extends StatefulWidget {
  const TelemetryDashboardScreen({super.key});

  @override
  State<TelemetryDashboardScreen> createState() =>
      _TelemetryDashboardScreenState();
}

class _TelemetryDashboardScreenState extends State<TelemetryDashboardScreen>
    with TickerProviderStateMixin {
  bool _showCelsius = true;
  late AnimationController _pulseController;
  late AnimationController _reconnectSpinController;
  final List<FlSpot> _tempHistory = [];
  int _xCounter = 0;
  static const int _maxPoints = 60;
  DateTime _lastPacketTime = DateTime.now();
  double _currentTemp = 0.0;
  double _currentHumidity = 0.0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _reconnectSpinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Listen to BLE streams after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble = context.read<BleManager>();
      ble.temperatureStream.listen((t) {
        if (!mounted) return;
        setState(() {
          _currentTemp = t;
          _lastPacketTime = DateTime.now();
          _tempHistory.add(FlSpot(_xCounter.toDouble(), t));
          _xCounter++;
          if (_tempHistory.length > _maxPoints) _tempHistory.removeAt(0);
        });
      });
      ble.humidityStream.listen((h) {
        if (!mounted) return;
        setState(() => _currentHumidity = h);
      });
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _reconnectSpinController.dispose();
    super.dispose();
  }

  Color _tempColor(double temp) {
    if (temp < 30) return AppColors.electricCyan;
    if (temp <= 35) return Colors.amber;
    return Colors.redAccent;
  }

  double _toDisplay(double celsius) =>
      _showCelsius ? celsius : celsius * 9 / 5 + 32;

  String _formatLastPacket() {
    final diff = DateTime.now().difference(_lastPacketTime);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }

  void _showDisconnectSheet(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      builder: (_) => _DisconnectSheet(
        onConfirm: () {
          Navigator.of(ctx).pop();
          context.read<BleManager>().disconnect();
          Navigator.of(ctx).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const BleScannerScreen()),
            (_) => false,
          );
        },
        onCancel: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bleManager = context.watch<BleManager>();
    final isReconnecting =
        bleManager.connectionStep == ConnectionStep.reconnecting;

    return Consumer<AppState>(
      builder: (context, appState, _) {
        final showHazard = appState.hazardActive && !appState.hazardSilenced;

        Widget scaffold = Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                if (isReconnecting) _buildReconnectBanner(),
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _buildHeader(context, bleManager),
                            const SizedBox(height: 16),
                            _buildHeroGauge(),
                            const SizedBox(height: 12),
                            _buildFilterCard(),
                            const SizedBox(height: 12),
                            _buildSamplingCard(context, appState),
                            const SizedBox(height: 12),
                            _buildChartCard(),
                            const SizedBox(height: 12),
                            _buildStatusBar(),
                            const SizedBox(height: 24),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

        if (showHazard) {
          return NeonGlowBorder(
            isActive: true,
            color: Colors.redAccent,
            borderRadius: 0,
            child: Stack(
              children: [
                scaffold,
                HazardModal(temperature: _currentTemp),
              ],
            ),
          );
        }

        return scaffold;
      },
    );
  }

  Widget _buildReconnectBanner() {
    return Container(
      width: double.infinity,
      color: Colors.amber.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          RotationTransition(
            turns: _reconnectSpinController,
            child: const Icon(Icons.sync, color: Colors.amber, size: 18),
          ),
          const SizedBox(width: 8),
          const Text(
            '⚡ HARDWARE RECONNECTING...',
            style: TextStyle(
              fontFamily: 'monospace',
              color: Colors.amber,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _buildHeader(BuildContext context, BleManager bleManager) {
    final rssi = bleManager.lastRssi;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: AppColors.electricCyan.withOpacity(0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (_, __) => Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                      Colors.green.shade300,
                      Colors.green,
                      _pulseController.value,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green
                            .withOpacity(0.4 + 0.4 * _pulseController.value),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                bleManager.connectedDeviceName ?? 'AQM Device',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RssiBars(rssi: rssi),
              const SizedBox(width: 6),
              Text(
                '$rssi dBm',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        IconButton(
          icon:
              const Icon(Icons.assessment_outlined, color: Colors.white54),
          tooltip: 'Audit Report',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AuditReportScreen()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.link_off, color: Colors.redAccent),
          tooltip: 'Disconnect',
          onPressed: () => _showDisconnectSheet(context),
        ),
      ],
    );
  }

  Widget _buildHeroGauge() {
    final color = _tempColor(_currentTemp);
    final display = _toDisplay(_currentTemp);
    final unit = _showCelsius ? '°C' : '°F';

    return Column(
      children: [
        SizedBox(
          height: 260,
          child: DualArcGauge(
            temperature: _currentTemp,
            humidity: _currentHumidity,
            tempColor: color,
            isCelsius: _showCelsius,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TempUnitChip(
              label: '°C',
              selected: _showCelsius,
              onTap: () => setState(() => _showCelsius = true),
            ),
            const SizedBox(width: 8),
            _TempUnitChip(
              label: '°F',
              selected: !_showCelsius,
              onTap: () => setState(() => _showCelsius = false),
            ),
            const SizedBox(width: 16),
            Text(
              '${display.toStringAsFixed(1)}$unit',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterCard() {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          '⚡ HARDWARE MOVING AVG FILTER: ACTIVE (LAST 5 SAMPLES SMOOTHED)',
          style: const TextStyle(
            fontFamily: 'monospace',
            color: AppColors.electricCyan,
            fontSize: 11,
            letterSpacing: 0.8,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildSamplingCard(BuildContext context, AppState appState) {
    final intervals = [1, 2, 5, 10];
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SAMPLING INTERVAL',
              style: TextStyle(
                fontFamily: 'monospace',
                color: Colors.white54,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: intervals.map((n) {
                final selected = appState.samplingIntervalSeconds == n;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: GestureDetector(
                      onTap: () {
                        appState.setSamplingInterval(n);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              '✓ Interval Updated on Hardware',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: AppColors.electricCyan,
                              ),
                            ),
                            backgroundColor: AppColors.cardBg,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding:
                            const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.electricCyan.withOpacity(0.12)
                              : Colors.white.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? AppColors.electricCyan
                                : Colors.white24,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          '${n}s',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: selected
                                ? AppColors.electricCyan
                                : Colors.white38,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard() {
    final spots = _tempHistory.isEmpty
        ? [const FlSpot(0, 25)]
        : List.generate(
            _tempHistory.length,
            (i) => FlSpot(i.toDouble(), _tempHistory[i].y),
          );

    final minX = spots.first.x;
    final maxX = spots.last.x;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'LIVE TEMPERATURE TRACE',
              style: TextStyle(
                fontFamily: 'monospace',
                color: Colors.white54,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  backgroundColor: Colors.transparent,
                  minY: 15,
                  maxY: 50,
                  minX: minX,
                  maxX: maxX,
                  clipData: const FlClipData.all(),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 5,
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: Colors.white10,
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 10,
                        reservedSize: 32,
                        getTitlesWidget: (value, _) => Text(
                          '${value.toInt()}°',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 30,
                        color: Colors.amber.withOpacity(0.6),
                        strokeWidth: 1,
                        dashArray: [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          labelResolver: (_) => '30°C',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 9,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      HorizontalLine(
                        y: 35,
                        color: Colors.redAccent.withOpacity(0.7),
                        strokeWidth: 1,
                        dashArray: [6, 4],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          labelResolver: (_) => '35°C',
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 9,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: AppColors.electricCyan,
                      barWidth: 2,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.electricCyan.withOpacity(0.18),
                            AppColors.electricCyan.withOpacity(0.0),
                          ],
                        ),
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

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          _StatusDot(color: Colors.green, label: 'BLE CONNECTED'),
          const SizedBox(width: 16),
          _StatusDot(
              color: AppColors.electricCyan, label: 'GATT STREAMS: ACTIVE'),
          const Spacer(),
          Text(
            _formatLastPacket(),
            style: const TextStyle(
              fontFamily: 'monospace',
              color: Colors.white38,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _TempUnitChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TempUnitChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.electricCyan.withOpacity(0.15)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                selected ? AppColors.electricCyan : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            color: selected ? AppColors.electricCyan : Colors.white38,
            fontWeight:
                selected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)
            ],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'monospace',
            color: Colors.white54,
            fontSize: 10,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _DisconnectSheet extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _DisconnectSheet({
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
        border: const Border(
          top: BorderSide(color: Colors.white12),
          left: BorderSide(color: Colors.white12),
          right: BorderSide(color: Colors.white12),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Icon(Icons.link_off, color: Colors.redAccent, size: 40),
          const SizedBox(height: 12),
          const Text(
            'Disconnect Device?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'BLE session will be terminated. Live telemetry stream will stop.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'DISCONNECT',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().slideY(
          begin: 0.3,
          end: 0,
          duration: 300.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

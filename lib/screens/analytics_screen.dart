import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../providers/threshold_provider.dart';
import '../models/sensor_data.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  // Time range selection: 24 Hours (Daily) or 168 Hours (Weekly)
  int _selectedHours = 24;

  // Active touched slice index for each chart to support interactive tooltips
  int _touchedStatusIndex = -1;
  int _touchedTempIndex = -1;
  int _touchedHumIndex = -1;
  int _touchedAqIndex = -1;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final threshold = context.watch<ThresholdProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.electricCyan : AppColors.lightPrimary;

    // Use actual recorded historical data (never mock/fabricated)
    final history = appState.getHistoryForLastHours(_selectedHours);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'ENVIRONMENTAL ANALYTICS',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: primaryColor,
            fontWeight: FontWeight.w800,
            fontSize: 17,
            letterSpacing: 1.5,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        actions: [
          // Range selection pills: Daily / Weekly
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
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
                  _buildRangeButton(24, 'DAILY (24H)', isDark, primaryColor),
                  _buildRangeButton(168, 'WEEKLY (7D)', isDark, primaryColor),
                ],
              ),
            ),
          ),
        ],
      ),
      body: history.isEmpty
          ? _buildEmptyState(isDark)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 80),
              children: [
                // 1. Sensor Data Summary Section (8 Essential Metrics)
                _buildSummarySection(history, isDark, primaryColor),
                const SizedBox(height: 20),

                // 2. Chart A: Overall Environmental Status Distribution
                _buildStatusDistributionPie(history, threshold, isDark),
                const SizedBox(height: 16),

                // 3. Chart B: Temperature Distribution Pie
                _buildTemperatureDistributionPie(history, threshold, isDark),
                const SizedBox(height: 16),

                // 4. Chart C: Humidity Distribution Pie
                _buildHumidityDistributionPie(history, threshold, isDark),
                const SizedBox(height: 16),

                // 5. Chart D: Air Quality Distribution Pie (MQ135 Raw ADC)
                _buildAirQualityDistributionPie(history, threshold, isDark),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildRangeButton(int hours, String label, bool isDark, Color primaryColor) {
    final isSelected = _selectedHours == hours;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _selectedHours = hours;
          _touchedStatusIndex = -1;
          _touchedTempIndex = -1;
          _touchedHumIndex = -1;
          _touchedAqIndex = -1;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: isSelected
                ? (isDark ? AppColors.background : Colors.white)
                : (isDark ? AppColors.textMuted : AppColors.lightTextMuted),
          ),
        ),
      ),
    );
  }

  // ── Sensor Data Summary (8 Metrics) ───────────────────────────────────────

  Widget _buildSummarySection(List<SensorData> history, bool isDark, Color primaryColor) {
    final temps = history.map((d) => d.temperature).toList();
    final hums = history.map((d) => d.humidity).toList();
    final aqs = history.map((d) => d.airQuality).toList();

    final avgTemp = temps.reduce((a, b) => a + b) / temps.length;
    final maxTemp = temps.reduce((a, b) => a > b ? a : b);
    final minTemp = temps.reduce((a, b) => a < b ? a : b);

    final avgHum = hums.reduce((a, b) => a + b) / hums.length;
    final maxHum = hums.reduce((a, b) => a > b ? a : b);
    final minHum = hums.reduce((a, b) => a < b ? a : b);

    final avgAq = aqs.reduce((a, b) => a + b) / aqs.length;
    final totalSamples = history.length;

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
                      Icon(Icons.query_stats_rounded, color: primaryColor, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'SENSOR DATA SUMMARY',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.themedSectionHeader(isDark).copyWith(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$totalSamples Samples',
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // 4 rows of 2 metrics
            Row(
              children: [
                Expanded(child: _summaryTile('AVG TEMPERATURE', '${avgTemp.toStringAsFixed(1)}°C', primaryColor, isDark)),
                const SizedBox(width: 10),
                Expanded(child: _summaryTile('MAX TEMPERATURE', '${maxTemp.toStringAsFixed(1)}°C', AppColors.crimsonNeon, isDark)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _summaryTile('MIN TEMPERATURE', '${minTemp.toStringAsFixed(1)}°C', emerald, isDark)),
                const SizedBox(width: 10),
                Expanded(child: _summaryTile('AVG HUMIDITY', '${avgHum.toStringAsFixed(1)}%', emerald, isDark)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _summaryTile('MAX HUMIDITY', '${maxHum.toStringAsFixed(1)}%', primaryColor, isDark)),
                const SizedBox(width: 10),
                Expanded(child: _summaryTile('MIN HUMIDITY', '${minHum.toStringAsFixed(1)}%', AppColors.radiantAmber, isDark)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _summaryTile('AVG MQ135 RAW', '${avgAq.toInt()} ADC', AppColors.radiantAmber, isDark)),
                const SizedBox(width: 10),
                Expanded(child: _summaryTile('TOTAL RECORDED', '$totalSamples Pts', isDark ? AppColors.textPrimary : AppColors.lightTextPrimary, isDark)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryTile(String label, String value, Color accentColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131924) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Pie Chart A: Environmental Status Distribution ─────────────────────────

  Widget _buildStatusDistributionPie(List<SensorData> history, ThresholdProvider threshold, bool isDark) {
    int normalCount = 0;
    int warningCount = 0;
    int criticalCount = 0;

    for (final d in history) {
      final tStat = threshold.getTemperatureStatus(d.temperature);
      final hStat = threshold.getHumidityStatus(d.humidity);
      final aStat = threshold.getAirQualityStatus(d.airQuality);

      if (tStat == MetricStatus.critical || hStat == MetricStatus.critical || aStat == MetricStatus.critical) {
        criticalCount++;
      } else if (tStat == MetricStatus.warning || hStat == MetricStatus.warning || aStat == MetricStatus.warning) {
        warningCount++;
      } else {
        normalCount++;
      }
    }

    final total = history.length;
    final normalPct = total > 0 ? (normalCount / total * 100) : 0.0;
    final warningPct = total > 0 ? (warningCount / total * 100) : 0.0;
    final criticalPct = total > 0 ? (criticalCount / total * 100) : 0.0;

    final emerald = isDark ? AppColors.neonEmerald : AppColors.lightSecondary;
    const amber = AppColors.radiantAmber;
    const crimson = AppColors.crimsonNeon;

    final items = [
      _PieSegment(label: 'Normal', count: normalCount, percentage: normalPct, color: emerald),
      _PieSegment(label: 'Warning', count: warningCount, percentage: warningPct, color: amber),
      _PieSegment(label: 'Critical', count: criticalCount, percentage: criticalPct, color: crimson),
    ];

    return _buildPieChartCard(
      title: 'ENVIRONMENTAL STATUS DISTRIBUTION',
      subtitle: 'Ratio of overall sensor readings within Normal, Warning, and Critical thresholds',
      items: items,
      touchedIndex: _touchedStatusIndex,
      onTouch: (idx) => setState(() => _touchedStatusIndex = idx),
      isDark: isDark,
    );
  }

  // ── Pie Chart B: Temperature Distribution ──────────────────────────────────

  Widget _buildTemperatureDistributionPie(List<SensorData> history, ThresholdProvider threshold, bool isDark) {
    int coolCount = 0;
    int normalCount = 0;
    int warmCount = 0;
    int criticalCount = 0;

    final normalMax = threshold.tempNormalMax;
    final warningMax = threshold.tempWarningMax;

    for (final d in history) {
      final t = d.temperature;
      if (t < 22.0) {
        coolCount++;
      } else if (t < normalMax) {
        normalCount++;
      } else if (t <= warningMax) {
        warmCount++;
      } else {
        criticalCount++;
      }
    }

    final total = history.length;
    final emerald = isDark ? AppColors.neonEmerald : AppColors.lightSecondary;
    final cyan = isDark ? AppColors.electricCyan : AppColors.lightPrimary;

    final items = [
      _PieSegment(label: 'Cool (<22°C)', count: coolCount, percentage: total > 0 ? coolCount / total * 100 : 0, color: cyan),
      _PieSegment(label: 'Normal (22–${normalMax.toInt()}°C)', count: normalCount, percentage: total > 0 ? normalCount / total * 100 : 0, color: emerald),
      _PieSegment(label: 'Warm (${normalMax.toInt()}–${warningMax.toInt()}°C)', count: warmCount, percentage: total > 0 ? warmCount / total * 100 : 0, color: AppColors.radiantAmber),
      _PieSegment(label: 'Critical (>${warningMax.toInt()}°C)', count: criticalCount, percentage: total > 0 ? criticalCount / total * 100 : 0, color: AppColors.crimsonNeon),
    ];

    return _buildPieChartCard(
      title: 'TEMPERATURE DISTRIBUTION',
      subtitle: 'Historical temperature occurrences grouped by thermal comfort and safety thresholds',
      items: items,
      touchedIndex: _touchedTempIndex,
      onTouch: (idx) => setState(() => _touchedTempIndex = idx),
      isDark: isDark,
    );
  }

  // ── Pie Chart C: Humidity Distribution ────────────────────────────────────

  Widget _buildHumidityDistributionPie(List<SensorData> history, ThresholdProvider threshold, bool isDark) {
    int dryCount = 0;
    int comfortableCount = 0;
    int humidCount = 0;
    int excessiveCount = 0;

    final humMin = threshold.humidityNormalMin;
    final humMax = threshold.humidityNormalMax;

    for (final d in history) {
      final h = d.humidity;
      if (h < threshold.humidityMin) {
        dryCount++;
      } else if (h <= humMax && h >= humMin) {
        comfortableCount++;
      } else if (h <= threshold.humidityMax) {
        humidCount++;
      } else {
        excessiveCount++;
      }
    }

    final total = history.length;
    final emerald = isDark ? AppColors.neonEmerald : AppColors.lightSecondary;
    final cyan = isDark ? AppColors.electricCyan : AppColors.lightPrimary;

    final items = [
      _PieSegment(label: 'Dry (<${threshold.humidityMin.toInt()}%)', count: dryCount, percentage: total > 0 ? dryCount / total * 100 : 0, color: AppColors.radiantAmber),
      _PieSegment(label: 'Optimal (${humMin.toInt()}–${humMax.toInt()}%)', count: comfortableCount, percentage: total > 0 ? comfortableCount / total * 100 : 0, color: emerald),
      _PieSegment(label: 'Humid (${humMax.toInt()}–${threshold.humidityMax.toInt()}%)', count: humidCount, percentage: total > 0 ? humidCount / total * 100 : 0, color: cyan),
      _PieSegment(label: 'Excessive (>${threshold.humidityMax.toInt()}%)', count: excessiveCount, percentage: total > 0 ? excessiveCount / total * 100 : 0, color: AppColors.crimsonNeon),
    ];

    return _buildPieChartCard(
      title: 'HUMIDITY DISTRIBUTION',
      subtitle: 'Relative humidity levels categorised across dry, optimal, and high ranges',
      items: items,
      touchedIndex: _touchedHumIndex,
      onTouch: (idx) => setState(() => _touchedHumIndex = idx),
      isDark: isDark,
    );
  }

  // ── Pie Chart D: Air Quality Distribution (MQ135 Raw ADC) ─────────────────

  Widget _buildAirQualityDistributionPie(List<SensorData> history, ThresholdProvider threshold, bool isDark) {
    int normalCount = 0;
    int moderateCount = 0;
    int elevatedCount = 0;
    int criticalCount = 0;

    final normalMax = threshold.aqNormalMax;
    final warningMax = threshold.aqWarningMax;

    for (final d in history) {
      final aq = d.airQuality;
      if (aq < 1000) {
        normalCount++;
      } else if (aq < normalMax) {
        moderateCount++;
      } else if (aq <= warningMax) {
        elevatedCount++;
      } else {
        criticalCount++;
      }
    }

    final total = history.length;
    final emerald = isDark ? AppColors.neonEmerald : AppColors.lightSecondary;
    final cyan = isDark ? AppColors.electricCyan : AppColors.lightPrimary;

    final items = [
      _PieSegment(label: 'Baseline (<1000 ADC)', count: normalCount, percentage: total > 0 ? normalCount / total * 100 : 0, color: emerald),
      _PieSegment(label: 'Normal (1000–$normalMax ADC)', count: moderateCount, percentage: total > 0 ? moderateCount / total * 100 : 0, color: cyan),
      _PieSegment(label: 'Elevated ($normalMax–$warningMax ADC)', count: elevatedCount, percentage: total > 0 ? elevatedCount / total * 100 : 0, color: AppColors.radiantAmber),
      _PieSegment(label: 'Critical (>$warningMax ADC)', count: criticalCount, percentage: total > 0 ? criticalCount / total * 100 : 0, color: AppColors.crimsonNeon),
    ];

    return _buildPieChartCard(
      title: 'AIR QUALITY DISTRIBUTION (MQ135 RAW ADC)',
      subtitle: 'Raw uncalibrated 12-bit ADC readings grouped by ambient air contamination ranges',
      items: items,
      touchedIndex: _touchedAqIndex,
      onTouch: (idx) => setState(() => _touchedAqIndex = idx),
      isDark: isDark,
    );
  }

  // ── Generic Pie Chart Card with Interactive Slices & Legends ──────────────

  Widget _buildPieChartCard({
    required String title,
    required String subtitle,
    required List<_PieSegment> items,
    required int touchedIndex,
    required ValueChanged<int> onTouch,
    required bool isDark,
  }) {
    // Filter segments that have > 0 readings for plotting
    final activeSegments = items.where((i) => i.count > 0).toList();

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                fontSize: 10,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),

            if (activeSegments.isEmpty)
              Container(
                height: 150,
                alignment: Alignment.center,
                child: Text(
                  'No readings in this range',
                  style: TextStyle(
                    color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                    fontSize: 11,
                  ),
                ),
              )
            else
              Row(
                children: [
                  // Pie Chart
                  SizedBox(
                    height: 135,
                    width: 135,
                    child: PieChart(
                      PieChartData(
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            if (!event.isInterestedForInteractions ||
                                response == null ||
                                response.touchedSection == null) {
                              onTouch(-1);
                              return;
                            }
                            onTouch(response.touchedSection!.touchedSectionIndex);
                          },
                        ),
                        borderData: FlBorderData(show: false),
                        sectionsSpace: 2,
                        centerSpaceRadius: 30,
                        sections: List.generate(activeSegments.length, (i) {
                          final seg = activeSegments[i];
                          final isTouched = i == touchedIndex;
                          final radius = isTouched ? 38.0 : 32.0;

                          return PieChartSectionData(
                            color: seg.color,
                            value: seg.percentage,
                            title: isTouched ? '${seg.percentage.toStringAsFixed(0)}%' : '',
                            radius: radius,
                            titleStyle: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Legends with percentages
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: items.map((seg) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: seg.color,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  seg.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                '${seg.percentage.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── Empty State ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(bool isDark) {
    final mutedColor = isDark ? AppColors.textMuted : AppColors.lightTextMuted;
    final secondaryColor = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pie_chart_outline_rounded, color: mutedColor, size: 64),
            const SizedBox(height: 16),
            Text(
              'Awaiting Telemetry Data',
              style: AppTextStyles.labelLarge.copyWith(color: secondaryColor, fontSize: 17),
            ),
            const SizedBox(height: 8),
            Text(
              'Connect via BLE, Wi-Fi, or Firebase to log genuine sensor history and view environmental distribution curves.',
              style: AppTextStyles.caption.copyWith(color: mutedColor, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PieSegment {
  final String label;
  final int count;
  final double percentage;
  final Color color;

  const _PieSegment({
    required this.label,
    required this.count,
    required this.percentage,
    required this.color,
  });
}

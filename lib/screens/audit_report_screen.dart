import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/incident_record.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class AuditReportScreen extends StatefulWidget {
  const AuditReportScreen({super.key});

  @override
  State<AuditReportScreen> createState() => _AuditReportScreenState();
}

class _AuditReportScreenState extends State<AuditReportScreen> {
  bool _isExporting = false;
  String _activeFilter = 'ALL'; // 'ALL', 'UNREAD', 'CRITICAL', 'WARNING'

  String _formatTimestamp(DateTime dt) =>
      DateFormat('MMM dd, yyyy • HH:mm:ss').format(dt);

  Future<void> _exportCsv(AppState appState) async {
    setState(() => _isExporting = true);
    HapticFeedback.lightImpact();
    try {
      final incidents = appState.incidents;
      final history = appState.sensorHistory;

      final List<List<dynamic>> rows = [
        ['--- AERION AeroSense Environmental Telemetry & Incident Audit Report ---'],
        ['Generated At', DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())],
        ['Total Incidents Recorded', incidents.length],
        ['Total Telemetry Samples', history.length],
        [],
        ['=== SECTION 1: ENVIRONMENTAL ALERTS AUDIT LOG ==='],
        [
          'Incident ID',
          'Alert Title',
          'Sensor Name',
          'Severity',
          'Sensor Reading',
          'Start Time',
          'End Time',
          'Duration (s)',
          'Status',
          'Acknowledged At'
        ],
        ...incidents.map((i) => [
              i.id,
              i.title,
              i.sensorName,
              i.severityLabel,
              i.readingString,
              i.startTime.toIso8601String(),
              i.endTime?.toIso8601String() ?? 'ACTIVE',
              i.duration.inSeconds,
              i.acknowledged ? 'READ' : 'UNREAD',
              i.acknowledgedAt?.toIso8601String() ?? 'N/A',
            ]),
        [],
        ['=== SECTION 2: RAW SENSOR TELEMETRY LOGS ==='],
        ['Timestamp', 'Temperature (°C)', 'Humidity (%)', 'Air Quality (MQ135 ADC)', 'Source'],
        ...history.map((d) => [
              d.timestamp.toIso8601String(),
              d.temperature.toStringAsFixed(2),
              d.humidity.toStringAsFixed(2),
              d.airQuality,
              d.source.name,
            ]),
      ];
      final csvData = const ListToCsvConverter().convert(rows);
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'aerosense_report_${DateTime.now().millisecondsSinceEpoch}.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csvData);

      // Attempt to copy to standard Android public Download directory
      String savedPath = file.path;
      try {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          final publicFile = File('${downloadDir.path}/$fileName');
          await publicFile.writeAsString(csvData);
          savedPath = publicFile.path;
        }
      } catch (_) {}

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'AERION AeroSense Sensor Telemetry & Alerts Report',
        text: 'AERION AeroSense Incident & Environmental Alerts Audit Log',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Report exported! Saved to: $savedPath',
              style: const TextStyle(fontFamily: AppTextStyles.fontFamily, color: Colors.white),
            ),
            backgroundColor: AppColors.successGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Export failed: $e',
              style: const TextStyle(fontFamily: AppTextStyles.fontFamily, color: Colors.white),
            ),
            backgroundColor: AppColors.criticalRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final allIncidents = appState.incidents;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.electricCyan : AppColors.lightPrimary;

    // Apply filter
    final filteredIncidents = allIncidents.where((i) {
      switch (_activeFilter) {
        case 'UNREAD':
          return !i.acknowledged;
        case 'CRITICAL':
          return i.severity == AlertSeverity.critical;
        case 'WARNING':
          return i.severity == AlertSeverity.warning;
        case 'ALL':
        default:
          return true;
      }
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'ENVIRONMENTAL ALERTS',
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
          if (appState.unreadIncidentsCount > 0)
            TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                appState.markAllIncidentsRead();
              },
              icon: const Icon(Icons.done_all_rounded, size: 16),
              label: const Text(
                'MARK ALL READ',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
              ),
            ),
          IconButton(
            tooltip: 'Refresh Alerts',
            icon: Icon(Icons.refresh_rounded, color: primaryColor, size: 20),
            onPressed: () async {
              HapticFeedback.lightImpact();
              await appState.refreshTelemetry();
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Export CSV Report',
            icon: _isExporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.ios_share_rounded, color: primaryColor, size: 20),
            onPressed: _isExporting ? null : () => _exportCsv(appState),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 1. Summary Statistics Row
          _buildSummaryCards(appState, isDark, primaryColor),

          // 2. Filter Pills
          _buildFilterChips(allIncidents, appState.unreadIncidentsCount, isDark, primaryColor),

          // 3. Alerts Timeline List
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                HapticFeedback.lightImpact();
                await appState.refreshTelemetry();
                if (mounted) setState(() {});
              },
              child: filteredIncidents.isEmpty
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: 350,
                        child: _buildEmptyState(isDark),
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      itemCount: filteredIncidents.length,
                      itemBuilder: (context, index) {
                        final incident = filteredIncidents[index];
                        return _buildAlertCard(context, appState, incident, isDark);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(AppState appState, bool isDark, Color primaryColor) {
    final cyanColor = isDark ? AppColors.electricCyan : AppColors.lightPrimary;
    final maxPeak = appState.maxRecordedTemperature;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: _summaryTile(
              label: 'TOTAL ALERTS',
              value: '${appState.totalIncidentsCount}',
              valueColor: cyanColor,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _summaryTile(
              label: 'UNREAD ALERTS',
              value: '${appState.unreadIncidentsCount}',
              valueColor: appState.unreadIncidentsCount > 0 ? AppColors.radiantAmber : cyanColor,
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _summaryTile(
              label: 'MAX TEMP PEAK',
              value: maxPeak > 0 ? '${maxPeak.toStringAsFixed(1)}°C' : '--',
              valueColor: maxPeak >= 35.0 ? AppColors.crimsonNeon : AppColors.radiantAmber,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile({
    required String label,
    required String value,
    required Color valueColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardBg : AppColors.lightCardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? AppColors.border : AppColors.lightBorder,
          width: 1,
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
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(
    List<IncidentRecord> all,
    int unreadCount,
    bool isDark,
    Color primaryColor,
  ) {
    final criticalCount = all.where((i) => i.severity == AlertSeverity.critical).length;
    final warningCount = all.where((i) => i.severity == AlertSeverity.warning).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _filterChip('ALL', 'All (${all.length})', isDark, primaryColor),
          const SizedBox(width: 8),
          _filterChip('UNREAD', 'Unread ($unreadCount)', isDark, primaryColor),
          const SizedBox(width: 8),
          _filterChip('CRITICAL', 'Critical ($criticalCount)', isDark, AppColors.crimsonNeon),
          const SizedBox(width: 8),
          _filterChip('WARNING', 'Warning ($warningCount)', isDark, AppColors.radiantAmber),
        ],
      ),
    );
  }

  Widget _filterChip(String filterKey, String label, bool isDark, Color accentColor) {
    final isSelected = _activeFilter == filterKey;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _activeFilter = filterKey);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.15)
              : (isDark ? AppColors.cardBg : AppColors.lightCardBg),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? accentColor : (isDark ? AppColors.border : AppColors.lightBorder),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? accentColor
                : (isDark ? AppColors.textSecondary : AppColors.lightTextSecondary),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertCard(
    BuildContext context,
    AppState appState,
    IncidentRecord incident,
    bool isDark,
  ) {
    final isAcked = incident.acknowledged;

    Color severityColor;
    IconData severityIcon;
    switch (incident.severity) {
      case AlertSeverity.critical:
        severityColor = AppColors.criticalRed;
        severityIcon = Icons.error_outline_rounded;
        break;
      case AlertSeverity.warning:
        severityColor = AppColors.criticalRed; // Vivid Red for Warning as requested
        severityIcon = Icons.warning_amber_rounded;
        break;
      case AlertSeverity.normal:
        severityColor = isDark ? AppColors.neonEmerald : AppColors.lightSecondary;
        severityIcon = Icons.check_circle_outline_rounded;
        break;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            appState.acknowledgeIncident(incident.id);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Severity color border stripe
                  Container(
                    width: 5,
                    color: severityColor,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header: Alert Title, Severity Badge & Read/Unread Status
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  incident.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Severity Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: severityColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: severityColor.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(severityIcon, color: severityColor, size: 12),
                                    const SizedBox(width: 4),
                                    Text(
                                      incident.severityLabel,
                                      style: TextStyle(
                                        fontFamily: AppTextStyles.fontFamily,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: severityColor,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Read / Unread status badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isAcked
                                      ? (isDark ? AppColors.border : AppColors.lightBorder)
                                      : (isDark ? AppColors.electricCyan : AppColors.lightPrimary).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isAcked ? 'READ' : 'UNREAD',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: isAcked
                                        ? (isDark ? AppColors.textMuted : AppColors.lightTextMuted)
                                        : (isDark ? AppColors.electricCyan : AppColors.lightPrimary),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Sensor name and Actual reading row
                          Row(
                            children: [
                              Icon(
                                Icons.sensors_rounded,
                                size: 15,
                                color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  incident.sensorName,
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 11.5,
                                    color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                incident.readingString,
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: severityColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Timestamp and Duration / Ongoing Status
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_rounded,
                                size: 12,
                                color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _formatTimestamp(incident.startTime),
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 10.5,
                                  color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                                ),
                              ),
                              const Spacer(),
                              if (incident.isActive)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.crimsonNeon.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'ACTIVE HAZARD',
                                    style: TextStyle(
                                      fontFamily: AppTextStyles.fontFamily,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.crimsonNeon,
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  'Duration: ${incident.durationLabel}',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 10.5,
                                    color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final emerald = isDark ? AppColors.neonEmerald : AppColors.lightSecondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: emerald.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: emerald.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.shield_outlined, color: emerald, size: 48),
            ),
            const SizedBox(height: 18),
            Text(
              'No Environmental Alerts Detected',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'All monitored sensor parameters (Temperature, Humidity, Air Quality) are currently operating within safe configured thresholds.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

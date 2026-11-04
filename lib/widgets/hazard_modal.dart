import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../screens/home_shell.dart';
import '../models/incident_record.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HazardModal
// Premium Emergency Thermal Hazard Overlay Widget (> 35.0°C)
// ─────────────────────────────────────────────────────────────────────────────

class HazardModal extends StatefulWidget {
  final double temperature;
  final AlertType alertType;
  final VoidCallback? onAcknowledge;

  const HazardModal({
    super.key,
    required this.temperature,
    this.alertType = AlertType.temperature,
    this.onAcknowledge,
  });

  @override
  State<HazardModal> createState() => _HazardModalState();
}

class _HazardModalState extends State<HazardModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  Timer? _hapticTimer;
  Timer? _durationTimer;
  Duration _elapsedBreachDuration = Duration.zero;
  DateTime? _alertStartTime;

  bool _isAcknowledging = false;

  @override
  void initState() {
    super.initState();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _startPeriodicHaptic();

    final appState = context.read<AppState>();
    _alertStartTime = appState.activeIncident?.startTime ?? DateTime.now();

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _alertStartTime != null) {
        setState(() {
          _elapsedBreachDuration = DateTime.now().difference(_alertStartTime!);
        });
      }
    });
  }

  void _startPeriodicHaptic() {
    _triggerHapticAlert();
    _hapticTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        _triggerHapticAlert();
      }
    });
  }

  void _triggerHapticAlert() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  @override
  void dispose() {
    _hapticTimer?.cancel();
    _durationTimer?.cancel();
    _glowController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds < 60) {
      return '${d.inSeconds}s';
    } else if (d.inMinutes < 60) {
      final s = d.inSeconds % 60;
      return '${d.inMinutes}m ${s.toString().padLeft(2, '0')}s';
    } else {
      final m = d.inMinutes % 60;
      return '${d.inHours}h ${m.toString().padLeft(2, '0')}m';
    }
  }

  Future<void> _onSilenceAndAcknowledge(BuildContext context) async {
    final appState = context.read<AppState>();
    setState(() => _isAcknowledging = true);
    _hapticTimer?.cancel();
    HapticFeedback.mediumImpact();

    if (widget.onAcknowledge != null) {
      widget.onAcknowledge!();
    } else {
      appState.acknowledgeHazard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final startTimeStr = _alertStartTime != null
        ? DateFormat('HH:mm:ss').format(_alertStartTime!)
        : '--:--:--';
    final durationStr = _formatDuration(_elapsedBreachDuration);

    return Material(
      color: Colors.black87,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: AnimatedBuilder(
            animation: _glowAnimation,
            builder: (context, child) {
              final glow = _glowAnimation.value;
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.crimsonNeon.withValues(alpha: 0.45 * glow),
                      blurRadius: 32 * glow,
                      spreadRadius: 3 * glow,
                    ),
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.20 * glow),
                      blurRadius: 70,
                      spreadRadius: 16,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF140808),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.crimsonNeon,
                  width: 2.0,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  _buildLiveTemperatureCard(),
                  const SizedBox(height: 14),
                  _buildTimeAndDurationRow(startTimeStr, durationStr),
                  const SizedBox(height: 16),
                  _buildWarningMessage(),
                  const SizedBox(height: 22),
                  _buildAcknowledgeButton(context),
                  const SizedBox(height: 12),
                  _buildAuditReportButton(context),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).scale(
          begin: const Offset(0.92, 0.92),
          end: const Offset(1, 1),
          duration: 300.ms,
          curve: Curves.easeOutBack,
        );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        AnimatedBuilder(
          animation: _glowAnimation,
          builder: (_, __) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.crimsonNeon.withValues(alpha: 0.18 * _glowAnimation.value),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.crimsonNeon,
              size: 42,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'CRITICAL THERMAL HAZARD',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: AppColors.crimsonNeon,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'DHT22 TEMPERATURE EXCEEDS CRITICAL THRESHOLD',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  Widget _buildLiveTemperatureCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.crimsonNeon.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.crimsonNeon.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        children: [
          Text(
            'CURRENT TEMPERATURE',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              color: AppColors.crimsonNeon,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                widget.temperature.toStringAsFixed(1),
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: Colors.white,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '°C',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: AppColors.crimsonNeon,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.crimsonNeon.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'SAFETY LIMIT: 35.0°C',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                color: AppColors.crimsonNeon,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeAndDurationRow(String startTimeStr, String durationStr) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ALERT START TIME',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: Colors.white60,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  startTimeStr,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.radiantAmber.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BREACH DURATION',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: AppColors.radiantAmber,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  durationStr,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: AppColors.radiantAmber,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWarningMessage() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.white70, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Immediate cooling or ventilation required. Silencing stops audible/haptic alerts; continuous thermal monitoring remains active until temperature drops below safety limit.',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                color: Colors.white70,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcknowledgeButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.volume_off_rounded, size: 18),
        label: Text(
          _isAcknowledging ? 'ACKNOWLEDGED...' : 'SILENCE & ACKNOWLEDGE',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.crimsonNeon,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: _isAcknowledging ? null : () => _onSilenceAndAcknowledge(context),
      ),
    );
  }

  Widget _buildAuditReportButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.notifications_active_outlined, size: 16),
        label: Text(
          'VIEW ALL ENVIRONMENTAL ALERTS',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: () {
          _onSilenceAndAcknowledge(context);
          HomeShell.switchTab(context, 4);
        },
      ),
    );
  }
}

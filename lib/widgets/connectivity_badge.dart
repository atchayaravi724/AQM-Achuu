import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../connectivity/connectivity_manager.dart';
import '../ble/ble_manager.dart';
import '../firebase/firebase_service.dart';
import '../wifi/wifi_sensor_service.dart';
import '../theme/app_theme.dart';

/// Compact 3-channel status row: Firebase | Wi-Fi | BLE
class ConnectivityBadge extends StatelessWidget {
  const ConnectivityBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final cm = context.watch<ConnectivityManager>();
    final ble = context.watch<BleManager>();
    final firebase = context.watch<FirebaseService>();
    final wifi = context.watch<WiFiSensorService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardBg : AppColors.lightCardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppColors.border : AppColors.lightBorder),
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x060F172A),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                )
              ],
      ),
      child: Row(
        children: [
          _ChannelDot(
            label: 'FIREBASE',
            icon: Icons.local_fire_department_rounded,
            isActive: firebase.isConnected,
            activeColor: isDark ? AppColors.neonEmerald : AppColors.lightSecondary,
            isDark: isDark,
          ),
          const SizedBox(width: 4),
          _Divider(isDark: isDark),
          const SizedBox(width: 4),
          _ChannelDot(
            label: 'WI-FI',
            icon: Icons.wifi_rounded,
            isActive: wifi.isConnected,
            activeColor: isDark ? AppColors.electricCyan : AppColors.lightPrimary,
            isDark: isDark,
          ),
          const SizedBox(width: 4),
          _Divider(isDark: isDark),
          const SizedBox(width: 4),
          _ChannelDot(
            label: 'BLE',
            icon: Icons.bluetooth_rounded,
            isActive: ble.connectionStep == ConnectionStep.connected,
            activeColor: AppColors.radiantAmber,
            isDark: isDark,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _modeColor(cm.activeMode, isDark).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _modeColor(cm.activeMode, isDark)),
            ),
            child: Text(
              cm.modeLabel,
              style: TextStyle(
                color: _modeColor(cm.activeMode, isDark),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _modeColor(ConnectivityMode mode, bool isDark) {
    switch (mode) {
      case ConnectivityMode.firebase:
        return isDark ? AppColors.neonEmerald : AppColors.lightSecondary;
      case ConnectivityMode.wifi:
        return isDark ? AppColors.electricCyan : AppColors.lightPrimary;
      case ConnectivityMode.ble:
        return AppColors.radiantAmber;
      case ConnectivityMode.none:
        return isDark ? AppColors.textMuted : AppColors.lightTextMuted;
    }
  }
}

class _ChannelDot extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color activeColor;
  final bool isDark;

  const _ChannelDot({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.activeColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveColor = isDark ? AppColors.textMuted : AppColors.lightTextMuted;
    final color = isActive ? activeColor : inactiveColor;
    return Row(
      children: [
        Icon(icon, color: color, size: 14)
            .animate(target: isActive ? 1 : 0)
            .fadeIn(duration: 300.ms),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  final bool isDark;
  const _Divider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 14,
      color: isDark ? AppColors.border : AppColors.lightBorder,
    );
  }
}

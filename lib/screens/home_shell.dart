import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import 'dashboard_screen.dart';
import 'ble_scanner_screen.dart';
import 'wifi_monitor_screen.dart';
import 'analytics_screen.dart';
import 'audit_report_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Allows any descendant screen to switch the active tab in HomeShell.
  /// Navigation order:
  /// 0: Dashboard
  /// 1: BLE
  /// 2: Wi-Fi
  /// 3: Analytics
  /// 4: Alerts
  /// 5: Settings
  static void switchTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_HomeShellState>();
    state?.setTab(index);
  }

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  void setTab(int index) {
    if (index >= 0 && index < _screens.length) {
      setState(() => _currentIndex = index);
    }
  }

  // Exact requested navigation order: Dashboard → BLE → Wi-Fi → Analytics → Alerts → Settings
  static const List<_TabItem> _tabs = [
    _TabItem(icon: Icons.dashboard_rounded,     label: 'Dashboard'),
    _TabItem(icon: Icons.bluetooth_rounded,     label: 'BLE'),
    _TabItem(icon: Icons.wifi_rounded,          label: 'Wi-Fi'),
    _TabItem(icon: Icons.bar_chart_rounded,     label: 'Analytics'),
    _TabItem(icon: Icons.notifications_rounded, label: 'Alerts'),
    _TabItem(icon: Icons.settings_rounded,      label: 'Settings'),
  ];

  final List<Widget> _screens = const [
    DashboardScreen(),     // 0: Dashboard
    BleScannerScreen(),    // 1: BLE
    WiFiMonitorScreen(),   // 2: Wi-Fi
    AnalyticsScreen(),     // 3: Analytics
    AuditReportScreen(),   // 4: Alerts
    SettingsScreen(),      // 5: Settings
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildNavBar(theme, isDark),
    );
  }

  Widget _buildNavBar(ThemeData theme, bool isDark) {
    final navBg = isDark ? AppColors.cardBg : AppColors.lightCardBg;
    final navBorder = isDark ? AppColors.border : AppColors.lightBorder;

    return Container(
      decoration: BoxDecoration(
        color: navBg,
        border: Border(
          top: BorderSide(color: navBorder, width: 1),
        ),
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: Color(0x080F172A),
                  blurRadius: 10,
                  offset: Offset(0, -3),
                ),
              ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 66,
          child: Row(
            children: List.generate(_tabs.length, (i) => _buildNavItem(i, isDark)),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, bool isDark) {
    final tab = _tabs[index];
    final isSelected = index == _currentIndex;
    final selectedColor = isDark ? AppColors.electricCyan : AppColors.lightPrimary;
    final unselectedColor = isDark ? AppColors.textMuted : AppColors.lightTextMuted;
    final color = isSelected ? selectedColor : unselectedColor;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _currentIndex = index);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isSelected ? selectedColor.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(color: selectedColor.withValues(alpha: 0.28), width: 1)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(tab.icon, color: color, size: 20)
                  .animate(target: isSelected ? 1 : 0)
                  .scaleXY(end: 1.12, duration: 150.ms),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  tab.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 10,
                    color: color,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final IconData icon;
  final String label;
  const _TabItem({required this.icon, required this.label});
}

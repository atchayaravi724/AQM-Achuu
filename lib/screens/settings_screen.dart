import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../providers/threshold_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Threshold Controllers
  final _tempNormalController = TextEditingController();
  final _tempWarningController = TextEditingController();

  final _humMinController = TextEditingController();
  final _humNormalMinController = TextEditingController();
  final _humNormalMaxController = TextEditingController();
  final _humMaxController = TextEditingController();

  final _aqNormalController = TextEditingController();
  final _aqWarningController = TextEditingController();

  final _intervalController = TextEditingController();
  String? _intervalError;

  bool _initialized = false;
  String? _validationError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final t = context.read<ThresholdProvider>();
      _syncControllersWithProvider(t);
      final appState = context.read<AppState>();
      _intervalController.text = appState.samplingIntervalSeconds.toString();
      _initialized = true;
    }
  }

  void _syncControllersWithProvider(ThresholdProvider t) {
    _tempNormalController.text = t.tempNormalMax.toStringAsFixed(1);
    _tempWarningController.text = t.tempWarningMax.toStringAsFixed(1);

    _humMinController.text = t.humidityMin.toStringAsFixed(0);
    _humNormalMinController.text = t.humidityNormalMin.toStringAsFixed(0);
    _humNormalMaxController.text = t.humidityNormalMax.toStringAsFixed(0);
    _humMaxController.text = t.humidityMax.toStringAsFixed(0);

    _aqNormalController.text = t.aqNormalMax.toString();
    _aqWarningController.text = t.aqWarningMax.toString();
  }

  @override
  void dispose() {
    _tempNormalController.dispose();
    _tempWarningController.dispose();
    _humMinController.dispose();
    _humNormalMinController.dispose();
    _humNormalMaxController.dispose();
    _humMaxController.dispose();
    _aqNormalController.dispose();
    _aqWarningController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _saveThresholds(ThresholdProvider threshold) async {
    final tempNormal = double.tryParse(_tempNormalController.text);
    final tempWarning = double.tryParse(_tempWarningController.text);

    final humMin = double.tryParse(_humMinController.text);
    final humNormalMin = double.tryParse(_humNormalMinController.text);
    final humNormalMax = double.tryParse(_humNormalMaxController.text);
    final humMax = double.tryParse(_humMaxController.text);

    final aqNormal = int.tryParse(_aqNormalController.text);
    final aqWarning = int.tryParse(_aqWarningController.text);

    if (tempNormal == null || tempWarning == null ||
        humMin == null || humNormalMin == null || humNormalMax == null || humMax == null ||
        aqNormal == null || aqWarning == null) {
      setState(() => _validationError = 'Please ensure all threshold inputs are valid numbers.');
      return;
    }

    final error = ThresholdProvider.validateThresholds(
      tempNormalMax: tempNormal,
      tempWarningMax: tempWarning,
      humMin: humMin,
      humNormalMin: humNormalMin,
      humNormalMax: humNormalMax,
      humMax: humMax,
      aqNormalMax: aqNormal,
      aqWarningMax: aqWarning,
    );

    if (error != null) {
      setState(() => _validationError = error);
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() => _validationError = null);
    await threshold.updateThresholds(
      tempNormalMax: tempNormal,
      tempWarningMax: tempWarning,
      humMin: humMin,
      humNormalMin: humNormalMin,
      humNormalMax: humNormalMax,
      humMax: humMax,
      aqNormalMax: aqNormal,
      aqWarningMax: aqWarning,
    );

    HapticFeedback.lightImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Environmental thresholds saved and applied immediately.',
            style: TextStyle(fontFamily: AppTextStyles.fontFamily),
          ),
          backgroundColor: AppColors.neonEmerald,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _restoreDefaults(ThresholdProvider threshold) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Restore Default Settings',
          style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Reset all environmental alert thresholds to standard factory defaults?\n\n'
          '• Temperature: Normal <30.0°C, Critical >35.0°C\n'
          '• Humidity: Safe 20%–85%, Normal 30%–70%\n'
          '• MQ-135 Gas: Normal <1500 ADC, Critical >2500 ADC',
          style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(fontFamily: AppTextStyles.fontFamily)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.electricCyan),
            child: const Text('RESTORE', style: TextStyle(fontFamily: AppTextStyles.fontFamily, color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await threshold.resetToDefaults();
      _syncControllersWithProvider(threshold);
      setState(() => _validationError = null);
      HapticFeedback.mediumImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'All thresholds restored to factory defaults.',
              style: TextStyle(fontFamily: AppTextStyles.fontFamily),
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final threshold = context.watch<ThresholdProvider>();
    final appState = context.watch<AppState>();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.electricCyan : AppColors.lightPrimary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'SETTINGS & THRESHOLDS',
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
        iconTheme: IconThemeData(
          color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Section A: Appearance & Theme (Light, Dark, System Default)
          _buildSectionHeader('APPEARANCE & THEME', isDark),
          const SizedBox(height: 8),
          _buildAppearanceCard(context, appState, isDark, primaryColor),
          const SizedBox(height: 20),

          // Section B: Environmental Alert Thresholds
          _buildSectionHeader('ENVIRONMENTAL ALERT THRESHOLDS', isDark),
          const SizedBox(height: 8),
          _buildThresholdsCard(threshold, isDark, primaryColor),
          const SizedBox(height: 20),

          // Section C: Alert Preferences
          _buildSectionHeader('ALERT NOTIFICATION PREFERENCES', isDark),
          const SizedBox(height: 8),
          _buildAlertPreferencesCard(threshold, isDark, primaryColor),
          const SizedBox(height: 20),

          // Section D: Units & Sampling
          _buildSectionHeader('UNITS & SAMPLING RATE', isDark),
          const SizedBox(height: 8),
          _buildUnitsCard(appState, isDark, primaryColor),
          const SizedBox(height: 20),

          // Section E: Application Information
          _buildSectionHeader('APPLICATION INFORMATION', isDark),
          const SizedBox(height: 8),
          _buildAppInfoCard(isDark, primaryColor),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
        ),
      ),
    );
  }

  // ── Section A: Appearance Card ─────────────────────────────────────────────

  Widget _buildAppearanceCard(
    BuildContext context,
    AppState appState,
    bool isDark,
    Color primaryColor,
  ) {
    final activeTheme = appState.themeMode;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            _buildThemeOption(
              title: 'Executive Porcelain Light',
              subtitle: 'Clean executive porcelain aesthetic with high contrast',
              icon: Icons.light_mode_rounded,
              isSelected: activeTheme == ThemeMode.light,
              isDark: isDark,
              accentColor: AppColors.lightPrimary,
              onTap: () => appState.setThemeMode(ThemeMode.light),
            ),
            const Divider(height: 1),
            _buildThemeOption(
              title: 'Stealth Midnight Cyber',
              subtitle: 'Stealth midnight cyber canvas with neon cyan highlights',
              icon: Icons.dark_mode_rounded,
              isSelected: activeTheme == ThemeMode.dark,
              isDark: isDark,
              accentColor: AppColors.electricCyan,
              onTap: () => appState.setThemeMode(ThemeMode.dark),
            ),
            const Divider(height: 1),
            _buildThemeOption(
              title: 'System Default',
              subtitle: 'Automatically follow device system theme settings',
              icon: Icons.brightness_auto_rounded,
              isSelected: activeTheme == ThemeMode.system,
              isDark: isDark,
              accentColor: primaryColor,
              onTap: () => appState.setThemeMode(ThemeMode.system),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? accentColor.withValues(alpha: 0.15) : (isDark ? AppColors.background : AppColors.lightBackground),
                border: Border.all(
                  color: isSelected ? accentColor : (isDark ? AppColors.border : AppColors.lightBorder),
                ),
              ),
              child: Icon(icon, color: isSelected ? accentColor : (isDark ? AppColors.textMuted : AppColors.lightTextMuted), size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: accentColor, size: 20)
            else
              Icon(Icons.radio_button_unchecked_rounded, color: isDark ? AppColors.border : AppColors.lightBorder, size: 20),
          ],
        ),
      ),
    );
  }

  // ── Section B: Environmental Thresholds Card ───────────────────────────────

  Widget _buildThresholdsCard(ThresholdProvider threshold, bool isDark, Color primaryColor) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Temperature Sub-section
            _subHeader('TEMPERATURE THRESHOLDS (°C)', Icons.thermostat_rounded, primaryColor, isDark),
            const SizedBox(height: 4),
            Text(
              'Below normal is Normal • Between is Warning • Above is Critical',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 10,
                color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _thresholdField(
                    label: 'Normal Limit (<)',
                    controller: _tempNormalController,
                    suffix: '°C',
                    hint: '30.0',
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _thresholdField(
                    label: 'Critical Threshold (>)',
                    controller: _tempWarningController,
                    suffix: '°C',
                    hint: '35.0',
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Humidity Sub-section (2x2 Grid for compact viewports)
            _subHeader('HUMIDITY THRESHOLDS (%)', Icons.water_drop_rounded, isDark ? AppColors.neonEmerald : AppColors.lightSecondary, isDark),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _thresholdField(
                    label: 'Min Safe (%)',
                    controller: _humMinController,
                    suffix: '%',
                    hint: '20',
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _thresholdField(
                    label: 'Normal Min (%)',
                    controller: _humNormalMinController,
                    suffix: '%',
                    hint: '30',
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _thresholdField(
                    label: 'Normal Max (%)',
                    controller: _humNormalMaxController,
                    suffix: '%',
                    hint: '70',
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _thresholdField(
                    label: 'Max Safe (%)',
                    controller: _humMaxController,
                    suffix: '%',
                    hint: '85',
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Air Quality Sub-section (MQ-135 Raw ADC)
            _subHeader('AIR QUALITY (MQ135 RAW ADC)', Icons.air_rounded, AppColors.radiantAmber, isDark),
            const SizedBox(height: 4),
            Text(
              'Configures raw 12-bit ADC thresholds (0 – 4095). Not calibrated AQI or ppm.',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 10,
                color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _thresholdField(
                    label: 'Normal Max ADC',
                    controller: _aqNormalController,
                    suffix: 'ADC',
                    hint: '1500',
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _thresholdField(
                    label: 'Critical Threshold (>)',
                    controller: _aqWarningController,
                    suffix: 'ADC',
                    hint: '2500',
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Validation Error if any
            if (_validationError != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.crimsonNeon.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.crimsonNeon.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.crimsonNeon, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _validationError!,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          color: AppColors.crimsonNeon,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Save and Restore Buttons
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: () => _saveThresholds(threshold),
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'SAVE THRESHOLDS',
                        style: TextStyle(fontFamily: AppTextStyles.fontFamily, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: isDark ? AppColors.background : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    onPressed: () => _restoreDefaults(threshold),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: isDark ? AppColors.border : AppColors.lightBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'RESTORE DEFAULTS',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _subHeader(String title, IconData icon, Color color, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 11.5,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _thresholdField({
    required String label,
    required TextEditingController controller,
    required String suffix,
    required String hint,
    required bool isDark,
  }) {
    final cardBg = isDark ? const Color(0xFF131924) : const Color(0xFFF1F5F9);
    final border = isDark ? AppColors.border : AppColors.lightBorder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 10,
            color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
            fontWeight: FontWeight.w800,
          ),
          decoration: InputDecoration(
            hintText: hint,
            suffixText: suffix,
            suffixStyle: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 11,
              color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
            ),
            filled: true,
            fillColor: cardBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: isDark ? AppColors.electricCyan : AppColors.lightPrimary),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      ],
    );
  }

  // ── Section C: Alert Preferences Card ──────────────────────────────────────

  Widget _buildAlertPreferencesCard(
    ThresholdProvider threshold,
    bool isDark,
    Color primaryColor,
  ) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _preferenceSwitch(
              title: 'Temperature Alerts',
              subtitle: 'Trigger notifications when thermal bounds are breached',
              value: threshold.enableTempAlerts,
              icon: Icons.thermostat_rounded,
              isDark: isDark,
              primaryColor: primaryColor,
              onChanged: (v) => threshold.setEnableTempAlerts(v),
            ),
            const Divider(height: 1),
            _preferenceSwitch(
              title: 'Humidity Alerts',
              subtitle: 'Trigger notifications when humidity deviates from safe zone',
              value: threshold.enableHumidityAlerts,
              icon: Icons.water_drop_rounded,
              isDark: isDark,
              primaryColor: primaryColor,
              onChanged: (v) => threshold.setEnableHumidityAlerts(v),
            ),
            const Divider(height: 1),
            _preferenceSwitch(
              title: 'Air Quality (MQ135) Alerts',
              subtitle: 'Trigger notifications when gas raw ADC exceeds critical limit',
              value: threshold.enableAirQualityAlerts,
              icon: Icons.air_rounded,
              isDark: isDark,
              primaryColor: primaryColor,
              onChanged: (v) => threshold.setEnableAirQualityAlerts(v),
            ),
            const Divider(height: 1),
            _preferenceSwitch(
              title: 'Sound Notifications',
              subtitle: 'Audible alarm on critical environmental breaches',
              value: threshold.enableSound,
              icon: Icons.volume_up_rounded,
              isDark: isDark,
              primaryColor: primaryColor,
              onChanged: (v) => threshold.setEnableSound(v),
            ),
            const Divider(height: 1),
            _preferenceSwitch(
              title: 'Vibration Haptic Feedback',
              subtitle: 'Haptic pulse alerts on critical incident triggers',
              value: threshold.enableVibration,
              icon: Icons.vibration_rounded,
              isDark: isDark,
              primaryColor: primaryColor,
              onChanged: (v) => threshold.setEnableVibration(v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preferenceSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required IconData icon,
    required bool isDark,
    required Color primaryColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: value ? primaryColor : (isDark ? AppColors.textMuted : AppColors.lightTextMuted), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeColor: primaryColor,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  // ── Section D: Units & Sampling Rate ───────────────────────────────────────

  Widget _buildUnitsCard(AppState appState, bool isDark, Color primaryColor) {
    final currentSec = appState.samplingIntervalSeconds;
    final cardBg = isDark ? const Color(0xFF131A26) : const Color(0xFFF1F5F9);
    final borderCol = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Temperature Scale
            Row(
              children: [
                Icon(Icons.straighten_rounded, color: primaryColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Temperature Scale',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        appState.showFahrenheit ? 'Fahrenheit (°F)' : 'Celsius (°C)',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('°C', style: TextStyle(fontFamily: AppTextStyles.fontFamily))),
                    ButtonSegment(value: true, label: Text('°F', style: TextStyle(fontFamily: AppTextStyles.fontFamily))),
                  ],
                  selected: {appState.showFahrenheit},
                  onSelectionChanged: (set) {
                    HapticFeedback.selectionClick();
                    appState.toggleTemperatureUnit();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Telemetry Sampling Header & Current Active Pill
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.speed_rounded, color: primaryColor, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Telemetry Sampling Rate',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: primaryColor.withValues(alpha: 0.5), width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, size: 12, color: primaryColor),
                      const SizedBox(width: 4),
                      Text(
                        '${currentSec}s Active',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          color: primaryColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'How frequently ESP32 streams sensor updates to the app & cloud.',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 14),

            // Quick Preset Selection (Highly visible chips)
            Text(
              'QUICK PRESETS',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildIntervalPresetChip(1, '1s Fast', currentSec, isDark, primaryColor, appState),
                _buildIntervalPresetChip(2, '2s Normal', currentSec, isDark, primaryColor, appState),
                _buildIntervalPresetChip(5, '5s Eco', currentSec, isDark, primaryColor, appState),
                _buildIntervalPresetChip(10, '10s Battery', currentSec, isDark, primaryColor, appState),
              ],
            ),
            const SizedBox(height: 16),

            // Manual Interval Entry
            Text(
              'MANUAL CUSTOM INTERVAL',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Type any custom interval between 1 and 60 seconds:',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 10.5,
                color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _intervalController,
                    keyboardType: TextInputType.number,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: cardBg,
                      hintText: 'e.g. 3',
                      hintStyle: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: isDark ? AppColors.textMuted : AppColors.lightTextMuted,
                        fontSize: 12,
                      ),
                      suffixText: 'sec',
                      suffixStyle: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: primaryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderCol),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: borderCol, width: 1.2),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: primaryColor, width: 1.8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () => _applyManualInterval(appState),
                  icon: const Icon(Icons.check_rounded, size: 16, color: Colors.black),
                  label: const Text(
                    'SET',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 2,
                  ),
                ),
              ],
            ),
            if (_intervalError != null) ...[
              const SizedBox(height: 6),
              Text(
                _intervalError!,
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: AppColors.criticalRed,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIntervalPresetChip(
    int seconds,
    String label,
    int activeSeconds,
    bool isDark,
    Color primaryColor,
    AppState appState,
  ) {
    final isSelected = seconds == activeSeconds;
    final selectedBg = primaryColor;
    final unselectedBg = isDark ? const Color(0xFF162032) : const Color(0xFFE2E8F0);
    const selectedText = Colors.black;
    final unselectedText = isDark ? Colors.white : const Color(0xFF1E293B);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        HapticFeedback.selectionClick();
        appState.setSamplingInterval(seconds);
        _intervalController.text = seconds.toString();
        setState(() => _intervalError = null);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : unselectedBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? selectedBg : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_circle_rounded, size: 14, color: Colors.black),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                color: isSelected ? selectedText : unselectedText,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _applyManualInterval(AppState appState) {
    final text = _intervalController.text.trim();
    final parsed = int.tryParse(text);

    if (parsed == null || parsed < 1 || parsed > 60) {
      setState(() => _intervalError = 'Please enter a valid interval between 1 and 60 seconds.');
      HapticFeedback.heavyImpact();
      return;
    }

    setState(() => _intervalError = null);
    appState.setSamplingInterval(parsed);
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Telemetry sampling interval set to ${parsed}s.',
          style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.electricCyan.withValues(alpha: 0.9),
      ),
    );
  }

  // ── Section E: Application Information ─────────────────────────────────────

  Widget _buildAppInfoCard(bool isDark, Color primaryColor) {
    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.blur_on_rounded, color: primaryColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AERION – AeroSense',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        'Version 2.0.0 (Build 2)',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(
              'About AERION',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'AERION AeroSense is an enterprise-grade IoT environmental monitoring architecture. '
              'It continuously captures ambient temperature, relative humidity, and air quality telemetry via ESP32 BLE GATT and Firebase Realtime Database synchronizers, ensuring instant hazard detection without simulated data.',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 11,
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

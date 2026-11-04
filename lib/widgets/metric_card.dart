import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'glass_card.dart';

/// Reusable metric display tile used across Dashboard and WiFi Monitor screens.
class MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final Color? valueColor;
  final IconData? icon;
  final Widget? trailing;

  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.valueColor,
    this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedValueColor = valueColor ?? (isDark ? AppColors.textPrimary : AppColors.lightTextPrimary);
    final secondaryColor = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;
    final mutedColor = isDark ? AppColors.textMuted : AppColors.lightTextMuted;

    return GlassCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: mutedColor, size: 14),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: AppTextStyles.themedLabel(isDark),
                ),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: AppTextStyles.monoValue.copyWith(
                    color: resolvedValueColor,
                    fontSize: 28,
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      unit!,
                      style: AppTextStyles.metricUnit.copyWith(
                        color: secondaryColor,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

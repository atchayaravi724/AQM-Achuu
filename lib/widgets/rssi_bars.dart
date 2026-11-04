import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Displays RSSI signal strength as animated vertical bars with dBm label.
///
/// Bar fill logic:
///   rssi > -60  → 4 bars (green)
///   rssi > -70  → 3 bars (green)
///   rssi > -80  → 2 bars (amber)
///   rssi ≤ -80  → 1 bar  (red)
class RssiBars extends StatelessWidget {
  final int rssi;

  const RssiBars({super.key, required this.rssi});

  int get _filledBars {
    if (rssi > -60) return 4;
    if (rssi > -70) return 3;
    if (rssi > -80) return 2;
    return 1;
  }

  Color get _barColor {
    if (rssi > -70) return AppColors.neonEmerald;
    if (rssi > -80) return AppColors.radiantAmber;
    return AppColors.crimsonNeon;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filled = _filledBars;
    final color = _barColor;
    final emptyColor = isDark
        ? AppColors.textMuted.withValues(alpha: 0.3)
        : AppColors.lightBorder;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Bar group
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(4, (index) {
            final barIndex = index + 1; // 1-based
            final isFilled = barIndex <= filled;
            // Each successive bar is taller: 8, 12, 16, 20 px
            final targetHeight = 4.0 + (barIndex * 4.0);
            final targetColor = isFilled ? color : emptyColor;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOut,
                width: 5,
                height: targetHeight,
                decoration: BoxDecoration(
                  color: targetColor,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: isFilled
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: isDark ? 0.45 : 0.25),
                            blurRadius: 4,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 5),
        // dBm label
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 350),
          style: AppTextStyles.metricSmall.copyWith(
            color: _barColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
          child: Text('$rssi dBm'),
        ),
      ],
    );
  }
}

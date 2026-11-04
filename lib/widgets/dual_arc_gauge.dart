import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Public widget
// ---------------------------------------------------------------------------

/// A dual concentric arc gauge that displays temperature (outer arc) and
/// humidity (inner arc) with smooth implicit animations and threshold indicators.
class DualArcGauge extends StatefulWidget {
  final double temperature;
  final double humidity;
  final double maxTemp;
  final double maxHumidity;
  final bool isCelsius;
  final bool hasData;
  final Color? tempColor;
  final Color? humidityColor;
  final double size;
  final VoidCallback? onToggleUnit;

  const DualArcGauge({
    super.key,
    required this.temperature,
    required this.humidity,
    this.maxTemp = 50.0,
    this.maxHumidity = 100.0,
    this.isCelsius = true,
    this.hasData = true,
    this.tempColor,
    this.humidityColor,
    this.size = 280.0,
    this.onToggleUnit,
  });

  /// Computes temperature status color based on thresholds:
  /// Blue: Normal (< 30°C)
  /// Amber: Warning (30°C – 35°C)
  /// Crimson: Critical (> 35°C)
  static Color getTemperatureColor(double tempInCelsius, {bool isDark = true}) {
    if (tempInCelsius < 30.0) {
      return isDark ? AppColors.electricCyan : AppColors.lightPrimary;
    } else if (tempInCelsius <= 35.0) {
      return AppColors.radiantAmber;
    } else {
      return AppColors.crimsonNeon;
    }
  }

  /// Computes qualitative threshold label for temperature
  static String getThresholdLabel(double tempInCelsius) {
    if (tempInCelsius < 30.0) return 'NORMAL (<30°C)';
    if (tempInCelsius <= 35.0) return 'WARNING (30–35°C)';
    return 'CRITICAL (>35°C)';
  }

  @override
  State<DualArcGauge> createState() => _DualArcGaugeState();
}

class _DualArcGaugeState extends State<DualArcGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _tempAnim;
  late Animation<double> _humidityAnim;

  double _prevTemp = 0;
  double _prevHumidity = 0;

  @override
  void initState() {
    super.initState();
    _prevTemp = widget.hasData ? widget.temperature : 0.0;
    _prevHumidity = widget.hasData ? widget.humidity : 0.0;

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _tempAnim = Tween<double>(begin: _prevTemp, end: _prevTemp)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _humidityAnim =
        Tween<double>(begin: _prevHumidity, end: _prevHumidity).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(DualArcGauge oldWidget) {
    super.didUpdateWidget(oldWidget);

    bool needsAnimate = false;
    final targetTemp = widget.hasData ? widget.temperature : 0.0;
    final targetHum = widget.hasData ? widget.humidity : 0.0;

    if (oldWidget.temperature != widget.temperature || oldWidget.hasData != widget.hasData) {
      _prevTemp = _tempAnim.value;
      _tempAnim = Tween<double>(begin: _prevTemp, end: targetTemp)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
      needsAnimate = true;
    }

    if (oldWidget.humidity != widget.humidity || oldWidget.hasData != widget.hasData) {
      _prevHumidity = _humidityAnim.value;
      _humidityAnim = Tween<double>(begin: _prevHumidity, end: targetHum)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
      needsAnimate = true;
    }

    if (needsAnimate) {
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final animTemp = _tempAnim.value;
        final animHumidity = _humidityAnim.value;

        // Resolve temperature in Celsius for threshold color logic
        final tempInCelsius = widget.isCelsius
            ? widget.temperature
            : (widget.temperature - 32) * 5 / 9;

        // Dynamic threshold color
        final resolvedTempColor = widget.tempColor ??
            (widget.hasData
                ? DualArcGauge.getTemperatureColor(tempInCelsius, isDark: isDark)
                : secondaryTextColor);

        // Humidity color: Emerald Green visualization
        final resolvedHumidityColor = widget.humidityColor ??
            (isDark ? AppColors.neonEmerald : AppColors.lightSecondary);

        // Display formatted temperature
        final displayTemp = widget.isCelsius
            ? animTemp
            : animTemp * 9 / 5 + 32;
        final unitLabel = widget.isCelsius ? '°C' : '°F';

        final tempFraction = widget.hasData
            ? (animTemp / widget.maxTemp).clamp(0.0, 1.0)
            : 0.0;
        final humFraction = widget.hasData
            ? (animHumidity / widget.maxHumidity).clamp(0.0, 1.0)
            : 0.0;

        final thresholdLabel = widget.hasData
            ? DualArcGauge.getThresholdLabel(tempInCelsius)
            : 'NO SENSOR DATA';

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Arc painter
                  CustomPaint(
                    size: Size(widget.size, widget.size),
                    painter: _DualArcPainter(
                      tempFraction: tempFraction,
                      humidityFraction: humFraction,
                      tempColor: resolvedTempColor,
                      humidityColor: resolvedHumidityColor,
                      isDark: isDark,
                    ),
                  ),
                  // Center labels
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Temperature value
                      GestureDetector(
                        onTap: widget.onToggleUnit,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              widget.hasData
                                  ? displayTemp.toStringAsFixed(1)
                                  : '--',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: widget.hasData ? resolvedTempColor : primaryTextColor,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: resolvedTempColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                unitLabel,
                                style: TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: resolvedTempColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Humidity value
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            widget.hasData
                                ? animHumidity.toStringAsFixed(1)
                                : '--',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: resolvedHumidityColor,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '%',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: secondaryTextColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'RH',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 10,
                              color: secondaryTextColor.withValues(alpha: 0.7),
                              letterSpacing: 1.1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Threshold indicator badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: resolvedTempColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: resolvedTempColor.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          thresholdLabel,
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: resolvedTempColor,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// CustomPainter
// ---------------------------------------------------------------------------

class _DualArcPainter extends CustomPainter {
  final double tempFraction;
  final double humidityFraction;
  final Color tempColor;
  final Color humidityColor;
  final bool isDark;

  /// Arc spans 240°, starting at -210° (measured from 3-o'clock, going clockwise).
  static const double _sweepDeg = 240.0;
  static const double _startDeg = -210.0;

  _DualArcPainter({
    required this.tempFraction,
    required this.humidityFraction,
    required this.tempColor,
    required this.humidityColor,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 16;
    final innerRadius = outerRadius - 26;

    _drawArc(
      canvas: canvas,
      center: center,
      radius: outerRadius,
      fraction: tempFraction,
      color: tempColor,
      strokeWidth: 12,
    );

    _drawArc(
      canvas: canvas,
      center: center,
      radius: innerRadius,
      fraction: humidityFraction,
      color: humidityColor,
      strokeWidth: 8,
    );
  }

  void _drawArc({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required double fraction,
    required Color color,
    required double strokeWidth,
  }) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final startRad = _deg2rad(_startDeg);
    final sweepRad = _deg2rad(_sweepDeg);
    final activeSweep = sweepRad * fraction;

    // --- Background track ---
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.06);
    canvas.drawArc(rect, startRad, sweepRad, false, trackPaint);

    if (fraction <= 0) return;

    // --- Glowing foreground arc ---
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawArc(rect, startRad, activeSweep, false, glowPaint);

    // Solid foreground arc on top
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, startRad, activeSweep, false, arcPaint);

    // --- Tip indicator dot ---
    final tipAngle = startRad + activeSweep;
    final tipOffset = Offset(
      center.dx + radius * math.cos(tipAngle),
      center.dy + radius * math.sin(tipAngle),
    );
    final dotRadius = strokeWidth / 2 + 1.5;

    // Outer glow
    final dotGlowPaint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, dotRadius * 1.5);
    canvas.drawCircle(tipOffset, dotRadius * 1.8, dotGlowPaint);

    // Solid dot
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(tipOffset, dotRadius, dotPaint);

    // White center highlight
    final dotHighlight = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(tipOffset, dotRadius * 0.4, dotHighlight);
  }

  static double _deg2rad(double deg) => deg * math.pi / 180.0;

  @override
  bool shouldRepaint(_DualArcPainter oldDelegate) {
    return oldDelegate.tempFraction != tempFraction ||
        oldDelegate.humidityFraction != humidityFraction ||
        oldDelegate.tempColor != tempColor ||
        oldDelegate.humidityColor != humidityColor ||
        oldDelegate.isDark != isDark;
  }
}

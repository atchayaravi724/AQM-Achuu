import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A frosted-glass styled card with optional backdrop blur, soft shadows, and adaptive borders.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double blurRadius;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final double borderWidth;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.blurRadius = 15.0,
    this.borderColor,
    this.borderRadius,
    this.backgroundColor,
    this.borderWidth = 1.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(16);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBg = isDark
        ? AppColors.cardBg.withValues(alpha: 0.90)
        : AppColors.lightCardBg;
    final defaultBorder = isDark ? AppColors.border : AppColors.lightBorder;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Color(0x0A0F172A),
                    blurRadius: 14,
                    offset: Offset(0, 3),
                    spreadRadius: 0,
                  ),
                  const BoxShadow(
                    color: Color(0x050F172A),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                    spreadRadius: 0,
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurRadius, sigmaY: blurRadius),
            child: Container(
              padding: padding ?? const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: backgroundColor ?? defaultBg,
                borderRadius: radius,
                border: Border.all(
                  color: borderColor ?? defaultBorder,
                  width: borderWidth,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

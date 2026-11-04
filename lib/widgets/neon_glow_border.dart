import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Wraps [child] with an animated pulsing neon glow border.
///
/// When [isActive] is true, the border pulses between low and full opacity
/// at ~1 Hz using a sine-wave animation. When false, a static dim border
/// is shown.
class NeonGlowBorder extends StatefulWidget {
  final bool isActive;
  final Color color;
  final Widget child;
  final double borderRadius;
  final double borderWidth;
  final double glowSpread;
  final double glowBlur;

  const NeonGlowBorder({
    super.key,
    required this.isActive,
    required this.color,
    required this.child,
    this.borderRadius = 16.0,
    this.borderWidth = 1.5,
    this.glowSpread = 2.0,
    this.glowBlur = 16.0,
  });

  @override
  State<NeonGlowBorder> createState() => _NeonGlowBorderState();
}

class _NeonGlowBorderState extends State<NeonGlowBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Full cycle = 1 second → 1 Hz
      duration: const Duration(seconds: 1),
    );

    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(NeonGlowBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _controller.repeat();
    } else if (!widget.isActive && oldWidget.isActive) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Maps the animation value [t] ∈ [0,1] to an opacity in [0.3, 1.0]
  /// using a full sine-wave cycle.
  double _pulseOpacity(double t) {
    // sin oscillates between -1 and 1 over one full cycle
    final sine = math.sin(2 * math.pi * t);
    // Map [-1, 1] → [0.3, 1.0]
    return 0.3 + (sine + 1) / 2 * 0.7;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      // Static dim border only
      return _buildBorder(
        borderColor: widget.color.withOpacity(0.4),
        shadows: const [],
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final opacity = _pulseOpacity(_controller.value);
        return _buildBorder(
          borderColor: widget.color.withOpacity(opacity),
          shadows: [
            // Inner tight glow
            BoxShadow(
              color: widget.color.withOpacity(opacity * 0.7),
              blurRadius: widget.glowBlur,
              spreadRadius: widget.glowSpread,
            ),
            // Outer soft halo
            BoxShadow(
              color: widget.color.withOpacity(opacity * 0.3),
              blurRadius: widget.glowBlur * 2.5,
              spreadRadius: widget.glowSpread * 0.5,
            ),
          ],
          child: child,
        );
      },
      child: widget.child,
    );
  }

  Widget _buildBorder({
    required Color borderColor,
    required List<BoxShadow> shadows,
    Widget? child,
  }) {
    final radius = BorderRadius.circular(widget.borderRadius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: borderColor,
          width: widget.borderWidth,
        ),
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: child ?? widget.child,
      ),
    );
  }
}

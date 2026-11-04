import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';
import 'home_shell.dart';

/// Animated Splash / Loading Screen for AERION AeroSense.
/// Displays branding, animated IoT sensor pulsing indicators,
/// dynamic status updates during initial load, and smoothly
/// transitions to [HomeShell].
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _statusText = 'Initializing AeroSense Systems...';
  double _progress = 0.15;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startLoadingSequence();
  }

  void _startLoadingSequence() {
    // Step 1: Initialize
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _statusText = 'Calibrating BLE & Wi-Fi Sensors...';
          _progress = 0.50;
        });
      }
    });

    // Step 2: Cloud Sync
    Timer(const Duration(milliseconds: 1100), () {
      if (mounted) {
        setState(() {
          _statusText = 'Verifying Firebase Cloud Streams...';
          _progress = 0.85;
        });
      }
    });

    // Step 3: Ready & Transition
    Timer(const Duration(milliseconds: 1700), () {
      if (mounted) {
        setState(() {
          _statusText = 'Ready. Launching Dashboard...';
          _progress = 1.0;
        });
      }
    });

    // Navigate to HomeShell
    _timer = Timer(const Duration(milliseconds: 2100), () {
      _navigateToHome();
    });
  }

  void _navigateToHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) => const HomeShell(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = AppColors.electricCyan;

    return Scaffold(
      backgroundColor: const Color(0xFF070A0F),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // Pulsing Branded Icon
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        primaryColor.withValues(alpha: 0.25),
                        AppColors.neonEmerald.withValues(alpha: 0.15),
                      ],
                    ),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.6),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.air_rounded,
                      size: 46,
                      color: primaryColor,
                    ),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(begin: 0.95, end: 1.05, duration: 1200.ms),

                const SizedBox(height: 32),

                // AERION Title
                const Text(
                  'AERION',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4.0,
                  ),
                )
                    .animate()
                    .fadeIn(duration: 600.ms)
                    .slideY(begin: 0.2, end: 0, duration: 600.ms),

                const SizedBox(height: 4),

                // AeroSense Sub-Brand
                Text(
                  'AEROSENSE',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: primaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3.0,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 200.ms, duration: 600.ms),

                const SizedBox(height: 8),

                // Tagline
                const Text(
                  'IoT Environmental Monitoring Intelligence',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: Color(0xFF94A3B8),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.5,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 400.ms, duration: 600.ms),

                const Spacer(flex: 2),

                // Progress Bar Container
                Container(
                  width: 220,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                            width: constraints.maxWidth * _progress,
                            height: 4,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: LinearGradient(
                                colors: [primaryColor, AppColors.neonEmerald],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withValues(alpha: 0.6),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                // Dynamic Status Text
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _statusText,
                    key: ValueKey<String>(_statusText),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: const Color(0xFF94A3B8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),

                const Spacer(flex: 1),

                // Skip / Direct tap option
                TextButton(
                  onPressed: _navigateToHome,
                  child: Text(
                    'Tap to Skip',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      color: primaryColor.withValues(alpha: 0.7),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


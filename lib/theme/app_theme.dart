import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Stealth Midnight Cyber Dark Theme
  static const Color background = Color(0xFF0B0F17);
  static const Color cardBg = Color(0xFF151B26);
  static const Color border = Color(0xFF212C3D);
  static const Color electricCyan = Color(0xFF00F2FE); // Primary
  static const Color neonEmerald = Color(0xFF00E676); // Success
  static const Color radiantAmber = Color(0xFFFFAB00); // Warning
  static const Color crimsonNeon = Color(0xFFFF1744); // Critical
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF484F58);
  static const Color onlineGreen = Color(0xFF00E676);
  static const Color warningOrange = Color(0xFFFFAB00);
  static const Color successGreen = Color(0xFF00E676);
  static const Color amber = Color(0xFFFFAB00);
  static const Color criticalRed = Color(0xFFFF1744);
  static const Color cyanAccent = Color(0xFF00F2FE);

  // Executive Porcelain Light Theme
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightCardBg = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightPrimary = Color(0xFF2563EB); // Royal Blue
  static const Color lightSecondary = Color(0xFF10B981); // Emerald Green
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B); // Labels
  static const Color lightTextMuted = Color(0xFF94A3B8);
  static const Color lightCardShadow = Color(0x0C0F172A);

  // Dynamic Theme-Aware Color Resolvers
  static Color getBackground(bool isDark) => isDark ? background : lightBackground;
  static Color getCardBg(bool isDark) => isDark ? cardBg : lightCardBg;
  static Color getBorder(bool isDark) => isDark ? border : lightBorder;
  static Color getPrimary(bool isDark) => isDark ? electricCyan : lightPrimary;
  static Color getSecondary(bool isDark) => isDark ? neonEmerald : lightSecondary;
  static Color getTextPrimary(bool isDark) => isDark ? textPrimary : lightTextPrimary;
  static Color getTextSecondary(bool isDark) => isDark ? textSecondary : lightTextSecondary;
  static Color getTextMuted(bool isDark) => isDark ? textMuted : lightTextMuted;

  static Color statusColor(double temp) {
    if (temp < 30) return neonEmerald;
    if (temp <= 35) return radiantAmber;
    return crimsonNeon;
  }

  static Color rssiColor(int rssi) {
    if (rssi > -65) return neonEmerald;
    if (rssi > -80) return radiantAmber;
    return crimsonNeon;
  }
}

class AppTextStyles {
  AppTextStyles._();

  static const String fontFamily = 'GoogleSans';

  // Google Sans Bold (w700) for large metric values and primary display
  static TextStyle get displayLarge => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 48,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  static TextStyle get displayMedium => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  // Google Sans Bold (w700) & Medium (w500) for titles and labels
  static TextStyle get labelLarge => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  static TextStyle get labelMedium => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  static TextStyle get labelSmall => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  // Google Sans Bold (w700) for primary metrics
  static TextStyle get metricValue => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 64,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  // Google Sans Medium (w500) for metric units
  static TextStyle get metricUnit => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  static TextStyle get metricSmall => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  // Google Sans Regular (w400) for body and descriptions
  static TextStyle get bodyLarge => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.textPrimary,
      );

  static TextStyle get bodyMedium => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  static TextStyle get bodySmall => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
      );

  static TextStyle get code => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textMuted,
      );

  // Section Headers
  static TextStyle get sectionHeader => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: 1.2,
      );

  static TextStyle get caption => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondary,
      );

  static TextStyle get label => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  static TextStyle get monoValue => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  // Themed helpers adapting cleanly to Executive Light and Stealth Dark
  static TextStyle themedSectionHeader(bool isDark) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
        letterSpacing: 1.2,
      );

  static TextStyle themedLabel(bool isDark) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
      );

  static TextStyle themedCaption(bool isDark) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: isDark ? AppColors.textSecondary : AppColors.lightTextSecondary,
      );

  static TextStyle themedMono(bool isDark, {double fontSize = 16, FontWeight fontWeight = FontWeight.w700}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: isDark ? AppColors.textPrimary : AppColors.lightTextPrimary,
      );
}

class AppTheme {
  AppTheme._();

  // Convenience color accessors
  static const Color background = AppColors.background;
  static const Color surface = AppColors.cardBg;
  static const Color cyan = AppColors.electricCyan;
  static const Color emerald = AppColors.neonEmerald;
  static const Color amber = AppColors.radiantAmber;
  static const Color red = AppColors.crimsonNeon;

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.electricCyan,
        secondary: AppColors.neonEmerald,
        surface: AppColors.cardBg,
        onPrimary: AppColors.background,
        onSecondary: AppColors.background,
        onSurface: AppColors.textPrimary,
        error: AppColors.crimsonNeon,
        onError: AppColors.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      dividerColor: AppColors.border,
      dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      textTheme: TextTheme(
        displayLarge: AppTextStyles.displayLarge,
        displayMedium: AppTextStyles.displayMedium,
        labelLarge: AppTextStyles.labelLarge,
        labelMedium: AppTextStyles.labelMedium,
        labelSmall: AppTextStyles.labelSmall,
        bodyLarge: AppTextStyles.bodyLarge,
        bodyMedium: AppTextStyles.bodyMedium,
        bodySmall: AppTextStyles.bodySmall,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.labelLarge.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.cardBg,
        selectedItemColor: AppColors.electricCyan,
        unselectedItemColor: AppColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.cardBg,
        contentTextStyle: AppTextStyles.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData get lightTheme {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: AppColors.lightPrimary,
        secondary: AppColors.lightSecondary,
        surface: AppColors.lightCardBg,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.lightTextPrimary,
        error: AppColors.crimsonNeon,
        onError: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: AppColors.lightCardBg,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.lightBorder, width: 1),
        ),
      ),
      dividerColor: AppColors.lightBorder,
      dividerTheme: const DividerThemeData(color: AppColors.lightBorder, space: 1),
      iconTheme: const IconThemeData(color: AppColors.lightTextSecondary),
      textTheme: TextTheme(
        displayLarge: AppTextStyles.displayLarge.copyWith(color: AppColors.lightTextPrimary),
        displayMedium: AppTextStyles.displayMedium.copyWith(color: AppColors.lightTextPrimary),
        labelLarge: AppTextStyles.labelLarge.copyWith(color: AppColors.lightTextPrimary),
        labelMedium: AppTextStyles.labelMedium.copyWith(color: AppColors.lightTextSecondary),
        labelSmall: AppTextStyles.labelSmall.copyWith(color: AppColors.lightTextSecondary),
        bodyLarge: AppTextStyles.bodyLarge.copyWith(color: AppColors.lightTextPrimary),
        bodyMedium: AppTextStyles.bodyMedium.copyWith(color: AppColors.lightTextSecondary),
        bodySmall: AppTextStyles.bodySmall.copyWith(color: AppColors.lightTextMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTextStyles.labelLarge.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.lightTextPrimary,
        ),
        iconTheme: const IconThemeData(color: AppColors.lightTextPrimary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.lightCardBg,
        selectedItemColor: AppColors.lightPrimary,
        unselectedItemColor: AppColors.lightTextMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.lightCardBg,
        contentTextStyle: AppTextStyles.labelMedium.copyWith(color: AppColors.lightTextPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.lightBorder),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

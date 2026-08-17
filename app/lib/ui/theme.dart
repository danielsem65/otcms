import 'package:flutter/material.dart';

/// OTCMS visual language — clean, professional pharmacy interface.
class OtcmsTheme {
  OtcmsTheme._();

  static const seed = Color(0xFF00897B); // pharmacy teal
  static const danger = Color(0xFFD32F2F);
  static const warning = Color(0xFFF57C00);
  static const caution = Color(0xFFFBC02D);
  static const safe = Color(0xFF2E7D32);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF7F9F9),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardTheme(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          side: BorderSide(color: Color(0xFFE3E8E8)),
        ),
      ),
      navigationRailTheme: const NavigationRailThemeData(
        backgroundColor: Color(0xFFFFFFFF),
        indicatorColor: Color(0x1F00897B),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD5DEE0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD5DEE0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
        headingTextStyle: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
    );
  }

  /// Expiry/stock status colors.
  static Color statusColor(StockStatus status) => switch (status) {
        StockStatus.expired || StockStatus.outOfStock => danger,
        StockStatus.critical || StockStatus.expiringVerySoon => warning,
        StockStatus.low || StockStatus.expiringSoon || StockStatus.expiringNormal => caution,
        StockStatus.healthy || StockStatus.safe => safe,
      };

  static const moneyFontWeight = FontWeight.w700;
}

enum StockStatus {
  healthy,
  low,
  critical,
  outOfStock,
  expired,
  expiringVerySoon,
  expiringSoon,
  expiringNormal,
  safe,
}

extension MoneyText on String {
  String get money => this;
}

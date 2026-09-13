/// 主题（ARCHITECTURE 7.2）
/// 对齐原型的色系：
///   primary   = #FF7A30  橙
///   background= #FFF9F2  米白
///   text      = #222 / 333
///   surface   = #F2F2F2  浅灰（次级卡）
library;

import 'package:flutter/material.dart';

class AppPalette {
  AppPalette._();

  // —— 原型主色（严格 1:1）——
  static const Color primary = Color(0xFFFF7A30);      // c-primary
  static const Color primaryWeak = Color(0xFFFFE8DC);  // c-primary-weak
  static const Color primaryDark = Color(0xFFE8621A);   // c-primary-dark

  // —— 中性色（按任务要求）——
  static const Color background = Color(0xFFFFF9F2);   // 米白
  static const Color surface = Color(0xFFFFFFFF);      // 卡
  static const Color surfaceMuted = Color(0xFFF2F2F2); // 浅灰
  static const Color border = Color(0xFFECECEE);
  static const Color text = Color(0xFF222222);
  static const Color textSub = Color(0xFF8A8A8E);
  static const Color textWeak = Color(0xFFC7C7CC);

  // —— 宏量 / 状态色 ——
  static const Color protein = Color(0xFF3B82F6); // 蓝
  static const Color carb = Color(0xFFF59E0B);     // 橙黄
  static const Color fat = Color(0xFFEF4444);      // 红
  static const Color ok = Color(0xFF22C55E);       // 绿
  static const Color warn = Color(0xFFF59E0B);     // 橙（与 carb 同色，统一语义）
  static const Color danger = Color(0xFFEF4444);   // 红
  static const Color neutral = Color(0xFF8A8A8E);
}

class AppTheme {
  AppTheme._();

  /// Material 3 主题（useMaterial3: true）。
  ///   - 主色 = primary
  ///   - surfaceTint = primary（卡片顶部高亮）
  ///   - 圆角 12（card / dialog）
  ///   - 默认 padding 16
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppPalette.primary,
      brightness: Brightness.light,
      primary: AppPalette.primary,
      onPrimary: Colors.white,
      surface: AppPalette.surface,
      onSurface: AppPalette.text,
      error: AppPalette.danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppPalette.background,
      fontFamily: 'PingFang SC',
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppPalette.surface,
        foregroundColor: AppPalette.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w600, color: AppPalette.text,
        ),
      ),
      cardTheme: const CardTheme(
        elevation: 0,
        color: AppPalette.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: AppPalette.primary,
          textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          foregroundColor: AppPalette.text,
          side: const BorderSide(color: AppPalette.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppPalette.primary,
          minimumSize: const Size(0, 40),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: AppPalette.border),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppPalette.border),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: AppPalette.primary, width: 1.5),
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xE61C1C1E),
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      dialogTheme: const DialogTheme(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppPalette.surface,
        selectedItemColor: AppPalette.primary,
        unselectedItemColor: AppPalette.textSub,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppPalette.surface,
        indicatorColor: AppPalette.primaryWeak,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppPalette.primary : AppPalette.textSub,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppPalette.primary : AppPalette.textSub,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: AppPalette.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

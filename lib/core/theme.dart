import 'package:flutter/material.dart';

/// 시니어 사용자를 고려한 기본 테마: 큰 글씨, 고대비, 넉넉한 터치 영역.
/// 손채은 님 디자인이 확정되면 색상·폰트만 여기서 바꾸면 됩니다.
class AppColors {
  static const primary = Color(0xFF1B5E7A);
  static const danger = Color(0xFFB3261E);
  static const dangerBg = Color(0xFFFCE8E6);
  static const ok = Color(0xFF1E6B3A);
  static const okBg = Color(0xFFE3F2E8);
  static const unknown = Color(0xFF5F5A4E);
  static const unknownBg = Color(0xFFF1EEE6);
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
  );
  final text = base.textTheme;
  return base.copyWith(
    textTheme: text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontSize: 20, fontWeight: FontWeight.w600),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 18, height: 1.5),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 17, height: 1.5),
      labelLarge: text.labelLarge?.copyWith(fontSize: 18),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 17),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 14,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
      subtitleTextStyle: TextStyle(fontSize: 15, color: Colors.black54),
    ),
  );
}

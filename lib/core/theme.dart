import 'package:flutter/material.dart';

/// 토스 느낌의 색 팔레트 (공개된 토스 스타일 색값을 참고한 근사치).
/// 강조색은 파랑 하나만 쓰고, 나머지는 회색 단계로 위계를 만듭니다.
class Toss {
  static const blue = Color(0xFF3182F6);
  static const blue50 = Color(0xFFE8F3FF);
  static const grey50 = Color(0xFFF9FAFB);
  static const grey100 = Color(0xFFF2F4F6);
  static const grey200 = Color(0xFFE5E8EB);
  static const grey300 = Color(0xFFD1D6DB);
  static const grey400 = Color(0xFFB0B8C1);
  static const grey500 = Color(0xFF8B95A1);
  static const grey600 = Color(0xFF6B7684);
  static const grey700 = Color(0xFF4E5968);
  static const grey900 = Color(0xFF191F28);
}

/// 앱 전체에서 쓰는 의미 색.
/// ⚠️ 판정 색(금기=빨강, 판정 불가=회갈색, 금기 기록 없음=중립 회색)은 의미 색이라 토스 블루로 바꾸지 않습니다.
class AppColors {
  static const primary = Toss.blue;
  static const danger = Color(0xFFB3261E);
  static const dangerBg = Color(0xFFFCE8E6);
  static const ok = Color(0xFF1E6B3A);
  static const okBg = Color(0xFFE3F2E8);
  static const unknown = Color(0xFF5F5A4E);
  static const unknownBg = Color(0xFFF1EEE6);

  /// '확인된 금기 기록 없음' — 안전처럼 보이지 않게 중립 회색
  static const neutral = Toss.grey700;
  static const neutralBg = Toss.grey100;

  /// 참고 정보(임부금기·용량주의) — 금기(빨강)와 구분되는 주황
  static const caution = Color(0xFFB45309);
  static const cautionBg = Color(0xFFFFF4E5);
}

/// 토스 스타일 테마
/// - 흰 배경 + 연회색 카드, 그림자 없음, 크게 둥근 모서리
/// - 화면 아래 꽉 찬 파란 버튼, 보조 버튼은 회색 면
/// - 입력창은 테두리 대신 회색 면
/// - 시니어 사용자를 위해 글자 크기는 기존처럼 크게 유지
ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Toss.blue,
    primary: Toss.blue,
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: Toss.grey900,
    error: AppColors.danger,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme.apply(bodyColor: Toss.grey900, displayColor: Toss.grey900);

  RoundedRectangleBorder rounded(double r) => RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
  OutlineInputBorder inputBorder([Color? c]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: c == null ? BorderSide.none : BorderSide(color: c, width: 1.5),
      );

  return base.copyWith(
    scaffoldBackgroundColor: Colors.white,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      titleLarge: text.titleLarge?.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
      titleSmall: text.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 18, height: 1.55, color: Toss.grey700),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 17, height: 1.5, color: Toss.grey700),
      bodySmall: text.bodySmall?.copyWith(fontSize: 13, color: Toss.grey500),
      labelLarge: text.labelLarge?.copyWith(fontSize: 18),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Toss.grey900,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Toss.grey900),
    ),
    dividerTheme: const DividerThemeData(color: Toss.grey100, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: Toss.grey50,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: rounded(20),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Toss.blue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Toss.grey100,
        disabledForegroundColor: Toss.grey500,
        minimumSize: const Size(64, 56),
        elevation: 0,
        shape: rounded(16),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: Toss.grey100,
        foregroundColor: Toss.grey700,
        side: BorderSide.none,
        minimumSize: const Size(64, 52),
        shape: rounded(14),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Toss.blue,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Toss.grey100,
      border: inputBorder(),
      enabledBorder: inputBorder(),
      focusedBorder: inputBorder(Toss.blue),
      errorBorder: inputBorder(AppColors.danger),
      focusedErrorBorder: inputBorder(AppColors.danger),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      hintStyle: const TextStyle(color: Toss.grey500),
      labelStyle: const TextStyle(color: Toss.grey600),
      prefixIconColor: Toss.grey500,
      suffixIconColor: Toss.grey500,
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 14,
      iconColor: Toss.grey600,
      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Toss.grey900),
      subtitleTextStyle: TextStyle(fontSize: 14, color: Toss.grey600),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Toss.grey100,
      selectedColor: Toss.blue50,
      checkmarkColor: Toss.blue,
      side: BorderSide.none,
      shape: StadiumBorder(),
      labelStyle: TextStyle(color: Toss.grey700, fontWeight: FontWeight.w600),
      secondaryLabelStyle: TextStyle(color: Toss.blue, fontWeight: FontWeight.w700),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Toss.blue50,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12.5,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? Toss.grey900 : Toss.grey500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? Toss.blue : Toss.grey400),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: Toss.blue,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: rounded(16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: rounded(24),
      titleTextStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Toss.grey900),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: Toss.grey300,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: rounded(14),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Toss.grey900,
      shape: rounded(12),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 16),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Toss.blue, linearTrackColor: Toss.grey100),
  );
}

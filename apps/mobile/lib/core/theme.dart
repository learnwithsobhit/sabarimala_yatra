import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Semantic colors that Material's ColorScheme doesn't cover.
/// Access via `context.sharanam`.
class SharanamColors extends ThemeExtension<SharanamColors> {
  const SharanamColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.danger,
    required this.dangerContainer,
    required this.urgentContainer,
    required this.onUrgentContainer,
    required this.offlineContainer,
    required this.gold,
    required this.border,
    required this.surfaceAlt,
    required this.passCard,
    required this.onPassCard,
    required this.onPassCardMuted,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color danger;
  final Color dangerContainer;
  final Color urgentContainer;
  final Color onUrgentContainer;
  final Color offlineContainer;
  final Color gold;
  final Color border;
  final Color surfaceAlt;
  final Color passCard;
  final Color onPassCard;
  final Color onPassCardMuted;

  static const light = SharanamColors(
    success: Color(0xFF166534),
    onSuccess: Colors.white,
    successContainer: Color(0xFFDCFCE7),
    onSuccessContainer: Color(0xFF14532D),
    danger: Color(0xFF9F1239),
    dangerContainer: Color(0xFFFFE4E6),
    urgentContainer: Color(0xFFFFEDD5),
    onUrgentContainer: Color(0xFF7C2D12),
    offlineContainer: Color(0xFFF0EAE0),
    gold: Color(0xFFD4A017),
    border: Color(0xFFE7E5E4),
    surfaceAlt: Color(0xFFF0EAE0),
    passCard: Color(0xFF1C1917),
    onPassCard: Color(0xFFF7F3EB),
    onPassCardMuted: Color(0xFFD6D3D1),
  );

  static const dark = SharanamColors(
    success: Color(0xFF22C55E),
    onSuccess: Color(0xFF052E16),
    successContainer: Color(0xFF10331D),
    onSuccessContainer: Color(0xFFBBF7D0),
    danger: Color(0xFFFB7185),
    dangerContainer: Color(0xFF3A1220),
    urgentContainer: Color(0xFF3A2A12),
    onUrgentContainer: Color(0xFFFED7AA),
    offlineContainer: Color(0xFF2A2522),
    gold: Color(0xFFD4A017),
    border: Color(0xFF3A342E),
    surfaceAlt: Color(0xFF2A2522),
    passCard: Color(0xFF1B1613),
    onPassCard: Color(0xFFF7F3EB),
    onPassCardMuted: Color(0xFFA8A29E),
  );

  @override
  SharanamColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? danger,
    Color? dangerContainer,
    Color? urgentContainer,
    Color? onUrgentContainer,
    Color? offlineContainer,
    Color? gold,
    Color? border,
    Color? surfaceAlt,
    Color? passCard,
    Color? onPassCard,
    Color? onPassCardMuted,
  }) {
    return SharanamColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      urgentContainer: urgentContainer ?? this.urgentContainer,
      onUrgentContainer: onUrgentContainer ?? this.onUrgentContainer,
      offlineContainer: offlineContainer ?? this.offlineContainer,
      gold: gold ?? this.gold,
      border: border ?? this.border,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      passCard: passCard ?? this.passCard,
      onPassCard: onPassCard ?? this.onPassCard,
      onPassCardMuted: onPassCardMuted ?? this.onPassCardMuted,
    );
  }

  @override
  SharanamColors lerp(SharanamColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return SharanamColors(
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      successContainer: l(successContainer, other.successContainer),
      onSuccessContainer: l(onSuccessContainer, other.onSuccessContainer),
      danger: l(danger, other.danger),
      dangerContainer: l(dangerContainer, other.dangerContainer),
      urgentContainer: l(urgentContainer, other.urgentContainer),
      onUrgentContainer: l(onUrgentContainer, other.onUrgentContainer),
      offlineContainer: l(offlineContainer, other.offlineContainer),
      gold: l(gold, other.gold),
      border: l(border, other.border),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      passCard: l(passCard, other.passCard),
      onPassCard: l(onPassCard, other.onPassCard),
      onPassCardMuted: l(onPassCardMuted, other.onPassCardMuted),
    );
  }
}

extension SharanamThemeX on BuildContext {
  SharanamColors get sharanam =>
      Theme.of(this).extension<SharanamColors>() ?? SharanamColors.light;
}

/// "Temple Lamp" light theme.
ThemeData buildSharanamTheme() => _build(Brightness.light);

/// "Midnight Darshan" dark theme.
ThemeData buildSharanamDarkTheme() => _build(Brightness.dark);

ThemeData _build(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final ext = isDark ? SharanamColors.dark : SharanamColors.light;

  const lampLight = Color(0xFFB45309);
  const lampDark = Color(0xFFE08A2E);
  const ivory = Color(0xFFF7F3EB);
  const charcoal = Color(0xFF1C1917);
  const nightBg = Color(0xFF141210);
  const nightSurface = Color(0xFF211D1A);

  final primary = isDark ? lampDark : lampLight;
  final background = isDark ? nightBg : ivory;
  final surface = isDark ? nightSurface : Colors.white;
  final ink = isDark ? ivory : charcoal;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: primary,
    onPrimary: isDark ? const Color(0xFF241300) : Colors.white,
    primaryContainer: isDark ? const Color(0xFF3A2A12) : const Color(0xFFFFEDD5),
    onPrimaryContainer: isDark ? const Color(0xFFFED7AA) : const Color(0xFF7C2D12),
    secondary: isDark ? ext.gold : charcoal,
    onSecondary: isDark ? charcoal : ivory,
    surface: background,
    onSurface: ink,
    surfaceContainerLowest: surface,
    surfaceContainerLow: surface,
    surfaceContainer: ext.surfaceAlt,
    error: ext.danger,
    onError: isDark ? const Color(0xFF2A040D) : Colors.white,
    errorContainer: ext.dangerContainer,
    onErrorContainer: isDark ? const Color(0xFFFECDD3) : const Color(0xFF881337),
    outline: ext.border,
    outlineVariant: ext.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
  );

  // Manrope for UI/body, Literata reserved for display/headline moments.
  final body = GoogleFonts.manropeTextTheme(base.textTheme);
  final textTheme = body
      .copyWith(
        displayLarge: GoogleFonts.literata(textStyle: body.displayLarge),
        displayMedium: GoogleFonts.literata(textStyle: body.displayMedium),
        displaySmall: GoogleFonts.literata(textStyle: body.displaySmall),
        headlineLarge: GoogleFonts.literata(
            textStyle: body.headlineLarge, fontWeight: FontWeight.w600),
        headlineMedium: GoogleFonts.literata(
            textStyle: body.headlineMedium, fontWeight: FontWeight.w600),
        headlineSmall: GoogleFonts.literata(
            textStyle: body.headlineSmall, fontWeight: FontWeight.w600),
        titleLarge: GoogleFonts.literata(
            textStyle: body.titleLarge, fontWeight: FontWeight.w600),
        bodyLarge: body.bodyLarge?.copyWith(fontSize: 16),
        bodyMedium: body.bodyMedium?.copyWith(fontSize: 15),
      )
      .apply(bodyColor: ink, displayColor: ink);

  return base.copyWith(
    textTheme: textTheme,
    extensions: [ext],
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.literata(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: ext.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.manrope(
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: ink,
        side: BorderSide(color: ext.border, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: ext.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: ext.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: scheme.primaryContainer,
      height: 72,
      labelTextStyle: WidgetStatePropertyAll(
        GoogleFonts.manrope(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        side: BorderSide(color: ext.border),
        textStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? ext.surfaceAlt : charcoal,
      contentTextStyle: GoogleFonts.manrope(color: ivory, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(color: ext.border),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 4),
    ),
  );
}

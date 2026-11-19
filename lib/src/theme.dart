import 'package:flutter/material.dart';

class MediaPalette {
  static const orange = Color(0xffff6719);
  static const ink = Color(0xff201d1a);
  static const cream = Color(0xfffffaf5);
  static const dark = Color(0xff121315);
  static const darkSurface = Color(0xff202125);
  static const divider = Color(0xffdedbd7);
}

ThemeData mediaTheme(Brightness mode) {
  final dark = mode == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: MediaPalette.orange,
    brightness: mode,
    surface: dark ? MediaPalette.dark : MediaPalette.cream,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: mode,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? MediaPalette.dark : MediaPalette.cream,
    appBarTheme: AppBarTheme(
      centerTitle: false, elevation: 0,
      backgroundColor: dark ? MediaPalette.dark : MediaPalette.cream,
      foregroundColor: dark ? Colors.white : MediaPalette.ink,
      titleTextStyle: TextStyle(
        color: dark ? Colors.white : MediaPalette.ink,
        fontWeight: FontWeight.w900, fontSize: 19,
      ),
    ),
    cardTheme: CardThemeData(
      color: dark ? MediaPalette.darkSurface : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: dark
            ? Colors.white12 : const Color(0xffebe4dd)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xff242629) : Colors.white,
      hintStyle: TextStyle(color: dark ? Colors.white54 : Colors.black45),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: MediaPalette.orange, width: 1.8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MediaPalette.orange,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? MediaPalette.darkSurface : Colors.white,
      indicatorColor: MediaPalette.orange.withValues(alpha: .13),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
    ),
    dividerColor: dark ? Colors.white12 : MediaPalette.divider,
  );
}

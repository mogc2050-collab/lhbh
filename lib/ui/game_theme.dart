import 'package:flutter/material.dart';

class GameColors {
  static const gold = Color(0xffe8bc66);
  static const paleGold = Color(0xffffe0a0);
  static const dark = Color(0xff1c201f);
  static const wood = Color(0xff4e3024);
  static const panel = Color(0xff29241e);
  static const green = Color(0xff66c879);
  static const parchment = Color(0xffffe7b7);
  static const muted = Color(0xffb9afa0);
}

ThemeData gameTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: GameColors.dark,
    colorScheme: ColorScheme.fromSeed(seedColor: GameColors.gold, brightness: Brightness.dark),
    fontFamily: 'Roboto',
    appBarTheme: const AppBarTheme(backgroundColor: GameColors.dark, foregroundColor: GameColors.paleGold),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class GPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final double radius;
  const GPanel({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.color, this.radius = 16});
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(colors: [color ?? const Color(0xff3c2c20), const Color(0xff211e1b)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      border: Border.all(color: GameColors.gold.withValues(alpha: 0.62), width: 1.3),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4))],
    ),
    child: child,
  );
}

class GButton extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  const GButton({super.key, required this.text, this.icon, this.onPressed, this.primary = false});
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      backgroundColor: primary ? const Color(0xff31673a) : const Color(0xff534029),
      foregroundColor: GameColors.paleGold,
      side: BorderSide(color: GameColors.gold.withValues(alpha: 0.7)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    ),
    icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 18),
    label: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const SectionTitle(this.title, this.icon, {super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: GameColors.gold, size: 22),
    const SizedBox(width: 8),
    Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: GameColors.paleGold))),
  ]);
}

class NeedBar extends StatelessWidget {
  final String title;
  final double value;
  final IconData icon;
  final Color color;
  const NeedBar(this.title, this.value, this.icon, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Icon(icon, size: 19, color: color), const SizedBox(width: 7),
      SizedBox(width: 58, child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
        value: value / 100, minHeight: 10,
        backgroundColor: Colors.black38, color: color,
      ))),
      const SizedBox(width: 8),
      SizedBox(width: 38, child: Text('${value.round()}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
    ]),
  );
}

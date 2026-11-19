import 'package:flutter/material.dart';
import 'game/game_state.dart';
import 'ui/game_screen.dart';
import 'ui/game_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KingdomApp());
}

class KingdomApp extends StatelessWidget {
  const KingdomApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ممالك الحياة',
    debugShowCheckedModeBanner: false,
    theme: gameTheme(),
    locale: const Locale('ar'),
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    home: FutureBuilder<GameState>(
      future: GameState.load(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(), SizedBox(height: 20), Text('جاري تجهيز مملكتك...'),
          ])));
        }
        return GameScreen(key: const ValueKey('play'), game: snapshot.data!);
      },
    ),
  );
}

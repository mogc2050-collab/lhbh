import 'package:flutter/material.dart';
import 'kingdom/engine.dart';
import 'visual/game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RebuiltKingdomApp());
}

class RebuiltKingdomApp extends StatelessWidget {
  const RebuiltKingdomApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ممالك الحياة',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ar'),
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff182d25),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffd0a150),
        brightness: Brightness.dark,
      ),
    ),
    builder: (context, child) => Directionality(
      textDirection: TextDirection.rtl, child: child!),
    home: FutureBuilder<KingdomEngine>(
      future: KingdomEngine.load(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text('جارٍ إنشاء عالمك الجديد...'),
            ],
          )));
        }
        return KingdomGame(key: const ValueKey('rebuild-v3'),
          engine: snapshot.data!);
      },
    ),
  );
}

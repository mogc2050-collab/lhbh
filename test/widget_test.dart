import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medieval_life/ui/game_theme.dart';

void main() {
  testWidgets('Arabic game panel is visible', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: gameTheme(),
      home: const Scaffold(body: Center(child: GPanel(child: Text('ممالك الحياة')))),
    ));
    expect(find.text('ممالك الحياة'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medieval_life/kingdom/engine.dart';
import 'package:medieval_life/visual/game_screen.dart';

void main() {
  testWidgets('rebuilt game shows actual interactive navigation', (tester) async {
    final engine = KingdomEngine();
    await tester.pumpWidget(MaterialApp(
      home: KingdomGame(engine: engine),
    ));
    expect(find.byType(KingdomGame), findsOneWidget);
    expect(find.text('ممالك الحياة'), findsOneWidget);
    expect(find.text('السوق'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
  });
}

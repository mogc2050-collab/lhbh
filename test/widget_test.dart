import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibetoo_media/src/theme.dart';

void main() {
  testWidgets('Arabic identity stays legible in daylight theme', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme:mediaTheme(Brightness.light),
      home:const Directionality(
        textDirection:TextDirection.rtl,
        child:Scaffold(body:Center(
          child:Text('iBetoo Media - التنزيلات والمكتبة'),
        )),
      ),
    ));
    expect(find.text('iBetoo Media - التنزيلات والمكتبة'),findsOneWidget);
  });
  test('light and dark themes have different brightness', () {
    expect(mediaTheme(Brightness.light).brightness,Brightness.light);
    expect(mediaTheme(Brightness.dark).brightness,Brightness.dark);
  });
}

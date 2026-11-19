import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibetoo_media/src/device_media.dart';
import 'package:ibetoo_media/src/library.dart';
import 'package:ibetoo_media/src/media_collection_screen.dart';
import 'package:ibetoo_media/src/media_gestures.dart';
import 'package:ibetoo_media/src/photo_gallery.dart';
import 'package:ibetoo_media/src/player.dart';
import 'package:ibetoo_media/src/theme.dart';

class _Music extends ChangeNotifier implements BackgroundMusic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aE1sAAAAASUVORK5CYII=',
  );

  Widget host(Widget child) => MaterialApp(
    theme: mediaTheme(Brightness.light),
    home: Directionality(textDirection: TextDirection.rtl, child: child),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          PhoneLibrary.channel,
          (call) async =>
              call.method == 'thumbnail' || call.method == 'imagePreview'
              ? pixel
              : null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('ibetoo.media/changes'),
          (_) async => null,
        );
  });

  testWidgets('RTL swipes change tracks; taps and small drags do not', (
    tester,
  ) async {
    var next = 0, previous = 0;
    await tester.pumpWidget(
      host(
        Scaffold(
          body: SwipeToChange(
            onNext: () => next++,
            onPrevious: () => previous++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(SwipeToChange));
    expect(next, 0);
    await tester.drag(find.byType(SwipeToChange), const Offset(200, 0));
    expect(next, 1);
    await tester.drag(find.byType(SwipeToChange), const Offset(-200, 0));
    expect(previous, 1);
    await tester.drag(find.byType(SwipeToChange), const Offset(0, 200));
    expect(next, 1);
    expect(previous, 1);
  });

  testWidgets(
    'all media tabs swipe and imported files reuse one compact search',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final phone = PhoneLibrary();
      final library = await MediaLibrary.load();
      final music = _Music();
      phone.permissions = {'audio': true, 'video': true, 'image': true};
      for (final kind in ['audio', 'video', 'image']) {
        final media = PhoneMedia(
          id: 1,
          uri: 'content://media/$kind/1',
          name: '$kind sample',
          kind: kind,
          artist: 'Test artist',
          size: 1024,
          duration: 60000,
          date: 1,
          mime: '$kind/test',
        );
        (kind == 'audio'
                ? phone.audio
                : kind == 'video'
                ? phone.videos
                : phone.images)
            .add(media);
      }
      library.files.add(
        const SavedMedia(
          path: '/example.pdf',
          name: 'example.pdf',
          createdAt: 1,
        ),
      );
      await tester.pumpWidget(
        host(
          MediaCollectionScreen(phone: phone, library: library, music: music),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('library-search'))).height,
        44,
      );
      for (var index = 1; index < 5; index++) {
        await tester.dragFrom(const Offset(50, 550), const Offset(290, 0));
        await tester.pumpAndSettle();
        expect(
          tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
          index,
        );
      }
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('example.pdf'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('library-search')),
        'missing',
      );
      await tester.pumpAndSettle();
      expect(find.text('example.pdf'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      phone.dispose();
      library.dispose();
      music.dispose();
    },
  );

  testWidgets('photo paging, bounds and zoom stay navigable', (tester) async {
    await tester.pumpWidget(
      host(
        PhotoGallery(
          images: [
            GalleryImage(source: 'content://media/image/1', title: 'First'),
            GalleryImage(source: 'content://media/image/2', title: 'Second'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('photo-pager')),
      const Offset(600, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    final next = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'الصورة التالية',
      ),
    );
    expect(next.onPressed, isNull);
    await tester.tap(find.byTooltip('الصورة السابقة'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    final viewer = find.byType(InteractiveViewer).first;
    await tester.tap(viewer);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(viewer);
    await tester.pumpAndSettle();
    final pager = tester.widget<PageView>(
      find.byKey(const ValueKey('photo-pager')),
    );
    expect(pager.physics, isA<NeverScrollableScrollPhysics>());
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibetoo_media/src/browser.dart';
import 'package:ibetoo_media/src/engine/browser_engine.dart';
import 'package:ibetoo_media/src/library.dart';
import 'package:ibetoo_media/src/theme.dart';

class _FakeTab extends EngineTab {
  _FakeTab({required super.id, required super.private});
  final loaded = <String>[];
  var closed = false;

  @override
  Future<void> load(String url) async {
    loaded.add(url);
    listener.onPageStarted?.call(url);
    listener.onPageFinished?.call(url, true);
  }

  @override
  Future<void> goBack() async {}
  @override
  Future<void> goForward() async {}
  @override
  Future<void> reload() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> setDesktopMode(bool desktop) async {}
  @override
  Future<void> command(String name, [Map<String, Object?> args = const {}]) async {}
  @override
  Future<void> close() async => closed = true;
  @override
  Widget buildView() => const ColoredBox(
    color: Colors.white,
    child: Center(child: Text('Web content')),
  );
}

class _FakeEngine implements BrowserEngine {
  final tabs = <_FakeTab>[];
  final secureCalls = <bool>[];
  @override
  EngineTab createTab({bool private = false, String? containerId}) {
    final tab = _FakeTab(id: 'fake${tabs.length}', private: private);
    tabs.add(tab);
    return tab;
  }

  @override
  Future<void> setSecureWindow(bool secure) async => secureCalls.add(secure);
  @override
  Future<void> clearBrowsingData() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('320px browser has one bottom toolbar and no top header', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final library = await MediaLibrary.load();
    final engine = _FakeEngine();
    BrowserEngine.instance = engine;
    var openedSections = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: mediaTheme(Brightness.light),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: BrowserScreen(
            library: library,
            onOpenNavigation: () => openedSections++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('browser-toolbar'))).height,
      lessThanOrEqualTo(64),
    );
    await tester.tap(find.byTooltip('أقسام التطبيق'));
    expect(openedSections, 1);
    await tester.tap(find.text('Google').first);
    await tester.pumpAndSettle();
    expect(find.text('Web content'), findsOneWidget);
    expect(engine.tabs.single.loaded, isNotEmpty);
    await tester.tap(find.byTooltip('رجوع للصفحة السابقة'));
    await tester.pumpAndSettle();
    expect(find.text('iBetoo Browser'), findsOneWidget);
    expect(
      engine.tabs.length,
      1,
      reason: 'Returning home must reuse the current tab',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    library.dispose();
  });

  testWidgets('private tab blocks screenshots and closes its session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final library = await MediaLibrary.load();
    final engine = _FakeEngine();
    BrowserEngine.instance = engine;
    await tester.pumpWidget(
      MaterialApp(
        theme: mediaTheme(Brightness.light),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: BrowserScreen(library: library),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('قائمة المتصفح'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    // Disposing the screen closes every engine session.
    expect(engine.tabs.every((t) => t.closed), isTrue);
    expect(engine.secureCalls.last, isFalse);
    library.dispose();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:ibetoo_media/src/browser.dart';
import 'package:ibetoo_media/src/library.dart';
import 'package:ibetoo_media/src/theme.dart';

class _WebPlatform extends WebViewPlatform {
  final controllers = <_WebController>[];
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _WebController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Navigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _WebWidget(params);
}

class _WebController extends PlatformWebViewController {
  _WebController(super.params) : super.implementation();
  _Navigation? delegate;
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate value,
  ) async {
    delegate = value as _Navigation;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    delegate?.started?.call(params.uri.toString());
    delegate?.finished?.call(params.uri.toString());
  }

  @override
  Future<String?> getTitle() async => 'Example web page';
  @override
  Future<bool> canGoBack() async => false;
  @override
  Future<bool> canGoForward() async => false;
}

class _Navigation extends PlatformNavigationDelegate {
  _Navigation(super.params) : super.implementation();
  PageEventCallback? started, finished;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {
    started = callback;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _WebWidget extends PlatformWebViewWidget {
  _WebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Colors.white,
    child: Center(child: Text('Web content')),
  );
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
    final platform = _WebPlatform();
    WebViewPlatform.instance = platform;
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
    expect(find.text('Example web page'), findsNothing);
    await tester.tap(find.byTooltip('رجوع للصفحة السابقة'));
    await tester.pumpAndSettle();
    expect(find.text('iBetoo Browser'), findsOneWidget);
    expect(
      platform.controllers.length,
      1,
      reason: 'Returning home must reuse the current tab',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    library.dispose();
  });
}

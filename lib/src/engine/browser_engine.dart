import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Callbacks a browser tab reports back to the UI. All are optional.
class EngineTabListener {
  void Function(String url)? onPageStarted;
  void Function(int percent)? onProgress;
  void Function(String url, bool success)? onPageFinished;
  void Function(String url)? onLocation;
  void Function(String title)? onTitle;
  void Function(bool canBack, bool canForward)? onHistory;
  void Function(String description)? onError;
  void Function(String url)? onNewTabRequested;
  void Function(String url)? onExternalLink;
  void Function(String url)? onDownloadRequested;
  void Function(bool fullscreen)? onFullscreen;
  void Function()? onCrashed;
}

/// One browsing session (one tab).
abstract class EngineTab {
  EngineTab({required this.id, required this.private});
  final String id;
  final bool private;
  final EngineTabListener listener = EngineTabListener();

  Future<void> load(String url);
  Future<void> goBack();
  Future<void> goForward();
  Future<void> reload();
  Future<void> stop();
  Future<void> setDesktopMode(bool desktop);

  /// Runs a named command in the page through the bundled WebExtension.
  /// Known names: `dark` {on}, `reader`.
  Future<void> command(String name, [Map<String, Object?> args = const {}]);
  Future<void> close();
  Widget buildView();
}

/// The rendering engine behind the browser screen.
abstract class BrowserEngine {
  /// Replaced by a fake in widget tests.
  static BrowserEngine instance = GeckoBrowserEngine();

  EngineTab createTab({bool private = false, String? containerId});

  /// Blocks screenshots while a private tab is on screen.
  Future<void> setSecureWindow(bool secure);
  Future<void> clearBrowsingData();
}

/// GeckoView-backed engine (Mozilla Gecko, the Firefox engine).
class GeckoBrowserEngine implements BrowserEngine {
  static const _methods = MethodChannel('aflaak/gecko');
  static const _events = EventChannel('aflaak/gecko/events');

  final Map<String, GeckoEngineTab> _tabs = {};
  StreamSubscription<dynamic>? _subscription;
  int _counter = 0;

  void _ensureListening() {
    _subscription ??= _events.receiveBroadcastStream().listen(
      _dispatch,
      onError: (Object e) => debugPrint('Gecko event error: $e'),
    );
  }

  @override
  EngineTab createTab({bool private = false, String? containerId}) {
    _ensureListening();
    final id = 't${DateTime.now().microsecondsSinceEpoch}x${_counter++}';
    final tab = GeckoEngineTab._(this, id, private);
    _tabs[id] = tab;
    // Channel calls are ordered, so later calls for this id are safe.
    unawaited(_invoke('create', {
      'tabId': id,
      'private': private,
      'containerId': containerId,
    }));
    return tab;
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _methods.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('Gecko $method failed: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  void _dispatch(dynamic raw) {
    if (raw is! Map) return;
    final tab = _tabs[raw['tabId']];
    if (tab == null) return;
    final l = tab.listener;
    switch (raw['type']) {
      case 'pageStart':
        l.onPageStarted?.call('${raw['url'] ?? ''}');
      case 'progress':
        l.onProgress?.call((raw['value'] as num?)?.toInt() ?? 0);
      case 'pageStop':
        l.onPageFinished?.call(tab.url, raw['success'] == true);
      case 'location':
        tab.url = '${raw['url'] ?? ''}';
        l.onLocation?.call(tab.url);
      case 'title':
        l.onTitle?.call('${raw['title'] ?? ''}');
      case 'history':
        l.onHistory?.call(raw['back'] == true, raw['forward'] == true);
      case 'error':
        l.onError?.call('${raw['message'] ?? ''}');
      case 'newTab':
        l.onNewTabRequested?.call('${raw['url'] ?? ''}');
      case 'external':
        l.onExternalLink?.call('${raw['url'] ?? ''}');
      case 'download':
        l.onDownloadRequested?.call('${raw['url'] ?? ''}');
      case 'fullscreen':
        l.onFullscreen?.call(raw['value'] == true);
      case 'crash':
        l.onCrashed?.call();
    }
  }

  @override
  Future<void> setSecureWindow(bool secure) async {
    await _invoke<void>('secure', {'value': secure});
  }

  @override
  Future<void> clearBrowsingData() async {
    await _invoke<void>('clearData');
  }
}

class GeckoEngineTab extends EngineTab {
  GeckoEngineTab._(this._engine, String id, bool private)
      : super(id: id, private: private);
  final GeckoBrowserEngine _engine;
  String url = '';
  bool _closed = false;

  Future<void> _call(String method, [Map<String, Object?> extra = const {}]) =>
      _closed
          ? Future<void>.value()
          : _engine._invoke<void>(method, {'tabId': id, ...extra});

  @override
  Future<void> load(String url) => _call('load', {'url': url});
  @override
  Future<void> goBack() => _call('back');
  @override
  Future<void> goForward() => _call('forward');
  @override
  Future<void> reload() => _call('reload');
  @override
  Future<void> stop() => _call('stop');
  @override
  Future<void> setDesktopMode(bool desktop) =>
      _call('desktop', {'value': desktop});
  @override
  Future<void> command(String name, [Map<String, Object?> args = const {}]) =>
      _call('command', {'name': name, 'args': args});

  @override
  Future<void> close() async {
    if (_closed) return;
    await _call('close');
    _closed = true;
    _engine._tabs.remove(id);
  }

  @override
  Widget buildView() => GeckoTabView(key: ValueKey('gecko-$id'), tabId: id);
}

/// Hosts the native GeckoView for one tab. Hybrid composition is required
/// because GeckoView renders through a SurfaceView.
class GeckoTabView extends StatelessWidget {
  const GeckoTabView({super.key, required this.tabId});
  final String tabId;
  static const viewType = 'aflaak/gecko_view';

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Center(child: Text('GeckoView is Android only'));
    }
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (params) {
        return PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: {'tabId': tabId},
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create();
      },
    );
  }
}

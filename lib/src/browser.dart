import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'library.dart';
import 'media_utils.dart';
import 'platform_bridge.dart';
import 'theme.dart';

/// Quetta-style mobile-first chrome, powered by Android WebView.
/// WebView does not offer Chrome extension APIs or complete request blocking.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.library,
    this.initialUrl,
    this.onOpenNavigation,
    this.isActive = true,
  });
  final MediaLibrary library;
  final String? initialUrl;
  final VoidCallback? onOpenNavigation;
  final bool isActive;
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserTab {
  _BrowserTab(this.controller, {this.private = false});
  final WebViewController controller;
  String url = '', title = '';
  bool loading = false, private = false;
  int progress = 0;
  bool canBack = false, canForward = false;
  bool get home => url.isEmpty || url == 'about:blank';
}

class _BrowserScreenState extends State<BrowserScreen> {
  final address = TextEditingController();
  final List<_BrowserTab> tabs = [];
  int selected = 0;
  bool reader = false;
  String? error;
  _BrowserTab get tab => tabs[selected];
  static const home = 'about:blank';

  @override
  void initState() {
    super.initState();
    _newTab(widget.initialUrl);
  }

  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  Uri _interpret(String query) {
    final value = query.trim();
    if (value.isEmpty) return Uri.parse('https://www.google.com');
    final fixed = MediaUtils.interpretAddress(value);
    if (fixed.host == 'www.google.com' && fixed.path == '/search') {
      final search = fixed.queryParameters['q'] ?? value;
      return switch (widget.library.searchEngine) {
        'DuckDuckGo' => Uri.https('duckduckgo.com', '/', {'q': search}),
        'Bing' => Uri.https('www.bing.com', '/search', {'q': search}),
        'Brave' => Uri.https('search.brave.com', '/search', {'q': search}),
        _ => fixed,
      };
    }
    return fixed;
  }

  void _newTab(String? initial, {bool private = false}) {
    late _BrowserTab created;
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white);
    if (controller.platform is AndroidWebViewController) {
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    created = _BrowserTab(controller, private: private);
    controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          final parsed = Uri.tryParse(request.url);
          if (parsed == null) return NavigationDecision.prevent;
          if (parsed.scheme == 'http') {
            // Upgrade insecure top-level navigation; do not claim all HTTPS
            // failures can be automatically repaired.
            controller.loadRequest(parsed.replace(scheme: 'https'));
            return NavigationDecision.prevent;
          }
          if (parsed.scheme != 'https' && parsed.scheme != 'about') {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageStarted: (url) {
          created.url = url;
          created.loading = true;
          if (mounted && identical(tab, created)) {
            address.text = url;
            setState(() => error = null);
          }
        },
        onProgress: (v) {
          created.progress = v;
          if (mounted && identical(tab, created)) setState(() {});
        },
        onPageFinished: (url) async {
          created.url = url;
          created.loading = false;
          created.title =
              await controller.getTitle() ?? Uri.tryParse(url)?.host ?? url;
          created.canBack = await controller.canGoBack();
          created.canForward = await controller.canGoForward();
          if (!mounted || !tabs.contains(created)) return;
          if (!created.private && url.startsWith('https://'))
            widget.library.visited(url);
          if (mounted && identical(tab, created)) {
            address.text = url;
            setState(() => error = null);
            if (widget.library.enhancedDark) await _injectDark(controller);
          }
        },
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted && identical(tab, created)) {
            setState(() {
              error = e.description;
              created.loading = false;
            });
          }
        },
      ),
    );
    tabs.add(created);
    selected = tabs.length - 1;
    address.text = '';
    if (mounted) setState(() {});
    if (initial != null && initial.isNotEmpty && initial != home) {
      _go(initial);
    }
  }

  void _go(String input) {
    final parsed = _interpret(input);
    if (parsed.scheme != 'https') return;
    FocusScope.of(context).unfocus();
    reader = false;
    tab.url = parsed.toString();
    tab.controller.loadRequest(parsed);
    address.text = parsed.toString();
    if (mounted) setState(() {});
  }

  void _switch(int index) {
    if (index < 0 || index >= tabs.length) return;
    setState(() {
      selected = index;
      reader = false;
      error = null;
      address.text = tab.home ? '' : tab.url;
    });
  }

  void _close(int index) {
    if (tabs.length == 1) {
      tabs.clear();
      selected = 0;
      _newTab(null);
      return;
    }
    tabs.removeAt(index);
    if (index < selected) selected--;
    if (selected >= tabs.length) selected = tabs.length - 1;
    if (mounted) setState(() => address.text = tab.home ? '' : tab.url);
  }

  Future<void> _back() async {
    if (tab.home) return;
    if (await tab.controller.canGoBack()) {
      await tab.controller.goBack();
    } else {
      _returnHome();
    }
  }

  void _returnHome() {
    reader = false;
    error = null;
    tab.url = home;
    tab.title = '';
    tab.canBack = false;
    tab.canForward = false;
    address.clear();
    tab.controller.loadRequest(Uri.parse(home));
    setState(() {});
  }

  Future<void> _forward() async {
    if (!tab.home && await tab.controller.canGoForward()) {
      await tab.controller.goForward();
    }
  }

  void _refresh() {
    if (tab.home) return;
    if (tab.loading) {
      tab.controller.runJavaScript('window.stop()');
    } else {
      tab.controller.reload();
    }
  }

  Future<void> _injectDark(WebViewController web) async {
    try {
      await web.runJavaScript(r'''(function(){
        if(document.getElementById('ibetoo-dark-overlay'))return;
        const style=document.createElement('style');
        style.id='ibetoo-dark-overlay';
        style.textContent='html{filter:invert(0.88) hue-rotate(180deg)!important} img,video,canvas,svg{filter:invert(1) hue-rotate(180deg)!important}';
        document.head.appendChild(style);
      })();''');
    } catch (_) {}
  }

  Future<void> _reader() async {
    if (tab.home) return;
    try {
      if (reader) {
        await tab.controller.reload();
        reader = false;
      } else {
        await tab.controller.runJavaScript(r'''(function(){
          let article=document.querySelector('article')||
            document.querySelector('main')||document.body;
          let clone=article.cloneNode(true);
          clone.querySelectorAll('script,style,nav,aside,header,footer,iframe,button,form').forEach(e=>e.remove());
          document.body.innerHTML='';
          document.body.style.cssText='margin:0;padding:22px;max-width:800px;margin:auto;font-family:system-ui;font-size:19px;line-height:1.8;background:#fff;color:#232323';
          document.body.appendChild(clone);
        })();''');
        reader = true;
      }
      if (mounted) setState(() {});
    } catch (e) {
      _notice('الموقع لا يدعم وضع القراءة: $e');
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message, maxLines: 3)));
  }

  Future<void> _openExternal() async {
    if (tab.home) return;
    await launchUrl(Uri.parse(tab.url), mode: LaunchMode.externalApplication);
  }

  void _showTabs() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .73,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      'علامات التبويب',
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'تبويب خاص',
                      onPressed: () {
                        Navigator.pop(ctx);
                        _newTab(null, private: true);
                      },
                      icon: const Icon(Icons.visibility_off_outlined),
                    ),
                    IconButton(
                      tooltip: 'تبويب جديد',
                      onPressed: () {
                        Navigator.pop(ctx);
                        _newTab(null);
                      },
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: tabs.length,
                    itemBuilder: (context, i) => Card(
                      child: ListTile(
                        selected: i == selected,
                        leading: Icon(
                          tabs[i].private
                              ? Icons.visibility_off_outlined
                              : Icons.language,
                          color: MediaPalette.orange,
                        ),
                        title: Text(
                          tabs[i].title.isEmpty ? 'تبويب جديد' : tabs[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          tabs[i].private ? 'لا يُسجّل في السجل' : tabs[i].url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _close(i);
                            Navigator.pop(ctx);
                          },
                        ),
                        onTap: () {
                          _switch(i);
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                  ),
                ),
                if (tabs.any((t) => t.private))
                  const Text(
                    'التبويب الخاص لا يُضاف لسجل التطبيق. WebView يشارك '
                    'بيانات الجلسة مع التبويبات الأخرى، لذلك ليس عزلاً كاملًا.',
                    style: TextStyle(fontSize: 11),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _homePage() {
    final marks = widget.library.bookmarks;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 38, 18, 35),
      children: [
        Center(
          child: Column(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xff3478f6), Color(0xff2053c6)],
                  ),
                ),
                child: const Icon(
                  Icons.explore_outlined,
                  color: Colors.white,
                  size: 37,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'iBetoo Browser',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 5),
              const Text(
                'تصفح خفيف، واضح، وتحت تحكمك.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        TextField(
          onSubmitted: _go,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'ابحث أو اكتب عنوان الموقع',
            suffixIcon: Icon(Icons.arrow_back_rounded),
          ),
        ),
        const SizedBox(height: 28),
        Text('وصول سريع', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 11,
          runSpacing: 11,
          children: [
            _shortcut('Google', Icons.search_rounded, 'https://www.google.com'),
            _shortcut(
              'YouTube',
              Icons.play_circle_fill_rounded,
              'https://m.youtube.com',
            ),
            _shortcut(
              'Wikipedia',
              Icons.menu_book_rounded,
              'https://ar.wikipedia.org',
            ),
            _shortcut(
              'ChatGPT',
              Icons.auto_awesome_rounded,
              'https://chatgpt.com',
            ),
            _shortcut(
              'Gemini',
              Icons.auto_awesome_outlined,
              'https://gemini.google.com',
            ),
            _shortcut(
              'WhatsApp',
              Icons.chat_outlined,
              'https://web.whatsapp.com',
            ),
            _shortcut('GitHub', Icons.code_rounded, 'https://github.com'),
            _shortcut(
              'Telegram',
              Icons.send_rounded,
              'https://web.telegram.org',
            ),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Text('المفضلة', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            TextButton(
              onPressed: _favoritesSheet,
              child: const Text('عرض الكل'),
            ),
          ],
        ),
        if (marks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text('اضغط على النجمة أثناء التصفح لإضافة موقع.'),
          )
        else
          for (final url in marks.take(7))
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.bookmark_outline,
                color: MediaPalette.orange,
              ),
              title: Text(Uri.tryParse(url)?.host ?? url),
              subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _go(url),
            ),
        const SizedBox(height: 20),
        Text('آخر الصفحات', style: Theme.of(context).textTheme.titleLarge),
        for (final url in widget.library.history.take(5))
          ListTile(
            dense: true,
            leading: const Icon(Icons.history),
            title: Text(Uri.tryParse(url)?.host ?? url),
            onTap: () => _go(url),
          ),
      ],
    );
  }

  Widget _shortcut(String label, IconData symbol, String url) => InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: () => _go(url),
    child: Container(
      width: ((MediaQuery.sizeOf(context).width - 58) / 3)
          .clamp(86, 116)
          .toDouble(),
      height: 97,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(symbol, size: 27, color: MediaPalette.orange),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
  void _favoritesSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('مواقعك المحفوظة', style: Theme.of(ctx).textTheme.titleLarge),
            for (final site in widget.library.bookmarks)
              ListTile(
                title: Text(site, maxLines: 1, overflow: TextOverflow.ellipsis),
                leading: const Icon(Icons.bookmark, color: MediaPalette.orange),
                onTap: () {
                  Navigator.pop(ctx);
                  _go(site);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    widget.library.toggleBookmark(site);
                    Navigator.pop(ctx);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showHistory() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Text('السجل', style: Theme.of(ctx).textTheme.titleLarge),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    widget.library.clearHistory();
                    Navigator.pop(ctx);
                  },
                  child: const Text('مسح السجل'),
                ),
              ],
            ),
            for (final site in widget.library.history)
              ListTile(
                title: Text(site, maxLines: 2),
                leading: const Icon(Icons.history),
                onTap: () {
                  Navigator.pop(ctx);
                  _go(site);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadDirectUrl() async {
    final input = TextEditingController(text: tab.home ? '' : tab.url);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تنزيل ملف مباشر'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.url,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(
            hintText: 'https://example.com/file.pdf',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input.text.trim()),
            child: const Text('تنزيل'),
          ),
        ],
      ),
    );
    input.dispose();
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      _notice('أدخل رابط HTTPS مباشر لملف مسموح بتنزيله');
      return;
    }
    try {
      final id = await PlatformMediaBridge.downloadUrl(url);
      _notice(id >= 0 ? 'بدأ التنزيل في مجلد Downloads' : 'تعذر بدء التنزيل');
    } catch (e) {
      _notice('تعذر تنزيل الرابط: $e');
    }
  }

  void _menu() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: .84,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
            children: [
              if (widget.onOpenNavigation != null)
                ListTile(
                  leading: const Icon(Icons.apps_rounded),
                  title: const Text('أقسام التطبيق'),
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onOpenNavigation!();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('الصفحة الرئيسية'),
                onTap: () {
                  Navigator.pop(ctx);
                  _returnHome();
                },
              ),
              if (!tab.home)
                ListTile(
                  leading: const Icon(Icons.arrow_forward_rounded),
                  title: const Text('الصفحة التالية'),
                  enabled: tab.canForward,
                  onTap: () {
                    Navigator.pop(ctx);
                    _forward();
                  },
                ),
              if (!tab.home)
                ListTile(
                  leading: Icon(
                    widget.library.starred(tab.url)
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                  ),
                  title: Text(
                    widget.library.starred(tab.url)
                        ? 'إزالة من المفضلة'
                        : 'أضف للمفضلة',
                  ),
                  onTap: () {
                    widget.library.toggleBookmark(tab.url);
                    Navigator.pop(ctx);
                    setState(() {});
                  },
                ),
              if (!tab.home)
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('نسخ رابط الصفحة'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: tab.url));
                    Navigator.pop(ctx);
                    _notice('تم نسخ الرابط');
                  },
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('تبويب جديد'),
                onTap: () {
                  Navigator.pop(ctx);
                  _newTab(null);
                },
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('تبويب بدون سجل محلي'),
                onTap: () {
                  Navigator.pop(ctx);
                  _newTab(null, private: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmarks_outlined),
                title: const Text('المفضلة'),
                onTap: () {
                  Navigator.pop(ctx);
                  _favoritesSheet();
                },
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('سجل التصفح'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showHistory();
                },
              ),
              ListTile(
                leading: const Icon(Icons.chrome_reader_mode_outlined),
                title: Text(reader ? 'إغلاق وضع القراءة' : 'وضع القراءة'),
                onTap: () {
                  Navigator.pop(ctx);
                  _reader();
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text('تنزيل ملف من رابط مباشر'),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadDirectUrl();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open_rounded),
                title: const Text('ملفات التنزيل'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await PlatformMediaBridge.openDownloads();
                  } catch (e) {
                    _notice('تعذر فتح التنزيلات: $e');
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.open_in_browser),
                title: const Text('فتح بمتصفح الجهاز'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openExternal();
                },
              ),
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const Text('الوضع الليلي للتطبيق'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.library.setTheme(!widget.library.darkMode);
                },
              ),
              SwitchListTile.adaptive(
                title: const Text('تظليل صفحات الويب'),
                subtitle: const Text('تجريبي وقد يؤثر على بعض الصور'),
                value: widget.library.enhancedDark,
                onChanged: (v) {
                  widget.library.setEnhancedDark(v);
                  Navigator.pop(ctx);
                  tab.controller.reload();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editAddress() {
    address.text = tab.home ? '' : tab.url;
    address.selection = TextSelection(
      baseOffset: 0,
      extentOffset: address.text.length,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(sheet).bottom + 16,
        ),
        child: TextField(
          controller: address,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(
            hintText: 'ابحث أو اكتب عنوان الموقع',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'انتقال',
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: () {
                Navigator.pop(sheet);
                _go(address.text);
              },
            ),
          ),
          onSubmitted: (value) {
            Navigator.pop(sheet);
            _go(value);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = tab;
    return PopScope(
      canPop: !widget.isActive || current.home,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.isActive && !current.home) _back();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    IndexedStack(
                      index: selected,
                      children: [
                        for (final item in tabs)
                          KeyedSubtree(
                            key: ObjectKey(item),
                            child: item.home
                                ? _homePage()
                                : WebViewWidget(controller: item.controller),
                          ),
                      ],
                    ),
                    if (current.loading)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: current.progress / 100,
                          color: MediaPalette.orange,
                          minHeight: 2,
                        ),
                      ),
                    if (error != null && !current.home)
                      Positioned(
                        top: 12,
                        left: 12,
                        right: 12,
                        child: Card(
                          child: ListTile(
                            leading: const Icon(Icons.wifi_off_rounded),
                            title: const Text('تعذّر فتح الصفحة'),
                            subtitle: Text(
                              error!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              tooltip: 'إعادة المحاولة',
                              icon: const Icon(Icons.refresh),
                              onPressed: current.controller.reload,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Material(
          key: const ValueKey('browser-toolbar'),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'أقسام التطبيق',
                    onPressed: widget.onOpenNavigation,
                    icon: const Icon(Icons.apps_rounded, size: 23),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: _editAddress,
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        height: 44,
                        padding: const EdgeInsetsDirectional.only(
                          start: 12,
                          end: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              current.private
                                  ? Icons.visibility_off_outlined
                                  : current.home
                                  ? Icons.search_rounded
                                  : Icons.lock_outline_rounded,
                              size: 16,
                              color: MediaPalette.orange,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                current.home
                                    ? 'بحث أو عنوان الموقع'
                                    : Uri.tryParse(current.url)?.host ??
                                          current.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            if (!current.home)
                              IconButton(
                                tooltip: current.loading
                                    ? 'إيقاف التحميل'
                                    : 'تحديث الصفحة',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  current.loading
                                      ? Icons.close_rounded
                                      : Icons.refresh_rounded,
                                  size: 19,
                                ),
                                onPressed: _refresh,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'رجوع للصفحة السابقة',
                    onPressed: current.home ? null : _back,
                    icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  ),
                  IconButton(
                    tooltip: 'علامات التبويب',
                    onPressed: _showTabs,
                    icon: Container(
                      width: 25,
                      height: 25,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.onSurface,
                          width: 1.6,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${tabs.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'قائمة المتصفح',
                    onPressed: _menu,
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

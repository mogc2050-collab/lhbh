import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';

import 'browser.dart';
import 'device_media.dart';
import 'library.dart';
import 'media_collection_screen.dart';
import 'player.dart';
import 'permission_panel.dart';
import 'theme.dart';

class MediaShell extends StatefulWidget {
  const MediaShell({super.key, required this.library, required this.music});
  final MediaLibrary library;
  final BackgroundMusic music;
  @override
  State<MediaShell> createState() => _MediaShellState();
}

class _MediaShellState extends State<MediaShell> with WidgetsBindingObserver {
  int selected = 0;
  final phone = PhoneLibrary();
  final auth = LocalAuthentication();
  GoogleSignInAccount? account;
  bool googleReady = false, googleBusy = false, locked = false;
  bool _authenticating = false;
  static const googleClient = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  @override
  void initState() {
    super.initState();
    locked = widget.library.appLock;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        phone.refresh();
        if (widget.library.appLock) _unlock();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && widget.library.appLock) {
      if (mounted) setState(() => locked = true);
    }
    if (state == AppLifecycleState.resumed && locked) {
      _unlock();
    }
    if (state == AppLifecycleState.resumed) phone.refresh();
  }

  Future<void> _unlock() async {
    if (!mounted || _authenticating) return;
    _authenticating = true;
    setState(() => locked = true);
    try {
      final ok = await auth.authenticate(
        localizedReason: 'افتح مكتبة iBetoo Media الخاصة بك',
        biometricOnly: false,
      );
      if (ok && mounted) setState(() => locked = false);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر التحقق من الهوية: $e')));
    } finally {
      _authenticating = false;
    }
  }

  Future<void> _toggleLock(bool enabled) async {
    if (!enabled) {
      widget.library.setAppLock(false);
      return;
    }
    try {
      final enabled = await auth.isDeviceSupported();
      if (!enabled) throw StateError('الجهاز لا يدعم حماية الهوية');
      final ok = await auth.authenticate(
        localizedReason: 'فعّل قفل iBetoo Media بالبصمة أو رمز جهازك',
        biometricOnly: false,
      );
      if (ok) widget.library.setAppLock(true);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('لم يتم تفعيل القفل: $e')));
    }
  }

  Future<void> _googleLogin() async {
    if (googleClient.isEmpty) {
      _snack('Google OAuth يحتاج Client ID وبصمة توقيع APK في Google Cloud.');
      return;
    }
    setState(() => googleBusy = true);
    try {
      if (!googleReady) {
        await GoogleSignIn.instance.initialize(serverClientId: googleClient);
        googleReady = true;
      }
      final user = await GoogleSignIn.instance.authenticate();
      if (mounted) setState(() => account = user);
    } catch (e) {
      _snack('تعذر تسجيل Google: $e');
    } finally {
      if (mounted) setState(() => googleBusy = false);
    }
  }

  Future<void> _googleLogout() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    if (mounted) setState(() => account = null);
  }

  void _snack(String message) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    phone.dispose();
    super.dispose();
  }

  void _openNowPlaying() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .88,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'قيد التشغيل',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await widget.music.dismissPlayback();
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('إغلاق التشغيل'),
                  ),
                  IconButton(
                    tooltip: 'تصغير المشغل',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
            ),
            Expanded(child: AudioDetail(music: widget.music)),
          ],
        ),
      ),
    );
  }

  void _openSections() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'مساحتك',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final item in [
                    (0, 'المتصفح', Icons.language_rounded),
                    (1, 'المكتبة', Icons.perm_media_outlined),
                    (2, 'الإعدادات', Icons.tune_rounded),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Semantics(
                          selected: selected == item.$1,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              Navigator.pop(sheet);
                              setState(() => selected = item.$1);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 22),
                              decoration: BoxDecoration(
                                color: selected == item.$1
                                    ? MediaPalette.orange.withValues(alpha: .13)
                                    : Theme.of(
                                        sheet,
                                      ).colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    item.$3,
                                    size: 28,
                                    color: MediaPalette.orange,
                                  ),
                                  const SizedBox(height: 9),
                                  Text(item.$2),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              MiniMusic(
                music: widget.music,
                open: () {
                  Navigator.pop(sheet);
                  _openNowPlaying();
                },
              ),
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: const Text('الأذونات والإشعارات'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () {
                  Navigator.pop(sheet);
                  showPermissionPanel(context, phone);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !locked && selected == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !locked && selected != 0) setState(() => selected = 0);
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: selected,
              children: [
                BrowserScreen(
                  library: widget.library,
                  isActive: selected == 0 && !locked,
                  onOpenNavigation: _openSections,
                ),
                MediaCollectionScreen(
                  phone: phone,
                  library: widget.library,
                  music: widget.music,
                  onOpenNavigation: _openSections,
                ),
                _MediaSettings(
                  library: widget.library,
                  phone: phone,
                  music: widget.music,
                  account: account,
                  onLogin: _googleLogin,
                  onLogout: _googleLogout,
                  googleBusy: googleBusy,
                  onLockChange: _toggleLock,
                  onOpenNavigation: _openSections,
                ),
              ],
            ),
            if (locked)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.lock_outline,
                          size: 72,
                          color: MediaPalette.orange,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'مكتبتك محمية',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _unlock,
                          icon: const Icon(Icons.fingerprint),
                          label: const Text('فتح القفل'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: locked || selected == 0
            ? null
            : AnimatedBuilder(
                animation: widget.music,
                builder: (context, _) => widget.music.currentTitle == null
                    ? const SizedBox.shrink()
                    : SafeArea(
                        top: false,
                        child: MiniMusic(
                          music: widget.music,
                          open: _openNowPlaying,
                        ),
                      ),
              ),
      ),
    );
  }
}

class _MediaSettings extends StatelessWidget {
  const _MediaSettings({
    required this.library,
    required this.phone,
    required this.music,
    required this.account,
    required this.onLogin,
    required this.onLogout,
    required this.googleBusy,
    required this.onLockChange,
    this.onOpenNavigation,
  });
  final MediaLibrary library;
  final PhoneLibrary phone;
  final BackgroundMusic music;
  final GoogleSignInAccount? account;
  final VoidCallback onLogin, onLogout;
  final bool googleBusy;
  final Future<void> Function(bool) onLockChange;
  final VoidCallback? onOpenNavigation;

  void _notice(BuildContext ctx, String message) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export(BuildContext context) async {
    try {
      await library.exportToUser();
      if (context.mounted)
        _notice(context, 'تم فتح نافذة حفظ النسخة الاحتياطية');
    } catch (e) {
      if (context.mounted) _notice(context, 'تعذر تصدير النسخة: $e');
    }
  }

  Future<void> _restore(BuildContext context) async {
    try {
      await library.importFromUser();
      if (context.mounted)
        _notice(context, 'تم استعادة إعدادات المكتبة والقوائم');
    } catch (e) {
      if (context.mounted) _notice(context, 'تعذر استعادة النسخة: $e');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: library,
    builder: (ctx, _) => Scaffold(
      appBar: AppBar(
        title: const Text('الإعدادات والخصوصية'),
        leading: IconButton(
          tooltip: 'أقسام التطبيق',
          onPressed: onOpenNavigation,
          icon: const Icon(Icons.apps_rounded),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 45),
        children: [
          _header('المظهر'),
          SwitchListTile.adaptive(
            title: const Text('الوضع الليلي'),
            secondary: const Icon(Icons.dark_mode_outlined),
            value: library.darkMode,
            onChanged: library.setTheme,
          ),
          SwitchListTile.adaptive(
            title: const Text('تظليل مواقع الويب'),
            subtitle: const Text('تجريبي، وقد يؤثر على مظهر الصور'),
            secondary: const Icon(Icons.contrast),
            value: library.enhancedDark,
            onChanged: library.setEnhancedDark,
          ),
          _header('المتصفح'),
          ListTile(
            title: const Text('محرك البحث'),
            subtitle: Text(library.searchEngine),
            trailing: DropdownButton<String>(
              value: library.searchEngine,
              underline: const SizedBox.shrink(),
              items: const [
                'Google',
                'DuckDuckGo',
                'Bing',
                'Brave',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) {
                if (v != null) library.setSearchEngine(v);
              },
            ),
          ),
          ListTile(
            title: const Text('مسح سجل تصفح التطبيق'),
            leading: const Icon(Icons.history),
            trailing: const Icon(Icons.delete_outline),
            onTap: () {
              library.clearHistory();
              _notice(context, 'تم مسح السجل');
            },
          ),
          _header('ملفات الجهاز'),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('صلاحيات الصوت والفيديو والصور'),
            subtitle: Text(
              'صوت ${phone.audioGranted ? "✓" : "×"} • '
              'فيديو ${phone.videoGranted ? "✓" : "×"} • '
              'صور ${phone.imageGranted ? "✓" : "×"}',
            ),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => showPermissionPanel(context, phone),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('إشعارات تشغيل الوسائط'),
            subtitle: Text(
              phone.notificationsGranted ? 'مفعّلة' : 'تحتاج إذنًا',
            ),
            onTap: () => showPermissionPanel(context, phone),
          ),
          _header('الصوت والفيديو'),
          ListTile(
            title: const Text('معادل الصوت Equalizer'),
            subtitle: Text(library.eqPreset),
            trailing: DropdownButton<String>(
              value: library.eqPreset,
              underline: const SizedBox.shrink(),
              items: const [
                'طبيعي',
                'Bass',
                'Rock',
                'صوت بشري',
                'Cinema',
                'مخصص',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) async {
                if (v == null) return;
                try {
                  await music.setEqualizer(v);
                } catch (e) {
                  if (context.mounted)
                    _notice(context, 'المعادل غير مدعوم على هذا الجهاز: $e');
                }
              },
            ),
          ),
          ListTile(
            title: const Text('سرعة تشغيل الصوت'),
            subtitle: Text('${library.musicSpeed.toStringAsFixed(2)}×'),
          ),
          Slider(
            value: library.musicSpeed,
            min: .5,
            max: 3,
            divisions: 10,
            onChanged: (v) => music.setSpeed(v),
          ),
          ListTile(
            title: const Text('حجم نص الترجمة'),
            subtitle: Text('${library.subtitleSize.round()} نقطة'),
          ),
          Slider(
            value: library.subtitleSize,
            min: 12,
            max: 36,
            divisions: 12,
            onChanged: library.setSubtitleSize,
          ),
          ListTile(
            title: const Text('مؤقت النوم'),
            subtitle: Text(
              library.sleepMinutes == 0
                  ? 'غير مفعل'
                  : '${library.sleepMinutes} دقيقة',
            ),
            trailing: DropdownButton<int>(
              value: library.sleepMinutes,
              underline: const SizedBox.shrink(),
              items: const [0, 15, 30, 45, 60, 90, 120]
                  .map(
                    (v) => DropdownMenuItem(
                      value: v,
                      child: Text(v == 0 ? 'إيقاف' : '$v د'),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) music.setSleepTimer(v);
              },
            ),
          ),
          _header('الخصوصية والحماية'),
          SwitchListTile.adaptive(
            title: const Text('قفل التطبيق'),
            subtitle: const Text('بصمة أو رمز قفل الجهاز عند الرجوع للتطبيق'),
            value: library.appLock,
            secondary: const Icon(Icons.fingerprint),
            onChanged: onLockChange,
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('تصدير بيانات المكتبة'),
            subtitle: const Text(
              'القوائم والمفضلة والتقدم والإعدادات، بدون نسخ الوسائط نفسها',
            ),
            onTap: () => _export(context),
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('استيراد نسخة احتياطية'),
            onTap: () => _restore(context),
          ),
          _header('حساب Google'),
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text(account?.displayName ?? 'تسجيل الدخول'),
            subtitle: Text(
              account?.email ?? 'يتطلب OAuth مُعدًا في Google Cloud',
            ),
            trailing: googleBusy
                ? const CircularProgressIndicator()
                : Icon(account == null ? Icons.login : Icons.logout),
            onTap: googleBusy
                ? null
                : account == null
                ? onLogin
                : onLogout,
          ),
          const SizedBox(height: 15),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'iBetoo Media يدعم تنزيل روابط الملفات المباشرة عبر أندرويد. المتصفح يستخدم '
              'Android WebView، ولا يدّعي دعم إضافات Chrome أو الحظر الكامل '
              'لمتتبعات المواقع. كل قوائم الوسائط محفوظة على الجهاز.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, height: 1.6, fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
  Widget _header(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 18, 8, 9),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w900,
        color: MediaPalette.orange,
      ),
    ),
  );
}

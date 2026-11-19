import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../game/catalog.dart';
import '../game/game_state.dart';
import 'game_theme.dart';
import 'world_painter.dart';

class GameScreen extends StatefulWidget {
  final GameState game;
  const GameScreen({super.key, required this.game});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  late final GameState g;
  final TransformationController camera = TransformationController();
  final List<Timer> timers = [];
  bool cameraReady = false;
  bool showIntro = true;
  bool showGuide = true;
  int? selectedX, selectedY;
  BuildingType? pendingBuild;

  @override
  void initState() {
    super.initState();
    g = widget.game;
    g.addListener(_refresh);
    WidgetsBinding.instance.addObserver(this);
    timers.add(Timer.periodic(const Duration(seconds: 1), (_) => g.advance()));
    timers.add(Timer.periodic(const Duration(milliseconds: 260), (_) => g.stepWalk()));
    timers.add(Timer.periodic(const Duration(seconds: 15), (_) => g.save()));
  }

  void _refresh() { if (mounted) setState(() {}); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) g.save();
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final t in timers) { t.cancel(); }
    g.removeListener(_refresh);
    g.save();
    camera.dispose();
    super.dispose();
  }

  void message(GameAction result) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: result.ok ? const Color(0xff315d3a) : const Color(0xff813b35),
      content: Text(result.message, textAlign: TextAlign.center),
      duration: const Duration(seconds: 2),
    ));
    if (result.ok) {
      g.save();
      if (g.soundOn) SystemSound.play(SystemSoundType.click);
    }
  }

  void worldTap(TapUpDetails details) {
    if (showIntro) return;
    final tile = VillagePainter.tileFrom(details.localPosition);
    final x = tile.x, y = tile.y;
    if (!g.inside(x, y)) return;
    setState(() { selectedX = x; selectedY = y; });
    if (pendingBuild != null) {
      final result = g.build(pendingBuild!, x, y);
      message(result);
      if (result.ok) setState(() => pendingBuild = null);
      return;
    }
    final b = g.buildingAt(x, y);
    if (b != null) {
      buildingSheet(b);
    } else {
      final result = g.walkTo(x, y);
      if (!result.ok) message(result);
    }
  }

  void sheet(String title, IconData icon, Widget Function(BuildContext) content, {double height = .77}) {
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * height,
          child: GPanel(padding: const EdgeInsets.all(11), child: Column(children: [
            Row(children: [
              Icon(icon, color: GameColors.gold), const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: GameColors.paleGold))),
              IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close_rounded)),
            ]),
            const Divider(color: Color(0xff947449)),
            Expanded(child: AnimatedBuilder(
              animation: g,
              builder: (context, _) => SingleChildScrollView(physics: const BouncingScrollPhysics(), child: content(context)),
            )),
          ])),
        ),
      )),
    );
  }

  Widget resourceLabel(Resource r, {bool large = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 9 : 7, vertical: large ? 8 : 5),
      decoration: BoxDecoration(color: const Color(0xee332a20), borderRadius: BorderRadius.circular(12), border: Border.all(color: GameColors.gold.withValues(alpha: .38))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(r.icon, size: large ? 21 : 17, color: r.color), const SizedBox(width: 5),
        Text('${g.count(r)}', style: TextStyle(fontSize: large ? 14 : 12, fontWeight: FontWeight.w900, color: Colors.white)),
        if (large) ...[const SizedBox(width: 3), Text(r.label, style: const TextStyle(fontSize: 11, color: GameColors.muted))],
      ]),
    ),
  );

  Widget playerStatus() => GPanel(padding: const EdgeInsets.all(9), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 16), SizedBox(width: 4), Text('حالة البطل', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900))]),
    ...['الجوع', 'العطش', 'الطاقة'].map((v) {
      final color = v == 'الطاقة' ? const Color(0xffffd266) : v == 'العطش' ? const Color(0xff76cdef) : const Color(0xff7bd583);
      return Padding(padding: const EdgeInsets.only(top: 6), child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 36, child: Text(v, style: const TextStyle(fontSize: 10))),
        SizedBox(width: 56, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: LinearProgressIndicator(value: g.needs[v]! / 100, minHeight: 7, color: color, backgroundColor: Colors.black38))),
        const SizedBox(width: 4), Text('${g.needs[v]!.round()}', style: const TextStyle(fontSize: 9)),
      ]));
    }),
  ]));

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: LayoutBuilder(builder: (context, viewport) {
      final size = Size(viewport.maxWidth, viewport.maxHeight);
      if (!cameraReady && size.width > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || cameraReady) return;
          const scale = .92;
          final point = VillagePainter.center(5, 5);
          camera.value = Matrix4.identity()
            ..translate(size.width / 2 - point.dx * scale, size.height * .54 - point.dy * scale)
            ..scale(scale);
          cameraReady = true;
        });
      }
      return Stack(children: [
        Positioned.fill(child: ClipRect(child: InteractiveViewer(
          transformationController: camera,
          boundaryMargin: const EdgeInsets.all(350),
          constrained: false,
          minScale: .45, maxScale: 2.3,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: worldTap,
            child: CustomPaint(size: VillagePainter.sceneSize,
              painter: VillagePainter(g, selectedX: selectedX, selectedY: selectedY, buildMode: pendingBuild != null)),
          ),
        ))),
        Positioned(left: 0, right: 0, top: 0, child: SafeArea(bottom: false, child: Column(children: [
          Container(color: const Color(0xcc201b17), height: 46, child: ListView(
            scrollDirection: Axis.horizontal,
            children: [for (final r in Resource.values) Center(child: resourceLabel(r))],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xee34261e), Color(0xaa22241e)])),
            child: Row(children: [
              const Icon(Icons.shield_rounded, size: 23, color: GameColors.gold),
              const SizedBox(width: 7),
              const Expanded(child: Text('ممالك الحياة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: GameColors.paleGold))),
              InkWell(onTap: questsSheet, child: const Icon(Icons.assignment_rounded, color: GameColors.paleGold, size: 22)),
              const SizedBox(width: 12),
              Column(children: [Text('اليوم ${g.day} • ${g.season}', style: const TextStyle(fontSize: 11)),
                Text(g.timeLabel, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: GameColors.gold))]),
              IconButton(icon: Icon(g.paused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: GameColors.paleGold), onPressed: g.togglePause),
              InkWell(onTap: g.cycleSpeed, child: Text('×${g.speed}', style: const TextStyle(fontSize: 17, color: GameColors.gold, fontWeight: FontWeight.w900))),
            ]),
          ),
        ]))),
        Positioned(top: 124, right: 8, child: SafeArea(child: playerStatus())),
        Positioned(left: 8, top: 128, child: SafeArea(child: Column(children: [
          _round(Icons.map_rounded, 'مركز', () { final p = VillagePainter.center(g.px, g.py); camera.value = Matrix4.identity()..translate(size.width / 2 - p.dx * .95, size.height * .52 - p.dy * .95)..scale(.95); }),
          const SizedBox(height: 8),
          _round(Icons.assignment_rounded, 'مهام', questsSheet),
          const SizedBox(height: 8),
          _round(Icons.bar_chart_rounded, 'اقتصاد', economySheet),
        ]))),
        if (pendingBuild != null) Positioned(left: 9, right: 9, bottom: 177, child: GPanel(
          color: const Color(0xff244c33), padding: const EdgeInsets.all(10),
          child: Row(children: [
            const Icon(Icons.touch_app_rounded, color: GameColors.paleGold), const SizedBox(width: 6),
            Expanded(child: Text('المس مكانًا فارغًا لبناء ${pendingBuild!.spec.name}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => setState(() => pendingBuild = null), icon: const Icon(Icons.close, color: Colors.white)),
          ]))),
        Positioned(left: 0, right: 0, bottom: 102, child: SafeArea(top: false, bottom: false,
          child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(children: [
            _action(Icons.restaurant_rounded, 'كُل', 'eat'),
            _action(Icons.water_drop_rounded, 'اشرب', 'drink'),
            _action(Icons.bedtime_rounded, 'نَم', 'sleep'),
            _action(Icons.forest_rounded, 'احتطب', 'chop'),
            _action(Icons.landscape_rounded, 'استخرج', 'mine'),
            _action(Icons.handyman_rounded, 'اصنع', 'craft'),
          ])))),
        Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(top: false, child: Container(
          height: 101, decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xff513523), Color(0xff251c19)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
            border: Border(top: BorderSide(color: GameColors.gold, width: 2)),
          ),
          child: Row(children: [
            _tab(Icons.person_rounded, 'الشخصية', characterSheet),
            _tab(Icons.map_rounded, 'الخريطة', mapSheet),
            _tab(Icons.inventory_2_rounded, 'المخزن', inventorySheet),
            _tab(Icons.storefront_rounded, 'السوق', marketSheet),
            _tab(Icons.construction_rounded, 'البناء', buildSheet),
          ]),
        ))),
        if (showIntro) Positioned.fill(child: ColoredBox(color: const Color(0xe51c211e), child: SafeArea(child: Center(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(26), child: GPanel(padding: const EdgeInsets.all(22), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.castle_rounded, size: 76, color: GameColors.gold), const SizedBox(height: 10),
          const Text('ممالك الحياة', style: TextStyle(fontSize: 35, color: GameColors.paleGold, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6), const Text('ابنِ • اتجر • اعمل • عش', style: TextStyle(fontSize: 16, color: GameColors.muted)),
          const SizedBox(height: 17),
          const Text('لعبة اقتصاد وحياة من العصور الوسطى. اشترِ الأخشاب والحجر، افتح خطوط الإنتاج، ابنِ البيوت وبِع العقارات، واهتم ببقاء بطلك سعيدًا وبصحة جيدة.', textAlign: TextAlign.center, style: TextStyle(height: 1.8)),
          const SizedBox(height: 18),
          const Text('✓ تعمل بدون إنترنت\n✓ حفظ تلقائي للتقدم\n✓ اقتصاد محلي وأسعار متغيرة\n✓ تحكم باللمس وتحريك الخريطة', textAlign: TextAlign.center, style: TextStyle(color: GameColors.green, height: 1.8)),
          const SizedBox(height: 22),
          SizedBox(width: double.infinity, child: GButton(text: g.loadedFromDisk ? 'متابعة مملكتك' : 'ابدأ مغامرتك', icon: Icons.play_arrow_rounded, primary: true, onPressed: () => setState(() => showIntro = false))),
        ])))))))),
      ]);
    }));
  }

  Widget _round(IconData icon, String label, VoidCallback action) => InkWell(onTap: action, child: Container(
    width: 48, height: 52, margin: const EdgeInsets.only(bottom: 2),
    decoration: BoxDecoration(color: const Color(0xdd3c2a1f), border: Border.all(color: GameColors.gold), borderRadius: BorderRadius.circular(17)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 21, color: GameColors.paleGold), Text(label, style: const TextStyle(fontSize: 9))]),
  ));
  Widget _action(IconData icon, String title, String id) => Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: GButton(text: title, icon: icon, onPressed: () => message(g.act(id))));
  Widget _tab(IconData icon, String title, VoidCallback action) => Expanded(child: InkWell(onTap: action, child: Container(
    margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
    decoration: BoxDecoration(color: const Color(0xff3c2c23), borderRadius: BorderRadius.circular(13), border: Border.all(color: const Color(0xff8b6d48))),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(icon, size: 29, color: GameColors.gold), const SizedBox(height: 4),
      Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900), maxLines: 1),
    ]),
  )));

  Widget costView(Map<Resource, int> cost) => Wrap(spacing: 7, runSpacing: 7, children: [
    for (final e in cost.entries) Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(e.key.icon, size: 14, color: g.count(e.key) >= e.value ? GameColors.green : Colors.redAccent), const SizedBox(width: 4), Text('${e.value}/${g.count(e.key)}', style: const TextStyle(fontSize: 11))]),
    ),
  ]);

  void buildSheet() {
    sheet('البناء والتطوير', Icons.construction_rounded, (_) => Column(children: [
      const Text('اختَر مبنى، ثم اضغط على مساحة خالية بالخريطة لوضعه. المباني تحتاج ذهبًا وموادًا حقيقية من مخزنك.', style: TextStyle(fontSize: 12, height: 1.6, color: GameColors.muted)),
      const SizedBox(height: 10),
      for (final type in BuildingType.values) Padding(padding: const EdgeInsets.only(bottom: 9), child: GPanel(color: const Color(0xff4d3427), padding: const EdgeInsets.all(10), child: Column(children: [
        Row(children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xff756043), borderRadius: BorderRadius.circular(11)), child: Icon(type.spec.icon, color: GameColors.paleGold, size: 29)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(type.spec.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), Text(type.spec.description, style: const TextStyle(color: GameColors.muted, fontSize: 11))])),
          const SizedBox(width: 5),
          GButton(text: 'اختيار', icon: Icons.add_rounded, primary: g.canAfford(g.buildingCost(type)), onPressed: () {
            setState(() { pendingBuild = type; selectedX = null; selectedY = null; });
            Navigator.of(context).pop();
          }),
        ]),
        const SizedBox(height: 8),
        costView(g.buildingCost(type)),
      ]))),
    ]), height: .81);
  }

  void buildingSheet(Building b) {
    sheet(b.type.spec.name, b.type.spec.icon, (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      Center(child: Icon(b.type.spec.icon, size: 82, color: GameColors.gold)),
      const SizedBox(height: 8),
      Center(child: Text('${b.type.spec.name} • المستوى ${b.level}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24))),
      Center(child: Text(b.type.spec.description, textAlign: TextAlign.center, style: const TextStyle(color: GameColors.muted))),
      const SizedBox(height: 24),
      const SectionTitle('متطلبات التطوير', Icons.upgrade_rounded),
      const SizedBox(height: 10),
      if (b.level == 5) const Text('المبنى بالفعل في المستوى الخامس، وهو المستوى الأقصى.'),
      if (b.level < 5) ...[
        costView(g.buildingCost(b.type, upgradeLevel: b.level + 1)),
        const SizedBox(height: 12),
        GButton(text: 'ترقية إلى المستوى ${b.level + 1}', icon: Icons.arrow_upward_rounded, primary: true, onPressed: () {
          message(g.upgrade(b));
          if (mounted) Navigator.of(context).pop();
        }),
      ],
      const SizedBox(height: 24),
      const SectionTitle('سوق العقارات', Icons.real_estate_agent_rounded),
      const SizedBox(height: 9),
      Text('قيمة بيع المبنى الحالية: ${g.saleValue(b)} قطعة ذهب. بعد البيع سيختفي المبنى ويُخصم إنتاجه من اقتصادك.'),
      const SizedBox(height: 9),
      GButton(text: 'بيع العقار مقابل ${g.saleValue(b)} ذهب', icon: Icons.sell_rounded, onPressed: () {
        showDialog<void>(context: context, builder: (ctx) => AlertDialog(
          title: const Text('تأكيد بيع العقار'),
          content: Text('هل تريد بيع ${b.type.spec.name}؟ عملية البيع نهائية وستفقد إنتاج المبنى.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            TextButton(onPressed: () {
              Navigator.pop(ctx);
              message(g.sellBuilding(b));
              if (mounted) Navigator.of(context).pop();
            }, child: const Text('تأكيد البيع')),
          ],
        ));
      }),
    ]), height: .62);
  }

  void marketSheet() {
    var buying = true;
    var quantity = 5;
    Resource active = Resource.wood;
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, redraw) => SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SizedBox(height: MediaQuery.sizeOf(ctx).height * .82, child: GPanel(child: Column(children: [
          Row(children: [const Icon(Icons.storefront_rounded, color: GameColors.gold, size: 28), const SizedBox(width: 8),
            const Expanded(child: Text('سوق المملكة', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: GameColors.paleGold))),
            IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close))]),
          AnimatedBuilder(animation: g, builder: (context, _) => Column(children: [
            Text('ذهب التاجر: ${g.merchantGold}  •  ذهبك: ${g.count(Resource.gold)}', style: const TextStyle(color: GameColors.muted, fontSize: 12)),
            const SizedBox(height: 8),
          ])),
          Row(children: [
            Expanded(child: GButton(text: 'شراء', icon: Icons.shopping_cart_rounded, primary: buying, onPressed: () => redraw(() { buying = true; }))),
            const SizedBox(width: 8),
            Expanded(child: GButton(text: 'بيع', icon: Icons.sell_rounded, primary: !buying, onPressed: () => redraw(() { buying = false; }))),
          ]), const SizedBox(height: 8),
          Expanded(child: AnimatedBuilder(animation: g, builder: (context, _) => ListView(children: [
            for (final r in Resource.values.where((r) => r != Resource.gold)) Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(onTap: () => redraw(() {active = r; quantity = 5;}), child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: active == r ? const Color(0xff655033) : Colors.black26, borderRadius: BorderRadius.circular(12), border: Border.all(color: active == r ? GameColors.gold : Colors.transparent)),
                child: Row(children: [
                  Icon(r.icon, color: r.color, size: 28), const SizedBox(width: 9),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.label, style: const TextStyle(fontWeight: FontWeight.bold)), Text('عندك: ${g.count(r)}  •  عند التاجر: ${g.merchantStock[r]}', style: const TextStyle(fontSize: 10, color: GameColors.muted))])),
                  Text('${g.marketPrice(r, buying: buying)} 🪙', style: const TextStyle(color: GameColors.paleGold, fontWeight: FontWeight.w800)),
                ]),
              )),
            ),
          ]))),
          const Divider(color: Color(0xff947449)),
          Text('${active.label}  •  سعر الوحدة ${g.marketPrice(active, buying: buying)} ذهب', style: const TextStyle(fontWeight: FontWeight.w800)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: () => redraw(() => quantity = (quantity - 1).clamp(1, 1000).toInt()), icon: const Icon(Icons.remove_circle_outline, color: GameColors.gold)),
            Text('$quantity', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            IconButton(onPressed: () => redraw(() => quantity = (quantity + 1).clamp(1, 1000).toInt()), icon: const Icon(Icons.add_circle_outline, color: GameColors.gold)),
            const SizedBox(width: 7),
            for (final jump in [10, 50]) Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: OutlinedButton(onPressed: () => redraw(() => quantity = jump), child: Text('$jump'))),
          ]),
          Text('الإجمالي: ${g.marketPrice(active, buying: buying) * quantity} ذهب', style: const TextStyle(color: GameColors.paleGold, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 7),
          SizedBox(width: double.infinity, child: GButton(text: buying ? 'تأكيد الشراء' : 'تأكيد البيع', icon: buying ? Icons.shopping_cart_checkout_rounded : Icons.price_check_rounded, primary: true, onPressed: () {
            final result = g.trade(active, quantity, buying: buying);
            message(result);
            redraw(() {});
          })),
        ]))),
      ))),
    );
  }

  void inventorySheet() {
    sheet('المخزن والموارد', Icons.inventory_2_rounded, (_) => Column(children: [
      Text('سعة التخزين: ${g.stored} / ${g.storageCapacity}', style: const TextStyle(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      LinearProgressIndicator(value: (g.stored / g.storageCapacity).clamp(0.0, 1.0).toDouble(), minHeight: 13, color: GameColors.gold, backgroundColor: Colors.black38),
      const SizedBox(height: 18),
      for (final r in Resource.values) ListTile(
        leading: CircleAvatar(backgroundColor: r.color.withValues(alpha: .16), child: Icon(r.icon, color: r.color)),
        title: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(r == Resource.gold ? 'العملة الرئيسية' : 'سعر الشراء ${g.marketPrice(r, buying: true)} • سعر البيع ${g.marketPrice(r, buying: false)}'),
        trailing: Text('${g.count(r)}', style: const TextStyle(fontSize: 20, color: GameColors.paleGold, fontWeight: FontWeight.bold)),
      ),
    ]));
  }

  void characterSheet() {
    sheet('الشخصية والاحتياجات', Icons.person_rounded, (_) => Column(children: [
      const CircleAvatar(radius: 43, backgroundColor: Color(0xff69503d), child: Icon(Icons.person_rounded, size: 65, color: GameColors.paleGold)),
      const SizedBox(height: 7),
      Text('بطل المملكة • المستوى ${g.level}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
      Text('الخبرة: ${g.xp} / ${g.xpForNext}', style: const TextStyle(fontSize: 12, color: GameColors.muted)),
      const SizedBox(height: 20),
      const SectionTitle('الحالة الصحية', Icons.favorite_rounded),
      NeedBar('الجوع', g.needs['الجوع']!, Icons.restaurant_rounded, Colors.lightGreenAccent),
      NeedBar('العطش', g.needs['العطش']!, Icons.water_drop_rounded, Colors.lightBlueAccent),
      NeedBar('الطاقة', g.needs['الطاقة']!, Icons.bolt_rounded, Colors.amberAccent),
      NeedBar('الصحة', g.needs['الصحة']!, Icons.favorite_rounded, Colors.redAccent),
      NeedBar('المزاج', g.needs['المزاج']!, Icons.sentiment_satisfied_rounded, Colors.greenAccent),
      NeedBar('النظافة', g.needs['النظافة']!, Icons.clean_hands_rounded, Colors.cyanAccent),
      const SizedBox(height: 18),
      const SectionTitle('اعتنِ بالبطل', Icons.volunteer_activism_rounded),
      const SizedBox(height: 10),
      Wrap(spacing: 7, runSpacing: 8, children: [
        GButton(text: 'تناول الطعام', icon: Icons.restaurant_rounded, primary: true, onPressed: () => message(g.act('eat'))),
        GButton(text: 'اشرب الماء', icon: Icons.water_drop_rounded, onPressed: () => message(g.act('drink'))),
        GButton(text: 'استرح 3 ساعات', icon: Icons.bedtime_rounded, onPressed: () => message(g.act('sleep'))),
        GButton(text: 'اغتسل', icon: Icons.clean_hands_rounded, onPressed: () => message(g.act('wash'))),
        GButton(text: 'اصنع أداة', icon: Icons.handyman_rounded, onPressed: () => message(g.act('craft'))),
      ]),
      const SizedBox(height: 15),
      const Text('المؤشرات تنخفض مع مرور وقت اللعبة. الطعام والشراب والنوم ضروريون للحفاظ على صحة البطل.', style: TextStyle(fontSize: 11, color: GameColors.muted, height: 1.5)),
    ]));
  }

  void questsSheet() {
    sheet('المهام والمكافآت', Icons.assignment_rounded, (_) => Column(children: [
      const Text('أكمل المهام لتربح الذهب والخبرة، وتوسّع تجارتك.', style: TextStyle(color: GameColors.muted)),
      const SizedBox(height: 10),
      for (final q in GameState.quests.entries) Padding(padding: const EdgeInsets.only(bottom: 9), child: GPanel(child: Row(children: [
        Icon(g.completedQuests.contains(q.key) ? Icons.check_circle_rounded : Icons.workspace_premium_rounded, color: GameColors.gold),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(q.value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
          Text('التقدم: ${g.questProgress(q.key)} • المكافأة 220 ذهب +70 خبرة', style: const TextStyle(fontSize: 10, color: GameColors.muted)),
        ])),
        if (g.completedQuests.contains(q.key)) const Text('مُنجَز', style: TextStyle(color: GameColors.green))
        else GButton(text: 'استلم', primary: g.questDone(q.key), onPressed: g.questDone(q.key) ? () => message(g.claim(q.key)) : null),
      ]))),
    ]), height: .72);
  }

  void economySheet() {
    sheet('دفتر اقتصاد المملكة', Icons.bar_chart_rounded, (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('المؤشرات اليومية', Icons.trending_up_rounded),
      const SizedBox(height: 12),
      _stat('دخل إيجارات المنازل', '+${g.rentPerDay} ذهب / يوم', Icons.home_rounded),
      _stat('تكلفة العمالة', '-${g.upkeepPerDay} ذهب / يوم', Icons.groups_rounded),
      _stat('طاقة العمال', '${g.workersNeeded} / ${g.housing}', Icons.engineering_rounded),
      _stat('سعة المخازن', '${g.stored} / ${g.storageCapacity}', Icons.inventory_2_rounded),
      _stat('المباني المملوكة', '${g.buildings.length}', Icons.castle_rounded),
      const SizedBox(height: 15),
      if (!g.hasLabor) const Text('⚠ لا يوجد سكن كافٍ لكل العمال. بعض المصانع ستتوقف عن الإنتاج.', style: TextStyle(color: Colors.orangeAccent)),
      const SizedBox(height: 13),
      const SectionTitle('سجل العمليات', Icons.receipt_long_rounded),
      const SizedBox(height: 9),
      if (g.history.isEmpty) const Text('لم تُسجّل أي معاملات بعد.', style: TextStyle(color: GameColors.muted)),
      for (final record in g.history.take(20)) ListTile(dense: true,
        leading: const Icon(Icons.history_rounded, color: GameColors.gold),
        title: Text(record.summary, style: const TextStyle(fontSize: 12)),
        trailing: Text('يوم ${record.day}', style: const TextStyle(fontSize: 10, color: GameColors.muted))),
    ]));
  }

  Widget _stat(String title, String value, IconData icon) => ListTile(
    leading: Icon(icon, color: GameColors.gold),
    title: Text(title, style: const TextStyle(fontSize: 12)),
    trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w900, color: GameColors.paleGold)),
  );

  void mapSheet() {
    sheet('الخريطة ودليل اللعب', Icons.map_rounded, (_) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('اسحب بإصبعك لتحريك الخريطة، واستخدم إصبعين للتقريب والإبعاد. المس أرضًا فارغة ليتحرك البطل إليها، أو المس مبنى لترقيته أو بيعه.', style: TextStyle(height: 1.8)),
      const SizedBox(height: 12),
      const SectionTitle('اقتصاد متصل', Icons.account_balance_rounded),
      const SizedBox(height: 10),
      const Text('الحطّابون ← الخشب ← المنشرة ← الألواح ← الورشة والأبنية\nالمزارع ← القمح + مياه البئر ← المخبز ← الخبز\nالمحجر ← الحجر ← مصنع الطوب ← البناء\nالمنازل ← عمال وإيجارات يومية\nالسوق ← بيع وشراء محدودان بمخزون وسيولة التاجر', style: TextStyle(height: 1.9)),
      const SizedBox(height: 18),
      const SectionTitle('المرافق الموجودة', Icons.location_city_rounded),
      for (final type in BuildingType.values) ListTile(dense: true, leading: Icon(type.spec.icon, color: GameColors.gold),
        title: Text(type.spec.name), trailing: Text('${g.buildings.where((b) => b.type == type).length}')),
      const SizedBox(height: 16),
      const SectionTitle('إعدادات', Icons.settings_rounded),
      SwitchListTile(title: const Text('صوت الضغطات'), value: g.soundOn, onChanged: (_) => g.toggleSound()),
      GButton(text: 'حفظ التقدم الآن', icon: Icons.save_rounded, primary: true, onPressed: () { g.save(); message(const GameAction(true, 'تم طلب حفظ تقدمك على الجهاز')); }),
      const SizedBox(height: 12),
      const Text('اللعبة تعمل بالكامل دون اتصال بالإنترنت. الحفظ محلي على الجهاز وقد يُحذف إذا حذفت بيانات التطبيق.', style: TextStyle(fontSize: 11, color: GameColors.muted)),
    ]), height: .80);
  }
}

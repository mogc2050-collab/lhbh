import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../game/catalog.dart';
import '../game/game_state.dart';
import '../game/world_regions.dart';
import 'sound_director.dart';
import 'world_painter.dart';

/// Premium illustrated UI: the four original concept artworks are the art
/// direction and backgrounds. Gameplay, prices, inventory and transactions
/// are live GameState values, not baked into the paintings.
///
/// 3D-looking artwork is deliberately not misrepresented as a realtime 3D
/// renderer. The separate interactive isometric world supports construction.
class PremiumGameScreen extends StatefulWidget {
  const PremiumGameScreen({super.key, required this.game});
  final GameState game;

  @override
  State<PremiumGameScreen> createState() => _PremiumGameScreenState();
}

class _PremiumGameScreenState extends State<PremiumGameScreen> with WidgetsBindingObserver {
  static const w = 941.0;
  static const h = 1672.0;
  static const gold = Color(0xffe8bd63);
  static const pale = Color(0xffffe9b7);
  static const ink = Color(0xff291b12);
  static const parchment = Color(0xffebd1a0);
  static const leaf = Color(0xff73c66d);
  static const art = [
    'design_reference/01_kingdom_overview_CONCEPT.png',
    'design_reference/02_market_CONCEPT.png',
    'design_reference/03_construction_CONCEPT.png',
    'design_reference/04_character_CONCEPT.png',
  ];
  static const saleResources = [
    Resource.wood, Resource.stone, Resource.grain, Resource.bread,
    Resource.tools, Resource.brick, Resource.plank, Resource.water,
    Resource.meat,
  ];

  late final GameState game;
  final sound = SoundDirector();
  final mapCamera = TransformationController();
  final List<Timer> timers = [];
  int page = 0;
  int quantity = 1;
  Resource selectedResource = Resource.wood;
  BuildingType? placement;
  bool buying = true;
  bool worldOpen = false;
  bool mapFocused = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    game = widget.game;
    game.addListener(_onGameChange);
    sound.enabled = game.soundOn;
    WidgetsBinding.instance.addObserver(this);
    timers.add(Timer.periodic(const Duration(seconds: 1), (_) => game.advance()));
    timers.add(Timer.periodic(const Duration(milliseconds: 280), (_) => game.stepWalk()));
    timers.add(Timer.periodic(const Duration(seconds: 15), (_) => game.save()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && game.soundOn) sound.startAmbience();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final path in art) {
      precacheImage(AssetImage(path), context);
    }
  }

  void _onGameChange() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) game.save();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final timer in timers) { timer.cancel(); }
    game.removeListener(_onGameChange);
    game.save();
    sound.dispose();
    mapCamera.dispose();
    super.dispose();
  }

  void _navigate(int target) {
    if (target == 4) {
      _openWorld();
      return;
    }
    HapticFeedback.selectionClick();
    sound.play('select');
    setState(() { page = target; worldOpen = false; });
  }

  void _act(GameAction result, {String cue = 'select'}) {
    if (!mounted) return;
    sound.play(result.ok ? cue : 'fail');
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: result.ok ? const Color(0xff37613a) : const Color(0xff80352b),
      content: Text(result.message, textAlign: TextAlign.center),
      duration: const Duration(seconds: 2),
    ));
    if (result.ok) game.save();
  }

  void _openWorld({BuildingType? build}) {
    setState(() {
      worldOpen = true;
      placement = build;
      mapFocused = false;
    });
    sound.play('select');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !worldOpen) return;
      _focusWorld();
    });
  }

  void _focusWorld() {
    final bounds = MediaQuery.sizeOf(context);
    const zoom = 0.65;
    final pos = VillagePainter.center(game.px, game.py);
    mapCamera.value = Matrix4.identity()
      ..translate(bounds.width * 0.5 - pos.dx * zoom,
          bounds.height * .48 - pos.dy * zoom)
      ..scale(zoom);
    mapFocused = true;
  }

  void _worldTap(TapUpDetails details) {
    final tile = VillagePainter.tileFrom(details.localPosition);
    if (!game.inside(tile.x, tile.y)) return;
    if (placement != null) {
      final result = game.build(placement!, tile.x, tile.y);
      _act(result, cue: 'build');
      if (result.ok) setState(() => placement = null);
      return;
    }
    final building = game.buildingAt(tile.x, tile.y);
    if (building != null) {
      _ownedBuilding(building);
    } else {
      _act(game.walkTo(tile.x, tile.y), cue: 'walk');
    }
  }

  Widget _world() => Stack(children: [
    Positioned.fill(child: ColoredBox(
      color: const Color(0xff173d35),
      child: InteractiveViewer(
        transformationController: mapCamera,
        minScale: .20, maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(500),
        constrained: false,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _worldTap,
          child: CustomPaint(
            size: VillagePainter.sceneSize,
            painter: VillagePainter(game, buildMode: placement != null),
          ),
        ),
      ),
    )),
    Positioned(top: 10, left: 10, right: 10, child: SafeArea(
      child: _goldPanel(Row(children: [
        IconButton(onPressed: () => setState(() => worldOpen = false),
            icon: const Icon(Icons.arrow_forward_rounded, color: pale)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(placement == null ? 'خريطة المملكة' : 'اختر مكان البناء', style:
              const TextStyle(color: pale, fontSize: 18, fontWeight: FontWeight.w900)),
          Text(game.city.name + ' • ' + GameState.worldSize.toString() + ' × ' +
              GameState.worldSize.toString(), style: const TextStyle(color: gold, fontSize: 12)),
        ])),
        IconButton(onPressed: _focusWorld,
            icon: const Icon(Icons.my_location_rounded, color: pale)),
      ]), padding: const EdgeInsets.all(5)),
    )),
    Positioned(left: 12, right: 12, bottom: 12, child: SafeArea(top: false,
      child: _goldPanel(Column(mainAxisSize: MainAxisSize.min, children: [
        Text(placement == null
            ? 'اسحب الخريطة للتجول، واضغط على أرض فارغة للمشي أو على مبنى لإدارته'
            : 'المس قطعة أرض خالية لبناء ' + placement!.spec.name,
          style: const TextStyle(color: pale, fontSize: 12), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _command('المباني', Icons.construction, _constructionPicker)),
          const SizedBox(width: 6),
          Expanded(child: _command('المدينة', Icons.location_city, _cities)),
          const SizedBox(width: 6),
          Expanded(child: _command('إلغاء', Icons.close, () {
            if (placement != null) setState(() => placement = null);
            else setState(() => worldOpen = false);
          })),
        ]),
      ])),
    )),
  ]);

  Widget _goldPanel(Widget child, {EdgeInsets padding = const EdgeInsets.all(12),
      Color? color}) => Container(
    padding: padding,
    decoration: BoxDecoration(
      border: Border.all(color: gold, width: 1.5),
      borderRadius: BorderRadius.circular(14),
      gradient: LinearGradient(colors: [
        color ?? const Color(0xff654026), const Color(0xff211810),
      ], begin: Alignment.topLeft, end: Alignment.bottomRight),
      boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 15, offset: Offset(0, 4))],
    ),
    child: child,
  );

  Widget _command(String text, IconData icon, VoidCallback? onTap,
      {bool green = false}) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(9),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 7),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: green
          ? [const Color(0xff58933b), const Color(0xff20472b)]
          : [const Color(0xff936331), const Color(0xff3b2618)]),
        border: Border.all(color: gold, width: 1),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, color: pale, size: 17), const SizedBox(width: 5),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: pale, fontWeight: FontWeight.w800, fontSize: 12)))]),
    ),
  );

  void _sheet(String title, Widget Function(BuildContext) contents,
      {double fraction = .77}) {
    sound.play('select');
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: SizedBox(height: MediaQuery.sizeOf(ctx).height * fraction,
            child: _goldPanel(Column(children: [
              Row(children: [
                const Icon(Icons.auto_awesome, color: gold),
                const SizedBox(width: 9),
                Expanded(child: Text(title, style: const TextStyle(
                    color: pale, fontSize: 21, fontWeight: FontWeight.w900))),
                IconButton(onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close, color: pale)),
              ]),
              const Divider(color: Color(0xffb48a4d)),
              Expanded(child: AnimatedBuilder(animation: game,
                builder: (context, _) => SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: contents(context),
                ))),
            ]))),
        )),
    );
  }

  Widget _tile(String title, String subtitle, IconData icon, {VoidCallback? onTap,
      String? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: _goldPanel(InkWell(onTap: onTap, child: Row(children: [
      Icon(icon, color: gold, size: 28), const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: pale, fontSize: 15, fontWeight: FontWeight.w900)),
        Text(subtitle, style: const TextStyle(color: Color(0xffd5be94), fontSize: 11, height: 1.5)),
      ])),
      if (trailing != null) Text(trailing, style: const TextStyle(color: leaf, fontWeight: FontWeight.w900)),
      const Icon(Icons.chevron_left_rounded, color: gold),
    ])), padding: const EdgeInsets.all(10)),
  );

  void _constructionPicker() {
    _sheet('المباني والإنشاءات', (_) => Column(children: [
      for (final type in BuildingType.values) _tile(type.spec.name,
        type.spec.description + ' • ' +
          game.buildingCost(type).entries.map((e) =>
            e.key.label + ': ' + e.value.toString()).join('، '),
        type.spec.icon, trailing: 'بناء', onTap: () {
          Navigator.pop(context);
          _openWorld(build: type);
        }),
    ]), fraction: .84);
  }

  void _ownedBuilding(Building b) {
    _sheet(b.type.spec.name + ' • المستوى ' + b.level.toString(), (_) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Icon(b.type.spec.icon, color: gold, size: 72)),
        const SizedBox(height: 15),
        Text(b.type.spec.description, textAlign: TextAlign.center,
            style: const TextStyle(color: pale, fontSize: 15)),
        const SizedBox(height: 20),
        _tile('المستوى القادم', game.buildingCost(b.type,
            upgradeLevel: b.level + 1).entries.map((e) =>
          e.key.label + ' ' + e.value.toString()).join(' • '),
          Icons.trending_up, trailing: 'ترقية', onTap: () {
          final result = game.upgrade(b);
          _act(result, cue: 'upgrade');
          if (result.ok) Navigator.pop(context);
        }),
        _tile('بيع العقار', 'العائد المتوقع: ' + game.saleValue(b).toString() +
            ' ذهب. لا يمكن التراجع بعد البيع.', Icons.sell_rounded,
          trailing: 'بيع', onTap: () async {
            final confirmed = await showDialog<bool>(context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('تأكيد بيع العقار'),
                content: Text('هل تريد بيع ' + b.type.spec.name +
                    ' مقابل ' + game.saleValue(b).toString() + ' ذهب؟'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('إلغاء')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('تأكيد البيع')),
                ],
              ));
            if (confirmed == true && mounted) {
              _act(game.sellBuilding(b), cue: 'sell');
              if (mounted) Navigator.pop(context);
            }
          }),
      ]));
  }

  void _cities() {
    _sheet('المدن والسفر', (_) => Column(children: [
      for (final city in kingdomCities) _tile(city.name,
        city.description + ' • المسافة ' +
        travelDistance(game.city, city).toString() + ' • الأجرة ' +
        travelFare(game.city, city).toString() + ' ذهب',
        Icons.location_city_rounded, trailing: game.currentCityId == city.id ?
          'أنت هنا' : 'سافر', onTap: () {
          if (game.currentCityId == city.id) return;
          final result = game.travelTo(city.id);
          _act(result, cue: 'travel');
          if (result.ok) {
            Navigator.pop(context);
            setState(() => worldOpen = false);
          }
        }),
    ]));
  }

  void _quests() {
    _sheet('المهام والمكافآت', (_) => Column(children: [
      for (final entry in GameState.quests.entries) _tile(entry.value,
        'التقدم: ' + game.questProgress(entry.key),
        game.completedQuests.contains(entry.key) ?
          Icons.verified_rounded : Icons.assignment_turned_in_rounded,
        trailing: game.completedQuests.contains(entry.key) ? 'مكتملة' :
          game.questDone(entry.key) ? 'استلام' : 'جارية',
        onTap: () => _act(game.claim(entry.key), cue: 'quest')),
    ]));
  }

  void _economy() {
    _sheet('اقتصاد المملكة والقرارات', (_) => Column(children: [
      _tile('الذهب الحالي', game.count(Resource.gold).toString() +
          ' ذهب • دخل الإيجارات: ' + game.rentPerDay.toString() +
          ' • الصيانة: ' + game.upkeepPerDay.toString(),
          Icons.paid_rounded),
      _tile('القروض', 'الدين: ' + game.loanDebt.toString() +
          ' ذهب، وفائدة 2% عن كل يوم داخل اللعبة',
          Icons.account_balance_rounded),
      Row(children: [
        Expanded(child: _command('اقترض 500', Icons.add, () =>
            _act(game.borrow(500), cue: 'loan'))),
        const SizedBox(width: 8),
        Expanded(child: _command('سدّد 200', Icons.remove, () =>
            _act(game.repay(200), cue: 'sell'))),
      ]),
      const SizedBox(height: 14),
      for (var policy = 0; policy < 3; policy++) _tile(
        ['ضرائب منخفضة', 'ضرائب متوازنة', 'ضرائب مرتفعة'][policy],
        ['دخل أقل ورضا أكبر للسكان', 'توازن الإيرادات والرضا',
         'دخل أعلى مع خطر انخفاض السمعة'][policy],
        Icons.balance_rounded,
        trailing: game.taxPolicy == policy ? 'الحالية' : 'اختر',
        onTap: () => _act(game.chooseTaxes(policy))),
      const SizedBox(height: 7),
      Text('استثمار القوافل: ' +
        (game.caravanStake > 0 ? game.caravanStake.toString() +
          ' ذهب حتى يوم ' + game.caravanMaturityDay.toString() : 'لا توجد قافلة حاليًا'),
        style: const TextStyle(color: pale, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      for (final city in kingdomCities.where((c) => c.id != game.currentCityId))
        _tile('قافلة إلى ' + city.name,
          'استثمر 500 ذهب. قد تربح أو تخسر حسب مخاطر الطريق.',
          Icons.local_shipping_rounded, trailing: 'أرسل', onTap: () =>
            _act(game.investCaravan(500, city.id), cue: 'caravan')),
    ]), fraction: .86);
  }

  void _inventory() {
    _sheet('المخزون والممتلكات', (_) => Column(children: [
      _tile('سعة المخزن', game.stored.toString() + ' / ' +
        game.storageCapacity.toString(), Icons.inventory_2_rounded),
      for (final resource in Resource.values)
        _tile(resource.label, 'المتوفر: ' + game.count(resource).toString(),
          resource.icon, trailing: resource == Resource.gold ? '' :
            'بيع ' + game.marketPrice(resource, buying: false).toString()),
      const SizedBox(height: 16),
      _tile('مبانيك', 'إدارة ' + game.buildings.length.toString() +
        ' مبنى قائم', Icons.apartment_rounded, onTap: _properties),
    ]));
  }

  void _properties() {
    _sheet('العقارات المملوكة', (_) => Column(children: [
      for (final b in game.buildings) _tile(b.type.spec.name,
        'المستوى ' + b.level.toString() + ' • موقع (' +
        b.x.toString() + '، ' + b.y.toString() + ')',
        b.type.spec.icon, trailing: 'إدارة', onTap: () {
          Navigator.pop(context);
          _ownedBuilding(b);
        }),
    ]));
  }

  void _trade() {
    final result = game.trade(selectedResource, quantity, buying: buying);
    _act(result, cue: buying ? 'buy' : 'sell');
    if (result.ok) setState(() => quantity = 1);
  }

  void _toggleSound() {
    game.toggleSound();
    sound.setEnabled(game.soundOn);
    sound.play('select');
  }

  Widget _hit(double left, double top, double width, double height,
      VoidCallback onTap, String label) => Positioned(
    left: left, top: top, width: width, height: height,
    child: Semantics(button: true, label: label, child: GestureDetector(
      behavior: HitTestBehavior.opaque, onTap: onTap,
      child: const SizedBox.expand(),
    )),
  );

  Widget _textPatch(double x, double y, double width, double height, String value,
      {double size = 29}) => Positioned(left: x, top: y,
    width: width, height: height, child: Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: const LinearGradient(colors: [
          Color(0xff30251d), Color(0xff241c17), Color(0xff382a20)]),
      ),
      child: Text(value, maxLines: 1, style: TextStyle(fontSize: size,
        color: Colors.white, fontWeight: FontWeight.w900,
        shadows: const [Shadow(color: Colors.black, blurRadius: 3)])),
    ));

  Widget _liveResources() => Stack(children: [
    _textPatch(83, 6, 95, 40, game.count(Resource.gold).toString()),
    _textPatch(303, 6, 60, 40, game.count(Resource.wood).toString()),
    _textPatch(503, 6, 53, 40, game.count(Resource.stone).toString()),
    _textPatch(645, 6, 62, 40, game.count(Resource.grain).toString()),
    _textPatch(826, 6, 58, 40, '0'),
    _hit(5, 5, 208, 51, _economy, 'رصيد الذهب واقتصاد المملكة'),
    _hit(230, 5, 500, 51, _inventory, 'الموارد والمخزن'),
    _hit(770, 5, 165, 51, _inventory, 'المخزون'),
  ]);

  Widget _bar(double value, Color color, {double height = 16}) =>
      LayoutBuilder(builder: (ctx, box) =>
        Container(height: height, padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: const Color(0xff20160e),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xff977849))),
          child: Align(alignment: Alignment.centerRight,
            child: AnimatedContainer(duration: const Duration(milliseconds: 330),
              width: math.max(0.0, box.maxWidth - 4) * (value.clamp(0, 100) / 100),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(colors: [color, Color.lerp(color,
                    Colors.white, .25)!]),
                boxShadow: [BoxShadow(color: color.withValues(alpha: .28),
                    blurRadius: 7)],
              ),
            ))));

  Widget _homeNeeds() => Positioned(left: 703, top: page == 1 ? 339 : 351,
    width: 211, height: 192,
    child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final record in [
          ('الجوع', const Color(0xff78c83c)), ('الطاقة', const Color(0xffe3ae24)),
          ('الصحة', const Color(0xffde514c)), ('المزاج', const Color(0xff7fcb3f))
        ]) Row(children: [
          Expanded(child: _bar(game.needs[record.$1] ?? 100, record.$2)),
          const SizedBox(width: 4),
          Container(width: 48, color: const Color(0xff231b12),
            child: Text((game.needs[record.$1] ?? 100).round().toString() + '%',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18,
                fontWeight: FontWeight.bold))),
        ]),
      ]));

  Widget _characterNeeds() => Positioned(left: 497, top: 480,
    width: 397, height: 287,
    child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      for (final record in [
        ('الجوع', const Color(0xff8acb43)), ('الطاقة', const Color(0xffe4b02b)),
        ('الصحة', const Color(0xffde4c4c)), ('المزاج', const Color(0xff6cca40)),
        ('النظافة', const Color(0xff5faedb)), ('العطش', const Color(0xffb19adc))
      ]) Row(children: [
        SizedBox(width: 90, child: Text(record.$1, style:
            const TextStyle(color: pale, fontSize: 19, fontWeight: FontWeight.w900))),
        Expanded(child: _bar(game.needs[record.$1] ?? 100, record.$2,
            height: 24)),
        const SizedBox(width: 6),
        Container(color: ink, width: 60,
          child: Text((game.needs[record.$1] ?? 100).round().toString() + '%',
            style: const TextStyle(color: pale, fontSize: 21,
              fontWeight: FontWeight.w900))),
      ]),
    ]));

  Widget _marketBoard() {
    final visible = saleResources.take(6).toList();
    return Positioned(left: 251, top: 883, width: 569, height: 382,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [
            Color(0xfff7e2b7), Color(0xffd9b67f)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter),
          border: Border.all(color: const Color(0xff7a4c22), width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
          DefaultTextStyle(
            style: const TextStyle(color: ink, fontSize: 23, fontWeight: FontWeight.w900),
            child: Row(children: [
              const Expanded(flex: 3, child: Text('المورد', textAlign: TextAlign.center)),
              Expanded(flex: 2, child: Text(buying ? 'لديك' : 'المتوفر',
                  textAlign: TextAlign.center)),
              const Expanded(flex: 2, child: Text('السعر', textAlign: TextAlign.center)),
            ]),
          ),
          const Divider(height: 8, color: Color(0xff8a5929)),
          for (final r in visible) Expanded(child: InkWell(
            onTap: () => setState(() { selectedResource = r; quantity = 1; }),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: selectedResource == r ? const Color(0xffe3bd65) :
                  const Color(0x55fff5dd),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: selectedResource == r ?
                    const Color(0xff875616) : const Color(0x4483623b))),
              child: Row(children: [
                Icon(r.icon, color: const Color(0xff735029), size: 29),
                const SizedBox(width: 7),
                Expanded(flex: 3, child: Text(r.label,
                    style: const TextStyle(color: ink, fontSize: 24,
                        fontWeight: FontWeight.w900))),
                Expanded(flex: 2, child: Text(
                  (buying ? game.merchantStock[r] : game.count(r)).toString(),
                  textAlign: TextAlign.center, style: const TextStyle(
                    color: ink, fontSize: 23, fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text(
                  game.marketPrice(r, buying: buying).toString() + ' 🪙',
                  textAlign: TextAlign.center, style: const TextStyle(
                    color: Color(0xff754818), fontSize: 22,
                    fontWeight: FontWeight.w900))),
              ]),
            ),
          )),
        ]),
      ));
  }

  Widget _marketActions() {
    final price = game.marketPrice(selectedResource, buying: buying);
    return Positioned(left: 100, top: 1264, width: 732, height: 158,
      child: _goldPanel(Column(children: [
        Row(children: [
          Expanded(child: Text((buying ? 'شراء ' : 'بيع ') + selectedResource.label,
            style: const TextStyle(color: pale, fontSize: 26, fontWeight: FontWeight.bold))),
          Text('السعر: ' + (price * quantity).toString() + ' ذهب',
            style: const TextStyle(color: gold, fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          IconButton(onPressed: () => setState(() => quantity = math.max(1, quantity - 1)),
            icon: const Icon(Icons.remove_circle, color: leaf, size: 35)),
          Text(quantity.toString(), style: const TextStyle(color: pale, fontSize: 27)),
          IconButton(onPressed: () => setState(() => quantity = math.min(999, quantity + 1)),
            icon: const Icon(Icons.add_circle, color: leaf, size: 35)),
        ]),
        Expanded(child: Row(children: [
          Expanded(child: _command('شراء', Icons.shopping_cart, () =>
              setState(() { buying = true; quantity = 1; }), green: buying)),
          const SizedBox(width: 9),
          Expanded(child: _command('بيع', Icons.sell_rounded, () =>
              setState(() { buying = false; quantity = 1; }), green: !buying)),
          const SizedBox(width: 9),
          Expanded(flex: 2, child: _command('تأكيد الصفقة',
              Icons.check_circle_rounded, _trade, green: true)),
        ])),
      ]), padding: const EdgeInsets.fromLTRB(15, 4, 15, 6)));
  }

  Widget _artStage() => Stack(children: [
    Positioned.fill(child: AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: Image.asset(art[page], key: ValueKey(page), fit: BoxFit.fill,
        filterQuality: FilterQuality.high, width: w, height: h),
    )),
    Positioned.fill(child: _liveResources()),
    if (page == 0 || page == 1) _homeNeeds(),
    if (page == 1) ...[
      _marketBoard(), _marketActions(),
      _hit(481, 808, 312, 78, () => setState(() => buying = true), 'شراء من السوق'),
      _hit(178, 808, 294, 78, () => setState(() => buying = false), 'بيع في السوق'),
    ],
    if (page == 0) ...[
      _hit(20, 289, 280, 338, _quests, 'المهام اليومية'),
      _hit(697, 292, 229, 257, _characterDialog, 'احتياجات الشخصية'),
      _hit(680, 716, 255, 170, () => _navigate(1), 'السوق والتجارة'),
      _hit(380, 435, 242, 228, _properties, 'المناشر والمباني'),
      _hit(93, 750, 205, 180, _properties, 'البيوت'),
      _hit(672, 1010, 236, 213, _constructionPicker, 'المزارع'),
      _hit(45, 1090, 370, 315, _openWorld, 'التحرك واللعب داخل العالم'),
      _hit(0, 970, 75, 257, _economy, 'اقتصاد المملكة'),
      _hit(840, 974, 101, 290, _characterDialog, 'تفاعلات البطل'),
    ],
    if (page == 2) ...[
      _hit(634, 286, 280, 618, _properties, 'تفاصيل المباني وترقيتها'),
      _hit(0, 500, 180, 351, _openWorld, 'وضع البناء'),
      for (var i = 0; i < 6; i++)
        _hit(16 + i * 152.5, 1038, 146, 393,
          () => _openWorld(build: [
            BuildingType.workshop, BuildingType.bakery,
            BuildingType.warehouse, BuildingType.sawmill,
            BuildingType.farm, BuildingType.house,
          ][i]), 'بناء ' + [
            'ورشة', 'مخبز', 'مخزن', 'منشرة', 'مزرعة', 'منزل'
          ][i]),
    ],
    if (page == 3) ...[
      _characterNeeds(),
      _hit(444, 770, 108, 126, () => _act(game.act('chop'), cue: 'chop'), 'اعمل واحتطب'),
      _hit(560, 770, 106, 126, () => _act(game.act('craft'), cue: 'craft'), 'اصنع أدوات'),
      _hit(678, 770, 103, 126, () => _act(game.act('sleep'), cue: 'sleep'), 'استرح'),
      _hit(793, 770, 111, 126, () => _act(game.act('eat'), cue: 'eat'), 'تناول طعاما'),
      _hit(453, 915, 439, 457, _inventory, 'المخزون الشخصي والمعدات'),
      _hit(32, 526, 277, 300, _characterDialog, 'المنزل والبطل'),
    ],
    _hit(17, 1450, 156, 197, () => _navigate(2), 'البناء والتطوير'),
    _hit(193, 1450, 161, 197, () => _navigate(1), 'السوق'),
    _hit(379, 1450, 158, 197, _inventory, 'المخزن'),
    _hit(563, 1450, 161, 197, _openWorld, 'الخريطة'),
    _hit(763, 1450, 160, 197, () => _navigate(3), 'الشخصية'),
    _hit(854, 55, 87, 90, _settings, 'الإعدادات'),
    _hit(581, 69, 61, 76, game.togglePause, 'إيقاف أو متابعة الزمن'),
    _hit(665, 69, 61, 76, game.cycleSpeed, 'تغيير سرعة الزمن'),
    _hit(9, 65, 250, 78, _cities, 'المملكة والمدن'),
    _hit(731, 146, 190, 135, _cities, 'خريطة المدن والسفر'),
  ]);

  void _characterDialog() {
    _sheet('الشخصية والاحتياجات', (_) => Column(children: [
      for (final need in game.needs.entries) Padding(
        padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [
          SizedBox(width: 78, child: Text(need.key,
            style: const TextStyle(color: pale, fontWeight: FontWeight.bold))),
          Expanded(child: _bar(need.value, const Color(0xff79c65c))),
          const SizedBox(width: 9),
          Text(need.value.round().toString() + '%',
            style: const TextStyle(color: pale)),
        ])),
      const SizedBox(height: 14),
      for (final action in [
        ('تناول الطعام', 'eat', Icons.restaurant_rounded),
        ('اشرب الماء', 'drink', Icons.water_drop),
        ('الراحة والنوم', 'sleep', Icons.bed),
        ('احتطب', 'chop', Icons.forest_rounded),
        ('التعدين', 'mine', Icons.terrain_rounded),
        ('صناعة أدوات', 'craft', Icons.handyman_rounded),
      ]) _tile(action.$1, 'إجراء يغيّر مواردك واحتياجات الشخصية',
        action.$3, trailing: 'تنفيذ', onTap: () =>
          _act(game.act(action.$2), cue: action.$2)),
    ]));
  }

  void _settings() {
    _sheet('الإعدادات', (_) => Column(children: [
      _tile('الأصوات والمؤثرات', game.soundOn ? 'مفعّلة' : 'متوقفة',
        game.soundOn ? Icons.volume_up : Icons.volume_off, onTap: _toggleSound,
        trailing: 'تبديل'),
      _tile('حفظ اللعبة', 'كل شيء محفوظ على هذا الجهاز فقط، دون إنترنت',
        Icons.save_rounded, trailing: 'حفظ', onTap: () {
          game.save();
          _act(const GameAction(true, 'تم حفظ التقدم'), cue: 'select');
        }),
      _tile('خريطة قابلة للعب', 'استكشف مساحة 32×32 قطعة أرض، وابنِ وتحرك',
        Icons.map_rounded, trailing: 'فتح', onTap: () {
          Navigator.pop(context);
          _openWorld();
        }),
      _tile('اقتصاد ومدن', 'ضرائب وقروض وقوافل وتجارة بين أربع مدن',
        Icons.account_balance_rounded, onTap: () {
          Navigator.pop(context); _economy();
        }),
      const Padding(padding: EdgeInsets.symmetric(vertical: 15),
        child: Text('الرسومات السينمائية هي أصول توضيحية ثابتة، أما '
          'الأسعار والقرارات والحفظ والاقتصاد والخريطة التفاعلية فتعمل بكود اللعبة. '
          'النسخة الحالية ليست محرّك 3D مجسّمًا.',
          style: TextStyle(color: Color(0xffd9c5a1), fontSize: 12, height: 1.6),
          textAlign: TextAlign.center)),
    ]));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff16130f),
    body: SafeArea(child: worldOpen ? _world() :
      SizedBox.expand(child: FittedBox(fit: BoxFit.fill,
        child: SizedBox(width: w, height: h, child: _artStage())))),
  );
}

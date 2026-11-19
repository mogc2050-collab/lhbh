import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalog.dart';
import 'world_regions.dart';

/// Single source of truth. All game rules run on-device, without APIs or network.
class GameState extends ChangeNotifier {
  static const int worldSize = 32;
  static const String saveKey = 'medieval_life_save_v1';
  final Map<Resource, int> inventory = {for (final r in Resource.values) r: 0};
  final Map<Resource, int> merchantStock = {for (final r in Resource.values) r: 150};
  final List<Building> buildings = [];
  final List<TradeRecord> history = [];
  final Set<String> completedQuests = {};
  final Map<String, double> needs = {
    'الجوع': 90, 'العطش': 90, 'الطاقة': 90, 'الصحة': 100,
    'المزاج': 80, 'النظافة': 90,
  };
  final List<Point<int>> route = [];
  // Existing save schema v1 remains loadable; new keys have safe defaults.
  String currentCityId = 'capital';
  int reputation = 65;
  int loanDebt = 0;
  int taxPolicy = 1; // 0 low, 1 balanced, 2 high
  int caravanStake = 0;
  int caravanMaturityDay = 0;
  String caravanDestinationId = '';
  final Map<String, Map<Resource, int>> regionalStock = {};
  final Map<String, int> regionalGold = {};
  KingdomCity get city => cityById(currentCityId);

  int nextBuildingId = 1;
  int minute = 8 * 60;
  int speed = 1;
  int xp = 0;
  int merchantGold = 25000;
  int px = 5, py = 6;
  int housesBuilt = 0, woodSold = 0, planksMade = 0, breadEaten = 0;
  bool paused = false;
  bool soundOn = true;
  bool loadedFromDisk = false;
  int _lastProductionSlot = 0;

  GameState() {
    _startFresh();
  }

  void _startFresh() {
    inventory.addAll({
      Resource.gold: 1850, Resource.wood: 260, Resource.stone: 190,
      Resource.grain: 100, Resource.plank: 32, Resource.bread: 7,
      Resource.brick: 16, Resource.water: 10, Resource.meat: 3,
      Resource.tools: 4,
    });
    merchantStock.addAll({
      Resource.wood: 250, Resource.stone: 200, Resource.grain: 260,
      Resource.plank: 100, Resource.bread: 110, Resource.brick: 130,
      Resource.water: 170, Resource.meat: 90, Resource.tools: 65,
    });
    _seed(BuildingType.house, 3, 4);
    _seed(BuildingType.house, 7, 6);
    _seed(BuildingType.lumberCamp, 2, 7);
    _seed(BuildingType.farm, 8, 3);
    _seed(BuildingType.sawmill, 5, 2);
    _seed(BuildingType.well, 8, 8);
    _seed(BuildingType.market, 4, 8);
    _seed(BuildingType.bakery, 7, 2);
    _lastProductionSlot = minute ~/ 30;
    _initRegions();
  }

  void _initRegions() {
    for (final region in kingdomCities) {
      regionalStock.putIfAbsent(region.id, () => {
        for (final r in Resource.values.where((r) => r != Resource.gold))
          r: (region.id == 'capital' ? merchantStock[r] ?? 150 :
              (230 / (region.priceFactor[r] ?? 1.0)).round().clamp(35, 380)).toInt(),
      });
      regionalGold.putIfAbsent(region.id, () => region.id == 'capital' ? merchantGold : 20000);
    }
  }

  void _seed(BuildingType t, int x, int y) => buildings.add(Building(nextBuildingId++, t, x, y));
  int count(Resource r) => inventory[r] ?? 0;
  int get day => minute ~/ 1440 + 1;
  int get hour => (minute % 1440) ~/ 60;
  int get minuteOfHour => minute % 60;
  String get timeLabel => '${hour.toString().padLeft(2, '0')}:${minuteOfHour.toString().padLeft(2, '0')}';
  String get season => ['الربيع', 'الصيف', 'الخريف', 'الشتاء'][((day - 1) ~/ 12) % 4];
  int get level => 1 + (sqrt(xp / 85)).floor();
  int get xpForNext => ((level) * (level)) * 85;
  int get housing => buildings.where((b) => b.type == BuildingType.house).fold<int>(0, (p, b) => p + 4 * b.level);
  int get workersNeeded => buildings.fold<int>(0, (p, b) => p + b.type.spec.work * b.level);
  int get storageCapacity => 950 + buildings.where((b) => b.type == BuildingType.warehouse).fold<int>(0, (p, b) => p + 500 * b.level);
  int get stored => Resource.values.where((r) => r != Resource.gold).fold<int>(0, (p, r) => p + count(r));
  int get rentPerDay {
    final base = buildings.where((b) => b.type == BuildingType.house)
        .fold<int>(0, (p, b) => p + 48 * b.level);
    final factor = [0.75, 1.0, 1.40][taxPolicy];
    return (base * factor * (reputation < 25 ? 0.65 : 1.0)).round();
  }
  int get upkeepPerDay => workersNeeded * 4;
  bool get hasLabor => workersNeeded <= housing;
  bool get isNight => hour < 6 || hour >= 19;
  bool get isAlive => needs['الصحة']! > 0;

  static Future<GameState> load() async {
    final state = GameState();
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(saveKey);
      if (raw != null) {
        state._restore(jsonDecode(raw) as Map<String, dynamic>);
        state.loadedFromDisk = true;
      }
    } catch (e) {
      debugPrint('Cannot load saved game: $e');
    }
    return state;
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(saveKey, jsonEncode(toJson()));
    } catch (e) {
      debugPrint('Cannot save: $e');
    }
  }

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'inventory': {for (final r in Resource.values) r.name: count(r)},
    'merchantStock': {for (final r in Resource.values) r.name: merchantStock[r] ?? 0},
    'buildings': buildings.map((b) => b.toJson()).toList(),
    'history': history.take(30).map((h) => h.toJson()).toList(),
    'completedQuests': completedQuests.toList(),
    'needs': needs,
    'nextBuildingId': nextBuildingId,
    'minute': minute,
    'speed': speed,
    'xp': xp,
    'merchantGold': merchantGold,
    'px': px, 'py': py,
    'housesBuilt': housesBuilt,
    'woodSold': woodSold,
    'planksMade': planksMade,
    'breadEaten': breadEaten,
    'paused': paused,
    'soundOn': soundOn,
    'currentCityId': currentCityId,
    'reputation': reputation,
    'loanDebt': loanDebt,
    'taxPolicy': taxPolicy,
    'caravanStake': caravanStake,
    'caravanMaturityDay': caravanMaturityDay,
    'caravanDestinationId': caravanDestinationId,
    'regionalStock': {
      for (final entry in regionalStock.entries)
        entry.key: {for (final r in Resource.values) r.name: entry.value[r] ?? 0},
    },
    'regionalGold': regionalGold,
  };

  void _restore(Map<String, dynamic> data) {
    if ((data['schema'] as num?)?.toInt() != 1) return;
    final inv = (data['inventory'] as Map?)?.cast<String, dynamic>() ?? {};
    final shop = (data['merchantStock'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final r in Resource.values) {
      if (inv.containsKey(r.name)) inventory[r] = (inv[r.name] as num).toInt().clamp(0, 999999999).toInt();
      if (shop.containsKey(r.name)) merchantStock[r] = (shop[r.name] as num).toInt().clamp(0, 999999999).toInt();
    }
    final savedBuildings = data['buildings'] as List?;
    if (savedBuildings != null) {
      buildings.clear();
      for (final item in savedBuildings) {
        buildings.add(Building.fromJson((item as Map).cast<String, dynamic>()));
      }
    }
    history.clear();
    for (final item in (data['history'] as List? ?? [])) {
      history.add(TradeRecord.fromJson((item as Map).cast<String, dynamic>()));
    }
    completedQuests.addAll((data['completedQuests'] as List? ?? []).cast<String>());
    final savedNeeds = (data['needs'] as Map?)?.cast<String, dynamic>() ?? {};
    for (final key in needs.keys) {
      if (savedNeeds[key] is num) needs[key] = (savedNeeds[key] as num).toDouble().clamp(0, 100).toDouble();
    }
    int number(String key, int fallback) => (data[key] as num?)?.toInt() ?? fallback;
    nextBuildingId = number('nextBuildingId', nextBuildingId);
    minute = max(0, number('minute', minute));
    speed = number('speed', 1).clamp(1, 4).toInt();
    xp = max(0, number('xp', 0));
    merchantGold = max(0, number('merchantGold', merchantGold));
    px = number('px', 5).clamp(0, worldSize - 1).toInt();
    py = number('py', 6).clamp(0, worldSize - 1).toInt();
    housesBuilt = number('housesBuilt', 0);
    woodSold = number('woodSold', 0);
    planksMade = number('planksMade', 0);
    breadEaten = number('breadEaten', 0);
    paused = data['paused'] == true;
    soundOn = data['soundOn'] != false;
    currentCityId = cityById(data['currentCityId'] as String? ?? 'capital').id;
    reputation = number('reputation', 65).clamp(0, 100).toInt();
    loanDebt = max(0, number('loanDebt', 0));
    taxPolicy = number('taxPolicy', 1).clamp(0, 2).toInt();
    caravanStake = max(0, number('caravanStake', 0));
    caravanMaturityDay = max(0, number('caravanMaturityDay', 0));
    caravanDestinationId = data['caravanDestinationId'] as String? ?? '';
    _initRegions();
    final savedStocks = data['regionalStock'];
    if (savedStocks is Map) {
      for (final region in kingdomCities) {
        final stocks = savedStocks[region.id];
        if (stocks is Map) {
          for (final r in Resource.values.where((r) => r != Resource.gold)) {
            if (stocks[r.name] is num) {
              regionalStock[region.id]![r] = (stocks[r.name] as num).toInt().clamp(0, 999999).toInt();
            }
          }
        }
      }
    } else {
      // Migration: legacy saves stored only the capital vendor's stock.
      regionalStock['capital'] = Map<Resource, int>.from(merchantStock);
    }
    final savedGold = data['regionalGold'];
    if (savedGold is Map) {
      for (final region in kingdomCities) {
        if (savedGold[region.id] is num) {
          regionalGold[region.id] = max(0, (savedGold[region.id] as num).toInt());
        }
      }
    } else {
      regionalGold['capital'] = merchantGold;
    }
    // Keep existing market widgets pointed at the market of the active city.
    merchantStock.addAll(regionalStock[currentCityId]!);
    merchantGold = regionalGold[currentCityId]!;
    _lastProductionSlot = minute ~/ 30;
    notifyListeners();
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(saveKey);
  }

  void togglePause() { paused = !paused; notifyListeners(); }
  void cycleSpeed() { speed = speed == 1 ? 2 : speed == 2 ? 4 : 1; notifyListeners(); }
  void toggleSound() { soundOn = !soundOn; notifyListeners(); }

  void advance() {
    if (paused) return;
    final previousDay = day;
    minute += 5 * speed;
    final slot = minute ~/ 30;
    while (_lastProductionSlot < slot) {
      _lastProductionSlot++;
      _produce();
      _degradeNeeds();
    }
    if (day > previousDay) {
      for (var i = previousDay; i < day; i++) {
        _newDay();
      }
    }
    notifyListeners();
  }

  void _newDay() {
    inventory[Resource.gold] = count(Resource.gold) + rentPerDay;
    inventory[Resource.gold] = max(0, count(Resource.gold) - upkeepPerDay);
    // Simulated cities produce/consume every day even when the hero is away.
    for (final region in kingdomCities) {
      final stock = regionalStock[region.id]!;
      for (final r in Resource.values.where((r) => r != Resource.gold)) {
        final supply = region.priceFactor[r] ?? 1;
        final production = (35 / supply).round();
        final consumption = (19 * supply).round();
        stock[r] = (stock[r]! + production - consumption).clamp(12, 550).toInt();
      }
      regionalGold[region.id] = min(65000, regionalGold[region.id]! + 350);
    }
    merchantStock.addAll(regionalStock[currentCityId]!);
    merchantGold = regionalGold[currentCityId]!;
    if (loanDebt > 0) {
      loanDebt += max(1, (loanDebt * 0.02).ceil());
      _log('فائدة قرض يومية 2%: إجمالي الدين $loanDebt ذهب');
    }
    reputation = (reputation + (taxPolicy == 0 ? 2 : taxPolicy == 2 ? -3 : 1))
        .clamp(0, 100).toInt();
    if (caravanStake > 0 && day >= caravanMaturityDay) {
      _settleCaravan();
    }
    history.insert(0, TradeRecord('إيجارات +$rentPerDay | مصروفات -$upkeepPerDay', day));
    if (history.length > 30) history.removeLast();
  }

  void _degradeNeeds() {
    _changeNeed('الجوع', -0.7);
    _changeNeed('العطش', -1.0);
    _changeNeed('الطاقة', -0.85);
    _changeNeed('النظافة', -0.22);
    if (needs['الجوع']! < 18 || needs['العطش']! < 18) _changeNeed('الصحة', -0.8);
    if (needs['الطاقة']! < 12) _changeNeed('الصحة', -0.4);
    if (needs['الجوع']! > 60 && needs['العطش']! > 60 && needs['الطاقة']! > 40) _changeNeed('الصحة', 0.16);
    _changeNeed('المزاج', needs['الصحة']! < 45 ? -0.6 : -0.10);
    if (needs['الصحة']! <= 0) {
      needs['الصحة'] = 35;
      needs['الجوع'] = 30;
      needs['العطش'] = 30;
      needs['الطاقة'] = 45;
      inventory[Resource.gold] = max(0, count(Resource.gold) - 200);
      _log('إغماء البطل: تكلفة علاج 200 ذهب');
    }
  }

  void _changeNeed(String key, double change) {
    needs[key] = (needs[key]! + change).clamp(0.0, 100.0).toDouble();
  }

  void _produce() {
    var availableLabor = housing;
    for (final b in buildings) {
      final needed = b.type.spec.work * b.level;
      if (needed > availableLabor) continue;
      availableLabor -= needed;
      final multiplier = b.level;
      final outputs = <Resource, int>{};
      final inputs = <Resource, int>{};
      switch (b.type) {
        case BuildingType.lumberCamp:
          outputs[Resource.wood] = 10 * multiplier;
        case BuildingType.quarry:
          outputs[Resource.stone] = 7 * multiplier;
        case BuildingType.farm:
          outputs[Resource.grain] = (season == 'الشتاء' ? 5 : 9) * multiplier;
        case BuildingType.sawmill:
          inputs[Resource.wood] = 7 * multiplier;
          outputs[Resource.plank] = 4 * multiplier;
        case BuildingType.bakery:
          inputs[Resource.grain] = 6 * multiplier;
          inputs[Resource.water] = 2 * multiplier;
          outputs[Resource.bread] = 3 * multiplier;
        case BuildingType.brickworks:
          inputs[Resource.stone] = 7 * multiplier;
          outputs[Resource.brick] = 4 * multiplier;
        case BuildingType.workshop:
          inputs[Resource.plank] = 3 * multiplier;
          inputs[Resource.stone] = 2 * multiplier;
          outputs[Resource.tools] = multiplier;
        case BuildingType.well:
          outputs[Resource.water] = 10 * multiplier;
        case BuildingType.house:
        case BuildingType.warehouse:
        case BuildingType.market:
          break;
      }
      if (inputs.entries.any((e) => count(e.key) < e.value)) continue;
      final producedCount = outputs.values.fold<int>(0, (a, b) => a + b);
      final usedCount = inputs.values.fold<int>(0, (a, b) => a + b);
      if (stored - usedCount + producedCount > storageCapacity) continue;
      for (final e in inputs.entries) inventory[e.key] = count(e.key) - e.value;
      for (final e in outputs.entries) inventory[e.key] = count(e.key) + e.value;
      planksMade += outputs[Resource.plank] ?? 0;
    }
  }

  int marketPrice(Resource r, {required bool buying}) {
    if (r == Resource.gold) return 1;
    final stock = merchantStock[r] ?? 100;
    final seasonal = 0.12 * sin(day * 1.37 + r.index * 2.14);
    final multiplier = (1 + (160 - stock) / 600 + seasonal).clamp(0.78, 1.50);
    final regional = city.priceFactor[r] ?? 1.0;
    final spread = buying ? 1.24 : 0.72;
    return max(1, (r.basePrice * multiplier * regional * spread).round());
  }

  GameAction trade(Resource r, int qty, {required bool buying}) {
    if (r == Resource.gold || qty < 1 || qty > 10000) return const GameAction(false, 'كمية غير صالحة');
    final unit = marketPrice(r, buying: buying);
    final total = qty * unit;
    if (buying) {
      if ((merchantStock[r] ?? 0) < qty) return const GameAction(false, 'التاجر لا يملك هذه الكمية');
      if (count(Resource.gold) < total) return const GameAction(false, 'رصيد الذهب غير كافٍ');
      if (stored + qty > storageCapacity) return const GameAction(false, 'المخزن ممتلئ، ابنِ مخزنًا جديدًا');
      inventory[Resource.gold] = count(Resource.gold) - total;
      merchantGold += total;
      inventory[r] = count(r) + qty;
      merchantStock[r] = (merchantStock[r] ?? 0) - qty;
      _log('اشتريت $qty ${r.label} مقابل $total ذهب');
      xp += max(2, qty ~/ 15);
    } else {
      if (count(r) < qty) return const GameAction(false, 'الكمية غير متوفرة في مخزنك');
      if (merchantGold < total) return const GameAction(false, 'التاجر لا يملك ذهبًا كافيًا');
      inventory[r] = count(r) - qty;
      inventory[Resource.gold] = count(Resource.gold) + total;
      merchantStock[r] = (merchantStock[r] ?? 0) + qty;
      merchantGold -= total;
      if (r == Resource.wood) woodSold += qty;
      _log('بعت $qty ${r.label} وربحت $total ذهب');
      xp += max(2, qty ~/ 15);
    }
    regionalStock[currentCityId] = Map<Resource, int>.from(merchantStock);
    regionalGold[currentCityId] = merchantGold;
    notifyListeners();
    return const GameAction(true, 'تم تنفيذ الصفقة بنجاح');
  }

  bool isWaterTile(int x, int y) => y >= 17 && y <= 19 && x < 17 && (x < 5 || x > 7);
  bool inside(int x, int y) => x >= 0 && y >= 0 && x < worldSize && y < worldSize;
  Building? buildingAt(int x, int y) {
    for (final b in buildings) {
      if (b.x == x && b.y == y) return b;
    }
    return null;
  }
  bool canPlace(int x, int y) => inside(x, y) && !isWaterTile(x, y) &&
      !kingdomCities.any((c) => c.x == x && c.y == y) &&
      buildingAt(x, y) == null && !(x == px && y == py);

  Map<Resource, int> buildingCost(BuildingType type, {int upgradeLevel = 1}) => {
    for (final e in type.spec.cost.entries)
      e.key: (e.value * (upgradeLevel == 1 ? 1 : (0.75 * upgradeLevel))).ceil(),
  };
  bool canAfford(Map<Resource, int> costs) => costs.entries.every((e) => count(e.key) >= e.value);
  void _spend(Map<Resource, int> costs) {
    for (final e in costs.entries) inventory[e.key] = count(e.key) - e.value;
  }

  GameAction build(BuildingType type, int x, int y) {
    if (!inside(x, y)) return const GameAction(false, 'الموقع خارج حدود القرية');
    if (!canPlace(x, y)) return const GameAction(false, 'الموقع مشغول أو أرض غير صالحة للبناء');
    final cost = buildingCost(type);
    if (!canAfford(cost)) return const GameAction(false, 'مواد البناء أو الذهب غير كافية');
    _spend(cost);
    buildings.add(Building(nextBuildingId++, type, x, y));
    if (type == BuildingType.house) housesBuilt++;
    xp += 35;
    _log('تم بناء ${type.spec.name} في ($x، $y)');
    notifyListeners();
    return GameAction(true, 'اكتمل بناء ${type.spec.name}!');
  }

  GameAction upgrade(Building b) {
    if (!buildings.contains(b)) return const GameAction(false, 'المبنى غير موجود');
    if (b.level >= 5) return const GameAction(false, 'وصل المبنى للمستوى الأقصى');
    final cost = buildingCost(b.type, upgradeLevel: b.level + 1);
    if (!canAfford(cost)) return const GameAction(false, 'موارد الترقية غير كافية');
    _spend(cost);
    b.level++;
    xp += 50;
    _log('تمت ترقية ${b.type.spec.name} للمستوى ${b.level}');
    notifyListeners();
    return const GameAction(true, 'تمت الترقية بنجاح');
  }

  int saleValue(Building b) {
    final original = b.type.spec.cost[Resource.gold] ?? 0;
    return (original * (0.65 + 0.30 * (b.level - 1))).round();
  }

  GameAction sellBuilding(Building b) {
    if (!buildings.contains(b)) return const GameAction(false, 'هذا المبنى غير موجود');
    if (b.type == BuildingType.house && buildings.where((v) => v.type == BuildingType.house).length <= 1) {
      return const GameAction(false, 'لا يمكنك بيع آخر منزل للأهالي');
    }
    final value = saleValue(b);
    if (merchantGold < value) return const GameAction(false, 'السوق لا يملك سيولة لشراء هذا العقار');
    buildings.remove(b);
    inventory[Resource.gold] = count(Resource.gold) + value;
    merchantGold -= value;
    regionalGold[currentCityId] = merchantGold;
    xp += 12;
    _log('بعت ${b.type.spec.name} بالمستوى ${b.level} مقابل $value ذهب');
    notifyListeners();
    return GameAction(true, 'تم بيع العقار مقابل $value ذهب');
  }

  void _log(String message) {
    history.insert(0, TradeRecord(message, day));
    if (history.length > 30) history.removeLast();
  }

  GameAction act(String action) {
    switch (action) {
      case 'eat':
        final food = count(Resource.bread) > 0 ? Resource.bread : Resource.meat;
        if (count(food) == 0) return const GameAction(false, 'لا يوجد طعام؛ اشترِ خبزًا أو شغّل المخبز');
        inventory[food] = count(food) - 1;
        _changeNeed('الجوع', food == Resource.bread ? 30 : 44);
        _changeNeed('المزاج', 2);
        breadEaten++;
        xp += 3;
      case 'drink':
        if (count(Resource.water) < 1) return const GameAction(false, 'لا يوجد ماء؛ ابنِ بئرًا أو اشترِ مياه');
        inventory[Resource.water] = count(Resource.water) - 1;
        _changeNeed('العطش', 37);
        xp += 1;
      case 'sleep':
        final previousDay = day;
        minute += 180;
        while (_lastProductionSlot < minute ~/ 30) {
          _lastProductionSlot++;
          _produce();
          _degradeNeeds();
        }
        for (var d = previousDay; d < day; d++) { _newDay(); }
        _changeNeed('الطاقة', 66);
        _changeNeed('الصحة', 8);
        _changeNeed('المزاج', 5);
        _changeNeed('الجوع', -7);
        _changeNeed('العطش', -9);
      case 'wash':
        if (count(Resource.water) < 2) return const GameAction(false, 'تحتاج وحدتين من الماء');
        inventory[Resource.water] = count(Resource.water) - 2;
        _changeNeed('النظافة', 40);
        _changeNeed('المزاج', 3);
      case 'chop':
        if (needs['الطاقة']! < 10) return const GameAction(false, 'البطل مرهق ويحتاج للراحة');
        if (stored + 9 > storageCapacity) return const GameAction(false, 'المخزن ممتلئ');
        inventory[Resource.wood] = count(Resource.wood) + 9;
        _changeNeed('الطاقة', -8);
        _changeNeed('الجوع', -2);
        xp += 6;
      case 'mine':
        if (needs['الطاقة']! < 10) return const GameAction(false, 'البطل مرهق ويحتاج للراحة');
        if (stored + 6 > storageCapacity) return const GameAction(false, 'المخزن ممتلئ');
        inventory[Resource.stone] = count(Resource.stone) + 6;
        _changeNeed('الطاقة', -9);
        _changeNeed('الجوع', -2);
        xp += 7;
      case 'craft':
        if (count(Resource.plank) < 3 || count(Resource.stone) < 2) {
          return const GameAction(false, 'التصنيع يحتاج 3 ألواح و2 حجر');
        }
        if (stored - 4 > storageCapacity) return const GameAction(false, 'المخزن ممتلئ');
        inventory[Resource.plank] = count(Resource.plank) - 3;
        inventory[Resource.stone] = count(Resource.stone) - 2;
        inventory[Resource.tools] = count(Resource.tools) + 1;
        _changeNeed('الطاقة', -5);
        xp += 12;
      default:
        return const GameAction(false, 'الأمر غير معروف');
    }
    notifyListeners();
    return const GameAction(true, 'تم تنفيذ الإجراء بنجاح');
  }

  /// Travel is not teleportation: it costs fare, food, water, energy and time.
  GameAction travelTo(String destinationId) {
    final target = cityById(destinationId);
    if (target.id == currentCityId) {
      return const GameAction(false, 'أنت موجود بالفعل في هذه المدينة');
    }
    final hours = travelHours(city, target);
    final fare = travelFare(city, target);
    final food = max(1, hours ~/ 4);
    if (count(Resource.gold) < fare) return const GameAction(false, 'الذهب لا يكفي ثمن السفر');
    if (count(Resource.bread) < food || count(Resource.water) < food) {
      return const GameAction(false, 'جهّز الخبز والماء اللازمين للسفر');
    }
    if (needs['الطاقة']! < 15) return const GameAction(false, 'البطل مرهق ويحتاج إلى النوم');
    inventory[Resource.gold] = count(Resource.gold) - fare;
    inventory[Resource.bread] = count(Resource.bread) - food;
    inventory[Resource.water] = count(Resource.water) - food;
    _changeNeed('الطاقة', -min(38, hours * 3).toDouble());
    _changeNeed('الجوع', -min(25, hours * 2).toDouble());
    _changeNeed('العطش', -min(28, hours * 2).toDouble());
    // Save vendor state before changing region.
    regionalStock[currentCityId] = Map<Resource, int>.from(merchantStock);
    regionalGold[currentCityId] = merchantGold;
    final oldDay = day;
    minute += hours * 60;
    while (_lastProductionSlot < minute ~/ 30) {
      _lastProductionSlot++;
      _produce();
      _degradeNeeds();
    }
    for (var d = oldDay; d < day; d++) { _newDay(); }
    currentCityId = target.id;
    merchantStock.addAll(regionalStock[target.id]!);
    merchantGold = regionalGold[target.id]!;
    px = target.x;
    py = target.y;
    route.clear();
    // Deterministic risk roll, reproducible in tests/offline play.
    final roll = ((day * 17 + target.x * 13 + target.y * 7 + xp) % 100) / 100.0;
    var incident = '';
    if (roll < target.danger) {
      final loss = min(count(Resource.gold), (fare * 0.6).round());
      inventory[Resource.gold] = count(Resource.gold) - loss;
      _changeNeed('الصحة', -8);
      reputation = max(0, reputation - 2);
      incident = '، وتعرضت القافلة للخطر وخسرت $loss ذهب';
    } else {
      xp += 20 + hours;
    }
    _log('سافرت إلى ${target.name} بتكلفة $fare ذهب و$food طعام/ماء$incident');
    notifyListeners();
    return GameAction(true, 'وصلت ${target.name} بعد $hours ساعات$incident');
  }

  GameAction chooseTaxes(int policy) {
    if (policy < 0 || policy > 2) return const GameAction(false, 'سياسة غير صالحة');
    taxPolicy = policy;
    _log('غيرت الضرائب إلى ${['مخفّضة', 'متوازنة', 'مرتفعة'][policy]}');
    notifyListeners();
    return const GameAction(true, 'تم تغيير الضرائب؛ سيتغير دخل الإيجارات ورضا السكان');
  }

  GameAction borrow(int amount) {
    if (amount <= 0 || amount > 2000 || loanDebt + amount > 3000) {
      return const GameAction(false, 'حد القروض الأقصى 3,000 ذهب');
    }
    if (reputation < 30) return const GameAction(false, 'سمعتك ضعيفة للحصول على قرض');
    loanDebt += amount;
    inventory[Resource.gold] = count(Resource.gold) + amount;
    _log('اقترضت $amount ذهب بفائدة مركبة 2% لكل يوم لعبة');
    notifyListeners();
    return GameAction(true, 'حصلت على $amount ذهب؛ لا تنسَ فوائد الدين');
  }

  GameAction repay(int amount) {
    if (loanDebt <= 0) return const GameAction(false, 'لا يوجد دين');
    final payment = min(amount, loanDebt);
    if (payment < 1 || count(Resource.gold) < payment) {
      return const GameAction(false, 'لا تملك ذهبًا كافيًا للسداد');
    }
    inventory[Resource.gold] = count(Resource.gold) - payment;
    loanDebt -= payment;
    reputation = min(100, reputation + 2);
    _log('سددت $payment ذهب من القرض');
    notifyListeners();
    return GameAction(true, 'تم سداد $payment ذهب، المتبقي $loanDebt');
  }

  GameAction investCaravan(int amount, String destinationId) {
    if (caravanStake > 0) return const GameAction(false, 'لديك قافلة استثمار قائمة بالفعل');
    if (amount < 100 || amount > 3000 || count(Resource.gold) < amount) {
      return const GameAction(false, 'استثمار غير صالح أو رصيد غير كافٍ');
    }
    final destination = cityById(destinationId);
    if (destination.id == currentCityId) {
      return const GameAction(false, 'اختر مدينة أخرى لتوجيه القافلة إليها');
    }
    inventory[Resource.gold] = count(Resource.gold) - amount;
    caravanStake = amount;
    caravanDestinationId = destinationId;
    caravanMaturityDay = day + 2 + travelHours(city, destination) ~/ 4;
    _log('أرسلت قافلة استثمار $amount ذهب إلى ${destination.name} حتى يوم $caravanMaturityDay');
    notifyListeners();
    return const GameAction(true, 'انطلقت القافلة، والعائد ليس مضمونًا');
  }

  void _settleCaravan() {
    final destination = cityById(caravanDestinationId);
    final amount = caravanStake;
    final riskRoll = ((day * 23 + destination.x * 7 + amount ~/ 25) % 100) / 100.0;
    // An adverse result loses part of the stake; good trade creates profit.
    final fraction = riskRoll < destination.danger ? -0.42 :
        riskRoll < destination.danger + 0.26 ? -0.10 :
        riskRoll < 0.79 ? 0.12 : 0.31;
    final payout = max(0, (amount * (1 + fraction)).round());
    inventory[Resource.gold] = count(Resource.gold) + payout;
    _log('عادت قافلة ${destination.name}: استثمرت $amount، واستلمت $payout ذهب');
    if (payout > amount) reputation = min(100, reputation + 2);
    caravanStake = 0;
    caravanMaturityDay = 0;
    caravanDestinationId = '';
  }

  static const quests = <String, String>{
    'build': 'ابنِ منزلًا إضافيًا',
    'sell': 'بع 30 وحدة من الخشب في السوق',
    'plank': 'أنتج 20 لوحًا بالمنشرة',
    'food': 'أطعم بطلك 3 مرات',
    'wealth': 'اجمع 5,000 قطعة ذهبية',
    'level': 'ارفع مستوى الشخصية إلى 4',
  };
  bool questDone(String key) => switch (key) {
    'build' => housesBuilt >= 1,
    'sell' => woodSold >= 30,
    'plank' => planksMade >= 20,
    'food' => breadEaten >= 3,
    'wealth' => count(Resource.gold) >= 5000,
    'level' => level >= 4,
    _ => false,
  };
  String questProgress(String key) => switch (key) {
    'build' => '$housesBuilt/1',
    'sell' => '$woodSold/30',
    'plank' => '$planksMade/20',
    'food' => '$breadEaten/3',
    'wealth' => '${count(Resource.gold)}/5000',
    'level' => '$level/4',
    _ => '',
  };
  GameAction claim(String key) {
    if (completedQuests.contains(key)) return const GameAction(false, 'استلمت المكافأة بالفعل');
    if (!questDone(key)) return const GameAction(false, 'المهمة لم تكتمل بعد');
    completedQuests.add(key);
    inventory[Resource.gold] = count(Resource.gold) + 220;
    xp += 70;
    _log('مكافأة مهمة: 220 ذهب و70 خبرة');
    notifyListeners();
    return const GameAction(true, 'حصلت على 220 ذهب و70 خبرة!');
  }

  /// Breadth first search on the grid. Build tiles are solid obstacles.
  GameAction walkTo(int targetX, int targetY) {
    if (!inside(targetX, targetY)) return const GameAction(false, 'خارج حدود القرية');
    if (buildingAt(targetX, targetY) != null || isWaterTile(targetX, targetY)) return const GameAction(false, 'اختر أرضًا صالحة للمشي');
    final start = Point(px, py), target = Point(targetX, targetY);
    final queue = Queue<Point<int>>()..add(start);
    final parent = <Point<int>, Point<int>?>{start: null};
    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      if (node == target) break;
      for (final delta in const [Point(1, 0), Point(-1, 0), Point(0, 1), Point(0, -1)]) {
        final next = Point(node.x + delta.x, node.y + delta.y);
        if (!inside(next.x, next.y) || isWaterTile(next.x, next.y) || buildingAt(next.x, next.y) != null || parent.containsKey(next)) continue;
        parent[next] = node;
        queue.add(next);
      }
    }
    if (!parent.containsKey(target)) return const GameAction(false, 'لا يوجد طريق لهذا المكان');
    route.clear();
    var current = target;
    while (current != start) {
      route.insert(0, current);
      current = parent[current]!;
    }
    notifyListeners();
    return const GameAction(true, 'جارٍ التحرك');
  }

  void stepWalk() {
    if (paused || route.isEmpty) return;
    final step = route.removeAt(0);
    px = step.x;
    py = step.y;
    notifyListeners();
  }
}

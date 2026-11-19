import 'package:flutter/material.dart';

enum Resource { gold, wood, stone, grain, plank, bread, brick, water, meat, tools }

extension ResourceInfo on Resource {
  String get label => switch (this) {
        Resource.gold => 'ذهب',
        Resource.wood => 'خشب',
        Resource.stone => 'حجر',
        Resource.grain => 'قمح',
        Resource.plank => 'ألواح',
        Resource.bread => 'خبز',
        Resource.brick => 'طوب',
        Resource.water => 'ماء',
        Resource.meat => 'لحم',
        Resource.tools => 'أدوات',
      };
  String get symbol => switch (this) {
        Resource.gold => '🪙',
        Resource.wood => '🪵',
        Resource.stone => '🪨',
        Resource.grain => '🌾',
        Resource.plank => '🪚',
        Resource.bread => '🥖',
        Resource.brick => '🧱',
        Resource.water => '💧',
        Resource.meat => '🍖',
        Resource.tools => '⚒️',
      };
  IconData get icon => switch (this) {
        Resource.gold => Icons.monetization_on_rounded,
        Resource.wood => Icons.forest_rounded,
        Resource.stone => Icons.terrain_rounded,
        Resource.grain => Icons.grass_rounded,
        Resource.plank => Icons.carpenter_rounded,
        Resource.bread => Icons.bakery_dining_rounded,
        Resource.brick => Icons.grid_on_rounded,
        Resource.water => Icons.water_drop_rounded,
        Resource.meat => Icons.restaurant_rounded,
        Resource.tools => Icons.handyman_rounded,
      };
  int get basePrice => switch (this) {
        Resource.gold => 1,
        Resource.wood => 8,
        Resource.stone => 10,
        Resource.grain => 6,
        Resource.plank => 21,
        Resource.bread => 26,
        Resource.brick => 20,
        Resource.water => 5,
        Resource.meat => 39,
        Resource.tools => 75,
      };
  Color get color => switch (this) {
        Resource.gold => const Color(0xffffca58),
        Resource.wood => const Color(0xffc79056),
        Resource.stone => const Color(0xffabb4c3),
        Resource.grain => const Color(0xffe6c765),
        Resource.plank => const Color(0xffdca66f),
        Resource.bread => const Color(0xffd99350),
        Resource.brick => const Color(0xffd87859),
        Resource.water => const Color(0xff72c7ed),
        Resource.meat => const Color(0xffe88c84),
        Resource.tools => const Color(0xffb3bbcb),
      };
}

enum BuildingType { house, lumberCamp, quarry, farm, sawmill, bakery, brickworks, workshop, well, warehouse, market }

class BuildingSpec {
  final String name;
  final String description;
  final IconData icon;
  final Map<Resource, int> cost;
  final int work;
  const BuildingSpec(this.name, this.description, this.icon, this.cost, this.work);
}

const specs = <BuildingType, BuildingSpec>{
  BuildingType.house: BuildingSpec('منزل', 'سكن للأهالي وعائد يومي من الإيجار', Icons.home_rounded,
      {Resource.wood: 60, Resource.stone: 30, Resource.plank: 10, Resource.gold: 350}, 0),
  BuildingType.lumberCamp: BuildingSpec('معسكر الحطابين', 'يستخرج جذوع الأشجار من الغابة', Icons.forest_rounded,
      {Resource.wood: 40, Resource.stone: 12, Resource.gold: 250}, 2),
  BuildingType.quarry: BuildingSpec('المحجر', 'يستخرج الحجر للمشروعات', Icons.landscape_rounded,
      {Resource.wood: 50, Resource.tools: 1, Resource.gold: 320}, 2),
  BuildingType.farm: BuildingSpec('مزرعة القمح', 'تزرع القمح لصناعة الطعام', Icons.grass_rounded,
      {Resource.wood: 40, Resource.stone: 10, Resource.gold: 220}, 1),
  BuildingType.sawmill: BuildingSpec('منشرة', 'تحول الخشب الخام إلى ألواح', Icons.carpenter_rounded,
      {Resource.wood: 50, Resource.stone: 30, Resource.gold: 380}, 2),
  BuildingType.bakery: BuildingSpec('مخبز', 'يحول القمح والماء إلى خبز', Icons.bakery_dining_rounded,
      {Resource.wood: 50, Resource.stone: 40, Resource.gold: 400}, 2),
  BuildingType.brickworks: BuildingSpec('مصنع الطوب', 'يصنع الطوب باستخدام الحجر', Icons.grid_view_rounded,
      {Resource.wood: 55, Resource.stone: 30, Resource.gold: 430}, 2),
  BuildingType.workshop: BuildingSpec('ورشة أدوات', 'تصنع المعدات من الألواح والحجر', Icons.handyman_rounded,
      {Resource.wood: 60, Resource.stone: 40, Resource.gold: 470}, 2),
  BuildingType.well: BuildingSpec('بئر ماء', 'يزود القرية بالمياه العذبة', Icons.water_drop_rounded,
      {Resource.wood: 25, Resource.stone: 45, Resource.gold: 250}, 0),
  BuildingType.warehouse: BuildingSpec('مخزن', 'يوسع سعة تخزين الموارد', Icons.inventory_2_rounded,
      {Resource.wood: 70, Resource.stone: 50, Resource.gold: 550}, 0),
  BuildingType.market: BuildingSpec('السوق', 'يسمح بتجارة الموارد وبيع الممتلكات', Icons.storefront_rounded,
      {Resource.wood: 70, Resource.stone: 35, Resource.gold: 550}, 1),
};

extension BuildingInfo on BuildingType {
  BuildingSpec get spec => specs[this]!;
}

class Building {
  final int id;
  final BuildingType type;
  final int x;
  final int y;
  int level;
  double progress;
  Building(this.id, this.type, this.x, this.y, {this.level = 1, this.progress = 0});

  Map<String, dynamic> toJson() => {
    'id': id, 'type': type.name, 'x': x, 'y': y, 'level': level, 'progress': progress,
  };

  factory Building.fromJson(Map<String, dynamic> json) {
    return Building(
      (json['id'] as num).toInt(),
      BuildingType.values.firstWhere((v) => v.name == json['type']),
      (json['x'] as num).toInt(),
      (json['y'] as num).toInt(),
      level: (json['level'] as num?)?.toInt() ?? 1,
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
    );
  }
}

class TradeRecord {
  final String summary;
  final int day;
  TradeRecord(this.summary, this.day);
  Map<String, dynamic> toJson() => {'summary': summary, 'day': day};
  factory TradeRecord.fromJson(Map<String, dynamic> j) =>
      TradeRecord(j['summary'] as String, (j['day'] as num).toInt());
}

class GameAction {
  final bool ok;
  final String message;
  const GameAction(this.ok, this.message);
}

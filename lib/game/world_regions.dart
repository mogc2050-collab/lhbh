import 'dart:math';
import 'catalog.dart';

/// Immutable offline world definition: four towns with different specialties.
/// Prices are calculated rather than downloaded from a server.
class KingdomCity {
  final String id;
  final String name;
  final String description;
  final int x;
  final int y;
  final double danger;
  final Map<Resource, double> priceFactor;
  const KingdomCity(this.id, this.name, this.description, this.x, this.y,
      this.danger, this.priceFactor);
}

const kingdomCities = <KingdomCity>[
  KingdomCity('capital', 'مدينة الوادي', 'مدينتك الرئيسية: الإسكان والصناعة والأسواق', 5, 5, 0.08, {
    Resource.wood: 1.00, Resource.stone: 1.02, Resource.grain: 1.10,
    Resource.plank: 1.00, Resource.bread: 1.08, Resource.brick: 1.00,
    Resource.water: 1.00, Resource.meat: 1.10, Resource.tools: 1.05,
  }),
  KingdomCity('forest', 'مدينة الغابة', 'الأخشاب وفيرة، لكن الطعام المستورد غالٍ', 25, 6, 0.18, {
    Resource.wood: 0.62, Resource.stone: 1.28, Resource.grain: 1.40,
    Resource.plank: 0.78, Resource.bread: 1.38, Resource.brick: 1.30,
    Resource.water: 0.95, Resource.meat: 1.14, Resource.tools: 1.25,
  }),
  KingdomCity('harbor', 'مدينة الميناء', 'تجارة نشطة وأغذية وفيرة وطلب مرتفع على مواد البناء', 7, 25, 0.13, {
    Resource.wood: 1.32, Resource.stone: 1.22, Resource.grain: 0.75,
    Resource.plank: 1.38, Resource.bread: 0.78, Resource.brick: 1.35,
    Resource.water: 0.80, Resource.meat: 0.70, Resource.tools: 1.28,
  }),
  KingdomCity('mountains', 'مدينة الجبال', 'الحجر والمعادن رخيصة؛ الخشب والأدوات مطلوبة', 25, 25, 0.30, {
    Resource.wood: 1.45, Resource.stone: 0.62, Resource.grain: 1.25,
    Resource.plank: 1.50, Resource.bread: 1.26, Resource.brick: 0.80,
    Resource.water: 1.24, Resource.meat: 1.12, Resource.tools: 1.38,
  }),
];

KingdomCity cityById(String id) => kingdomCities.firstWhere(
  (c) => c.id == id, orElse: () => kingdomCities.first,
);

int travelDistance(KingdomCity from, KingdomCity to) =>
    (from.x - to.x).abs() + (from.y - to.y).abs();

int travelFare(KingdomCity from, KingdomCity to) =>
    max(25, travelDistance(from, to) * 6);

int travelHours(KingdomCity from, KingdomCity to) =>
    max(2, (travelDistance(from, to) / 5).ceil());

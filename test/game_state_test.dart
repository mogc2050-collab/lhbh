import 'package:flutter_test/flutter_test.dart';
import 'package:medieval_life/game/catalog.dart';
import 'package:medieval_life/game/game_state.dart';
import 'package:medieval_life/game/world_regions.dart';

void main() {
  group('Local game economy', () {
    test('new game has player, land, resources and eight buildings', () {
      final game = GameState();
      expect(game.buildings.length, 8);
      expect(game.count(Resource.gold), greaterThan(0));
      expect(game.housing, 8);
      expect(GameState.worldSize, 32);
    });

    test('buying subtracts gold, reduces vendor stock and adds resources', () {
      final game = GameState();
      final initialGold = game.count(Resource.gold);
      final stock = game.merchantStock[Resource.stone]!;
      final initial = game.count(Resource.stone);
      final cost = game.marketPrice(Resource.stone, buying: true) * 2;
      final result = game.trade(Resource.stone, 2, buying: true);
      expect(result.ok, isTrue);
      expect(game.count(Resource.gold), initialGold - cost);
      expect(game.count(Resource.stone), initial + 2);
      expect(game.merchantStock[Resource.stone], stock - 2);
    });

    test('merchant never pays more per item than it charges', () {
      final game = GameState();
      for (final r in Resource.values.where((r) => r != Resource.gold)) {
        expect(game.marketPrice(r, buying: true), greaterThan(game.marketPrice(r, buying: false)));
      }
    });

    test('selling more stock than owned is rejected', () {
      final game = GameState();
      expect(game.trade(Resource.tools, 100, buying: false).ok, isFalse);
      expect(game.trade(Resource.stone, 0, buying: true).ok, isFalse);
    });

    test('house building takes actual resources and increases housing', () {
      final game = GameState();
      final wood = game.count(Resource.wood);
      final money = game.count(Resource.gold);
      final result = game.build(BuildingType.house, 9, 9);
      expect(result.ok, isTrue);
      expect(game.count(Resource.wood), lessThan(wood));
      expect(game.count(Resource.gold), lessThan(money));
      expect(game.housing, 12);
      expect(game.housesBuilt, 1);
    });

    test('properties can be sold for a payout', () {
      final game = GameState();
      final firstHouse = game.buildings.firstWhere((b) => b.type == BuildingType.house);
      final price = game.saleValue(firstHouse);
      final gold = game.count(Resource.gold);
      expect(game.sellBuilding(firstHouse).ok, isTrue);
      expect(game.count(Resource.gold), gold + price);
    });

    test('hand crafting consumes planks and stone', () {
      final game = GameState();
      final planks = game.count(Resource.plank);
      final tools = game.count(Resource.tools);
      expect(game.act('craft').ok, isTrue);
      expect(game.count(Resource.plank), planks - 3);
      expect(game.count(Resource.tools), tools + 1);
    });

    test('quest rewards cannot be claimed twice', () {
      final game = GameState();
      expect(game.build(BuildingType.house, 10, 9).ok, isTrue);
      expect(game.claim('build').ok, isTrue);
      expect(game.claim('build').ok, isFalse);
    });

    test('player navigates on walkable tiles', () {
      final game = GameState();
      expect(game.walkTo(6, 5).ok, isTrue);
      for (var i = 0; i < 30; i++) { game.stepWalk(); }
      expect(game.px, 6);
      expect(game.py, 5);
    });


    test('all four cities exist within the expanded world', () {
      expect(kingdomCities.length, 4);
      for (final city in kingdomCities) {
        expect(city.x, inInclusiveRange(0, GameState.worldSize - 1));
        expect(city.y, inInclusiveRange(0, GameState.worldSize - 1));
      }
      expect(GameState.worldSize * GameState.worldSize, 1024);
    });

    test('different cities have independent market prices and stock', () {
      final game = GameState();
      final homeWoodPrice = game.marketPrice(Resource.wood, buying: true);
      final originalStock = game.merchantStock[Resource.wood];
      final result = game.travelTo('forest');
      expect(result.ok, isTrue);
      expect(game.city.name, 'مدينة الغابة');
      expect(game.marketPrice(Resource.wood, buying: true), lessThan(homeWoodPrice));
      expect(game.merchantStock[Resource.wood], isNot(originalStock));
      expect(game.travelTo('capital').ok, isTrue);
      expect(game.merchantStock[Resource.wood], originalStock);
    });

    test('travel consumes fare and food and moves hero between towns', () {
      final game = GameState();
      final oldGold = game.count(Resource.gold);
      final oldBread = game.count(Resource.bread);
      expect(game.travelTo('harbor').ok, isTrue);
      expect(game.currentCityId, 'harbor');
      expect(game.px, 7);
      expect(game.py, 25);
      expect(game.count(Resource.gold), lessThan(oldGold));
      expect(game.count(Resource.bread), lessThan(oldBread));
      expect(game.travelTo('harbor').ok, isFalse);
    });

    test('trading in a city updates its own independent merchant stock', () {
      final game = GameState();
      expect(game.travelTo('forest').ok, isTrue);
      final stock = game.merchantStock[Resource.wood]!;
      expect(game.trade(Resource.wood, 2, buying: true).ok, isTrue);
      expect(game.merchantStock[Resource.wood], stock - 2);
      expect(game.regionalStock['forest']![Resource.wood], stock - 2);
    });

    test('loans increase cash and debt while repayment reduces both', () {
      final game = GameState();
      final old = game.count(Resource.gold);
      expect(game.borrow(500).ok, isTrue);
      expect(game.loanDebt, 500);
      expect(game.count(Resource.gold), old + 500);
      expect(game.repay(200).ok, isTrue);
      expect(game.loanDebt, 300);
    });

    test('tax policy changes rent and affects public satisfaction', () {
      final game = GameState();
      final balancedRent = game.rentPerDay;
      expect(game.chooseTaxes(2).ok, isTrue);
      expect(game.rentPerDay, greaterThan(balancedRent));
      expect(game.chooseTaxes(0).ok, isTrue);
      expect(game.rentPerDay, lessThan(balancedRent));
    });

    test('caravans have a maturity day and money is invested immediately', () {
      final game = GameState();
      final before = game.count(Resource.gold);
      expect(game.investCaravan(500, 'forest').ok, isTrue);
      expect(game.caravanStake, 500);
      expect(game.count(Resource.gold), before - 500);
      expect(game.investCaravan(500, 'harbor').ok, isFalse);
      expect(game.caravanMaturityDay, greaterThan(game.day));
    });

    test('new regional data is included without breaking old save schema', () {
      final game = GameState();
      final json = game.toJson();
      expect(json['schema'], 1);
      expect((json['regionalStock'] as Map).length, 4);
      expect(json['currentCityId'], 'capital');
      expect(json['loanDebt'], 0);
    });

    test('save JSON contains necessary offline data', () {
      final game = GameState();
      final data = game.toJson();
      expect(data['schema'], 1);
      expect((data['buildings'] as List).length, 8);
      expect((data['inventory'] as Map).containsKey('wood'), isTrue);
    });
  });
}

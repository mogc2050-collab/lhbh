import 'package:flutter_test/flutter_test.dart';
import 'package:medieval_life/kingdom/catalog.dart';
import 'package:medieval_life/kingdom/engine.dart';

void main(){
 group('Rebuilt kingdom V3 - independent offline engine',(){
   test('creates 64x64 world with four actual cities and independent objects',(){
     final g=KingdomEngine();
     expect(KingdomEngine.worldSize,64);
     expect(towns.length,4);
     expect(Facility.values.length,20);
     expect(Good.values.length,17);
     expect(g.sites.length,greaterThan(20));
     expect(g.sites.where((s)=>s.owned),isNotEmpty);
     expect(g.cityId,'valley');
     expect(g.heroX,11);
     expect(g.stock[Good.wood],greaterThan(0));
   });
   test('places a house, pays for it and increases housing',(){
     final g=KingdomEngine();
     final oldGold=g.gold, oldWood=g.amount(Good.wood);
     final oldPopulation=g.population;
     final result=g.construct(Facility.house,16,15);
     expect(result.ok,isTrue);
     expect(g.siteAt(16,15)?.kind,Facility.house);
     expect(g.gold,lessThan(oldGold));
     expect(g.amount(Good.wood),lessThan(oldWood));
     expect(g.population,oldPopulation+4);
   });
   test('building in water and over another building is rejected',(){
     final g=KingdomEngine();
     expect(g.construct(Facility.house,31,30).ok,isFalse);
     expect(g.construct(Facility.house,7,9).ok,isFalse);
     expect(g.construct(Facility.castle,16,15).ok,isFalse);
   });
   test('upgrade spends materials and sale removes the actual property',(){
     final g=KingdomEngine();
     final house=g.sites.firstWhere((s)=>s.kind==Facility.house&&s.owned);
     expect(g.upgrade(house).ok,isTrue);
     expect(house.level,2);
     final money=g.gold;
     final sale=g.saleValue(house);
     expect(g.sellSite(house).ok,isTrue);
     expect(g.gold,money+sale);
     expect(g.sites.contains(house),isFalse);
   });
   test('production recipe requires inputs and produces real output',(){
     final g=KingdomEngine();
     final bread=g.amount(Good.bread);
     g.passMinutes(60);
     expect(g.amount(Good.bread),greaterThan(bread));
     expect(g.labor,lessThanOrEqualTo(g.population));
   });
   test('broken supply chain cannot manufacture goods from nothing',(){
     final g=KingdomEngine();
     g.stock[Good.grain]=0;
     g.stock[Good.flour]=0;
     // Farms need water and run before the well in the hourly cycle.
     g.stock[Good.water]=0;
     final bread=g.amount(Good.bread);
     g.passMinutes(60);
     expect(g.amount(Good.bread),bread);
   });
   test('market buy subtracts money, changes seller stock and adds goods',(){
     final g=KingdomEngine();
     final gold=g.gold;
     final vendor=g.cityStock[g.cityId]![Good.stone]!;
     final stones=g.amount(Good.stone);
     final price=g.marketPrice(Good.stone,buying:true);
     expect(g.trade(Good.stone,3,buying:true).ok,isTrue);
     expect(g.gold,gold-3*price);
     expect(g.amount(Good.stone),stones+3);
     expect(g.cityStock[g.cityId]![Good.stone],vendor-3);
   });
   test('market sales pay cash, consume inventory and update vendor stock',(){
     final g=KingdomEngine();
     final oldGold=g.gold, oldWood=g.amount(Good.wood);
     expect(g.trade(Good.wood,5,buying:false).ok,isTrue);
     expect(g.gold,greaterThan(oldGold));
     expect(g.amount(Good.wood),oldWood-5);
   });
   test('trading cannot exploit negative quantities or unlimited stock',(){
     final g=KingdomEngine();
     expect(g.trade(Good.wood,0,buying:true).ok,isFalse);
     expect(g.trade(Good.wood,-5,buying:false).ok,isFalse);
     expect(g.trade(Good.wood,5000,buying:true).ok,isFalse);
     expect(g.trade(Good.gold,1,buying:true).ok,isFalse);
   });
   test('regional prices respond to location and regional specialization',(){
     final g=KingdomEngine();
     final valleyPrice=g.marketPrice(Good.wood,buying:true);
     expect(g.travel('forest').ok,isTrue);
     expect(g.city.name,'مدينة الغابة');
     expect(g.marketPrice(Good.wood,buying:true),lessThan(valleyPrice));
   });
   test('travel consumes fare and provisions while production continues',(){
     final g=KingdomEngine();
     final target=townById('port');
     final before=g.gold;
     final cost=g.travelCost(target);
     expect(g.travel(target.id).ok,isTrue);
     expect(g.heroX,target.x);
     expect(g.heroY,target.y);
     expect(g.gold,lessThanOrEqualTo(before-cost));
     expect(g.cityId,'port');
     expect(g.travel(target.id).ok,isFalse);
   });
   test('delivering contract only succeeds at correct city with cargo',(){
     final g=KingdomEngine();
     final contract=deliveries.first;
     expect(g.deliver(contract).ok,isFalse);
     expect(g.travel(contract.destination).ok,isTrue);
     final before=g.gold;
     expect(g.deliver(contract).ok,isTrue);
     expect(g.gold,before+contract.reward);
     expect(g.deliver(contract).ok,isFalse);
   });
   test('financial decisions have different costs and consequences',(){
     final g=KingdomEngine();
     final baseline=g.rentPerDay;
     expect(g.setTax(2).ok,isTrue);
     expect(g.rentPerDay,greaterThan(baseline));
     expect(g.setTax(0).ok,isTrue);
     expect(g.rentPerDay,lessThan(baseline));
     final gold=g.gold;
     expect(g.borrow(500).ok,isTrue);
     expect(g.gold,gold+500);
     expect(g.debt,500);
     expect(g.repay(200).ok,isTrue);
     expect(g.debt,300);
   });
   test('investment locks capital then settles on maturity day',(){
     final g=KingdomEngine();
     final old=g.gold;
     expect(g.caravan('forest',500).ok,isTrue);
     expect(g.gold,old-500);
     expect(g.caravan('port',500).ok,isFalse);
     g.passMinutes(1440*7);
     expect(g.caravanAmount,0);
     expect(g.caravanReady,0);
   });
   test('hunger thirst health energy are affected by player actions',(){
     final g=KingdomEngine();
     final bread=g.amount(Good.bread);
     final hunger=g.needs['الجوع']!;
     expect(g.act('eat').ok,isTrue);
     expect(g.amount(Good.bread),bread-1);
     expect(g.needs['الجوع']!,greaterThan(hunger));
     expect(g.act('chop').ok,isTrue);
     expect(g.needs['الطاقة']!,lessThan(90));
   });
   test('hero moves on walkable terrain and avoids building cells',(){
     final g=KingdomEngine();
     expect(g.walkTo(11,14).ok,isTrue);
     g.stepHero();
     expect(g.heroX,11);
     expect(g.heroY,14);
     expect(g.walkTo(11,12).ok,isFalse);
   });
   test('every facility has meaningful data and a defined cost',(){
     for(final type in Facility.values){
       expect(type.info.name,isNotEmpty);
       expect(type.info.icon,isNotEmpty);
       expect(type.info.cost,isNotEmpty);
     }
   });
   test('new V3 save format has no dependency on the old game',(){
     final g=KingdomEngine();
     expect(KingdomEngine.saveKey,contains('v3'));
     final state=g.toJson();
     expect(state['schema'],3);
     expect((state['cityStock'] as Map).length,4);
     final fresh=KingdomEngine();
     fresh.restore(state);
     expect(fresh.sites.length,g.sites.length);
     expect(fresh.gold,g.gold);
     expect(fresh.cityId,g.cityId);
   });
   test('unrecognized and malformed game actions are rejected',(){
     final g=KingdomEngine();
     expect(g.act('fake').ok,isFalse);
     expect(g.setTax(7).ok,isFalse);
     expect(g.borrow(5000).ok,isFalse);
     expect(g.repay(100).ok,isFalse);
   });
 });
}

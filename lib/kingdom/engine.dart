import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'catalog.dart';

/// V3 standalone simulation. No imports from the old game or old save schema.
/// No network, IAP, Firebase, or hidden timers outside the active game.
class KingdomEngine extends ChangeNotifier {
  static const worldSize = 64;
  static const saveKey = 'mamlakat_life_rebuilt_v3';
  final Map<Good,int> stock = {for(final g in Good.values) g:0};
  final List<Site> sites = [];
  final List<String> journal = [];
  final Set<String> delivered = {};
  final Map<String,Map<Good,int>> cityStock = {};
  final Map<String,int> cityGold = {};
  final List<Point<int>> route = [];
  final Map<String,double> needs = {
    'الجوع':86, 'العطش':86, 'الطاقة':90,
    'الصحة':100, 'المزاج':78, 'النظافة':88,
  };
  int nextId=1, clock=8*60, speed=1, heroX=11,heroY=13;
  int reputation=68, taxes=1, debt=0, xp=0, dayIncome=0, dayExpenses=0;
  int caravanAmount=0,caravanReady=0;
  String caravanCity='', cityId='valley';
  bool paused=false,sound=true,loaded=false;
  int _lastHour=8;
  KingdomEngine() { _fresh(); }

  Town get city=>townById(cityId);
  int get day=>clock~/1440+1;
  int get hour=>(clock%1440)~/60;
  String get timeLabel=>'${hour.toString().padLeft(2,'0')}:${(clock%60).toString().padLeft(2,'0')}';
  String get season=>['الربيع','الصيف','الخريف','الشتاء'][((day-1)~/14)%4];
  int get level=>1+(sqrt(xp/80)).floor();
  int get gold=>amount(Good.gold);
  int amount(Good g)=>stock[g]??0;
  int get population=>sites.where((s)=>s.owned).fold<int>(0,
    (a,s)=>a+s.kind.info.beds*s.level);
  int get labor=>sites.where((s)=>s.owned).fold<int>(0,
    (a,s)=>a+s.kind.info.workers*s.level);
  int get storageLimit=>950+sites.where((s)=>s.owned)
      .fold<int>(0,(a,s)=>a+s.kind.info.capacity*s.level);
  int get stored=>Good.values.where((g)=>g!=Good.gold)
      .fold<int>(0,(a,g)=>a+amount(g));
  int get rentPerDay=>(population*22*[.7,1.0,1.4][taxes]).round();
  int get upkeepPerDay=>sites.where((s)=>s.owned).fold<int>(0,
       (a,s)=>a+s.kind.info.upkeep*s.level);
  bool get alive=>needs['الصحة']!>0;
  bool inside(int x,int y)=>x>=0 && y>=0 && x<worldSize && y<worldSize;
  Site? siteAt(int x,int y) {
    for(final s in sites.reversed) {
      if(s.x==x && s.y==y) return s;
    }
    return null;
  }
  Point<int> npcTile(Person p) {
    // Simple repeatable work/rest schedule rather than a static NPC sticker.
    if(hour>=20||hour<6) return Point(p.x-1,p.y-1);
    if(hour>=16&&hour<18) return Point(p.x+1,p.y);
    return Point(p.x,p.y);
  }
  Person? personAt(int x,int y) {
    for(final p in people) {
      final location=npcTile(p);
      if(location.x==x && location.y==y) return p;
    }
    return null;
  }

  void _fresh() {
    stock.addAll({
      Good.gold:2600,Good.wood:95,Good.stone:85,Good.grain:64,
      Good.flour:22,Good.bread:22,Good.water:75,Good.plank:28,
      Good.brick:18,Good.iron:8,Good.tools:7,Good.vegetables:24,
      Good.meat:13,Good.wool:12,Good.cloth:5,Good.furniture:3,
      Good.medicine:3,
    });
    void add(Facility t,int x,int y,{bool owned=true}) =>
      sites.add(Site(nextId++,t,x,y,owned:owned));
    add(Facility.castle,11,12,owned:false);
    for(final p in const [Point(7,9),Point(8,9),Point(7,10),Point(8,10)]) {
      add(Facility.house,p.x,p.y);
    }
    add(Facility.woodcutter,6,13);
    add(Facility.farm,10,6);
    add(Facility.well,12,10);
    add(Facility.sawmill,13,8);
    add(Facility.mill,9,7);
    add(Facility.bakery,10,8);
    add(Facility.market,15,11);
    add(Facility.warehouse,14,10);
    for(final t in towns.where((t)=>t.id!='valley')) {
      add(Facility.castle,t.x,t.y,owned:false);
      add(Facility.house,t.x-3,t.y-2,owned:false);
      add(Facility.house,t.x+3,t.y-2,owned:false);
      add(Facility.house,t.x-3,t.y+2,owned:false);
      add(Facility.market,t.x+3,t.y+2,owned:false);
      add(Facility.farm,t.x-4,t.y-4,owned:false);
      add(Facility.well,t.x-2,t.y+3,owned:false);
    }
    for(final town in towns) {
      cityStock[town.id]={
        for(final g in Good.values.where((g)=>g!=Good.gold))
          g: (260/(town.factors[g]??1.0)).round().clamp(45,700).toInt(),
      };
      cityGold[town.id]=24000;
    }
    _lastHour=clock~/60;
    _log('بدأت حياتك في مدينة الوادي. كل قرار اقتصادي له أثر حقيقي.');
  }

  void _log(String event) {
    journal.insert(0,'يوم $day • $event');
    if(journal.length>80) journal.removeLast();
  }
  void _notice() { notifyListeners(); }
  GameResult _fail(String message)=>GameResult(false,message);
  GameResult _success(String message,{int experience=0}) {
    xp+=experience;
    _log(message);
    _notice();
    return GameResult(true,message);
  }
  bool canPay(Map<Good,int> items)=>items.entries.every((e)=>
      amount(e.key)>=e.value);
  void _take(Map<Good,int> items) {
    for(final e in items.entries) stock[e.key]=amount(e.key)-e.value;
  }
  void _give(Map<Good,int> items) {
    for(final e in items.entries) stock[e.key]=amount(e.key)+e.value;
  }
  Map<Good,int> buildCost(Facility kind,{int level=1}) {
    final cost={for(final e in kind.info.cost.entries)
       e.key:(e.value*(1+(level-1)*.75)).ceil()};
    // Luxury goods are used in advanced housing and service buildings.
    if(kind==Facility.house && level>=3) {
      cost[Good.furniture]=2*(level-2);
      if(level>=4) cost[Good.cloth]=level-2;
    }
    if(kind==Facility.tavern && level>=3) {
      cost[Good.cloth]=2*(level-2);
    }
    return cost;
  }
  bool _nearTown(int x,int y)=>towns.any((t)=>
      (x-t.x).abs()+(y-t.y).abs()<=16);

  GameResult construct(Facility kind,int x,int y) {
    if(!inside(x,y)||landAt(x,y)==Land.river||landAt(x,y)==Land.hill) {
      return _fail('الأرض غير صالحة للبناء');
    }
    if(!_nearTown(x,y)) return _fail('ابنِ بالقرب من إحدى المدن');
    if(siteAt(x,y)!=null||personAt(x,y)!=null||
      (heroX==x&&heroY==y)) return _fail('القطعة مشغولة');
    if(kind==Facility.castle) return _fail('القلاع الرئيسية ليست للبيع');
    final cost=buildCost(kind);
    if(!canPay(cost)) return _fail('موارد البناء لا تكفي');
    _take(cost);
    sites.add(Site(nextId++,kind,x,y));
    return _success('شيدت ${kind.info.name} في ($x،$y)',experience:26);
  }
  GameResult upgrade(Site s) {
    if(!s.owned) return _fail('هذا المبنى لا تملكه');
    if(s.level>=5) return _fail('وصل المبنى لأقصى مستوى');
    final cost=buildCost(s.kind,level:s.level+1);
    if(!canPay(cost)) return _fail('مواد الترقية غير كافية');
    _take(cost);s.level++;
    return _success('طورت ${s.kind.info.name} إلى المستوى ${s.level}',
        experience:36);
  }
  int saleValue(Site s)=> (buildCost(s.kind,level:s.level)[Good.gold]??0)*55~/100;
  GameResult sellSite(Site s) {
    if(!s.owned) return _fail('هذا العقار ليس ملكك');
    final value=saleValue(s);
    stock[Good.gold]=gold+value;
    sites.remove(s);
    return _success('بعت ${s.kind.info.name} وربحت $value ذهب');
  }

  /// One hour of real simulation. Sites consume ingredients before output,
  /// affected by available workers, storage and seasons.
  void _hourly() {
    var workers=population;
    for(final s in sites.where((s)=>s.owned)) {
      final bp=s.kind.info;
      final needed=bp.workers*s.level;
      if(needed>workers) continue;
      workers-=needed;
      if(bp.outputs.isEmpty && ![Facility.tavern,Facility.clinic,Facility.stable].contains(s.kind)) continue;
      final inputs={for(final e in bp.inputs.entries) e.key:e.value*s.level};
      final outputs={for(final e in bp.outputs.entries)
        e.key:e.value*s.level};
      if(s.kind==Facility.farm&&season=='الشتاء') {
        for(final g in outputs.keys.toList()) {
          outputs[g]=(outputs[g]!*.45).ceil();
        }
      }
      if(!canPay(inputs)) continue;
      final takes=inputs.values.fold<int>(0,(a,b)=>a+b);
      final gives=outputs.values.fold<int>(0,(a,b)=>a+b);
      if(stored-takes+gives>storageLimit) continue;
      _take(inputs);_give(outputs);
      if(s.kind==Facility.tavern) {
        stock[Good.gold]=gold+12*s.level;
        _need('المزاج',1.5*s.level);
      }
      if(s.kind==Facility.clinic) _need('الصحة',2.0*s.level);
    }
    _need('الجوع',-1.5);
    _need('العطش',-2.0);
    _need('الطاقة',-1.6);
    _need('النظافة',-.5);
    if(needs['الجوع']!<15||needs['العطش']!<15) _need('الصحة',-3);
    if(needs['الطاقة']!<10) _need('الصحة',-1);
    if(needs['الصحة']!<20) _need('المزاج',-1);
    if(needs['الصحة']!<=0) {
      stock[Good.gold]=max(0,gold-180);
      needs.addAll({'الجوع':45,'العطش':45,'الطاقة':60,
        'الصحة':35,'المزاج':35,'النظافة':40});
      _log('أُغمي على البطل، ودُفع 180 ذهب للعلاج');
    }
  }

  void _daily() {
    final rent=rentPerDay;
    final wages=upkeepPerDay+labor*2;
    dayIncome=rent;dayExpenses=wages;
    stock[Good.gold]=max(0,gold+rent-wages);
    final food=max(1,population~/4);
    final water=max(1,population~/3);
    final foodDelivered=min(amount(Good.bread),food);
    final waterDelivered=min(amount(Good.water),water);
    stock[Good.bread]=amount(Good.bread)-foodDelivered;
    stock[Good.water]=amount(Good.water)-waterDelivered;
    if(foodDelivered<food||waterDelivered<water) {
      reputation=max(0,reputation-4);
      _need('المزاج',-5);
      _log('نقص المؤن في المدينة، وانخفض رضا السكان');
    } else {
      reputation=min(100,reputation+(taxes==0?3:taxes==1?1:-3));
      _need('المزاج',taxes==2?-2:1);
    }
    if(debt>0) debt+=(debt*.015).ceil();
    for(final t in towns) {
      final local=cityStock[t.id]!;
      for(final g in local.keys) {
        final factor=t.factors[g]??1.0;
        local[g]=(local[g]!+(22/factor).round()-(12*factor).round())
            .clamp(8,900).toInt();
      }
      cityGold[t.id]=min(100000,cityGold[t.id]!+250);
    }
    if(caravanAmount>0&&day>=caravanReady) {
      final dest=townById(caravanCity);
      final chance=((day*17+caravanAmount+dest.x*13)%100)/100;
      final factor=chance < dest.danger ? 0.54 : chance < 0.52 ? 1.09 : 1.32;
      final payout=(caravanAmount*factor).round();
      stock[Good.gold]=gold+payout;
      _log('عادت قافلتك من ${dest.name} بعائد $payout ذهب');
      caravanAmount=0;caravanReady=0;caravanCity='';
    }
    _log('إيراد اليوم $rent؛ الأجور والصيانة $wages');
  }

  void _need(String key,double change) {
    needs[key]=(needs[key]!+change).clamp(0.0,100.0).toDouble();
  }
  void passMinutes(int minutes) {
    if(minutes<1) return;
    final oldDay=day;
    clock+=minutes;
    while(_lastHour<clock~/60) { _lastHour++;_hourly(); }
    for(var d=oldDay;d<day;d++) { _daily(); }
    _notice();
  }
  void tick() {
    if(paused) return;
    passMinutes(speed*10);
    stepHero();
  }
  void pause() {paused=!paused;_notice();}
  void changeSpeed() {speed=speed==1?2:speed==2?4:1;_notice();}
  void toggleSound() {sound=!sound;_notice();}
  void _consumeHero(Map<Good,int> goods) { _take(goods); }

  GameResult act(String action) {
    switch(action) {
      case 'eat':
        if(amount(Good.bread)<1) return _fail('لا يوجد خبز');
        _consumeHero({Good.bread:1});_need('الجوع',28);
        return _success('تناولت خبزًا واستعدت نشاطك');
      case 'drink':
        if(amount(Good.water)<1) return _fail('لا توجد مياه');
        _consumeHero({Good.water:1});_need('العطش',34);
        return _success('شربت ماءً نظيفًا');
      case 'sleep':
        passMinutes(360);
        _need('الطاقة',75);_need('المزاج',7);
        return _success('نمت واستعدت طاقتك');
      case 'wash':
        if(amount(Good.water)<2) return _fail('النظافة تحتاج ماءين');
        _consumeHero({Good.water:2});_need('النظافة',42);
        return _success('اغتسلت وأصبحت أنظف');
      case 'chop':
        if(needs['الطاقة']!<12) return _fail('البطل مرهق');
        if(stored+8>storageLimit) return _fail('المخزن ممتلئ');
        _give({Good.wood:8});_need('الطاقة',-9);_need('الجوع',-4);
        return _success('جمعت 8 أخشاب',experience:9);
      case 'mine':
        if(needs['الطاقة']!<12) return _fail('البطل مرهق');
        if(stored+6>storageLimit) return _fail('المخزن ممتلئ');
        _give({Good.stone:6});_need('الطاقة',-10);
        return _success('جمعت 6 أحجار',experience:11);
      case 'heal':
        if(amount(Good.medicine)<1) return _fail('تحتاج دواء');
        _take({Good.medicine:1});_need('الصحة',38);
        return _success('استعملت الدواء');
      case 'work':
        _need('الطاقة',-12);_need('الجوع',-6);
        stock[Good.gold]=gold+50;
        passMinutes(90);
        return _success('عملت بالأجر وربحت 50 ذهب',experience:12);
    }
    return _fail('الإجراء غير موجود');
  }

  int marketPrice(Good g,{required bool buying}) {
    if(g==Good.gold) return 1;
    final local=cityStock[cityId]![g]??200;
    final scarcity=(1+(230-local)/550).clamp(.7,1.55);
    final seasonFactor=1+.09*sin(day*1.4+g.index);
    final factor=city.factors[g]??1;
    final spread=buying?1.24:.72;
    // Owning a local market really matters: better deals in this city.
    final localMarket=sites.any((s)=>s.owned&&s.kind==Facility.market&&
      (s.x-city.x).abs()+(s.y-city.y).abs()<=16);
    final marketBonus=localMarket?(buying?.94:1.06):1.0;
    return max(1,(g.base*factor*scarcity*seasonFactor*spread*
      marketBonus).round());
  }
  GameResult trade(Good g,int qty,{required bool buying}) {
    if(g==Good.gold||qty<1||qty>999) return _fail('كمية غير صالحة');
    final market=cityStock[cityId]!;
    final cost=marketPrice(g,buying:buying)*qty;
    if(buying) {
      if((market[g]??0)<qty) return _fail('التاجر لا يملك هذه الكمية');
      if(gold<cost) return _fail('الذهب لا يكفي');
      if(stored+qty>storageLimit) return _fail('المخزن ممتلئ');
      _take({Good.gold:cost});_give({g:qty});
      market[g]=market[g]!-qty;
      cityGold[cityId]=cityGold[cityId]!+cost;
      return _success('اشتريت $qty ${g.label} مقابل $cost ذهب',
        experience:max(1,qty~/10));
    }
    if(amount(g)<qty) return _fail('لا تملك الكمية المطلوبة');
    if(cityGold[cityId]!<cost) return _fail('تاجر المدينة لا يملك السيولة');
    _take({g:qty});_give({Good.gold:cost});
    market[g]=(market[g]??0)+qty;
    cityGold[cityId]=cityGold[cityId]!-cost;
    return _success('بعت $qty ${g.label} وربحت $cost ذهب',
      experience:max(1,qty~/10));
  }

  int travelHours(Town to)=>max(2,((city.x-to.x).abs()+
      (city.y-to.y).abs())~/6);
  int travelCost(Town to)=>travelHours(to)*16*
      (sites.any((s)=>s.owned&&s.kind==Facility.stable)?3:4)~/4;
  GameResult travel(String destination) {
    final to=townById(destination);
    if(to.id==cityId) return _fail('أنت في هذه المدينة بالفعل');
    final hours=travelHours(to),cost=travelCost(to);
    final rations=max(1,(hours/3).ceil());
    if(!canPay({Good.gold:cost,Good.bread:rations,Good.water:rations})) {
      return _fail('تحتاج $cost ذهب و$rations خبز وماء للسفر');
    }
    _take({Good.gold:cost,Good.bread:rations,Good.water:rations});
    passMinutes(hours*60);
    _need('الطاقة',-min(35.0,hours*3.0));
    _need('الجوع',-min(27.0,hours*2.0));
    final roll=((day*19+to.x*7+xp)%100)/100;
    if(roll<to.danger) {
      final lost=min(gold,cost~/2);
      _take({Good.gold:lost});_need('الصحة',-9);
      _log('تعرضت القافلة لهجوم وخسرت $lost ذهب');
    }
    cityId=to.id;heroX=to.x;heroY=to.y;route.clear();
    return _success('وصلت إلى ${to.name} بعد $hours ساعات',experience:30);
  }

  GameResult borrow(int amount) {
    if(amount<1||debt+amount>4000||reputation<25) {
      return _fail('حد الدين 4000، ويُشترط رضا السكان');
    }
    debt+=amount;_give({Good.gold:amount});
    return _success('اقترضت $amount ذهب؛ الدين حاليًا $debt');
  }
  GameResult repay(int amount) {
    final pay=min(amount,debt);
    if(pay<=0||gold<pay) return _fail('لا يمكن سداد هذا المبلغ');
    _take({Good.gold:pay});debt-=pay;
    return _success('سددت $pay ذهب من الدين');
  }
  GameResult setTax(int value) {
    if(value<0||value>2) return _fail('سياسة ضريبية غير صالحة');
    taxes=value;
    return _success('أصبحت الضرائب ${['منخفضة','متوازنة','مرتفعة'][value]}');
  }
  GameResult caravan(String destination,int investment) {
    if(caravanAmount>0) return _fail('لديك قافلة قيد السفر بالفعل');
    if(destination==cityId||investment<100||investment>2000||
        gold<investment) return _fail('الاستثمار أو الوجهة غير صالحين');
    _take({Good.gold:investment});caravanAmount=investment;
    caravanCity=destination;
    caravanReady=day+2+travelHours(townById(destination))~/5;
    return _success('أرسلت قافلة بقيمة $investment ذهب، والربح غير مضمون');
  }
  GameResult deliver(Delivery d) {
    if(delivered.contains(d.id)) return _fail('نفذت العقد سابقًا');
    if(cityId!=d.destination) return _fail('يجب الوصول إلى مدينة التسليم');
    if(amount(d.item)<d.amount) return _fail('بضاعة العقد غير كافية');
    _take({d.item:d.amount});_give({Good.gold:d.reward});
    delivered.add(d.id);
    return _success('سلّمت عقد ${d.item.label} وربحت ${d.reward} ذهب',
        experience:75);
  }

  GameResult meet(Person p) {
    final pos=npcTile(p);
    if((heroX-pos.x).abs()+(heroY-pos.y).abs()>8) {
      return _fail('اقترب من الشخص للتفاعل معه');
    }
    _need('المزاج',2);
    return _success('${p.name}: ${p.job=='تاجر'?'أسعار اليوم تتغير حسب العرض والطلب':p.job=='مزارعة'?'الماء هو أساس الغذاء':p.job=='بنّاء'?'كل بناء يحتاج مواد وعمال':'التنقل مخاطرة وفرصة في الوقت نفسه'}');
  }

  GameResult walkTo(int x,int y) {
    if(!inside(x,y)||landAt(x,y)==Land.river||
        siteAt(x,y)!=null) return _fail('اختر أرضًا مفتوحة');
    final start=Point(heroX,heroY),target=Point(x,y);
    final queue=Queue<Point<int>>()..add(start);
    final previous=<Point<int>,Point<int>?>{start:null};
    while(queue.isNotEmpty) {
      final node=queue.removeFirst();
      if(node==target) break;
      for(final delta in const [Point(1,0),Point(0,1),Point(-1,0),Point(0,-1)]) {
        final next=Point(node.x+delta.x,node.y+delta.y);
        if(!inside(next.x,next.y)||landAt(next.x,next.y)==Land.river||
            siteAt(next.x,next.y)!=null||previous.containsKey(next)) continue;
        previous[next]=node;queue.add(next);
      }
    }
    if(!previous.containsKey(target)) return _fail('لا يوجد طريق للوصول');
    route.clear();
    var item=target;
    while(item!=start) {route.insert(0,item);item=previous[item]!;}
    _notice();
    return const GameResult(true,'البطل يتحرك نحو المكان');
  }
  void stepHero() {
    if(route.isEmpty||paused) return;
    final next=route.removeAt(0);heroX=next.x;heroY=next.y;
    _notice();
  }

  Map<String,dynamic> toJson() => {
    'schema':3,'city':cityId,'clock':clock,'speed':speed,
    'heroX':heroX,'heroY':heroY,'nextId':nextId,'xp':xp,
    'reputation':reputation,'taxes':taxes,'debt':debt,
    'caravanAmount':caravanAmount,'caravanReady':caravanReady,
    'caravanCity':caravanCity,'paused':paused,'sound':sound,
    'stock':{for(final g in Good.values) g.name:amount(g)},
    'needs':needs,'sites':sites.map((s)=>s.toJson()).toList(),
    'cityStock':{for(final e in cityStock.entries) e.key:{
       for(final e2 in e.value.entries)e2.key.name:e2.value}},
    'cityGold':cityGold,'delivered':delivered.toList(),
    'journal':journal.take(30).toList(),
  };
  void restore(Map<String,dynamic> d) {
    if(d['schema']!=3) return;
    int number(String k,int fallback)=>(d[k] as num?)?.toInt()??fallback;
    clock=max(0,number('clock',clock));
    speed=number('speed',speed).clamp(1,4).toInt();
    heroX=number('heroX',heroX).clamp(0,63).toInt();
    heroY=number('heroY',heroY).clamp(0,63).toInt();
    nextId=max(1,number('nextId',nextId));
    xp=max(0,number('xp',xp));
    reputation=number('reputation',reputation).clamp(0,100).toInt();
    taxes=number('taxes',taxes).clamp(0,2).toInt();
    debt=max(0,number('debt',debt));
    caravanAmount=max(0,number('caravanAmount',0));
    caravanReady=max(0,number('caravanReady',0));
    caravanCity=d['caravanCity'] as String? ?? '';
    cityId=townById(d['city'] as String? ?? 'valley').id;
    paused=d['paused']==true;sound=d['sound']!=false;
    final items=d['stock'];if(items is Map) {
      for(final g in Good.values) {
        if(items[g.name] is num) stock[g]=(items[g.name] as num)
           .toInt().clamp(0,999999999).toInt();
      }
    }
    final status=d['needs'];if(status is Map) {
      for(final key in needs.keys) {
        if(status[key] is num) needs[key]=(status[key] as num)
            .toDouble().clamp(0,100).toDouble();
      }
    }
    if(d['sites'] is List) {
      sites.clear();
      for(final value in d['sites'] as List) {
        sites.add(Site.fromJson(Map<String,dynamic>.from(value as Map)));
      }
    }
    final shops=d['cityStock'];if(shops is Map) {
      for(final c in towns) {
        final snapshot=shops[c.id];
        if(snapshot is Map) {
          for(final g in Good.values.where((g)=>g!=Good.gold)) {
            if(snapshot[g.name] is num) cityStock[c.id]![g]=
                (snapshot[g.name] as num).toInt().clamp(0,999999).toInt();
          }
        }
      }
    }
    final golds=d['cityGold'];if(golds is Map) {
      for(final c in towns) {
        if(golds[c.id] is num) cityGold[c.id]=
            (golds[c.id] as num).toInt().clamp(0,9999999).toInt();
      }
    }
    delivered.addAll((d['delivered'] as List? ?? []).whereType<String>());
    journal.clear();
    journal.addAll((d['journal'] as List? ?? []).whereType<String>());
    _lastHour=clock~/60;_notice();
  }
  static Future<KingdomEngine> load() async {
    final state=KingdomEngine();
    try {
      final preferences=await SharedPreferences.getInstance();
      final saved=preferences.getString(saveKey);
      if(saved!=null) {
        state.restore(jsonDecode(saved) as Map<String,dynamic>);
        state.loaded=true;
      }
    } catch(e) {debugPrint('Rebuilt kingdom save unavailable: $e');}
    return state;
  }
  Future<void> save() async {
    try {
      final preferences=await SharedPreferences.getInstance();
      await preferences.setString(saveKey,jsonEncode(toJson()));
    } catch(e) {debugPrint('Rebuilt kingdom save failed: $e');}
  }
}

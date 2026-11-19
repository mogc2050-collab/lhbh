import 'dart:math';

enum Good { gold, wood, stone, grain, flour, bread, water, plank, brick, iron, tools, vegetables, meat, wool, cloth, furniture, medicine }

extension GoodInfo on Good {
  String get label => const ['ذهب','أخشاب','حجر','قمح','دقيق','خبز','ماء','ألواح','طوب','حديد','أدوات','خضار','لحوم','صوف','قماش','أثاث','دواء'][index];
  String get icon => const ['🪙','🪵','🪨','🌾','🥣','🥖','💧','🪚','🧱','⛓️','🔨','🥕','🥩','🐑','🧵','🪑','🧪'][index];
  int get base => const [1,8,10,7,12,20,4,17,23,22,54,12,27,16,34,85,65][index];
}

enum Facility { house, woodcutter, quarry, farm, well, sawmill, mill, bakery, brickyard, mine, forge, ranch, weaver, carpentry, market, warehouse, tavern, stable, clinic, castle }

class Blueprint {
  final String name, icon, description;
  final Map<Good,int> cost, inputs, outputs;
  final int workers, beds, capacity, upkeep;
  const Blueprint(this.name,this.icon,this.description,this.cost,this.inputs,this.outputs,this.workers,this.beds,this.capacity,this.upkeep);
}
const blueprints = <Facility,Blueprint>{
  Facility.house: Blueprint('منزل','🏠','سكن وإيراد إيجار',{Good.wood:16,Good.stone:10,Good.gold:140},{},{},0,4,0,1),
  Facility.woodcutter: Blueprint('معسكر حطابين','🪓','يجمع الأخشاب',{Good.wood:9,Good.stone:5,Good.gold:90},{},{Good.wood:8},1,0,0,2),
  Facility.quarry: Blueprint('محجر','🪨','ينتج الحجارة',{Good.wood:12,Good.gold:130},{},{Good.stone:7},2,0,0,3),
  Facility.farm: Blueprint('مزرعة','🌾','تنتج الحبوب والخضار',{Good.wood:12,Good.gold:125},{Good.water:2},{Good.grain:8,Good.vegetables:3},2,0,0,3),
  Facility.well: Blueprint('بئر','💧','إمدادات مياه نظيفة',{Good.stone:12,Good.gold:95},{},{Good.water:10},1,0,0,1),
  Facility.sawmill: Blueprint('منشرة','🪚','خشب إلى ألواح',{Good.wood:18,Good.stone:8,Good.gold:185},{Good.wood:6},{Good.plank:4},2,0,0,3),
  Facility.mill: Blueprint('مطحنة','⚙️','قمح إلى دقيق',{Good.plank:7,Good.stone:9,Good.gold:190},{Good.grain:8},{Good.flour:6},2,0,0,3),
  Facility.bakery: Blueprint('مخبز','🥖','دقيق وماء إلى خبز',{Good.plank:9,Good.brick:6,Good.gold:205},{Good.flour:5,Good.water:2},{Good.bread:6},2,0,0,4),
  Facility.brickyard: Blueprint('مصنع طوب','🧱','حجارة وماء إلى طوب',{Good.wood:13,Good.stone:12,Good.gold:230},{Good.stone:7,Good.water:2},{Good.brick:5},2,0,0,4),
  Facility.mine: Blueprint('منجم','⛏️','استخراج خام الحديد',{Good.wood:15,Good.stone:14,Good.gold:280},{Good.tools:1},{Good.iron:6},3,0,0,6),
  Facility.forge: Blueprint('حدادة','⚒️','حديد وألواح إلى أدوات',{Good.brick:12,Good.plank:9,Good.gold:300},{Good.iron:4,Good.plank:2},{Good.tools:2},2,0,0,5),
  Facility.ranch: Blueprint('حظيرة مواشي','🐄','لحوم وصوف',{Good.wood:20,Good.grain:14,Good.gold:280},{Good.grain:4,Good.water:2},{Good.meat:4,Good.wool:4},2,0,0,5),
  Facility.weaver: Blueprint('ورشة نسيج','🧵','صوف إلى قماش',{Good.plank:9,Good.tools:2,Good.gold:320},{Good.wool:5},{Good.cloth:3},2,0,0,4),
  Facility.carpentry: Blueprint('ورشة نجارة','🪑','ألواح إلى أثاث',{Good.plank:12,Good.tools:2,Good.gold:350},{Good.plank:5,Good.tools:1},{Good.furniture:2},2,0,0,5),
  Facility.market: Blueprint('سوق','⚖️','تجارة حقيقية',{Good.plank:10,Good.brick:7,Good.gold:320},{},{},2,0,0,5),
  Facility.warehouse: Blueprint('مخزن','📦','سعة تخزين إضافية',{Good.wood:22,Good.stone:12,Good.gold:225},{},{},1,0,600,3),
  Facility.tavern: Blueprint('نُزل','🍲','دخل من الضيافة',{Good.plank:12,Good.brick:12,Good.gold:470},{Good.meat:2,Good.vegetables:3},{},2,0,0,6),
  Facility.stable: Blueprint('إسطبل','🐎','سفر أرخص وأسرع',{Good.plank:14,Good.grain:12,Good.gold:340},{Good.grain:2},{},1,0,0,4),
  Facility.clinic: Blueprint('عيادة','🏥','تساعد على العلاج',{Good.brick:12,Good.plank:10,Good.gold:420},{Good.medicine:1},{},2,0,0,6),
  Facility.castle: Blueprint('قلعة','🏰','مركز الحكم',{Good.stone:100,Good.brick:90,Good.gold:4000},{},{},5,0,0,25),
};
extension FacilityInfo on Facility { Blueprint get info => blueprints[this]!; }

enum Land { meadow, forest, path, river, bridge, hill, soil }
class Town {
 final String id,name,description; final int x,y; final double danger;
 final Map<Good,double> factors;
 const Town(this.id,this.name,this.description,this.x,this.y,this.danger,this.factors);
}
const towns = <Town>[
  Town('valley','مدينة الوادي','تجارة وسكن',11,12,.07,{Good.grain:.9,Good.wood:1.08,Good.stone:1.02}),
  Town('forest','مدينة الغابة','الأخشاب والألواح',48,12,.15,{Good.wood:.58,Good.plank:.72,Good.bread:1.38}),
  Town('port','مدينة الميناء','الغذاء والقوافل',13,49,.13,{Good.meat:.65,Good.grain:.78,Good.vegetables:.72,Good.wood:1.32}),
  Town('mountain','مدينة الجبال','الحجر والحديد',49,49,.27,{Good.stone:.55,Good.iron:.62,Good.tools:.8,Good.wood:1.52}),
];
Town townById(String id) => towns.firstWhere((t)=>t.id==id,orElse:()=>towns.first);

class Site {
 final int id; final Facility kind; int x,y,level; final bool owned;
 Site(this.id,this.kind,this.x,this.y,{this.level=1,this.owned=true});
 Map<String,dynamic> toJson()=>{'id':id,'kind':kind.name,'x':x,'y':y,'level':level,'owned':owned};
 factory Site.fromJson(Map<String,dynamic> d)=>Site((d['id'] as num).toInt(),
  Facility.values.firstWhere((f)=>f.name==d['kind'],orElse:()=>Facility.house),
  (d['x'] as num).toInt(),(d['y'] as num).toInt(),
  level:(d['level'] as num?)?.toInt()??1,owned:d['owned']!=false);
}
class Person {
 final String id,name,job,icon,city; final int x,y;
 const Person(this.id,this.name,this.job,this.icon,this.city,this.x,this.y);
}
final people = <Person>[for(final c in towns)...[
 Person(c.id+'-merchant','التاجر حسن','تاجر','🧺',c.id,c.x+2,c.y+1),
 Person(c.id+'-builder','المعلم فارس','بنّاء','🛠',c.id,c.x-2,c.y+2),
 Person(c.id+'-farmer','الفلاحة سلمى','مزارعة','🌿',c.id,c.x+1,c.y-3),
 Person(c.id+'-traveler','الرحالة أمين','رحالة','🧭',c.id,c.x-1,c.y-2),
]];
class Delivery {
 final String id; final Good item; final int amount,reward; final String destination;
 const Delivery(this.id,this.item,this.amount,this.reward,this.destination);
}
const deliveries = [
 Delivery('d1',Good.wood,25,360,'port'),
 Delivery('d2',Good.grain,25,340,'forest'),
 Delivery('d3',Good.stone,20,410,'valley'),
 Delivery('d4',Good.plank,12,430,'mountain'),
 Delivery('d5',Good.bread,20,360,'mountain'),
 Delivery('d6',Good.iron,12,510,'valley'),
];
class GameResult {
 final bool ok; final String message;
 const GameResult(this.ok,this.message);
}

Land landAt(int x,int y) {
 final nearest=towns.map((c)=>(x-c.x).abs()+(y-c.y).abs()).reduce(min);
 if(nearest<=4) return Land.path;
 if((x-31).abs()<=1 && (y-31).abs()<=1) return Land.bridge;
 if((x-31).abs()<=1 && y>3 && y<62) return Land.river;
 if((y-31).abs()<=1 && x>4 && x<59) return Land.path;
 if((x-11).abs()<=1 && y>=12 && y<=31) return Land.path;
 if((x-48).abs()<=1 && y>=12 && y<=31) return Land.path;
 if((x-13).abs()<=1 && y>=31 && y<=49) return Land.path;
 if((x-49).abs()<=1 && y>=31 && y<=49) return Land.path;
 final seed=(x*3727 ^ y*1543 ^ x*y*73).abs()%100;
 if(seed>92 && x>35 && y>36) return Land.hill;
 if(seed>83 && y<28) return Land.forest;
 if(seed>76 && x<27 && y>33) return Land.soil;
 return Land.meadow;
}

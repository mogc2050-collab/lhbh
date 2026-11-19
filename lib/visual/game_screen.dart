import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../kingdom/audio.dart';
import '../kingdom/catalog.dart';
import '../kingdom/engine.dart';
import 'world_painter.dart';
import 'skin.dart';

class KingdomGame extends StatefulWidget {
  final KingdomEngine engine;
  const KingdomGame({super.key,required this.engine});
  @override
  State<KingdomGame> createState()=>_KingdomGameState();
}

class _KingdomGameState extends State<KingdomGame>
    with SingleTickerProviderStateMixin,WidgetsBindingObserver {
  late final KingdomEngine g;
  final camera=TransformationController();
  final List<Timer> timers=[];
  final audio=KingdomAudio();
  late final AnimationController movement;
  Facility? selectedFacility;
  Good chosenGood=Good.wood;
  bool buying=true,showTasks=true,showNeeds=true,running=false;
  int quantity=1;
  bool _focused=false;

  @override
  void initState(){
    super.initState();
    g=widget.engine;g.addListener(_gameChanged);
    audio.enabled=g.sound;
    WidgetsBinding.instance.addObserver(this);
    movement=AnimationController(vsync:this,
        duration:const Duration(seconds:4))..repeat();
    timers.add(Timer.periodic(const Duration(seconds:1),(_)=>g.tick()));
    timers.add(Timer.periodic(const Duration(milliseconds:270),(_){
      g.stepHero(running:running);
      if(running) g.stepHero(running:true);
    }));
    timers.add(Timer.periodic(const Duration(seconds:12),
        (_)=>g.save()));
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(!mounted)return;
      _focusHero();
      audio.start();
    });
  }
  void _gameChanged(){if(mounted)setState((){});}
  @override
  void didChangeAppLifecycleState(AppLifecycleState state){
    if(state!=AppLifecycleState.resumed)g.save();
  }
  @override
  void dispose(){
    for(final t in timers)t.cancel();
    WidgetsBinding.instance.removeObserver(this);
    g.removeListener(_gameChanged);
    g.save();
    camera.dispose();
    movement.dispose();
    audio.dispose();
    super.dispose();
  }

  void _focusHero(){
    if(!mounted)return;
    final view=MediaQuery.sizeOf(context);
    final p=MapSpace.at(g.heroX,g.heroY);
    const zoom=.72;
    camera.value=Matrix4.identity()
       ..translate(view.width/2-p.dx*zoom,view.height*.49-p.dy*zoom)
       ..scale(zoom);
    _focused=true;
  }
  void _msg(GameResult r,{String cue='ui'}){
    audio.cue(r.ok?cue:'error');
    HapticFeedback.selectionClick();
    if(!mounted)return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior:SnackBarBehavior.floating,
      backgroundColor:r.ok?const Color(0xff366638):
        const Color(0xff883c34),
      content:Text(r.message,textAlign:TextAlign.center),
      duration:const Duration(seconds:2),
    ));
    if(r.ok)g.save();
  }
  void _onTile(TapUpDetails info) {
    final cell=MapSpace.tile(info.localPosition);
    if(!g.inside(cell.x,cell.y))return;
    if(selectedFacility!=null){
      final result=g.construct(selectedFacility!,cell.x,cell.y);
      _msg(result,cue:'build');
      if(result.ok)setState(()=>selectedFacility=null);
      return;
    }
    final site=g.siteAt(cell.x,cell.y);
    if(site!=null){_siteDetails(site);return;}
    final person=g.personAt(cell.x,cell.y);
    if(person!=null){_personDetails(person);return;}
    final result=g.walkTo(cell.x,cell.y);
    if(!result.ok)_msg(result);
    else audio.cue('walk');
  }
  Widget _world()=>InteractiveViewer(
    transformationController:camera,
    constrained:false,boundaryMargin:const EdgeInsets.all(720),
    minScale:.12,maxScale:2.8,
    child:GestureDetector(
      behavior:HitTestBehavior.opaque,onTapUp:_onTile,
      child:SizedBox.fromSize(size:MapSpace.size,child:Stack(children:[
        RepaintBoundary(child:CustomPaint(size:MapSpace.size,
          painter:WorldPainter(g))),
        IgnorePointer(child:AnimatedBuilder(animation:movement,
          builder:(_,child)=>CustomPaint(size:MapSpace.size,
            painter:LifePainter(g,movement.value)))),
      ])),
    ),
  );

  void _sheet(String heading,Widget Function(BuildContext,StateSetter) body,
      {double height=.82}) {
    audio.cue('ui');
    showModalBottomSheet<void>(context:context,
      isScrollControlled:true,backgroundColor:Colors.transparent,
      builder:(ctx)=>SafeArea(top:false,child:Padding(
        padding:const EdgeInsets.fromLTRB(7,0,7,7),
        child:SizedBox(height:MediaQuery.sizeOf(ctx).height*height,
          child:RoyalPanel(child:Column(children:[
            Row(children:[
              Container(width:7,height:30,decoration:BoxDecoration(
                color:KColor.gold,borderRadius:BorderRadius.circular(3))),
              const SizedBox(width:9),
              Expanded(child:Text(heading,style:const TextStyle(
                color:KColor.light,fontWeight:FontWeight.w900,fontSize:19))),
              IconButton(onPressed:()=>Navigator.pop(ctx),
                icon:const Icon(Icons.close,color:KColor.light)),
            ]),
            const Divider(color:Color(0xff9f794a),thickness:1),
            Expanded(child:StatefulBuilder(builder:(ctx,update)=>
              AnimatedBuilder(animation:g,builder:(_,child)=>
                SingleChildScrollView(
                  physics:const BouncingScrollPhysics(),
                  padding:const EdgeInsets.only(bottom:25),
                  child:body(ctx,update))))),
          ]))),
      )),
    );
  }

  Widget _infoLine(String title,String detail,String icon,{
      VoidCallback? onTap,String? action})=>Padding(
    padding:const EdgeInsets.symmetric(vertical:5),
    child:RoyalPanel(padding:const EdgeInsets.all(8),child:InkWell(
      onTap:onTap,child:Row(children:[
        Text(icon,style:const TextStyle(fontSize:27)),
        const SizedBox(width:9),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Text(title,style:const TextStyle(color:KColor.light,
              fontWeight:FontWeight.w900,fontSize:14)),
            Text(detail,style:const TextStyle(color:KColor.muted,
              height:1.45,fontSize:11)),
          ])),
        if(action!=null)Padding(padding:const EdgeInsets.only(right:4),
          child:Text(action,style:const TextStyle(color:KColor.gold,
            fontWeight:FontWeight.w900))),
        if(onTap!=null)const Icon(Icons.chevron_left_rounded,color:KColor.gold),
      ]),
    )),
  );
  String costs(Map<Good,int> items) => items.entries.map((e)=>
      e.key.icon+' '+e.value.toString()).join('   ');
  Widget _heading(String title)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:11),
    child:Row(children:[
      const Icon(Icons.stars_rounded,color:KColor.gold,size:18),
      const SizedBox(width:7),
      Text(title,style:const TextStyle(color:KColor.light,
         fontSize:16,fontWeight:FontWeight.w900)),
    ]),
  );

  void _market() {
    _sheet('السوق • بيع وشراء بأسعار حقيقية',(ctx,update)=>Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Row(children:[
          Expanded(child:RoyalButton(text:'شراء',icon:Icons.shopping_cart,
             green:buying,onTap:()=>update(()=>buying=true))),
          const SizedBox(width:8),
          Expanded(child:RoyalButton(text:'بيع',icon:Icons.sell_rounded,
             green:!buying,onTap:()=>update(()=>buying=false))),
        ]),
        const SizedBox(height:8),
        Text('مدينة: '+g.city.name+' • رصيدك: '+g.gold.toString()+' ذهب',
          style:const TextStyle(color:KColor.light,fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        for(final good in Good.values.where((a)=>a!=Good.gold))
          InkWell(onTap:()=>update((){
            chosenGood=good;quantity=1;
          }),child:Container(
            margin:const EdgeInsets.only(bottom:5),
            decoration:BoxDecoration(
              color:chosenGood==good?const Color(0xff9b713a):
                const Color(0xff3e2c20),
              border:Border.all(color:chosenGood==good?KColor.gold:
                const Color(0xff785538)),
              borderRadius:BorderRadius.circular(8)),
            padding:const EdgeInsets.all(8),
            child:Row(children:[
              Text(good.icon,style:const TextStyle(fontSize:23)),
              const SizedBox(width:9),
              Expanded(child:Text(good.label,style:const TextStyle(
                color:KColor.light,fontWeight:FontWeight.w800))),
              Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
                Text(g.marketPrice(good,buying:buying).toString()+' ذهب',
                  style:const TextStyle(color:KColor.gold,
                    fontSize:14,fontWeight:FontWeight.w900)),
                Text((buying?
                  g.cityStock[g.cityId]![good]:g.amount(good)).toString()+
                  ' متوفر',style:const TextStyle(color:KColor.muted,
                    fontSize:10)),
              ]),
            ]),
          )),
        _heading('تفاصيل الصفقة'),
        RoyalPanel(child:Column(children:[
          Text(chosenGood.icon+' '+chosenGood.label,
            style:const TextStyle(color:KColor.light,
                fontWeight:FontWeight.w900,fontSize:19)),
          Row(mainAxisAlignment:MainAxisAlignment.center,children:[
            IconButton(onPressed:()=>update(()=>quantity=
               (quantity-1).clamp(1,999).toInt()),icon:const Icon(
                Icons.remove_circle,color:KColor.gold,size:29)),
            Text(quantity.toString(),style:const TextStyle(color:KColor.light,
              fontSize:24,fontWeight:FontWeight.bold)),
            IconButton(onPressed:()=>update(()=>quantity=
               (quantity+1).clamp(1,999).toInt()),icon:const Icon(
                Icons.add_circle,color:KColor.gold,size:29)),
          ]),
          Text('الإجمالي: '+(g.marketPrice(chosenGood,buying:buying)*quantity)
            .toString()+' ذهب',style:const TextStyle(color:KColor.light,
              fontWeight:FontWeight.bold)),
          const SizedBox(height:9),
          RoyalButton(text:buying?'تأكيد الشراء':'تأكيد البيع',
            icon:Icons.check_circle_rounded,green:true,
            onTap:(){
              final result=g.trade(chosenGood,quantity,buying:buying);
              _msg(result,cue:buying?'buy':'sell');
              if(result.ok)update(()=>quantity=1);
            }),
        ])),
      ]),height:.88);
  }

  void _construction() {
    _sheet('البناء والتطوير • 20 مبنى',(ctx,update)=>Column(children:[
      const Text('كل مبنى مستقل في العالم. اختر المبنى ثم اضغط على أرض خالية؛ '
        'التكلفة تُخصم فعليًا، والإنتاج يحتاج عمالًا وخامات.',
        style:TextStyle(color:KColor.muted,fontSize:12,height:1.6)),
      const SizedBox(height:11),
      GridView.builder(shrinkWrap:true,
        physics:const NeverScrollableScrollPhysics(),
        itemCount:Facility.values.where((v)=>v!=Facility.castle).length,
        gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:2,childAspectRatio:.74,
          mainAxisSpacing:8,crossAxisSpacing:8),
        itemBuilder:(ctx,index){
          final type=Facility.values.where((v)=>
             v!=Facility.castle).elementAt(index);
          final bp=type.info;
          final cost=g.buildCost(type);
          return RoyalPanel(padding:const EdgeInsets.all(7),
            child:Column(children:[
              Expanded(child:BuildingPortrait(type:type,engine:g,height:90)),
              const SizedBox(height:5),
              Text(bp.name,style:const TextStyle(color:KColor.light,
                fontWeight:FontWeight.w900,fontSize:12)),
              Text(costs(cost),maxLines:2,textAlign:TextAlign.center,
                style:const TextStyle(color:KColor.muted,fontSize:11)),
              const SizedBox(height:5),
              RoyalButton(text:'اختر للبناء',icon:Icons.add,
                 green:g.canPay(cost),onTap:(){
                   Navigator.pop(ctx);
                   setState(()=>selectedFacility=type);
                   audio.cue('build');
                 }),
            ]),
          );
        }),
    ]),height:.89);
  }

  void _siteDetails(Site site) {
    final bp=site.kind.info;
    _sheet(bp.name+' • المستوى '+site.level.toString(),
      (ctx,update)=>Column(children:[
        BuildingPortrait(type:site.kind,engine:g,height:165),
        const SizedBox(height:10),
        Text(bp.description,style:const TextStyle(color:KColor.light,
           fontSize:14),textAlign:TextAlign.center),
        const SizedBox(height:12),
        _infoLine('الموقع',site.x.toString()+'، '+site.y.toString(),
          '📍'),
        _infoLine('العمال',((bp.workers*site.level)).toString()+
          ' عامل', '👷'),
        _infoLine('المواد المستهلكة في كل دورة',
          bp.inputs.isEmpty?'لا توجد':costs({
            for(final e in bp.inputs.entries)e.key:e.value*site.level}),
          '🧰'),
        _infoLine('المنتجات في كل دورة',
          bp.outputs.isEmpty?'مرفق خدمات':costs({
            for(final e in bp.outputs.entries)e.key:e.value*site.level}),
          '📦'),
        if(!site.owned)...[
          _heading('مبنى تابع للمدينة'),
          RoyalButton(text:'استكشف السوق',icon:Icons.store,
             onTap:(){
               Navigator.pop(ctx);_market();
             }),
        ] else ...[
          _heading('إدارة ممتلكاتك'),
          _infoLine('تكلفة الترقية',costs(g.buildCost(
              site.kind,level:site.level+1)), '⬆️'),
          Row(children:[
            Expanded(child:RoyalButton(text:'ترقية',icon:Icons.upgrade,
              green:true,onTap:(){
                _msg(g.upgrade(site),cue:'upgrade');update((){});
              })),
            const SizedBox(width:7),
            Expanded(child:RoyalButton(text:'بيع '+
                 g.saleValue(site).toString()+' ذهب',
                icon:Icons.sell,onTap:()async {
                  final yes=await showDialog<bool>(context:ctx,
                    builder:(dialogCtx)=>AlertDialog(
                      title:const Text('تأكيد بيع المبنى'),
                      content:const Text('البيع دائم. هل تريد إتمام الصفقة؟'),
                      actions:[
                        TextButton(onPressed:()=>Navigator.pop(dialogCtx,false),
                           child:const Text('إلغاء')),
                        FilledButton(onPressed:()=>Navigator.pop(dialogCtx,true),
                           child:const Text('بيع')),
                      ]));
                  if(yes==true&&ctx.mounted){
                    _msg(g.sellSite(site),cue:'sell');Navigator.pop(ctx);
                  }
                })),
          ]),
        ],
      ]));
  }

  void _heroes() {
    _sheet('الشخصية • الحياة اليومية',(ctx,update)=>Column(children:[
      RoyalPanel(child:Row(children:[
        Container(width:70,height:80,
          alignment:Alignment.center,
          decoration:BoxDecoration(color:KColor.wood,
            border:Border.all(color:KColor.gold),
            borderRadius:BorderRadius.circular(9)),
          child:const Text('🧔🏻‍♂️',style:TextStyle(fontSize:46))),
        const SizedBox(width:11),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            const Text('البطل • صاحب القرار',style:TextStyle(color:KColor.light,
              fontWeight:FontWeight.w900,fontSize:15)),
            Text('المستوى '+g.level.toString()+' • الخبرة '+g.xp.toString(),
              style:const TextStyle(color:KColor.muted)),
            Text('السمعة '+g.reputation.toString()+'%',
              style:const TextStyle(color:KColor.gold)),
          ])),
      ])),
      const SizedBox(height:10),
      RoyalPanel(child:Column(children:[
        for(final n in g.needs.entries)
          StatusMeter(name:n.key,value:n.value,
            color:n.key=='الصحة'?const Color(0xffe2504a):
              n.key=='الطاقة'?const Color(0xffe2b73e):
              n.key=='المزاج'?const Color(0xff9ecb3c):
              const Color(0xff69c45b),
            symbol:switch(n.key){
              'الجوع'=>'🍗','العطش'=>'💧','الطاقة'=>'⚡',
              'الصحة'=>'❤️','المزاج'=>'🙂',_=>'🧼'}),
      ])),
      _heading('أفعالك تغيّر احتياجاتك ومواردك'),
      for(final act in const [
        ('كُل','eat','🍗'),('اشرب','drink','💧'),
        ('نام واسترح','sleep','🛌'),('استحم','wash','🧼'),
        ('احتطب','chop','🪓'),('استخرج أحجار','mine','⛏️'),
        ('العمل بأجر','work','🛠'),('استخدم علاجًا','heal','🧪'),
      ]) _infoLine(act.$1,'تفاعل حقيقي مع احتياجات الشخصية',act.$3,
        action:'تنفيذ',onTap:()=>_msg(g.act(act.$2),cue:act.$2)),
      _heading('حقيبتك الشخصية'),
      for(final good in Good.values.where((item)=>item!=Good.gold))
        _infoLine(good.label,g.amount(good).toString()+' وحدة',
          good.icon),
    ]),height:.88);
  }

  void _storage(){
    _sheet('مخازن المملكة',(ctx,update)=>Column(children:[
      _infoLine('سعة المخازن',g.stored.toString()+' من '+
        g.storageLimit.toString()+' وحدة','📦'),
      for(final good in Good.values)
        _infoLine(good.label,'مملوك: '+g.amount(good).toString()+
          ' • سعر السوق: '+g.marketPrice(good,buying:false).toString(),
           good.icon),
      _heading('عقاراتك'),
      for(final site in g.sites.where((s)=>s.owned))
        _infoLine(site.kind.info.name,
          'المستوى '+site.level.toString()+
          ' • الموقع '+site.x.toString()+'، '+site.y.toString(),
          site.kind.info.icon,action:'إدارة',onTap:(){
            Navigator.pop(ctx);_siteDetails(site);
          }),
    ]),height:.88);
  }

  void _travel() {
    _sheet('المدن والسفر والقوافل',(ctx,update)=>Column(children:[
      _infoLine('موقعك',g.city.name+' • '+g.city.description,'📍'),
      for(final city in towns) _infoLine(city.name,
        city.description+
        (city.id==g.cityId?' • أنت هنا':
         ' • '+g.travelHours(city).toString()+' ساعات، '+
         g.travelCost(city).toString()+' ذهب ومؤن'),
        '🏰',action:city.id==g.cityId?'هنا':'سافر',
        onTap:(){
          if(city.id==g.cityId)return;
          final result=g.travel(city.id);
          _msg(result,cue:'travel');
          if(result.ok){
            Navigator.pop(ctx);
            WidgetsBinding.instance.addPostFrameCallback((_){
              if(mounted)_focusHero();
            });
          }
        }),
      _heading('الأخطار والفرص'),
      const Text('كل مدينة لها مخزون وأسعار مستقلة. قد تربح من فرق الأسعار '
          'بين المدن أو تخسر بسبب تكاليف السفر والمخاطر.',
        style:TextStyle(color:KColor.muted,fontSize:12,height:1.7)),
      const SizedBox(height:10),
      RoyalButton(text:'افتح القوافل الاستثمارية',
        icon:Icons.local_shipping_rounded,onTap:(){
          Navigator.pop(ctx);_economy();
        }),
    ]));
  }

  void _economy() {
    _sheet('وزارة المال • قراراتك الاقتصادية',(ctx,update)=>Column(children:[
      _infoLine('ميزانية المملكة',g.gold.toString()+
        ' ذهب • دخل إيجارات '+g.rentPerDay.toString()+
        ' • صيانة '+g.upkeepPerDay.toString(),'🪙'),
      _infoLine('عدد السكان والعمال',g.population.toString()+
        ' سعة سكن • '+g.labor.toString()+' وظيفة','👨‍👩‍👧‍👦'),
      _infoLine('السمعة العامة',g.reputation.toString()+'%','👑'),
      _heading('الضرائب: قرار يُغير الإيرادات والرضا'),
      for(var i=0;i<3;i++) _infoLine(
        ['ضرائب منخفضة','ضرائب متوازنة','ضرائب مرتفعة'][i],
        ['رضا أعلى مقابل دخل أقل','توازن بين الدخل والسمعة',
         'زيادة الإيرادات مقابل غضب السكان'][i],
        '⚖️',action:g.taxes==i?'الحالية':'اختر',
        onTap:()=>_msg(g.setTax(i),cue:'tax')),
      _heading('الخزينة والقروض'),
      _infoLine('ديونك',g.debt.toString()+
        ' ذهب • فائدة 1.5% لكل يوم','🏦'),
      Row(children:[
        Expanded(child:RoyalButton(text:'اقترض 500',
          icon:Icons.add_rounded,onTap:()=>_msg(g.borrow(500),cue:'bank'))),
        const SizedBox(width:8),
        Expanded(child:RoyalButton(text:'سدّد 200',
          icon:Icons.remove_rounded,onTap:()=>_msg(g.repay(200),cue:'coin'))),
      ]),
      _heading('قوافل ذات ربح وخسارة'),
      if(g.caravanAmount>0)_infoLine('قافلة قائمة',
        g.caravanAmount.toString()+' ذهب • العودة يوم '+
          g.caravanReady.toString(),'🐎')
      else for(final c in towns.where((t)=>t.id!=g.cityId))
        _infoLine('قافلة إلى '+c.name,
          'مخاطرة '+(c.danger*100).round().toString()+
          '% • استثمار 500 ذهب','🐎',action:'أرسل',
          onTap:()=>_msg(g.caravan(c.id,500),cue:'caravan')),
      _heading('سجل التعاملات'),
      for(final e in g.journal.take(15))
        Padding(padding:const EdgeInsets.symmetric(vertical:5),
          child:Text(e,style:const TextStyle(color:KColor.muted,
             fontSize:12))),
    ]),height:.88);
  }

  void _contracts() {
    _sheet('مهام المملكة وعقود التجارة',(ctx,update)=>Column(children:[
      const Text('كل مهمة مرتبطة بإنتاج أو بناء أو شراء أو احتياجاتك. '
          'المكافآت لا تُستلم إلا مرة واحدة.',
        style:TextStyle(color:KColor.muted,height:1.7)),
      _heading('مهام البناء والإنتاج'),
      for(final goal in KingdomEngine.questTitles.entries)
        _infoLine(goal.value,
          g.goalProgress(goal.key).toString()+' / '+
          g.goalTarget(goal.key).toString(),
          '🎯',
          action:g.claimedGoals.contains(goal.key)?'مكتملة':
              g.goalProgress(goal.key)>=g.goalTarget(goal.key)?
              'استلم 200 ذهب':'جارية',
          onTap:()=>_msg(g.claimGoal(goal.key),cue:'quest')),
      _heading('عقود النقل والتسليم'),
      const Text('انتقل إلى مدينة التسليم حاملًا البضاعة، '
        'ثم استلم مكافأة العقد مرة واحدة.',
        style:TextStyle(color:KColor.muted,height:1.7)),
      const SizedBox(height:12),
      for(final d in deliveries)_infoLine(
        'تسليم '+d.amount.toString()+' '+d.item.label,
        'الوجهة: '+townById(d.destination).name+
          ' • المكافأة: '+d.reward.toString()+' ذهب',
        d.item.icon,
        action:g.delivered.contains(d.id)?'مكتمل':'سلّم',
        onTap:()=>_msg(g.deliver(d),cue:'quest')),
    ]));
  }

  void _personDetails(Person p) {
    _sheet(p.name,(ctx,update)=>Column(children:[
      Center(child:Text(p.icon,style:const TextStyle(fontSize:83))),
      const SizedBox(height:10),
      Text(p.job+' في '+townById(p.city).name,
        style:const TextStyle(color:KColor.light,fontSize:17,
          fontWeight:FontWeight.bold)),
      const SizedBox(height:12),
      RoyalButton(text:'تحدث معه',icon:Icons.chat_bubble_outline,
        onTap:()=>_msg(g.meet(p),cue:'citizen')),
      const SizedBox(height:12),
      RoyalButton(text:p.job=='تاجر'?'تجارة في السوق':
        p.job=='بنّاء'?'اختر مشروع بناء':
        p.job=='رحالة'?'المدن والسفر':'عمل بالمزرعة',
        icon:Icons.touch_app,green:true,onTap:(){
          Navigator.pop(ctx);
          if(p.job=='تاجر')_market();
          else if(p.job=='بنّاء')_construction();
          else if(p.job=='رحالة')_travel();
          else _msg(g.act('work'),cue:'wood');
        }),
    ]),height:.54);
  }

  Widget _shortcut(IconData icon,String title,VoidCallback action)=>
      InkWell(onTap:action,child:RoyalPanel(padding:const EdgeInsets.all(6),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          Icon(icon,color:KColor.light,size:22),
          Text(title,style:const TextStyle(color:KColor.light,fontSize:9,
            fontWeight:FontWeight.bold)),
        ])));
  Widget _topBar()=>SafeArea(bottom:false,
    child:Column(mainAxisSize:MainAxisSize.min,children:[
      Container(height:42,color:const Color(0xe51a1512),
        child:ListView(scrollDirection:Axis.horizontal,children:[
          for(final good in [Good.gold,Good.wood,Good.stone,Good.grain,
             Good.bread,Good.water,Good.tools,Good.plank])
            CoinLabel(good:good,count:g.amount(good),onTap:_storage),
        ])),
      RoyalPanel(padding:const EdgeInsets.symmetric(horizontal:8,
          vertical:5),child:Row(children:[
        const Icon(Icons.shield_rounded,color:KColor.gold,size:30),
        const SizedBox(width:6),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            const Text('ممالك الحياة',style:TextStyle(color:KColor.light,
              fontSize:16,fontWeight:FontWeight.w900)),
            Text(g.city.name,style:const TextStyle(color:KColor.muted,
              fontSize:10)),
          ])),
        Column(children:[
          Text('اليوم '+g.day.toString()+' • '+g.season,
            style:const TextStyle(color:KColor.light,fontSize:10)),
          Text(g.timeLabel,style:const TextStyle(color:KColor.gold,
            fontWeight:FontWeight.bold)),
        ]),
        IconButton(onPressed:g.pause,
          icon:Icon(g.paused?Icons.play_arrow:Icons.pause,
          color:KColor.light)),
        InkWell(onTap:g.changeSpeed,child:Text('×'+g.speed.toString(),
          style:const TextStyle(color:KColor.gold,
            fontWeight:FontWeight.w900,fontSize:16))),
        const SizedBox(width:7),
        MapDial(engine:g,onTap:_travel),
      ])),
    ]));
  Widget _overlays()=>Row(crossAxisAlignment:CrossAxisAlignment.start,
    children:[
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          RoyalPanel(padding:const EdgeInsets.all(7),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,
              children:[
                InkWell(onTap:()=>setState(()=>showTasks=!showTasks),
                  child:Row(children:[
                    const Icon(Icons.assignment,color:KColor.gold,size:17),
                    const SizedBox(width:4),
                    const Expanded(child:Text('المهام',style:TextStyle(
                        color:KColor.light,fontWeight:FontWeight.bold))),
                    Icon(showTasks?Icons.expand_less:Icons.expand_more,
                      color:KColor.gold,size:19),
                  ])),
                if(showTasks)...[
                  const Divider(color:KColor.wood),
                  for(final quest in KingdomEngine.questTitles.entries.take(3))
                    Padding(padding:const EdgeInsets.symmetric(vertical:4),
                      child:InkWell(onTap:_contracts,child:Text(
                        '🎯 '+quest.value+' ('+
                        g.goalProgress(quest.key).toString()+' / '+
                        g.goalTarget(quest.key).toString()+')',
                        maxLines:2,style:const TextStyle(
                          color:KColor.light,fontSize:10)))),
                  RoyalButton(text:'كل العقود',icon:Icons.list,
                    onTap:_contracts),
                ],
              ])),
          const SizedBox(height:6),
          _shortcut(Icons.account_balance,'الاقتصاد',_economy),
          const SizedBox(height:5),
          _shortcut(Icons.travel_explore,'السفر',_travel),
        ])),
      const SizedBox(width:5),
      Expanded(child:RoyalPanel(padding:const EdgeInsets.all(7),
        child:Column(children:[
          InkWell(onTap:()=>setState(()=>showNeeds=!showNeeds),
            child:Row(children:[
              const Icon(Icons.favorite,color:KColor.gold,size:17),
              const SizedBox(width:5),
              const Expanded(child:Text('احتياجات البطل',
                style:TextStyle(color:KColor.light,fontSize:11,
                  fontWeight:FontWeight.bold))),
              Icon(showNeeds?Icons.expand_less:Icons.expand_more,
                  color:KColor.gold,size:19),
            ])),
          if(showNeeds)...[
            for(final key in ['الجوع','العطش','الطاقة','الصحة'])
              StatusMeter(name:key,value:g.needs[key]??100,
                color:key=='الصحة'?const Color(0xffcf514b):
                  key=='الطاقة'?const Color(0xffe4b63f):
                  const Color(0xff6cc657),
                symbol:switch(key){
                  'الجوع'=>'🍗','العطش'=>'💧','الطاقة'=>'⚡',_=>'❤️'}),
            RoyalButton(text:'إدارة الشخصية',
                icon:Icons.person,onTap:_heroes),
          ],
        ]))),
    ]);
  Widget _bottomNav()=>SafeArea(top:false,child:RoyalPanel(
    padding:const EdgeInsets.fromLTRB(5,8,5,4),
    child:Row(children:[
      _nav(Icons.person,'الشخصية',_heroes),
      _nav(Icons.map,'الخريطة',_travel),
      _nav(Icons.inventory_2,'المخزن',_storage),
      _nav(Icons.storefront,'السوق',_market),
      _nav(Icons.construction,'البناء',_construction),
    ]),
  ));
  Widget _nav(IconData icon,String title,VoidCallback action)=>Expanded(
    child:Padding(padding:const EdgeInsets.symmetric(horizontal:2),
      child:InkWell(onTap:action,
        child:Container(
          padding:const EdgeInsets.symmetric(vertical:7),
          decoration:BoxDecoration(
            gradient:const LinearGradient(colors:[
               Color(0xff96673e),Color(0xff422b1b)]),
            border:Border.all(color:KColor.gold),
            borderRadius:BorderRadius.circular(10)),
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            Icon(icon,color:KColor.light,size:28),
            const SizedBox(height:3),
            Text(title,style:const TextStyle(color:KColor.light,
                fontWeight:FontWeight.bold,fontSize:10)),
          ]),
        ),
      ),
    ),
  );
  void _step(int x,int y) {
    final result = g.walkTo(g.heroX+x,g.heroY+y);
    if(result.ok) audio.cue('walk');
    else _msg(result);
  }

  void _interact() {
    for(final person in people) {
      final p=g.npcTile(person);
      if((g.heroX-p.x).abs()+(g.heroY-p.y).abs()<=5) {
        _personDetails(person);
        return;
      }
    }
    for(final site in g.sites) {
      if((g.heroX-site.x).abs()+(g.heroY-site.y).abs()<=3) {
        _siteDetails(site);
        return;
      }
    }
    _msg(const GameResult(false,'لا يوجد شخص أو مبنى قريب للتفاعل'));
  }

  Widget _pad(IconData icon,VoidCallback action) =>
    InkWell(onTap:action,customBorder:const CircleBorder(),
      child:Container(
        width:39,height:39,
        decoration:BoxDecoration(
          shape:BoxShape.circle,
          color:const Color(0xcc3d3020),
          border:Border.all(color:KColor.gold,width:1)),
        child:Icon(icon,color:KColor.light,size:24),
      ));

  Widget _joystick()=>RoyalPanel(
    padding:const EdgeInsets.all(4),
    child:SizedBox(width:128,height:121,child:Stack(children:[
      Positioned(top:0,left:44,child:_pad(Icons.keyboard_arrow_up,
        ()=>_step(-1,0))),
      Positioned(top:40,left:0,child:_pad(Icons.keyboard_arrow_left,
        ()=>_step(0,1))),
      Positioned(top:40,right:0,child:_pad(Icons.keyboard_arrow_right,
        ()=>_step(0,-1))),
      Positioned(bottom:0,left:44,child:_pad(Icons.keyboard_arrow_down,
        ()=>_step(1,0))),
      Center(child:InkWell(onTap:_focusHero,
        child:Container(width:39,height:39,
          decoration:BoxDecoration(
            shape:BoxShape.circle,
            color:const Color(0xffa57a3f),
            border:Border.all(color:KColor.light,width:2)),
          child:const Icon(Icons.my_location,color:KColor.light,size:22)))),
    ])),
  );

  Widget _controls()=>Row(
    mainAxisAlignment:MainAxisAlignment.spaceBetween,
    crossAxisAlignment:CrossAxisAlignment.end,
    children:[
      _joystick(),
      Column(mainAxisSize:MainAxisSize.min,children:[
        _shortcut(running?Icons.directions_run:Icons.directions_walk,
          running?'ركض ✓':'ركض',(){
            setState(()=>running=!running);
            _msg(GameResult(true,running?'تم تفعيل الركض':'تم إيقاف الركض'));
          }),
        const SizedBox(height:5),
        _shortcut(Icons.front_hand_rounded,'تفاعل',_interact),
        const SizedBox(height:5),
        _shortcut(Icons.handyman,'عمل',()=>
          _msg(g.act('work'),cue:'wood')),
      ]),
    ]);
  
  void _settings(){
    _sheet('إعدادات المملكة',(ctx,update)=>Column(children:[
      _infoLine('مؤثرات صوتية أصلية تعمل أوفلاين',
        g.sound?'الصوت يعمل':'صامت','🔊',
        action:'تبديل',onTap:(){
          g.toggleSound();audio.toggle();
        }),
      _infoLine('حفظ التقدم',
        'يُحفظ محليًا على جهازك، بدون أي حساب','💾',
        action:'احفظ',onTap:(){
          g.save();_msg(const GameResult(true,'تم حفظ اللعبة'));
        }),
      _infoLine('الخريطة الكبيرة',
        '64 × 64 قطعة أرض، مدينة وسكان ومبانٍ منفصلة','🗺️'),
      _infoLine('نظام اقتصاد جديد',
        'لا يُستخدم أي كود أو حفظ من المحرك القديم','⚙️'),
      const Padding(padding:EdgeInsets.all(12),
        child:Text('تنبيه: الرسم الحالي إيزومتري 2.5D مرسوم بالكود، '
          'وليس نموذجًا ثلاثي الأبعاد سينمائيًا. كل مبنى وشخصية '
          'يُرسم ويُدار ككائن مستقل.',
          style:TextStyle(color:KColor.muted,height:1.7),
          textAlign:TextAlign.center)),
    ]),height:.58);
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xff152c24),
    body:Stack(children:[
      Positioned.fill(child:_world()),
      Positioned(top:0,left:0,right:0,child:_topBar()),
      Positioned(top:150,left:7,right:7,child:_overlays()),
      Positioned(bottom:102,left:8,right:8,child:_controls()),
      Positioned(bottom:0,left:0,right:0,child:_bottomNav()),
      if(selectedFacility!=null)Positioned(bottom:248,left:8,right:8,
        child:RoyalPanel(child:Row(children:[
          const Icon(Icons.touch_app,color:KColor.gold,size:23),
          const SizedBox(width:7),
          Expanded(child:Text('المس قطعة أرض لبناء '+
              selectedFacility!.info.name,
            style:const TextStyle(color:KColor.light,
              fontWeight:FontWeight.bold,fontSize:12))),
          IconButton(onPressed:()=>setState(()=>selectedFacility=null),
            icon:const Icon(Icons.close,color:KColor.light)),
        ]))),
    ]),
  );
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../kingdom/catalog.dart';
import '../kingdom/engine.dart';
import 'world_painter.dart';

class KColor {
  static const gold=Color(0xffe7b956);
  static const light=Color(0xffffe4a8);
  static const dark=Color(0xff211711);
  static const wood=Color(0xff6f462c);
  static const parchment=Color(0xfff0d8a4);
  static const green=Color(0xff5c9636);
  static const red=Color(0xffab4337);
  static const muted=Color(0xffdac6a4);
}

class RoyalPanel extends StatelessWidget {
  final Widget child; final EdgeInsets padding;
  final bool paper;
  const RoyalPanel({super.key,required this.child,
    this.padding=const EdgeInsets.all(12),this.paper=false});
  @override
  Widget build(BuildContext context) => Container(
    padding:padding,
    decoration:BoxDecoration(
      gradient:LinearGradient(
        begin:Alignment.topLeft,end:Alignment.bottomRight,
        colors:paper?
          [const Color(0xfff7e5b9),const Color(0xffcda871)]:
          [const Color(0xff795030),const Color(0xff3c281b),const Color(0xff251a13)]),
      borderRadius:BorderRadius.circular(13),
      border:Border.all(color:KColor.gold,width:1.6),
      boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:14,
        offset:Offset(0,5))],
    ),
    child:Stack(children:[
      child,
      Positioned(left:1,top:1,child:_rivet()),
      Positioned(right:1,top:1,child:_rivet()),
      Positioned(left:1,bottom:1,child:_rivet()),
      Positioned(right:1,bottom:1,child:_rivet()),
    ]),
  );
  Widget _rivet()=>Container(width:5,height:5,decoration:const BoxDecoration(
    color:Color(0xfff6d17c),shape:BoxShape.circle));
}

class RoyalButton extends StatelessWidget {
  final String text; final IconData icon; final VoidCallback? onTap;
  final bool green;
  const RoyalButton({super.key,required this.text,required this.icon,
     this.onTap,this.green=false});
  @override
  Widget build(BuildContext context)=>InkWell(
    onTap:onTap,borderRadius:BorderRadius.circular(9),
    child:Container(
      alignment:Alignment.center,
      constraints:const BoxConstraints(minHeight:41),
      padding:const EdgeInsets.symmetric(horizontal:8,vertical:8),
      decoration:BoxDecoration(
        borderRadius:BorderRadius.circular(9),
        gradient:LinearGradient(
          begin:Alignment.topCenter,end:Alignment.bottomCenter,
          colors:green?[const Color(0xff83bf49),const Color(0xff28612f)]:
          [const Color(0xffad7a3c),const Color(0xff56371f)]),
        border:Border.all(color:KColor.gold,width:1.4),
        boxShadow:const [BoxShadow(color:Color(0x88301c13),
          blurRadius:3,offset:Offset(0,3))],
      ),
      child:Row(mainAxisAlignment:MainAxisAlignment.center,
        mainAxisSize:MainAxisSize.min,children:[
          Icon(icon,size:18,color:KColor.light),const SizedBox(width:5),
          Flexible(child:Text(text,maxLines:1,overflow:TextOverflow.ellipsis,
            style:const TextStyle(color:Colors.white,fontSize:12,
              fontWeight:FontWeight.w900))),
        ]),
    ),
  );
}

class StatusMeter extends StatelessWidget {
  final String name; final double value; final Color color;
  final String symbol;
  const StatusMeter({super.key,required this.name,required this.value,
    required this.color,required this.symbol});
  @override
  Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.symmetric(vertical:3),
    child:Row(children:[
      SizedBox(width:20,child:Text(symbol,style:const TextStyle(fontSize:14))),
      const SizedBox(width:3),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Row(children:[
            Expanded(child:Text(name,style:const TextStyle(
              color:KColor.light,fontSize:10,fontWeight:FontWeight.bold))),
            Text(value.round().toString()+'%',style:const TextStyle(
              color:KColor.light,fontSize:9)),
          ]),
          const SizedBox(height:2),
          Container(height:8,decoration:BoxDecoration(
            color:const Color(0xff231913),borderRadius:BorderRadius.circular(9)),
            child:FractionallySizedBox(widthFactor:value.clamp(0,100)/100,
              alignment:Alignment.centerRight,
              child:DecoratedBox(decoration:BoxDecoration(
                borderRadius:BorderRadius.circular(9),
                gradient:LinearGradient(colors:[
                  color,Color.lerp(color,Colors.white,.3)!])))),
          ),
        ])),
    ]),
  );
}
class CoinLabel extends StatelessWidget {
 final Good good;final int count;final VoidCallback? onTap;
 const CoinLabel({super.key,required this.good,required this.count,this.onTap});
 @override
 Widget build(BuildContext context)=>InkWell(
   onTap:onTap,
   child:Container(
     margin:const EdgeInsets.symmetric(horizontal:3,vertical:4),
     padding:const EdgeInsets.symmetric(horizontal:9,vertical:6),
     decoration:BoxDecoration(
       gradient:const LinearGradient(colors:[
         Color(0xff654329),Color(0xff271d16)]),
       border:Border.all(color:const Color(0xffb48a50)),
       borderRadius:BorderRadius.circular(9)),
     child:Row(mainAxisSize:MainAxisSize.min,children:[
       Text(good.icon,style:const TextStyle(fontSize:17)),
       const SizedBox(width:5),
       Text(count.toString(),style:const TextStyle(color:Colors.white,
         fontWeight:FontWeight.bold,fontSize:13)),
     ]),
   ),
 );
}

class BuildingPortrait extends StatelessWidget {
  final Facility type;final KingdomEngine engine;
  final double height;
  const BuildingPortrait({super.key,required this.type,required this.engine,
     this.height=106});
  @override
  Widget build(BuildContext context) => Container(
    height:height,
    clipBehavior:Clip.antiAlias,
    decoration:BoxDecoration(
      gradient:const LinearGradient(colors:[
        Color(0xff92b770),Color(0xff426e48)]),
      borderRadius:BorderRadius.circular(8),
      border:Border.all(color:KColor.gold)),
    child:CustomPaint(painter:_MiniBuildingPainter(type,engine)),
  );
}

class _MiniBuildingPainter extends CustomPainter {
  final Facility type;final KingdomEngine engine;
  _MiniBuildingPainter(this.type,this.engine);
  @override
  void paint(Canvas c,Size size) {
    c.drawRect(Offset.zero&size,
      Paint()..color=const Color(0xff597c4d));
    final painter=WorldPainter(engine);
    final scale=math.min(size.width/105,size.height/125);
    c.save();
    c.translate(size.width*.50,size.height*.84);
    c.scale(scale);
    c.translate(-MapSpace.ox,-MapSpace.oy);
    painter.site(c,Site(-1,type,0,0));
    c.restore();
  }
  @override
  bool shouldRepaint(covariant _MiniBuildingPainter old)=>old.type!=type;
}

class MapDial extends StatelessWidget {
 final KingdomEngine engine;final VoidCallback onTap;
 const MapDial({super.key,required this.engine,required this.onTap});
 @override
 Widget build(BuildContext context)=>InkWell(
   onTap:onTap,
   customBorder:const CircleBorder(),
   child:Container(width:79,height:79,
     decoration:BoxDecoration(shape:BoxShape.circle,
       border:Border.all(color:KColor.gold,width:3),
       boxShadow:const [BoxShadow(color:Colors.black54,blurRadius:7)]),
     child:ClipOval(child:CustomPaint(painter:_MiniMapPainter(engine))),
   ),
 );
}
class _MiniMapPainter extends CustomPainter {
 final KingdomEngine engine;_MiniMapPainter(this.engine);
 @override
 void paint(Canvas c,Size size){
   c.drawColor(const Color(0xff517e43),BlendMode.src);
   for(var x=0;x<64;x+=2){
     for(var y=0;y<64;y+=2){
       final t=landAt(x,y);
       if(t==Land.meadow)continue;
       final color=switch(t){
         Land.river=>const Color(0xff499bcc),
         Land.bridge=>const Color(0xff8b724c),
         Land.path=>const Color(0xffc3ae80),
         Land.forest=>const Color(0xff285c30),
         Land.hill=>const Color(0xff969280),
         Land.soil=>const Color(0xff997a4d),
         _=>const Color(0xff4d8b45),
       };
       c.drawRect(Rect.fromLTWH(x*size.width/64,y*size.height/64,
         3,3),Paint()..color=color);
     }
   }
   for(final town in towns){
     final p=Offset(town.x*size.width/64,town.y*size.height/64);
     c.drawCircle(p,3,Paint()..color=const Color(0xffffdb7b));
     c.drawCircle(p,1.4,Paint()..color=const Color(0xff674323));
   }
   c.drawCircle(Offset(engine.heroX*size.width/64,
     engine.heroY*size.height/64),4,
     Paint()..color=const Color(0xfffef8e5));
 }
 @override
 bool shouldRepaint(covariant _MiniMapPainter old)=>
   old.engine.heroX!=engine.heroX||old.engine.heroY!=engine.heroY||
   old.engine.cityId!=engine.cityId;
}

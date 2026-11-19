import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../kingdom/catalog.dart';
import '../kingdom/engine.dart';

/// Independent procedural sprites: every visible site has its own coordinates,
/// type and hit target. No screenshot is rendered in gameplay.
class MapSpace {
  static const tw=82.0,th=42.0,ox=2744.0,oy=130.0;
  static const Size size=Size(5488,3140);
  static Offset at(int x,int y)=>Offset(ox+(x-y)*tw/2,oy+(x+y)*th/2);
  static math.Point<int> tile(Offset v){
    final a=(v.dx-ox)/(tw/2),b=(v.dy-oy)/(th/2);
    return math.Point(((a+b)/2).round(),((b-a)/2).round());
  }
}

class WorldPainter extends CustomPainter {
  final KingdomEngine game; final int fingerprint;
  WorldPainter(this.game):fingerprint=game.sites.fold<int>(game.sites.length,
      (a,s)=>a+s.id+s.level*7)+game.day;
  void poly(Canvas c,List<Offset> ps,Color color,{Color? edge}){
    final path=Path()..moveTo(ps.first.dx,ps.first.dy);
    for(final p in ps.skip(1)) {path.lineTo(p.dx,p.dy);}
    path.close();
    c.drawPath(path,Paint()..color=color);
    if(edge!=null)c.drawPath(path,Paint()..color=edge
      ..style=PaintingStyle.stroke..strokeWidth=1);
  }
  void circ(Canvas c,Offset p,double r,Color color)=>c.drawCircle(p,r,
      Paint()..color=color);
  void line(Canvas c,Offset a,Offset b,Color color,double weight) =>
      c.drawLine(a,b,Paint()..color=color..strokeWidth=weight
        ..strokeCap=StrokeCap.round);
  void square(Canvas c,Rect r,Color color,{Color? edge,double radius=0}){
    final shape=RRect.fromRectAndRadius(r,Radius.circular(radius));
    c.drawRRect(shape,Paint()..color=color);
    if(edge!=null)c.drawRRect(shape,Paint()..color=edge
      ..style=PaintingStyle.stroke..strokeWidth=1);
  }
  double noise(int x,int y,int z)=>((x*137+y*251+x*y*47+z*137)%101)/101;
  void ground(Canvas c,int x,int y){
    final p=MapSpace.at(x,y),t=landAt(x,y),n=noise(x,y,3);
    final color=switch(t){
      Land.path=>Color.lerp(const Color(0xffa2967b),const Color(0xffc5b695),n)!,
      Land.river=>Color.lerp(const Color(0xff20628b),const Color(0xff469cba),n)!,
      Land.bridge=>const Color(0xff846544),
      Land.forest=>const Color(0xff3d7339),
      Land.hill=>const Color(0xff888c77),
      Land.soil=>const Color(0xff987144),
      Land.meadow=>Color.lerp(const Color(0xff50833d),const Color(0xff80aa4f),n)!,
    };
    poly(c,[p.translate(0,-21),p.translate(41,0),p.translate(0,21),
        p.translate(-41,0)],color,
      edge:Color.lerp(color,Colors.black,.12));
    if(t==Land.bridge) {
      for(var i=-2;i<=2;i++) {
        line(c,p.translate(-32,i*5.0),p.translate(32,i*5.0),
          const Color(0xffd6ab73),3);
      }
      line(c,p.translate(-38,-15),p.translate(38,-15),
        const Color(0xff69482d),4);
      line(c,p.translate(-38,15),p.translate(38,15),
        const Color(0xff69482d),4);
    } else if(t==Land.river) {
      line(c,p.translate(-19,-2),p.translate(-2,3),
        const Color(0xffa7d8e2),1.8);
      line(c,p.translate(6,-5),p.translate(22,1),
        const Color(0xff64b4d0),1.8);
    } else if(t==Land.path){
      for(var i=0;i<3;i++) square(c,Rect.fromCenter(
        center:p.translate((noise(x,y,i+5)-.5)*47,
          (noise(x,y,i+11)-.5)*13),
        width:7,height:3),const Color(0x55e2cfad),radius:1);
    } else if(t==Land.soil){
      for(var i=-2;i<3;i++) line(c,p.translate(-25,i*3.0),
        p.translate(24,i*3.0),const Color(0xffc39b59),2);
    } else if(t==Land.meadow&&noise(x,y,29)>.83) {
      circ(c,p.translate(-8,-4),1.9,const Color(0xffecdf80));
      circ(c,p.translate(9,5),1.5,const Color(0xfff1f0d3));
    }
  }
  void tree(Canvas c,Offset p,{double scale=1}){
    c.save();c.translate(p.dx,p.dy);c.scale(scale);
    c.drawOval(const Rect.fromLTWH(-19,2,37,13),
       Paint()..color=const Color(0x66402b20));
    line(c,const Offset(0,0),const Offset(0,-30),
      const Color(0xff64442c),8);
    for(final v in const [
      (Offset(-13,-32),17.0,Color(0xff386c35)),
      (Offset(13,-34),20.0,Color(0xff3c8036)),
      (Offset(-3,-48),24.0,Color(0xff57913c)),
      (Offset(-15,-47),10.0,Color(0xff89b453)),
    ]) {circ(c,v.$1,v.$2,v.$3);}
    c.restore();
  }
  void rock(Canvas c,Offset p,{double scale=1}){
    c.save();c.translate(p.dx,p.dy);c.scale(scale);
    poly(c,const [Offset(-23,2),Offset(-10,-15),Offset(9,-16),
      Offset(23,-2),Offset(11,10),Offset(-17,8)],
      const Color(0xff888e8e),edge:const Color(0xff3e4c4d));
    poly(c,const [Offset(-23,2),Offset(-10,-15),Offset(-4,-2),
      Offset(-17,8)],const Color(0xff5c676c));
    poly(c,const [Offset(-10,-15),Offset(9,-16),Offset(23,-2),
      Offset(-4,-2)],const Color(0xffb2bab6));
    c.restore();
  }
  void farm(Canvas c,Offset p){
    square(c,Rect.fromCenter(center:p,width:69,height:33),
      const Color(0xff76512e),edge:const Color(0xffdac07e),radius:2);
    for(var i=0;i<5;i++){
      final dx=-27.0+i*13;
      line(c,p.translate(dx,-12),p.translate(dx+4,11),
        const Color(0xffcfa65d),2.4);
      for(var j=0;j<4;j++) circ(c,p.translate(dx+j%2*4,-11+j*6.0),
        2.6,j.isOdd?const Color(0xffe2bc4d):const Color(0xff75ad43));
    }
    for(final dx in [-32.0,32.0])line(c,p.translate(dx,-18),
        p.translate(dx,17),const Color(0xffd4b078),3);
  }
  void house(Canvas c,Offset p,Facility facility,{int level=1}){
    final industrial=[
      Facility.forge,Facility.bakery,Facility.brickyard,
      Facility.mill,Facility.carpentry,Facility.weaver,
      Facility.tavern,Facility.clinic,
    ].contains(facility);
    final roof=industrial?const Color(0xffa85433):
      facility==Facility.sawmill?const Color(0xff765839):
      const Color(0xffad4c36);
    final wall=industrial?const Color(0xffc19d6d):
      const Color(0xffe0caa5);
    c.drawOval(Rect.fromCenter(center:p.translate(0,6),
        width:76,height:23),Paint()..color=const Color(0x88432b19));
    poly(c,[p.translate(-34,-4),p.translate(0,-21),
      p.translate(0,-56),p.translate(-34,-40)],wall,
      edge:const Color(0xff67472d));
    poly(c,[p.translate(0,-21),p.translate(34,-4),
      p.translate(34,-40),p.translate(0,-56)],
      Color.lerp(wall,Colors.black,.16)!,edge:const Color(0xff67472d));
    for(final dx in [-26.0,-9.0,10.0,27.0]) line(c,
      p.translate(dx,-9),p.translate(dx,-39),
      const Color(0xff795431),2.5);
    square(c,Rect.fromLTWH(p.dx-8,p.dy-27,15,23),
      const Color(0xff563520),edge:const Color(0xffc99c5e));
    square(c,Rect.fromLTWH(p.dx-24,p.dy-33,11,13),
      const Color(0xffffd66e),edge:const Color(0xff8e5630));
    square(c,Rect.fromLTWH(p.dx+13,p.dy-32,12,12),
      const Color(0xffffcf67),edge:const Color(0xff8e5630));
    poly(c,[p.translate(-42,-40),p.translate(-11,-76),
      p.translate(5,-77),p.translate(-20,-43)],
      Color.lerp(roof,Colors.white,.18)!,
      edge:const Color(0xff633d2b));
    poly(c,[p.translate(-20,-43),p.translate(5,-77),
      p.translate(44,-43),p.translate(9,-30)],
      roof,edge:const Color(0xff633d2b));
    for(var i=0;i<3;i++) {
      line(c,p.translate(-15+i*9.0,-48-i*8.0),
          p.translate(12+i*9.0,-35-i*1.5),
          const Color(0x557e341f),1.5);
    }
    if(industrial){
      square(c,Rect.fromLTWH(p.dx-15,p.dy-93,10,21),
        const Color(0xff898b85),edge:const Color(0xff4d4e4c));
    }
    if(facility!=Facility.house){
      circ(c,p.translate(1,-67),11,const Color(0xff3b2b1c));
      final icon=TextPainter(text:TextSpan(text:facility.info.icon,
        style:const TextStyle(fontSize:15)),textDirection:TextDirection.ltr)
        ..layout();
      icon.paint(c,p.translate(-7,-77));
    }
    if(level>1) {
      final label=TextPainter(text:TextSpan(text:level.toString(),
        style:const TextStyle(color:Color(0xffffe4a1),
          fontWeight:FontWeight.bold,fontSize:12)),
        textDirection:TextDirection.ltr)..layout();
      label.paint(c,p.translate(21,-79));
    }
  }
  void market(Canvas c,Offset p){
    c.drawOval(Rect.fromCenter(center:p.translate(0,8),
       width:90,height:25),Paint()..color=const Color(0x99523018));
    square(c,Rect.fromLTWH(p.dx-38,p.dy-25,77,30),
       const Color(0xff8c5930),edge:const Color(0xffd5a75e));
    for(final dx in [-31.0,32.0]) {
      line(c,p.translate(dx,-37),p.translate(dx,5),
         const Color(0xff674428),4);
    }
    for(var i=0;i<6;i++) {
      final x=-42.0+i*14;
      poly(c,[p.translate(x,-36),p.translate(x+15,-36),
        p.translate(x+9,-23),p.translate(x-3,-23)],
        i.isEven?const Color(0xffb34330):
        const Color(0xffe9dfc6));
      circ(c,p.translate(-30+i*11.0,-12),4,
        i.isEven?const Color(0xffe3482e):const Color(0xffe5b844));
    }
    poly(c,[p.translate(-43,-36),p.translate(-18,-56),
      p.translate(18,-56),p.translate(43,-36)],
      const Color(0xffb8563e),edge:const Color(0xfff3dba9));
  }
  void castle(Canvas c,Offset p) {
    c.drawOval(Rect.fromCenter(center:p.translate(0,8),
        width:126,height:28),Paint()..color=const Color(0x88512e20));
    for(final dx in [-37.0,36.0]){
      square(c,Rect.fromLTWH(p.dx+dx-13,p.dy-113,27,101),
        const Color(0xff999fa0),edge:const Color(0xff4f595b));
      for(var i=0;i<4;i++)square(c,Rect.fromLTWH(
        p.dx+dx-16+i*9,p.dy-122,8,10),const Color(0xffb1b6b2));
      square(c,Rect.fromLTWH(p.dx+dx-4,p.dy-83,8,15),
        const Color(0xff3b4a57));
    }
    square(c,Rect.fromLTWH(p.dx-23,p.dy-89,47,80),
      const Color(0xffa7adab),edge:const Color(0xff546066));
    for(var i=0;i<5;i++) square(c,Rect.fromLTWH(
      p.dx-23+i*10,p.dy-97,9,9),const Color(0xffc2c5ba));
    square(c,Rect.fromLTWH(p.dx-9,p.dy-28,18,21),
      const Color(0xff413327),edge:const Color(0xffdab971),radius:5);
    line(c,p.translate(0,-98),p.translate(0,-146),
      const Color(0xff61452f),3);
    poly(c,[p.translate(0,-146),p.translate(27,-134),
      p.translate(0,-122)],const Color(0xff285487));
    circ(c,p.translate(12,-135),3,const Color(0xfff7c45c));
  }
  void site(Canvas c,Site s) {
    final p=MapSpace.at(s.x,s.y);
    switch (s.kind) {
      case Facility.farm:
        farm(c,p);
        break;
      case Facility.quarry:
      case Facility.mine:
        rock(c,p,scale:1.4);
        break;
      case Facility.well:
        square(c,Rect.fromCenter(center:p,width:38,height:21),
            const Color(0xff797979),edge:const Color(0xffccd3d0),radius:7);
        circ(c,p,11,const Color(0xff3188af));
        line(c,p.translate(-15,-5),p.translate(-15,-33),
          const Color(0xff745239),4);
        line(c,p.translate(15,-5),p.translate(15,-33),
          const Color(0xff745239),4);
        poly(c,[p.translate(-22,-33),p.translate(0,-48),
          p.translate(23,-33),p.translate(13,-29),
          p.translate(-13,-29)],const Color(0xff914934));
        break;
      case Facility.market:
        market(c,p);
        break;
      case Facility.castle:
        castle(c,p);
        break;
      case Facility.ranch:
        farm(c,p);
        circ(c,p.translate(-10,-5),8,const Color(0xffe3d6b4));
        circ(c,p.translate(14,-3),7,const Color(0xffe9ba96));
        break;
      default:
        house(c,p,s.kind,level:s.level);
        if(s.kind==Facility.woodcutter||s.kind==Facility.sawmill){
          for(var i=0;i<3;i++) line(c,p.translate(12,5+i*5.0),
            p.translate(35,5+i*5.0),const Color(0xffa26e3d),4);
        }
        break;
    }
  }
  @override
  void paint(Canvas c,Size size){
    c.drawRect(Offset.zero&size,Paint()..color=const Color(0xff244c3f));
    final cells=<int,Site>{for(final s in game.sites) s.x*64+s.y:s};
    for(var depth=0;depth<=126;depth++){
      for(var x=0;x<64;x++){
        final y=depth-x;if(y<0||y>=64)continue;
        ground(c,x,y);
        final siteValue=cells[x*64+y];
        if(siteValue!=null){site(c,siteValue);continue;}
        final terrain=landAt(x,y),p=MapSpace.at(x,y);
        if(terrain==Land.forest&&noise(x,y,9)>.42){
          tree(c,p,scale:.73+noise(x,y,20)*.24);
        } else if(terrain==Land.hill){
          rock(c,p,scale:.75+noise(x,y,4)*.3);
        } else if(terrain==Land.meadow&&noise(x,y,26)>.965){
          tree(c,p,scale:.70);
        }
      }
    }
  }
  @override
  bool shouldRepaint(covariant WorldPainter other)=>
    fingerprint!=other.fingerprint;
}
class LifePainter extends CustomPainter{
  final KingdomEngine game;final double phase;
  LifePainter(this.game,this.phase);
  void figure(Canvas c,Offset p,{bool hero=false,bool walking=false,
    Color shirt=const Color(0xff3f6d61)}){
    final hop=walking?math.sin(phase*2*math.pi)*2.0:0.0;
    c.save();c.translate(p.dx,p.dy+hop);
    c.drawOval(const Rect.fromLTWH(-15,-1,30,8),
      Paint()..color=const Color(0x77352119));
    if(hero)c.drawOval(const Rect.fromLTWH(-20,-7,40,18),
      Paint()..color=const Color(0xff78db67)..style=PaintingStyle.stroke
      ..strokeWidth=2.5);
    final legs=Paint()..color=const Color(0xff44322c)
      ..strokeWidth=4..strokeCap=StrokeCap.round;
    c.drawLine(const Offset(-5,-5),const Offset(-5,-17),legs);
    c.drawLine(const Offset(5,-5),const Offset(5,-17),legs);
    final cloak=Path()..moveTo(-10,-36)..lineTo(6,-36)
      ..lineTo(16,-9)..lineTo(-16,-9)..close();
    c.drawPath(cloak,Paint()..color=hero?
        const Color(0xffa33739):shirt);
    c.drawRRect(RRect.fromRectAndRadius(
      const Rect.fromLTWH(-9,-37,18,22),const Radius.circular(3)),
      Paint()..color=const Color(0xffa48461));
    c.drawCircle(const Offset(0,-47),9,
      Paint()..color=const Color(0xffdfa982));
    c.drawArc(const Rect.fromLTWH(-9,-56,18,15),math.pi,math.pi,
      false,Paint()..color=const Color(0xff433128));
    if(hero)c.drawCircle(const Offset(0,-29),3.5,
      Paint()..color=const Color(0xfff4d46d));
    c.restore();
  }
  @override
  void paint(Canvas c,Size size){
    for(final p in people){
      final npc=game.npcTile(p);
      final wobble=math.sin(phase*2*math.pi+p.x*.7)*3.5;
      figure(c,MapSpace.at(npc.x,npc.y).translate(wobble,0),
        shirt:p.job=='مزارعة'?const Color(0xff816a9a):
        p.job=='تاجر'?const Color(0xff846345):
        const Color(0xff4e7883),walking:true);
    }
    figure(c,MapSpace.at(game.heroX,game.heroY),hero:true,
      walking:game.route.isNotEmpty);
    for(final s in game.sites.where((v)=>[
      Facility.forge,Facility.bakery,Facility.brickyard].contains(v.kind))){
      final p=MapSpace.at(s.x,s.y);
      for(var i=0;i<3;i++){
        c.drawCircle(p.translate(-12+math.sin(phase*6+i)*4,
          -93-phase*15-i*9),3.0+i,
          Paint()..color=const Color(0x66e7e9dc));
      }
    }
  }
  @override
  bool shouldRepaint(covariant LifePainter old)=>old.phase!=phase;
}

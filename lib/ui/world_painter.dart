import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../game/catalog.dart';
import '../game/game_state.dart';
import '../game/world_regions.dart';

/// Original vector-isometric art. It is painted in Flutter, not a noninteractive screenshot.
class VillagePainter extends CustomPainter {
  final GameState game;
  final int? selectedX, selectedY;
  final bool buildMode;
  final int animationFrame;
  VillagePainter(this.game, {this.selectedX, this.selectedY,
      this.buildMode = false, this.animationFrame = 0});

  static const double halfW = 53, halfH = 28;
  // Approximately seven times more buildable land than the original 12×12 map.
  static const double originX = 1740, originY = 165;
  static const Size sceneSize = Size(3500, 2050);

  static Offset center(int x, int y) => Offset(originX + (x - y) * halfW, originY + (x + y) * halfH);
  static math.Point<int> tileFrom(Offset p) {
    final a = (p.dx - originX) / halfW, b = (p.dy - originY) / halfH;
    return math.Point(((a + b) / 2).round(), ((b - a) / 2).round());
  }

  void polygon(Canvas c, List<Offset> points, Color fill, {Color? stroke, double width = 1}) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) { path.lineTo(p.dx, p.dy); }
    path.close();
    c.drawPath(path, Paint()..color = fill);
    if (stroke != null) c.drawPath(path, Paint()..color = stroke..style = PaintingStyle.stroke..strokeWidth = width);
  }

  void oval(Canvas c, Offset p, double rx, double ry, Color color) => c.drawOval(
    Rect.fromCenter(center: p, width: rx * 2, height: ry * 2), Paint()..color = color);

  void line(Canvas c, Offset a, Offset b, Color color, double w) => c.drawLine(a, b,
    Paint()..color = color..strokeWidth = w..strokeCap = StrokeCap.round);

  void tile(Canvas c, Offset p, Color fill, {Color? outline, double stroke = 1}) => polygon(c, [
    Offset(p.dx, p.dy - halfH), Offset(p.dx + halfW, p.dy),
    Offset(p.dx, p.dy + halfH), Offset(p.dx - halfW, p.dy),
  ], fill, stroke: outline, width: stroke);

  void text(Canvas c, String text, Offset at, {double size = 12, Color color = Colors.white, bool bold = true}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color,
        shadows: const [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1))])),
      textDirection: TextDirection.rtl,
      maxLines: 1,
    )..layout();
    tp.paint(c, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(bg, Paint()..shader = const LinearGradient(
      colors: [Color(0xff86bcb4), Color(0xff326d50), Color(0xff264c38)],
      begin: Alignment.topCenter, end: Alignment.bottomCenter).createShader(bg));
    final rand = math.Random(43);
    // Three repeating ranges maintain a skyline across the expanded world.
    for (var mountainSection = 0; mountainSection < 3; mountainSection++) {
      canvas.save();
      canvas.translate(mountainSection * 1400.0, 0);
    polygon(canvas, const [Offset(0, 250), Offset(130, 30), Offset(220, 160), Offset(390, 25), Offset(570, 185), Offset(790, 10), Offset(980, 177), Offset(1120, 20), Offset(1350, 170), Offset(1490, 50), Offset(1490, 390), Offset(0, 390)], const Color(0xff54796f));
    polygon(canvas, const [Offset(0, 330), Offset(160, 170), Offset(340, 305), Offset(510, 128), Offset(750, 270), Offset(920, 155), Offset(1160, 310), Offset(1300, 160), Offset(1490, 310), Offset(1490, 470), Offset(0, 470)], const Color(0xff346247));
    for (var i = 0; i < 90; i++) {
      final x = rand.nextDouble() * 1500, y = 190 + rand.nextDouble() * 260;
      polygon(canvas, [Offset(x, y-22), Offset(x-11, y+10), Offset(x+11, y+10)], Color.lerp(const Color(0xff0b533f), const Color(0xff628a48), rand.nextDouble())!);
    }
    canvas.restore();
    }
    // Castle silhouette and banner.
    for (final x in [608.0, 659.0, 714.0]) {
      canvas.drawRect(Rect.fromLTWH(x, 145, 42, 102), Paint()..color = const Color(0xffb2aaa0));
      for (var i = 0; i < 4; i++) {
        canvas.drawRect(Rect.fromLTWH(x + i * 11, 134, 7, 16), Paint()..color = const Color(0xffcec5b4));
      }
      canvas.drawRect(Rect.fromLTWH(x + 15, 190, 10, 22), Paint()..color = const Color(0xff2b3034));
    }
    canvas.drawRect(const Rect.fromLTWH(643, 185, 83, 66), Paint()..color = const Color(0xffbab1a3));
    line(canvas, const Offset(690, 131), const Offset(690, 100), const Color(0xff403426), 3);
    polygon(canvas, const [Offset(691, 101), Offset(730, 113), Offset(691, 125)], const Color(0xffc79142));
    // Ground tiles.
    for (var row = 0; row < GameState.worldSize * 2 - 1; row++) {
      for (var x = 0; x < GameState.worldSize; x++) {
        final y = row - x;
        if (y < 0 || y >= GameState.worldSize) continue;
        final p = center(x, y);
        final road = x == 5 || y == 5 || x == 25 || y == 25 || (x >= 3 && x <= 8 && y == 8);
        final greens = [const Color(0xff69934d), const Color(0xff749e54), const Color(0xff7ea657), const Color(0xff658a4a)];
        final water = game.isWaterTile(x, y);
        final ground = water
            ? (row.isEven ? const Color(0xff3b9eae) : const Color(0xff317c9c))
            : road ? (row.isEven ? const Color(0xffb3a18a) : const Color(0xffa39683))
            : greens[(x * 7 + y * 13) % greens.length];
        tile(canvas, p, ground, outline: Colors.black.withValues(alpha: 0.055));
        if (water) {
          final shimmer = math.sin(animationFrame * 0.38 + x * 1.6 + y).abs();
          line(canvas, Offset(p.dx - 15, p.dy - 2), Offset(p.dx + 8 + shimmer * 8, p.dy - 2),
              const Color(0xffb2e3ed).withValues(alpha: .22 + shimmer * .24), 1.7);
        } else if (road) {
          for (var i = 0; i < 5; i++) {
            final ox = ((x * 11 + y * 17 + i * 29) % 70 - 35).toDouble();
            final oy = ((x * 3 + y * 9 + i * 7) % 24 - 12).toDouble();
            line(canvas, Offset(p.dx + ox, p.dy + oy), Offset(p.dx + ox + 13, p.dy + oy + 4), const Color(0xff8c806c).withValues(alpha: 0.65), 1);
          }
        } else if (game.buildingAt(x, y) == null) {
          for (var i = 0; i < 4; i++) {
            final ox = ((x * 17 + y * 11 + i * 19) % 65 - 32).toDouble();
            final oy = ((x * 23 + y * 19 + i * 7) % 26 - 13).toDouble();
            line(canvas, Offset(p.dx + ox, p.dy + oy), Offset(p.dx + ox + 3, p.dy + oy - 6), const Color(0xff315e31), 1.2);
          }
        }
        if (selectedX == x && selectedY == y) {
          tile(canvas, p, const Color(0x6656ff9e), outline: const Color(0xffd6ffa1), stroke: 3);
          text(canvas, buildMode ? '+' : '✦', Offset(p.dx, p.dy - 8), size: 24, color: Colors.white);
        }
      }
    }
    // Render sprites in a separate depth-sorted pass; foreground ground must
    // not paint over buildings or the controllable hero.
    for (var row = 0; row < GameState.worldSize * 2 - 1; row++) {
      for (var x = 0; x < GameState.worldSize; x++) {
        final y = row - x;
        if (y < 0 || y >= GameState.worldSize) continue;
        final p = center(x, y);
        final road = x == 5 || y == 5 || x == 25 || y == 25 || (x >= 3 && x <= 8 && y == 8);
        final building = game.buildingAt(x, y);
        final town = kingdomCities.where((c) => c.x == x && c.y == y);
        if (town.isNotEmpty) {
          drawCityGate(canvas, p, town.first);
        } else if (building != null) {
          drawBuilding(canvas, p, building);
        } else if (!game.isWaterTile(x, y) && !road && (x + y * 3) % 8 == 2 && !(x == game.px && y == game.py)) {
          drawTree(canvas, Offset(p.dx + 5, p.dy - 4), 0.76 + (x % 3) * 0.11);
        } else if (!game.isWaterTile(x, y) && !road && (x * 3 + y * 7) % 12 == 3) {
          drawFlower(canvas, p);
        }
        if (x == game.px && y == game.py) drawHero(canvas, p);
      }
    }
    // Seasonal light and a visible day/night cycle.
    if (game.season == 'الشتاء') {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0x3389b6cb));
    } else if (game.season == 'الخريف') {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0x21d6814d));
    }
    if (game.isNight) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0x9a0b1935));
      for (final b in game.buildings.where((v) => v.type == BuildingType.house || v.type == BuildingType.market)) {
        final glow = center(b.x, b.y) + const Offset(29, -29);
        final circle = Rect.fromCircle(center: glow, radius: 25);
        canvas.drawOval(circle, Paint()..shader = const RadialGradient(colors: [Color(0x99ffe29b), Color(0x00ffdd77)]).createShader(circle));
      }
    }
    // Each city has its own identity and a persistent marker on the world map.
    // Little road signs for wayfinding.
    final sign = center(4, 5);
    line(canvas, Offset(sign.dx + 14, sign.dy + 10), Offset(sign.dx + 14, sign.dy - 30), const Color(0xff5b3c28), 5);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(sign.dx - 17, sign.dy - 36, 65, 20), const Radius.circular(4)), Paint()..color = const Color(0xff5b3523));
    text(canvas, 'السوق', Offset(sign.dx + 15, sign.dy - 26), size: 13, color: const Color(0xffffe0a0));
  }


  void drawCityGate(Canvas canvas, Offset p, KingdomCity city) {
    final pulse = 0.5 + 0.5 * math.sin(animationFrame * .35);
    final active = game.currentCityId == city.id;
    oval(canvas, Offset(p.dx, p.dy + 9), 50 + pulse * 7, 21 + pulse * 2,
        active ? const Color(0x8870ff9b) : const Color(0x889fd5f3));
    // Height, shading and drop shadows give buildings visible volume.
    polygon(canvas, [Offset(p.dx-39,p.dy+8), Offset(p.dx,p.dy+27),
      Offset(p.dx,p.dy-55), Offset(p.dx-39,p.dy-73)], const Color(0xff8a918a));
    polygon(canvas, [Offset(p.dx,p.dy+27), Offset(p.dx+42,p.dy+5),
      Offset(p.dx+42,p.dy-74), Offset(p.dx,p.dy-55)], const Color(0xffc5c0a5));
    for (final xx in [-29.0, 14.0]) {
      canvas.drawRect(Rect.fromLTWH(p.dx+xx,p.dy-112,19,71),
          Paint()..color=const Color(0xffd5c7ab));
      for (var i=0;i<3;i++) {
        canvas.drawRect(Rect.fromLTWH(p.dx+xx+i*6,p.dy-119,5,13),
          Paint()..color=const Color(0xfff1d6a8));
      }
    }
    polygon(canvas,[Offset(p.dx-15,p.dy+20),Offset(p.dx+12,p.dy+6),
      Offset(p.dx+12,p.dy-22),Offset(p.dx-15,p.dy-10)],const Color(0xff473324));
    line(canvas,Offset(p.dx+2,p.dy-118),Offset(p.dx+2,p.dy-145),
      const Color(0xff5a412c),2.6);
    polygon(canvas,[Offset(p.dx+4,p.dy-146),Offset(p.dx+36,p.dy-139),
      Offset(p.dx+4,p.dy-131)], active ? const Color(0xff7bc78c) : const Color(0xffffc966));
    final box = Rect.fromCenter(center:Offset(p.dx,p.dy-169),width:158,height:30);
    canvas.drawRRect(RRect.fromRectAndRadius(box,const Radius.circular(9)),
      Paint()..color=const Color(0xe533281d));
    text(canvas, city.name, Offset(p.dx,p.dy-169),size:15,
      color:active?const Color(0xffd7ffb7):const Color(0xffffdc95));
  }

  void drawFlower(Canvas canvas, Offset p) {
    for (var i = 0; i < 4; i++) {
      final pos = Offset(p.dx - 13 + i * 8, p.dy + (i.isOdd ? -5 : 1));
      line(canvas, pos, Offset(pos.dx, pos.dy - 8), const Color(0xff39713e), 2);
      oval(canvas, Offset(pos.dx, pos.dy - 9), 3, 3, i.isEven ? const Color(0xfff9c9d8) : const Color(0xffffdb8e));
    }
  }

  void drawTree(Canvas canvas, Offset p, double scale) {
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.scale(scale);
    oval(canvas, const Offset(10, 6), 26, 9, Colors.black.withValues(alpha: 0.18));
    line(canvas, const Offset(0, 5), const Offset(0, -42), const Color(0xff704a2c), 10);
    for (final part in [const Offset(-18, -38), const Offset(19, -40), const Offset(0, -60), const Offset(-6, -28)]) {
      oval(canvas, part, 24, 25, const Color(0xff2d6d39));
      oval(canvas, Offset(part.dx - 6, part.dy - 8), 15, 17, const Color(0xff579951));
    }
    canvas.restore();
  }

  void drawBuilding(Canvas canvas, Offset p, Building b) {
    if (b.type == BuildingType.farm) {
      tile(canvas, p, const Color(0xff705435), outline: const Color(0xffe0b36b), stroke: 3);
      for (var row = -2; row <= 2; row++) {
        for (var i = 0; i < 6; i++) {
          final x = p.dx - 32 + i * 12 + row * 3;
          final y = p.dy + row * 5;
          line(canvas, Offset(x, y+6), Offset(x, y-8), const Color(0xffaab74f), 1.5);
          oval(canvas, Offset(x, y-9), 3, 6, const Color(0xffefcd58));
        }
      }
      text(canvas, '🌾', Offset(p.dx, p.dy - 27), size: 18);
      return;
    }
    if (b.type == BuildingType.well) {
      oval(canvas, Offset(p.dx, p.dy + 10), 30, 12, Colors.black26);
      oval(canvas, Offset(p.dx, p.dy - 7), 25, 16, const Color(0xffb6b4a4));
      oval(canvas, Offset(p.dx, p.dy - 9), 16, 9, const Color(0xff4ca0b0));
      line(canvas, Offset(p.dx - 24, p.dy - 7), Offset(p.dx - 24, p.dy - 56), const Color(0xff75563d), 5);
      line(canvas, Offset(p.dx + 24, p.dy - 7), Offset(p.dx + 24, p.dy - 56), const Color(0xff75563d), 5);
      polygon(canvas, [Offset(p.dx - 35, p.dy - 57), Offset(p.dx, p.dy - 79), Offset(p.dx + 35, p.dy - 57), Offset(p.dx, p.dy - 47)], const Color(0xffa0563e), stroke: const Color(0xffe3a66b));
      return;
    }
    if (b.type == BuildingType.lumberCamp || b.type == BuildingType.quarry) {
      final color = b.type == BuildingType.lumberCamp ? const Color(0xffb88758) : const Color(0xff999f9c);
      oval(canvas, Offset(p.dx, p.dy + 8), 40, 16, Colors.black26);
      for (var i = 0; i < 5; i++) {
        final offset = Offset(p.dx - 24 + i * 10, p.dy - (i % 2) * 8);
        if (b.type == BuildingType.lumberCamp) {
          line(canvas, offset, Offset(offset.dx + 24, offset.dy - 12), color, 10);
          oval(canvas, offset, 5, 6, const Color(0xffe4c68b));
        } else {
          polygon(canvas, [offset, Offset(offset.dx + 11, offset.dy - 18), Offset(offset.dx + 23, offset.dy + 3)], color, stroke: const Color(0xffc5c5be));
        }
      }
      drawSimpleShed(canvas, p);
      return;
    }
    final house = b.type == BuildingType.house;
    final store = b.type == BuildingType.market;
    final roofColor = store ? const Color(0xffbf6757) : house ? const Color(0xff9e4f3e) : const Color(0xff705039);
    oval(canvas, Offset(p.dx + 6, p.dy + 17), 46, 16, Colors.black.withValues(alpha: 0.24));
    // Isometric walls, roof and doors.
    polygon(canvas, [Offset(p.dx - 40, p.dy - 7), Offset(p.dx, p.dy + 14), Offset(p.dx, p.dy - 42), Offset(p.dx - 40, p.dy - 61)], const Color(0xffb7a78d), stroke: const Color(0xff67513e));
    polygon(canvas, [Offset(p.dx, p.dy + 14), Offset(p.dx + 42, p.dy - 8), Offset(p.dx + 42, p.dy - 61), Offset(p.dx, p.dy - 42)], const Color(0xffe0c4a0), stroke: const Color(0xff715a44));
    polygon(canvas, [Offset(p.dx - 50, p.dy - 65), Offset(p.dx - 6, p.dy - 93), Offset(p.dx + 11, p.dy - 57), Offset(p.dx - 40, p.dy - 34)], roofColor, stroke: const Color(0xfff1b87b), width: 2);
    polygon(canvas, [Offset(p.dx - 6, p.dy - 93), Offset(p.dx + 45, p.dy - 62), Offset(p.dx + 49, p.dy - 34), Offset(p.dx + 11, p.dy - 57)], Color.lerp(roofColor, Colors.black, .16)!, stroke: const Color(0xffd49a68), width: 2);
    for (var i = 0; i < 4; i++) {
      line(canvas, Offset(p.dx - 38 + i * 11, p.dy - 61 - i * 7), Offset(p.dx - 27 + i * 11, p.dy - 38 - i * 7), const Color(0x66723924), 2);
    }
    polygon(canvas, [Offset(p.dx + 12, p.dy + 8), Offset(p.dx + 28, p.dy), Offset(p.dx + 28, p.dy - 33), Offset(p.dx + 12, p.dy - 24)], const Color(0xff523524));
    polygon(canvas, [Offset(p.dx + 31, p.dy - 24), Offset(p.dx + 40, p.dy - 29), Offset(p.dx + 40, p.dy - 43), Offset(p.dx + 31, p.dy - 39)], const Color(0xffffd371));
    // Chimney and level flag.
    if (!store) {
      canvas.drawRect(Rect.fromLTWH(p.dx + 19, p.dy - 97, 13, 28), Paint()..color = const Color(0xff9f9280));
      oval(canvas, Offset(p.dx + 26, p.dy - 105), 9, 6, const Color(0x77eeeeee));
    } else {
      line(canvas, Offset(p.dx - 39, p.dy - 8), Offset(p.dx - 39, p.dy - 70), const Color(0xff443321), 5);
      line(canvas, Offset(p.dx + 42, p.dy - 8), Offset(p.dx + 42, p.dy - 61), const Color(0xff443321), 5);
      for (var i = 0; i < 5; i++) {
        canvas.drawRect(Rect.fromLTWH(p.dx - 26 + i * 11, p.dy - 20 + (i % 2) * 3, 9, 9), Paint()..color = i.isEven ? const Color(0xffd84740) : const Color(0xff79b94a));
      }
    }
    if (b.level > 1) {
      text(canvas, '★${b.level}', Offset(p.dx, p.dy - 104), size: 15, color: const Color(0xffffd16d));
    }
  }

  void drawSimpleShed(Canvas canvas, Offset p) {
    line(canvas, Offset(p.dx-33, p.dy+5), Offset(p.dx-33, p.dy-41), const Color(0xff503b2b), 6);
    line(canvas, Offset(p.dx+32, p.dy+6), Offset(p.dx+32, p.dy-39), const Color(0xff503b2b), 6);
    polygon(canvas, [Offset(p.dx - 41, p.dy - 39), Offset(p.dx, p.dy - 72), Offset(p.dx + 41, p.dy - 39), Offset(p.dx, p.dy - 19)], const Color(0xff80603e), stroke: const Color(0xffd6a064), width: 2);
  }

  void drawHero(Canvas canvas, Offset p) {
    final bob = math.sin(animationFrame * .7) * (game.route.isEmpty ? 1.2 : 3.6);
    p = p + Offset(0, bob);
    oval(canvas, Offset(p.dx, p.dy + 9), 25, 11, const Color(0x6658ff91));
    oval(canvas, Offset(p.dx, p.dy + 9), 21, 8, const Color(0xff9ef8a1));
    oval(canvas, Offset(p.dx, p.dy + 8), 17, 5, const Color(0xff375e3d));
    line(canvas, Offset(p.dx - 8, p.dy + 3), Offset(p.dx - 9, p.dy - 16), const Color(0xff403122), 7);
    line(canvas, Offset(p.dx + 7, p.dy + 3), Offset(p.dx + 8, p.dy - 16), const Color(0xff403122), 7);
    polygon(canvas, [Offset(p.dx - 13, p.dy - 17), Offset(p.dx - 20, p.dy - 55), Offset(p.dx + 14, p.dy - 55), Offset(p.dx + 22, p.dy - 14)], const Color(0xff8e3535), stroke: const Color(0xffe0b272), width: 1.5);
    polygon(canvas, [Offset(p.dx - 11, p.dy - 59), Offset(p.dx, p.dy - 68), Offset(p.dx + 11, p.dy - 59), Offset(p.dx + 9, p.dy - 37), Offset(p.dx - 9, p.dy - 37)], const Color(0xff4e342d));
    oval(canvas, Offset(p.dx, p.dy - 74), 10, 12, const Color(0xffdcaf80));
    oval(canvas, Offset(p.dx, p.dy - 84), 12, 7, const Color(0xff4b3028));
    text(canvas, '✦', Offset(p.dx, p.dy - 40), color: const Color(0xffffdd7c), size: 15);
  }

  @override
  bool shouldRepaint(covariant VillagePainter oldDelegate) => true;
}

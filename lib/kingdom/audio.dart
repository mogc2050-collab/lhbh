import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

/// All sound effects are synthesized offline with distinct envelopes.
class KingdomAudio {
  bool enabled=true;
  bool _disposed=false;
  final Map<String,AudioPlayer> players={};
  final Map<String,Uint8List> cache={};
  final AudioPlayer ambience=AudioPlayer();

  static const tones=<String,List<int>>{
    'ui':[690,990], 'walk':[160,132], 'build':[140,220,320,450],
    'upgrade':[330,450,650,890], 'buy':[470,650,850],
    'sell':[910,670,510], 'error':[300,190],
    'wood':[110,175], 'stone':[420,230], 'craft':[205,295,400],
    'eat':[280,440], 'drink':[520,810], 'sleep':[560,350,220],
    'wash':[490,780], 'heal':[410,710,980],
    'travel':[180,250,330,410], 'arrive':[500,720,1070],
    'bank':[360,530,760], 'tax':[510,390], 'caravan':[160,320,490],
    'quest':[540,790,1100], 'citizen':[390,510],
    'coin':[1050,870], 'ambient':[100,170,310],
  };

  Uint8List _sample(String event) {
    const rate=16000;
    final notes=tones[event]??tones['ui']!;
    final calm=event=='ambient';
    final seconds=calm?6.0:.14+notes.length*.125;
    final count=(seconds*rate).round();
    final bytes=ByteData(44+count*2);
    void label(int start,String value) {
      for(var i=0;i<value.length;i++) {
        bytes.setUint8(start+i,value.codeUnitAt(i));
      }
    }
    label(0,'RIFF');bytes.setUint32(4,36+count*2,Endian.little);
    label(8,'WAVE');label(12,'fmt ');
    bytes.setUint32(16,16,Endian.little);
    bytes.setUint16(20,1,Endian.little);
    bytes.setUint16(22,1,Endian.little);
    bytes.setUint32(24,rate,Endian.little);
    bytes.setUint32(28,rate*2,Endian.little);
    bytes.setUint16(32,2,Endian.little);
    bytes.setUint16(34,16,Endian.little);
    label(36,'data');bytes.setUint32(40,count*2,Endian.little);
    for(var i=0;i<count;i++) {
      final t=i/rate;
      double value=0;
      if(calm) {
        value=math.sin(t*130*2*math.pi)*.025;
        value+=math.sin(t*325*2*math.pi)*.008;
        final bird=math.pow(math.max(0,math.sin(t*4)),15).toDouble();
        value+=bird*math.sin(t*1700*2*math.pi)*.027;
      } else {
        final index=math.min(notes.length-1,(t/.12).floor());
        final local=t-index*.12;
        final envelope=math.min(1.0,local/.008)*
            math.exp(-math.max(0,local)*8)*
            math.min(1.0,(seconds-t)/.07).clamp(0.0,1.0);
        final freq=notes[index].toDouble();
        value=(
          math.sin(local*freq*2*math.pi)+
          .19*math.sin(local*freq*3.07*2*math.pi)
        )*envelope*.22;
      }
      bytes.setInt16(44+2*i,(value.clamp(-1,1)*32767).round(),
          Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  void cue(String event) {
    if(!enabled||_disposed) return;
    final player=players.putIfAbsent(event,()=>AudioPlayer());
    unawaited(_play(player,event));
  }
  Future<void> _play(AudioPlayer player,String event) async {
    try {
      await player.stop();
      if(!enabled||_disposed)return;
      await player.play(BytesSource(cache.putIfAbsent(event,
        ()=>_sample(event))),volume:.66);
    } catch (_) {}
  }
  Future<void> start() async {
    if(!enabled||_disposed)return;
    try {
      await ambience.setReleaseMode(ReleaseMode.loop);
      await ambience.play(BytesSource(cache.putIfAbsent('ambient',
        ()=>_sample('ambient'))),volume:.20);
    } catch (_) {}
  }
  void toggle() {
    enabled=!enabled;
    if(enabled) {unawaited(start());}
    else {
      unawaited(ambience.stop());
      for(final p in players.values) {unawaited(p.stop());}
    }
  }
  void dispose() {
    _disposed=true;
    unawaited(ambience.dispose());
    for(final p in players.values) {unawaited(p.dispose());}
    players.clear();
  }
}

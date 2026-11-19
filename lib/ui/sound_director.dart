import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

/// Synthesizes original effect WAVs in memory. Offline and asset-free.
/// This also keeps GitHub builds deterministic and avoids network audio assets.
class SoundDirector {
  final Map<String, AudioPlayer> _players = {};
  final Map<String, Uint8List> _samples = {};
  final AudioPlayer _ambient = AudioPlayer();
  bool enabled = true;
  bool _closed = false;

  static const pitches = <String, List<int>>{
    'select': [790, 1100], 'walk': [160, 115],
    'build': [180, 260, 390], 'upgrade': [330, 490, 660, 920],
    'buy': [530, 740, 980], 'sell': [900, 680, 450],
    'craft': [210, 295, 250], 'chop': [180, 130],
    'mine': [300, 220], 'eat': [290, 380],
    'drink': [520, 750], 'sleep': [490, 350, 240],
    'travel': [200, 260, 330, 420], 'arrival': [410, 570, 800],
    'fail': [280, 180], 'quest': [540, 800, 1140],
    'caravan': [280, 390, 540], 'loan': [390, 290],
  };

  Uint8List _wav(String cue) {
    const sampleRate = 16000;
    final notes = pitches[cue] ?? pitches['select']!;
    final ambient = cue == 'ambience';
    final seconds = ambient ? 5.0 : 0.17 + notes.length * 0.115;
    final count = (seconds * sampleRate).floor();
    final data = ByteData(44 + count * 2);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) { data.setUint8(offset + i, value.codeUnitAt(i)); }
    }
    ascii(0, 'RIFF'); data.setUint32(4, 36 + count * 2, Endian.little);
    ascii(8, 'WAVE'); ascii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little); data.setUint16(22, 1, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little); data.setUint16(34, 16, Endian.little);
    ascii(36, 'data'); data.setUint32(40, count * 2, Endian.little);
    for (var i = 0; i < count; i++) {
      final t = i / sampleRate;
      double value;
      if (ambient) {
        final wind = math.sin(2 * math.pi * 90 * t) * .013 *
            (1 + .4 * math.sin(2 * math.pi * .16 * t));
        final birds = math.sin(2 * math.pi * (1750 + 250 * math.sin(t * 19)) * t) *
            math.pow(math.max(0, math.sin(t * 4.2)), 15).toDouble() * .028;
        value = wind + birds;
      } else {
        final index = math.min(notes.length - 1, (t / .11).floor());
        final age = t - index * .11;
        final attack = math.min(1.0, t / .006);
        final release = math.exp(-math.max(0, age) * 10) *
            math.min(1.0, (seconds - t) / .075).clamp(0.0, 1.0);
        final frequency = notes[index].toDouble();
        final noise = math.sin(2 * math.pi * (frequency * 3.83) * t) * .12;
        value = (math.sin(2 * math.pi * frequency * age) + noise) *
            attack * release * .24;
      }
      data.setInt16(44 + i * 2, (value.clamp(-1, 1) * 32767).toInt(), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  void play(String cue) {
    if (!enabled || _closed) return;
    final player = _players.putIfAbsent(cue, () => AudioPlayer());
    unawaited(_play(player, cue));
  }

  Future<void> _play(AudioPlayer player, String cue) async {
    try {
      await player.stop();
      if (enabled && !_closed) {
        await player.play(BytesSource(_samples.putIfAbsent(cue, () => _wav(cue))), volume: .75);
      }
    } catch (_) { /* Audio must never break gameplay. */ }
  }

  Future<void> startAmbience() async {
    if (!enabled || _closed) return;
    try {
      await _ambient.setReleaseMode(ReleaseMode.loop);
      await _ambient.play(BytesSource(_samples.putIfAbsent('ambience', () => _wav('ambience'))), volume: .32);
    } catch (_) {}
  }

  void setEnabled(bool value) {
    enabled = value;
    if (!value) {
      unawaited(_ambient.stop());
      for (final p in _players.values) { unawaited(p.stop()); }
    } else { unawaited(startAmbience()); }
  }

  void dispose() {
    _closed = true;
    unawaited(_ambient.dispose());
    for (final p in _players.values) { unawaited(p.dispose()); }
    _players.clear();
  }
}

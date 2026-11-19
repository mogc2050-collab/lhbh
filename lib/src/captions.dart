import 'dart:io';
import 'package:flutter/foundation.dart';

@immutable
class CaptionCue {
  const CaptionCue(this.start,this.end,this.text);
  final Duration start,end;
  final String text;
}

class Captions {
  static Duration? _time(String value){
    final match=RegExp(r'(\d{1,2}):([0-5]?\d):([0-5]?\d)[,.](\d{1,3})')
      .firstMatch(value.trim());
    if(match==null)return null;
    final millis=match.group(4)!.padRight(3,'0');
    return Duration(hours:int.parse(match.group(1)!),
      minutes:int.parse(match.group(2)!),
      seconds:int.parse(match.group(3)!),
      milliseconds:int.parse(millis));
  }
  /// Supports plain SRT and VTT subtitle files chosen by the user.
  static List<CaptionCue> parse(String contents){
    final blocks=contents.replaceAll('\r\n','\n')
      .replaceFirst(RegExp(r'^WEBVTT[^\n]*\n'), '')
      .split(RegExp(r'\n\s*\n'));
    final out=<CaptionCue>[];
    for(final block in blocks){
      final lines=block.split('\n');
      final index=lines.indexWhere((line)=>line.contains('-->'));
      if(index<0)continue;
      final times=lines[index].split('-->');
      if(times.length!=2)continue;
      final start=_time(times[0]),end=_time(times[1]);
      if(start==null||end==null||end<=start)continue;
      final text=lines.skip(index+1).join('\n').trim()
        .replaceAll(RegExp(r'<[^>]*>'),'');
      if(text.isNotEmpty)out.add(CaptionCue(start,end,text));
    }
    out.sort((a,b)=>a.start.compareTo(b.start));
    return out;
  }
  static Future<List<CaptionCue>> fromFile(String path) async =>
    parse(await File(path).readAsString());
  static String at(List<CaptionCue> cues,Duration position,
    {Duration offset=Duration.zero}){
    if(cues.isEmpty)return '';
    final time=position+offset;
    var lo=0,hi=cues.length-1;
    while(lo<=hi){
      final mid=(lo+hi)~/2;
      final cue=cues[mid];
      if(time<cue.start){hi=mid-1;}
      else if(time>=cue.end){lo=mid+1;}
      else{return cue.text;}
    }
    return '';
  }
}

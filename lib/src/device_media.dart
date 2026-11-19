import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class PhoneMedia {
  const PhoneMedia({
    required this.id,required this.uri,required this.name,
    required this.kind,required this.size,required this.duration,
    required this.date,required this.mime,
  });
  final int id;
  final String uri;
  final String name;
  final String kind;
  final int size;
  final int duration;
  final int date;
  final String mime;

  bool get audio=>kind=='audio';
  bool get video=>kind=='video';

  factory PhoneMedia.fromJson(Map<String,dynamic> row)=>PhoneMedia(
    id:(row['id'] as num?)?.toInt()??0,
    uri:row['uri'] as String? ?? '',
    name:row['name'] as String? ?? 'ملف بدون اسم',
    kind:row['kind'] as String? ?? 'audio',
    size:(row['size'] as num?)?.toInt()??0,
    duration:(row['duration'] as num?)?.toInt()??0,
    date:(row['date'] as num?)?.toInt()??0,
    mime:row['mime'] as String? ?? '',
  );
}

class PhoneLibrary extends ChangeNotifier {
  static const _channel=MethodChannel('ibetoo.media/device');
  final List<PhoneMedia> audio=[];
  final List<PhoneMedia> videos=[];
  Map<String,bool> permissions={'audio':false,'video':false,'notifications':false};
  bool loading=false;
  String? error;

  bool get audioGranted=>permissions['audio']==true;
  bool get videoGranted=>permissions['video']==true;
  bool get notificationsGranted=>permissions['notifications']==true;

  Future<void> refresh({bool askPermissions=false}) async {
    if(loading) return;
    loading=true;
    error=null;
    notifyListeners();
    try {
      if(askPermissions){
        final response=await _channel.invokeMapMethod<String,bool>('requestPermissions');
        if(response!=null)permissions=Map<String,bool>.from(response);
      }else{
        final response=await _channel.invokeMapMethod<String,bool>('permissions');
        if(response!=null)permissions=Map<String,bool>.from(response);
      }
      if(audioGranted){
        final list=await _channel.invokeMethod<List<dynamic>>('scan',{'kind':'audio'});
        audio..clear()..addAll((list??[]).whereType<Map>().map(
          (v)=>PhoneMedia.fromJson(Map<String,dynamic>.from(v))));
      }else{audio.clear();}
      if(videoGranted){
        final list=await _channel.invokeMethod<List<dynamic>>('scan',{'kind':'video'});
        videos..clear()..addAll((list??[]).whereType<Map>().map(
          (v)=>PhoneMedia.fromJson(Map<String,dynamic>.from(v))));
      }else{videos.clear();}
    }on PlatformException catch(e){
      error='تعذّر قراءة وسائط الهاتف: ${e.message ?? e.code}';
    }catch(e){
      error='تعذّر فهرسة ملفات الهاتف: $e';
    }finally{
      loading=false;
      notifyListeners();
    }
  }

  /// For sources that require a private file path for background playback.
  /// One track at a time, not bulk-copying the user's whole phone library.
  static Future<String> playableAudio(String uri) async {
    if(!uri.startsWith('content://')) return uri;
    final file=await _channel.invokeMethod<String>('audioCache',{'uri':uri});
    if(file==null||file.isEmpty)throw StateError('لا يمكن قراءة الملف');
    return file;
  }
}

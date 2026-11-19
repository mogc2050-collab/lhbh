import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class PhoneMedia {
  const PhoneMedia({required this.id,required this.uri,required this.name,
    required this.kind,required this.size,required this.duration,
    required this.date,required this.mime,
    this.artist='',this.album='',this.albumId=0,this.folder=''});
  final int id,size,duration,date,albumId;
  final String uri,name,kind,mime,artist,album,folder;
  bool get audio=>kind=='audio';
  bool get video=>kind=='video';
  bool get image=>kind=='image';
  factory PhoneMedia.fromJson(Map<String,dynamic> j)=>PhoneMedia(
    id:(j['id'] as num?)?.toInt()??0,
    uri:j['uri'] as String? ?? '',
    name:j['name'] as String? ?? 'ملف',
    kind:j['kind'] as String? ?? 'audio',
    size:(j['size'] as num?)?.toInt()??0,
    duration:(j['duration'] as num?)?.toInt()??0,
    date:(j['date'] as num?)?.toInt()??0,
    mime:j['mime'] as String? ?? '',
    artist:j['artist'] as String? ?? '',
    album:j['album'] as String? ?? '',
    albumId:(j['albumId'] as num?)?.toInt()??0,
    folder:j['folder'] as String? ?? '');
}

class PhoneLibrary extends ChangeNotifier {
  PhoneLibrary(){
    _events=const EventChannel('ibetoo.media/changes')
      .receiveBroadcastStream().listen((_) {
        _debounce?.cancel();
        _debounce=Timer(const Duration(milliseconds:1200),refresh);
      },onError:(Object e){debugPrint('Media index watcher: $e');});
  }
  StreamSubscription<dynamic>? _events;
  Timer? _debounce;
  static const channel=MethodChannel('ibetoo.media/device');
  final List<PhoneMedia> audio=[],videos=[],images=[];
  final Map<String,Uint8List> thumbs={};
  Map<String,bool> permissions={'audio':false,'video':false,
    'image':false,'notifications':false};
  bool loading=false;
  String? error;
  bool get audioGranted=>permissions['audio']==true;
  bool get videoGranted=>permissions['video']==true;
  bool get imageGranted=>permissions['image']==true;
  bool get notificationsGranted=>permissions['notifications']==true;
  List<PhoneMedia> get all=>[...audio,...videos,...images];
  List<PhoneMedia> get playable=>[...audio,...videos];
  Map<String,List<PhoneMedia>> get folders {
    final out=<String,List<PhoneMedia>>{};
    for(final e in all){
      out.putIfAbsent(e.folder.isEmpty?'بدون مجلد':e.folder,()=>[]).add(e);
    }
    return out;
  }
  Map<String,List<PhoneMedia>> get artists {
    final out=<String,List<PhoneMedia>>{};
    for(final e in audio){
      out.putIfAbsent(e.artist.isEmpty?'فنان غير معروف':e.artist,()=>[]).add(e);
    }
    return out;
  }
  Map<String,List<PhoneMedia>> get albums {
    final out=<String,List<PhoneMedia>>{};
    for(final e in audio){
      out.putIfAbsent(e.album.isEmpty?'ألبوم غير معروف':e.album,()=>[]).add(e);
    }
    return out;
  }
  Future<void> refresh({bool askPermissions=false}) async{
    if(loading)return;
    loading=true;error=null;notifyListeners();
    try{
      final state=await channel.invokeMapMethod<String,bool>(
        askPermissions?'requestPermissions':'permissions');
      if(state!=null)permissions=Map<String,bool>.from(state);
      for(final entry in <(String,List<PhoneMedia>,bool)>[
        ('audio',audio,audioGranted),('video',videos,videoGranted),
        ('image',images,imageGranted),
      ]){
        entry.$2.clear();
        if(!entry.$3)continue;
        try{
          final rows=await channel.invokeMethod<List<dynamic>>(
            'scan',{'kind':entry.$1});
          entry.$2.addAll((rows??[]).whereType<Map>().map((x)=>
            PhoneMedia.fromJson(Map<String,dynamic>.from(x))));
        }catch(e){
          error='بعض الوسائط تعذّر فهرستها: $e';
        }
      }
    }on PlatformException catch(e){error=e.message??e.code;}
    catch(e){error='فشل فهرسة الوسائط: $e';}
    finally{loading=false;notifyListeners();}
  }
  Future<Uint8List?> artwork(String uri) async {
    if(thumbs.containsKey(uri))return thumbs[uri];
    try{
      final result=await channel.invokeMethod<Uint8List>(
        'thumbnail',{'uri':uri});
      if(result!=null&&result.isNotEmpty){
        if(thumbs.length>120)thumbs.remove(thumbs.keys.first);
        thumbs[uri]=result;
        notifyListeners();
        return result;
      }
    }catch(_){}
    return null;
  }
  Future<Uint8List?> imagePreview(String uri) async{
    return channel.invokeMethod<Uint8List>('imagePreview',{'uri':uri});
  }
  Future<List<List<String>>> findDuplicates() async{
    final data=await channel.invokeMethod<List<dynamic>>('duplicates');
    return (data??[]).whereType<Map>().map((e)=>
      (e['uris'] as List? ?? []).whereType<String>().toList()
    ).where((e)=>e.length>1).toList();
  }
  PhoneMedia? byUri(String uri){
    for(final m in all){if(m.uri==uri)return m;}
    return null;
  }
  @override void dispose(){
    _debounce?.cancel();
    _events?.cancel();
    super.dispose();
  }
  static Future<String> playableAudio(String uri) async{
    if(!uri.startsWith('content://'))return uri;
    final file=await channel.invokeMethod<String>('audioCache',{'uri':uri});
    if(file==null||file.isEmpty)throw StateError('الملف غير متاح');
    return file;
  }
}

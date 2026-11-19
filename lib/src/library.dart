import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'media_utils.dart';

class SavedMedia {
  const SavedMedia({
    required this.path,required this.name,required this.createdAt,
  });
  final String path;
  final String name;
  final int createdAt;
  Map<String,dynamic> toJson() => {
    'path':path,'name':name,'createdAt':createdAt,
  };
  factory SavedMedia.fromJson(Map<String,dynamic> m) => SavedMedia(
    path:m['path'] as String? ?? '',
    name:m['name'] as String? ?? '',
    createdAt:(m['createdAt'] as num?)?.toInt() ?? 0,
  );
}

class DownloadRecord {
  DownloadRecord({
    required this.id,required this.url,required this.title,
    required this.createdAt,
    this.status='waiting',this.downloaded=0,this.total=-1,
  });
  final int id;
  final String url;
  final String title;
  final int createdAt;
  String status;
  int downloaded;
  int total;
  double? get progress => total > 0
      ? (downloaded / total).clamp(0.0,1.0) : null;
  Map<String,dynamic> toJson() => {
    'id':id,'url':url,'title':title,'createdAt':createdAt,
  };
  factory DownloadRecord.fromJson(Map<String,dynamic> m) => DownloadRecord(
    id:(m['id'] as num).toInt(),
    url:m['url'] as String? ?? '',
    title:m['title'] as String? ?? '',
    createdAt:(m['createdAt'] as num?)?.toInt() ?? 0,
  );
}

class DownloadBridge {
  static const MethodChannel _bridge =
      MethodChannel('ibetoo.media/downloads');

  static Future<int> enqueue({
    required Uri url,required String filename,String? userAgent,
  }) async {
    if (!MediaUtils.canDownload(url)) {
      throw const FormatException('هذا الرابط غير مؤهل للتنزيل.');
    }
    final result=await _bridge.invokeMethod<int>('enqueue',{
      'url':url.toString(),'filename':filename,'userAgent':userAgent??'',
    });
    if (result==null || result<1) throw StateError('لم يبدأ التنزيل');
    return result;
  }

  static Future<List<Map<String,dynamic>>> query(List<int> ids) async {
    if (ids.isEmpty) return [];
    final data=await _bridge.invokeMethod<List<dynamic>>(
      'query',{'ids':ids});
    return (data??[]).whereType<Map>().map((m)=>
        Map<String,dynamic>.from(m)).toList();
  }

  static Future<String> copyToCache(int id) async {
    final path=await _bridge.invokeMethod<String>(
      'copyToCache',{'id':id});
    if (path==null || path.isEmpty) throw StateError('الملف غير متاح');
    return path;
  }
  static Future<void> open(int id) =>
      _bridge.invokeMethod<void>('open',{'id':id});
  static Future<void> share(int id) =>
      _bridge.invokeMethod<void>('share',{'id':id});
  static Future<void> delete(int id) =>
      _bridge.invokeMethod<void>('delete',{'id':id});
  static Future<void> showSystemDownloads() =>
      _bridge.invokeMethod<void>('showDownloads');
  static Future<void> shareLocal(String path,String name) =>
      _bridge.invokeMethod<void>('shareLocal',{'path':path,'name':name});
  static Future<bool> enterPip() async =>
      await _bridge.invokeMethod<bool>('pip') ?? false;
}

class MediaLibrary extends ChangeNotifier {
  MediaLibrary._();
  static const key='ibetoo_media_library_v1';
  static Future<MediaLibrary> load() async {
    final state=MediaLibrary._();
    try {
      final prefs=await SharedPreferences.getInstance();
      final raw=prefs.getString(key);
      if(raw!=null){
        final json=jsonDecode(raw) as Map<String,dynamic>;
        state.darkMode=json['darkMode']==true;
        state.bookmarks.addAll((json['bookmarks'] as List? ?? [])
            .whereType<String>());
        state.history.addAll((json['history'] as List? ?? [])
            .whereType<String>());
        for(final item in (json['downloads'] as List? ?? [])){
          if(item is Map) state.downloads.add(DownloadRecord.fromJson(
              Map<String,dynamic>.from(item)));
        }
        for(final item in (json['files'] as List? ?? [])){
          if(item is Map) state.files.add(SavedMedia.fromJson(
              Map<String,dynamic>.from(item)));
        }
      }
    } catch(e) {
      debugPrint('Saved library could not be restored: $e');
    }
    return state;
  }

  bool darkMode=false;
  final List<String> bookmarks=[];
  final List<String> history=[];
  final List<DownloadRecord> downloads=[];
  final List<SavedMedia> files=[];
  Timer? _saveLater;

  void _notify() {
    notifyListeners();
    _saveLater?.cancel();
    _saveLater=Timer(const Duration(milliseconds:250),save);
  }

  Future<void> save() async {
    try {
      final prefs=await SharedPreferences.getInstance();
      await prefs.setString(key,jsonEncode({
        'darkMode':darkMode,'bookmarks':bookmarks,
        'history':history.take(180).toList(),
        'downloads':downloads.map((m)=>m.toJson()).toList(),
        'files':files.map((m)=>m.toJson()).toList(),
      }));
    } catch(e) { debugPrint('Unable to save library: $e'); }
  }
  void setTheme(bool dark) {darkMode=dark;_notify();}
  bool starred(String url)=>bookmarks.contains(url);
  void toggleBookmark(String url) {
    if(bookmarks.contains(url)){bookmarks.remove(url);}
    else {bookmarks.insert(0,url);}
    _notify();
  }
  void visited(String url) {
    if(url.isEmpty || !url.startsWith('http')) return;
    history.remove(url);history.insert(0,url);
    if(history.length>180)history.removeLast();
    _notify();
  }
  void clearHistory() {history.clear();_notify();}

  Future<DownloadRecord> addDownload(
      String text,{String? filename,String? userAgent}) async {
    final url=Uri.parse(text);
    if(!MediaUtils.canDownload(url)) throw FormatException(
        'الرابط غير مدعوم للتنزيل. اختر ملفًا مباشرًا مسموحًا به.');
    final title=filename ?? MediaUtils.fileTitle(url);
    final id=await DownloadBridge.enqueue(
        url:url,filename:title,userAgent:userAgent);
    final item=DownloadRecord(
      id:id,url:text,title:title,createdAt:DateTime.now().millisecondsSinceEpoch,
    );
    downloads.insert(0,item);
    _notify();
    return item;
  }

  Future<void> refreshDownloads() async {
    if(downloads.isEmpty)return;
    try {
      final data=await DownloadBridge.query(
          downloads.map((e)=>e.id).toList());
      for(final item in data){
        final id=(item['id'] as num?)?.toInt();
        for(final record in downloads.where((x)=>x.id==id)){
          record.status=item['status'] as String? ?? 'unknown';
          record.downloaded=(item['downloaded'] as num?)?.toInt()??0;
          record.total=(item['total'] as num?)?.toInt()??-1;
        }
      }
      notifyListeners();
    } catch(e){debugPrint('Download status unavailable: $e');}
  }

  Future<void> removeDownload(DownloadRecord item) async {
    await DownloadBridge.delete(item.id);
    downloads.removeWhere((e)=>e.id==item.id);
    _notify();
  }

  Future<SavedMedia> importFile(String source,String displayName) async {
    final original=File(source);
    if(!await original.exists()) throw StateError('الملف غير متاح');
    final directory=Directory(
      (await getApplicationDocumentsDirectory()).path+'/library');
    await directory.create(recursive:true);
    final safe=displayName.replaceAll(RegExp(r'[^\w.\-\u0600-\u06FF ]'),'_');
    final id=DateTime.now().microsecondsSinceEpoch;
    final destination=File('${directory.path}/${id}_${safe}');
    await original.copy(destination.path);
    final entry=SavedMedia(path:destination.path,
      name:displayName,createdAt:DateTime.now().millisecondsSinceEpoch);
    files.insert(0,entry);
    _notify();
    return entry;
  }

  Future<void> removeFile(SavedMedia file) async {
    final target=File(file.path);
    if(await target.exists())await target.delete();
    files.removeWhere((m)=>m.path==file.path);
    _notify();
  }

  @override
  void dispose() {
    _saveLater?.cancel();
    super.dispose();
  }
}

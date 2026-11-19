import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SavedMedia {
  const SavedMedia({required this.path,required this.name,required this.createdAt,
    this.folder='مستوردة'});
  final String path,name,folder;
  final int createdAt;
  Map<String,dynamic> toJson()=>{'path':path,'name':name,
    'folder':folder,'createdAt':createdAt};
  factory SavedMedia.fromJson(Map<String,dynamic> j)=>SavedMedia(
    path:j['path'] as String? ?? '',
    name:j['name'] as String? ?? '',
    folder:j['folder'] as String? ?? 'مستوردة',
    createdAt:(j['createdAt'] as num?)?.toInt()??0);
}

class Playlist {
  Playlist({required this.name,List<String>? items}):items=items??[];
  String name;
  final List<String> items;
  Map<String,dynamic> toJson()=>{'name':name,'items':items};
  factory Playlist.fromJson(Map<String,dynamic> j)=>Playlist(
    name:j['name'] as String? ?? 'قائمة',
    items:(j['items'] as List? ?? []).whereType<String>().toList());
}

/// The library is deliberately offline-first. No downloader or web scraping.
class MediaLibrary extends ChangeNotifier {
  MediaLibrary._();
  static const key='ibetoo_library_v3';
  static Future<MediaLibrary> load() async {
    final s=MediaLibrary._();
    try {
      final prefs=await SharedPreferences.getInstance();
      var raw=prefs.getString(key);
      raw??=prefs.getString('ibetoo_media_library_v1');
      if(raw!=null) {
        final j=jsonDecode(raw) as Map<String,dynamic>;
        s.darkMode=j['darkMode']==true;
        s.privateMode=false; // Private browsing never survives a restart.
        s.blockTrackers=j['blockTrackers']!=false;
        s.enhancedDark=j['enhancedDark']==true;
        s.searchEngine=j['searchEngine'] as String? ?? 'Google';
        s.appLock=j['appLock']==true;
        s.bookmarks.addAll((j['bookmarks'] as List? ?? []).whereType<String>());
        s.history.addAll((j['history'] as List? ?? []).whereType<String>());
        for(final e in (j['files'] as List? ?? [])){
          if(e is Map)s.files.add(SavedMedia.fromJson(Map<String,dynamic>.from(e)));
        }
        for(final e in (j['playlists'] as List? ?? [])){
          if(e is Map)s.playlists.add(Playlist.fromJson(Map<String,dynamic>.from(e)));
        }
        s.favorites.addAll((j['favorites'] as List? ?? []).whereType<String>());
        s.playCount.addAll(_intMap(j['playCount']));
        s.playedAt.addAll(_intMap(j['playedAt']));
        s.resume.addAll(_intMap(j['resume']));
        s.customTitles.addAll(_stringMap(j['customTitles']));
        s.folderLabels.addAll(_stringMap(j['folderLabels']));
        s.musicSpeed=(j['musicSpeed'] as num?)?.toDouble()??1.0;
        s.videoSpeed=(j['videoSpeed'] as num?)?.toDouble()??1.0;
        s.subtitleSize=(j['subtitleSize'] as num?)?.toDouble()??18.0;
        s.eqPreset=j['eqPreset'] as String? ?? 'طبيعي';
        s.sleepMinutes=(j['sleepMinutes'] as num?)?.toInt()??0;
      }
    }catch(e){debugPrint('Could not restore library settings: $e');}
    return s;
  }
  static Map<String,int> _intMap(dynamic data) {
    if(data is! Map)return {};
    return {for(final e in data.entries)
      if(e.key is String && e.value is num)
        e.key as String:(e.value as num).toInt()};
  }
  static Map<String,String> _stringMap(dynamic data) {
    if(data is! Map)return {};
    return {for(final e in data.entries)
      if(e.key is String && e.value is String)
        e.key as String:e.value as String};
  }

  bool darkMode=false,privateMode=false,blockTrackers=true,
    enhancedDark=false,appLock=false;
  String searchEngine='Google',eqPreset='طبيعي';
  double musicSpeed=1,videoSpeed=1,subtitleSize=18;
  int sleepMinutes=0;
  final List<String> bookmarks=[],history=[];
  final List<SavedMedia> files=[];
  final List<Playlist> playlists=[];
  final Set<String> favorites={};
  final Map<String,int> playCount={},playedAt={},resume={};
  final Map<String,String> customTitles={},folderLabels={};
  Timer? _saveTimer;

  void changed(){
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer=Timer(const Duration(milliseconds:350),save);
  }
  void setTheme(bool dark){darkMode=dark;changed();}
  void setPrivateMode(bool enabled){privateMode=enabled;changed();}
  void setTrackerBlock(bool enabled){blockTrackers=enabled;changed();}
  void setEnhancedDark(bool enabled){enhancedDark=enabled;changed();}
  void setAppLock(bool enabled){appLock=enabled;changed();}
  void setSearchEngine(String engine){searchEngine=engine;changed();}
  void setMusicSpeed(double speed){musicSpeed=speed.clamp(.5,3).toDouble();changed();}
  void setVideoSpeed(double speed){videoSpeed=speed.clamp(.5,3).toDouble();changed();}
  void setEqualizer(String preset){eqPreset=preset;changed();}
  void setSubtitleSize(double size){subtitleSize=size.clamp(12,36).toDouble();changed();}
  void setSleepMinutes(int minutes){sleepMinutes=minutes;changed();}
  bool starred(String url)=>bookmarks.contains(url);
  void toggleBookmark(String url){
    if(bookmarks.contains(url)){bookmarks.remove(url);}
    else{bookmarks.insert(0,url);}
    changed();
  }
  void visited(String url){
    if(privateMode||!url.startsWith('https://'))return;
    history.remove(url);history.insert(0,url);
    if(history.length>200)history.removeLast();
    changed();
  }
  void clearHistory(){history.clear();changed();}

  bool isFavorite(String uri)=>favorites.contains(uri);
  void toggleFavorite(String uri){
    if(!favorites.add(uri))favorites.remove(uri);
    changed();
  }
  void recordPlay(String uri){
    playCount.update(uri,(v)=>v+1,ifAbsent:()=>1);
    playedAt[uri]=DateTime.now().millisecondsSinceEpoch;
    changed();
  }
  void saveResume(String uri,Duration pos){
    if(pos.inSeconds<1)return;
    if(resume[uri]==pos.inMilliseconds)return;
    resume[uri]=pos.inMilliseconds;
    changed();
  }
  Duration positionFor(String uri)=>Duration(milliseconds:resume[uri]??0);
  List<String> mostPlayed({int limit=30}){
    final items=playCount.keys.toList()
      ..sort((a,b)=>(playCount[b]??0).compareTo(playCount[a]??0));
    return items.take(limit).toList();
  }
  void setTitle(String uri,String title){
    customTitles[uri]=title.trim();changed();
  }

  Playlist createPlaylist(String name){
    final clean=name.trim();
    if(clean.isEmpty)throw ArgumentError('اسم القائمة مطلوب');
    if(playlists.any((e)=>e.name==clean))throw StateError('الاسم موجود');
    final p=Playlist(name:clean);
    playlists.add(p);changed();return p;
  }
  void renamePlaylist(Playlist p,String name){
    if(name.trim().isEmpty)return;
    p.name=name.trim();changed();
  }
  void deletePlaylist(Playlist p){playlists.remove(p);changed();}
  void appendToPlaylist(Playlist p,String uri){
    if(!p.items.contains(uri))p.items.add(uri);
    changed();
  }
  void removeFromPlaylist(Playlist p,String uri){
    p.items.remove(uri);changed();
  }
  void reorder(Playlist p,int oldIndex,int newIndex){
    if(oldIndex<0||oldIndex>=p.items.length)return;
    if(newIndex>oldIndex)newIndex--;
    newIndex=newIndex.clamp(0,p.items.length-1).toInt();
    final v=p.items.removeAt(oldIndex);
    p.items.insert(newIndex,v);changed();
  }

  Future<SavedMedia> importFile(String source,String displayName) async {
    final file=File(source);
    if(!await file.exists())throw StateError('الملف غير متاح');
    final dir=Directory('${(await getApplicationDocumentsDirectory()).path}/library');
    await dir.create(recursive:true);
    final safe=displayName.replaceAll(RegExp(r'[^\w.\-\u0600-\u06FF ]'),'_');
    final id=DateTime.now().microsecondsSinceEpoch;
    final copy=await file.copy('${dir.path}/${id}_$safe');
    final entry=SavedMedia(path:copy.path,name:displayName,
      createdAt:DateTime.now().millisecondsSinceEpoch);
    files.insert(0,entry);changed();return entry;
  }
  Future<void> removeFile(SavedMedia media) async {
    if(await File(media.path).exists())await File(media.path).delete();
    files.remove(media);favorites.remove(media.path);changed();
  }
  Future<void> renameImported(SavedMedia media,String newName) async {
    if(newName.trim().isEmpty)return;
    final at=files.indexOf(media);
    if(at<0)return;
    files[at]=SavedMedia(path:media.path,name:newName.trim(),
      folder:media.folder,createdAt:media.createdAt);
    changed();
  }
  void moveImported(SavedMedia media,String folder){
    final index=files.indexOf(media);
    if(index<0)return;
    files[index]=SavedMedia(path:media.path,name:media.name,
      folder:folder.trim().isEmpty?'مستوردة':folder.trim(),
      createdAt:media.createdAt);
    changed();
  }
  Future<Uint8List> exportBackup() async {
    final data=<String,dynamic>{
      'schema':3,'app':'ibetoo_media','bookmarks':bookmarks,'history':history,
      'playlists':playlists.map((v)=>v.toJson()).toList(),
      'favorites':favorites.toList(),'playCount':playCount,
      'playedAt':playedAt,'resume':resume,'customTitles':customTitles,
      'darkMode':darkMode,'blockTrackers':blockTrackers,
      'eqPreset':eqPreset,'musicSpeed':musicSpeed,'videoSpeed':videoSpeed,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(data)));
  }
  Future<void> importBackup(Uint8List bytes) async {
    if(bytes.length>2*1024*1024)throw FormatException('ملف النسخة كبير');
    final j=jsonDecode(utf8.decode(bytes));
    if(j is! Map||j['app']!='ibetoo_media')throw FormatException('نسخة غير صالحة');
    bookmarks..clear()..addAll((j['bookmarks'] as List? ?? []).whereType<String>().take(500));
    history..clear()..addAll((j['history'] as List? ?? []).whereType<String>().take(200));
    playlists.clear();
    for(final item in (j['playlists'] as List? ?? []).take(150)){
      if(item is Map)playlists.add(Playlist.fromJson(Map<String,dynamic>.from(item)));
    }
    favorites..clear()..addAll((j['favorites'] as List? ?? []).whereType<String>().take(5000));
    playCount..clear()..addAll(_intMap(j['playCount']));
    playedAt..clear()..addAll(_intMap(j['playedAt']));
    resume..clear()..addAll(_intMap(j['resume']));
    customTitles..clear()..addAll(_stringMap(j['customTitles']));
    changed();
  }
  Future<void> exportToUser() async {
    final bytes=await exportBackup();
    await FilePicker.saveFile(fileName:'ibetoo-library-backup.json',
      bytes:bytes,mimeType:'application/json');
  }
  Future<void> importFromUser() async {
    final picked=await FilePicker.pickFiles(type:FileType.custom,
      allowedExtensions:['json']);
    if(picked.isEmpty)return;
    final first=picked.first;
    if(first.path==null)throw StateError('ملف النسخة غير متاح');
    await importBackup(await File(first.path!).readAsBytes());
  }
  Future<void> save() async {
    try{
      final prefs=await SharedPreferences.getInstance();
      await prefs.setString(key,jsonEncode({
        'schema':3,'darkMode':darkMode,'bookmarks':bookmarks,
        'history':history,'files':files.map((m)=>m.toJson()).toList(),
        'playlists':playlists.map((m)=>m.toJson()).toList(),
        'favorites':favorites.toList(),'playedAt':playedAt,
        'playCount':playCount,'resume':resume,
        'customTitles':customTitles,'folderLabels':folderLabels,
        'blockTrackers':blockTrackers,'enhancedDark':enhancedDark,
        'searchEngine':searchEngine,'appLock':appLock,
        'musicSpeed':musicSpeed,'videoSpeed':videoSpeed,
        'subtitleSize':subtitleSize,'eqPreset':eqPreset,
        'sleepMinutes':sleepMinutes,
      }));
    }catch(e){debugPrint('Cannot save library: $e');}
  }
  @override
  void dispose(){_saveTimer?.cancel();super.dispose();}
}

class MediaUtils {
  static const audio=<String>{'mp3','m4a','aac','flac','ogg','wav','opus'};
  static const video=<String>{'mp4','m4v','mov','webm','mkv','avi','3gp'};
  static const image=<String>{'jpg','jpeg','png','gif','webp','heic'};
  static String extension(String name){
    final raw=Uri.tryParse(name)?.path??name;
    final file=raw.split('/').last;
    final dot=file.lastIndexOf('.');
    return dot>0?file.substring(dot+1).toLowerCase():'';
  }
  static bool isAudio(String file)=>audio.contains(extension(file));
  static bool isVideo(String file)=>video.contains(extension(file));
  static bool isImage(String file)=>image.contains(extension(file));
  static String displaySize(int bytes){
    if(bytes<0)return 'غير معروف';
    if(bytes<1024)return '$bytes B';
    if(bytes<1048576)return '${(bytes/1024).toStringAsFixed(1)} KB';
    if(bytes<1073741824)return '${(bytes/1048576).toStringAsFixed(1)} MB';
    return '${(bytes/1073741824).toStringAsFixed(1)} GB';
  }
  static Uri interpretAddress(String query){
    final input=query.trim();
    if(input.isEmpty)return Uri.parse('https://www.google.com/');
    final uri=Uri.tryParse(input);
    if(uri!=null&&uri.scheme=='https'&&uri.host.isNotEmpty)return uri;
    final domain=RegExp(r'^[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+(?:/[^\s]*)?$');
    if(domain.hasMatch(input))return Uri.parse('https://$input');
    return Uri.https('www.google.com','/search',{'q':input});
  }
  static String fileTitle(Uri uri){
    if(uri.pathSegments.isEmpty)return 'ملف';
    return Uri.decodeComponent(uri.pathSegments.last);
  }
}

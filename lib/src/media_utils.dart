/// Direct, user-authorized resources only. This is not a site video extractor.
class MediaUtils {
  static const supported = <String>{
    'mp3','m4a','aac','flac','ogg','wav','opus',
    'mp4','m4v','mov','webm','mkv','avi','3gp',
    'jpg','jpeg','png','gif','webp','heic','pdf','epub',
    'zip','7z','rar','apk','txt','csv','json','docx','xlsx','pptx'
  };
  static const audio = <String>{'mp3','m4a','aac','flac','ogg','wav','opus'};
  static const video = <String>{'mp4','m4v','mov','webm','mkv','avi','3gp'};
  static const image = <String>{'jpg','jpeg','png','gif','webp','heic'};

  static String extension(String name) {
    final raw = Uri.tryParse(name)?.path ?? name;
    final n = raw.split('/').last;
    final position = n.lastIndexOf('.');
    return position > 0 ? n.substring(position + 1).toLowerCase() : '';
  }
  static bool isDirectFile(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      supported.contains(extension(uri.path));
  static bool isAudio(String name) => audio.contains(extension(name));
  static bool isVideo(String name) => video.contains(extension(name));
  static bool isImage(String name) => image.contains(extension(name));

  static bool isYouTube(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'youtube.com' || host.endsWith('.youtube.com') ||
        host == 'youtu.be' || host.endsWith('.youtu.be') ||
        host == 'youtube-nocookie.com' || host.endsWith('.youtube-nocookie.com');
  }
  static bool canDownload(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host.isNotEmpty && !isYouTube(uri);

  static Uri interpretAddress(String query) {
    final value = query.trim();
    if (value.isEmpty) return Uri.parse('https://www.google.com/');
    final parsed = Uri.tryParse(value);
    if (parsed != null && (parsed.scheme == 'http' ||
        parsed.scheme == 'https') && parsed.host.isNotEmpty) return parsed;
    if (!value.contains(' ') && value.contains('.') &&
        !value.startsWith('.')) {
      return Uri.parse('https://$value');
    }
    return Uri.https('www.google.com','/search',{'q':value});
  }

  static String fileTitle(Uri uri) {
    final component = Uri.decodeComponent(uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last : '');
    if (component.isNotEmpty && !component.contains('/')) return component;
    return 'media-file';
  }

  static String displaySize(int bytes) {
    if (bytes < 0) return 'غير معروف';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return (bytes / 1024).toStringAsFixed(1) + ' KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return (bytes / (1024 * 1024)).toStringAsFixed(1) + ' MB';
    }
    return (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1) + ' GB';
  }

  static String? validateDownload(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || !canDownload(uri)) {
      return 'الرابط لازم يكون مباشرًا بصيغة HTTP أو HTTPS ومن مصدر يسمح بالتنزيل.';
    }
    if (uri.scheme != 'https') {
      return 'الرابط غير مشفّر؛ التطبيق يقبل HTTPS فقط.';
    }
    return null;
  }
}

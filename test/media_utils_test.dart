import 'package:flutter_test/flutter_test.dart';
import 'package:ibetoo_media/src/media_utils.dart';

void main() {
  group('Web navigation and safe direct downloads', () {
    test('searches typed text through a proper encoded Google query', () {
      final uri=MediaUtils.interpretAddress('أغنية بدون نت');
      expect(uri.host,'www.google.com');
      expect(uri.queryParameters['q'],'أغنية بدون نت');
    });
    test('understands domain and HTTPS links', () {
      expect(MediaUtils.interpretAddress('example.org').toString(),
        'https://example.org');
      expect(MediaUtils.interpretAddress('https://example.com/a').path,'/a');
    });
    test('does not turn untrusted file schemes into web navigation', () {
      final url=MediaUtils.interpretAddress('file:///etc/passwd');
      expect(url.host,'www.google.com');
    });
    test('direct file extension is detected without query interference', () {
      expect(MediaUtils.isDirectFile(
        Uri.parse('https://files.example.org/movie.mp4?token=123')),true);
      expect(MediaUtils.isDirectFile(
        Uri.parse('https://files.example.org/blog/article')),false);
    });
    test('YouTube and its short URLs are never download targets', () {
      for(final site in [
        'https://www.youtube.com/watch?v=example',
        'https://youtu.be/example',
        'https://music.youtube.com/abc',
      ]) {
        expect(MediaUtils.canDownload(Uri.parse(site)),false);
      }
    });
    test('rejects unsafe URL schemes for download manager', () {
      expect(MediaUtils.canDownload(Uri.parse('javascript:alert(1)')),false);
      expect(MediaUtils.canDownload(Uri.parse('file:///sdcard/data')),false);
      expect(MediaUtils.canDownload(
        Uri.parse('https://example.net/file.mp3')),true);
    });
    test('classifies local video, music, photos and file types', () {
      expect(MediaUtils.isAudio('TRACK.MP3'),true);
      expect(MediaUtils.isVideo('clip.mov'),true);
      expect(MediaUtils.isImage('photo.jpg'),true);
      expect(MediaUtils.isAudio('archive.zip'),false);
      expect(MediaUtils.isDirectFile(
        Uri.parse('https://example.org/document.pdf')),true);
    });
    test('extracts filename and formats sizes in Arabic interface', () {
      expect(MediaUtils.fileTitle(
        Uri.parse('https://host.example/film.webm?x=3')),'film.webm');
      expect(MediaUtils.displaySize(1050000),'1.0 MB');
      expect(MediaUtils.displaySize(-1),'غير معروف');
    });
  });
}

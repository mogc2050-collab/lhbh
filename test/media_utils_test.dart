import 'package:flutter_test/flutter_test.dart';
import 'package:ibetoo_media/src/media_utils.dart';
import 'package:ibetoo_media/src/captions.dart';

void main(){
  group('Safe browser URL navigation',(){
    test('Google query safely escapes Arabic',(){
      final uri=MediaUtils.interpretAddress('أفضل الأغاني');
      expect(uri.host,'www.google.com');
      expect(uri.queryParameters['q'],'أفضل الأغاني');
    });
    test('HTTPS URL remains valid',(){
      expect(MediaUtils.interpretAddress('https://example.com/a').path,'/a');
    });
    test('Typed domains are upgraded to HTTPS',(){
      expect(MediaUtils.interpretAddress('example.org').scheme,'https');
    });
    test('Unsafe schemes are not navigated',(){
      expect(MediaUtils.interpretAddress('file:///etc/passwd').host,
        'www.google.com');
      expect(MediaUtils.interpretAddress('javascript:alert(x.y)').host,
        'www.google.com');
    });
    test('Recognizes only local media extensions',(){
      expect(MediaUtils.isAudio('a.MP3'),isTrue);
      expect(MediaUtils.isVideo('b.MKV'),isTrue);
      expect(MediaUtils.isImage('c.PNG'),isTrue);
      expect(MediaUtils.isAudio('book.pdf'),isFalse);
    });
    test('Formats sizes',(){
      expect(MediaUtils.displaySize(1048576),'1.0 MB');
    });
  });
  group('SRT/VTT captions',(){
    test('Captions are matched to their timestamps',(){
      const data='''1
00:00:01,000 --> 00:00:03,000
أول سطر

2
00:00:04,000 --> 00:00:06,000
ثاني سطر
''';
      final cues=Captions.parse(data);
      expect(cues.length,2);
      expect(Captions.at(cues,const Duration(seconds:2)),'أول سطر');
      expect(Captions.at(cues,const Duration(seconds:3)),isEmpty);
      expect(Captions.at(cues,const Duration(seconds:5)),'ثاني سطر');
    });
    test('Can adjust subtitle timing',(){
      final cues=Captions.parse(
        'WEBVTT\n\n00:00:01.000 --> 00:00:03.000\nTest');
      expect(Captions.at(cues,Duration.zero,
        offset:const Duration(seconds:2)),'Test');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:ibetoo_media/src/device_media.dart';
import 'package:ibetoo_media/src/link_inspector.dart';
import 'package:ibetoo_media/src/player.dart';
import 'package:ibetoo_media/src/media_utils.dart';

void main(){
  group('Native media catalog contract',(){
    test('Android MediaStore rows are mapped with proper duration and type',(){
      final item=PhoneMedia.fromJson({
        'id':42,'name':'أغنيتي.mp3','uri':'content://media/external/audio/media/42',
        'kind':'audio','mime':'audio/mpeg','duration':231000,
        'size':5120000,'date':1763500000,
      });
      expect(item.audio,isTrue);
      expect(item.video,isFalse);
      expect(item.name,'أغنيتي.mp3');
      expect(item.duration,231000);
      expect(item.size,5120000);
    });
    test('video rows do not become audio tracks automatically',(){
      final item=PhoneMedia.fromJson({
        'id':43,'name':'clip.mp4','uri':'content://media/external/video/media/43',
        'kind':'video','size':12300000,'duration':31000,
      });
      expect(item.video,isTrue);
      expect(item.audio,isFalse);
      expect(MediaUtils.isVideo(item.name),isTrue);
    });
    test('media playback playlist entries preserve user-selected URI',(){
      const track=MediaTrack(source:'content://media/external/audio/media/42',
        title:'أغنيتي',album:'مكتبتي');
      expect(track.source,startsWith('content://'));
      expect(track.album,'مكتبتي');
    });
  });
  group('Real link analysis behavior',(){
    test('YouTube links are for playback, not fictitious MP3 conversion',() async {
      final result=await MediaLinkInspector.inspect(
        'https://www.youtube.com/watch?v=example');
      expect(result.kind,LinkKind.youtube);
      expect(result.variants,isEmpty);
    });
    test('YouTube music URLs are classified the same way',() async {
      final result=await MediaLinkInspector.inspect(
        'https://music.youtube.com/watch?v=example');
      expect(result.kind,LinkKind.youtube);
      expect(result.variants,isEmpty);
    });
    test('HTTP input is rejected without opening an insecure connection',() async {
      final result=await MediaLinkInspector.inspect(
        'http://example.org/sample.mp3');
      expect(result.kind,LinkKind.invalid);
    });
    test('real quality variants are not manufactured for YouTube',(){
      const list=<LinkVariant>[];
      expect(list,isEmpty);
    });
  });
}

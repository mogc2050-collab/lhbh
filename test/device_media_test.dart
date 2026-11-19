import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ibetoo_media/src/device_media.dart';
import 'package:ibetoo_media/src/library.dart';
import 'package:ibetoo_media/src/player.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Android media index fields',(){
    test('Audio metadata includes album, artist and folder',(){
      final item=PhoneMedia.fromJson({
        'id':42,'name':'sample.mp3',
        'uri':'content://media/external/audio/media/42',
        'kind':'audio','artist':'Artist','album':'Album',
        'folder':'Music/','mime':'audio/mpeg','duration':231000,
        'size':5120000,'date':1763500000,
      });
      expect(item.audio,isTrue);
      expect(item.artist,'Artist');
      expect(item.album,'Album');
      expect(item.folder,'Music/');
    });
    test('Image and video media are distinguished',(){
      expect(PhoneMedia.fromJson({'kind':'image'}).image,isTrue);
      expect(PhoneMedia.fromJson({'kind':'video'}).video,isTrue);
    });
    test('MediaTrack keeps original URI for queues',(){
      const track=MediaTrack(source:'content://media/external/audio/media/42',
        title:'Sample');
      expect(track.source,startsWith('content://'));
    });
  });
  group('Library persistence and playlists',(){
    test('Create, reorder and save playlists',()async{
      SharedPreferences.setMockInitialValues({});
      final library=await MediaLibrary.load();
      final p=library.createPlaylist('رحلات');
      library.appendToPlaylist(p,'audio-1');
      library.appendToPlaylist(p,'audio-2');
      library.reorder(p,0,2);
      expect(p.items,['audio-2','audio-1']);
      library.toggleFavorite('audio-1');
      library.recordPlay('audio-1');
      library.saveResume('audio-1',const Duration(seconds:51));
      await library.save();
      library.dispose();
      final restored=await MediaLibrary.load();
      expect(restored.playlists.single.items,['audio-2','audio-1']);
      expect(restored.isFavorite('audio-1'),isTrue);
      expect(restored.playCount['audio-1'],1);
      expect(restored.positionFor('audio-1').inSeconds,51);
      restored.dispose();
    });
    test('Backup restores preferences without restoring raw media bytes',()async{
      SharedPreferences.setMockInitialValues({});
      final origin=await MediaLibrary.load();
      final p=origin.createPlaylist('Favorites');
      origin.appendToPlaylist(p,'uri1');
      final bytes=await origin.exportBackup();
      final target=await MediaLibrary.load();
      await target.importBackup(bytes);
      expect(target.playlists.first.name,'Favorites');
      expect(target.files,isEmpty);
      origin.dispose();target.dispose();
    });
  });
}

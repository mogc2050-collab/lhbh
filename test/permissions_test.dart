import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibetoo_media/src/device_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(
    () => messenger.setMockMethodCallHandler(
      const MethodChannel('ibetoo.media/changes'),
      (_) async => null,
    ),
  );

  test('audio access never requests notifications or other media', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(PhoneLibrary.channel, (call) async {
      calls.add(call);
      if (call.method == 'scan') return <dynamic>[];
      return {
        'audio': true,
        'video': false,
        'image': false,
        'notifications': false,
      };
    });
    final phone = PhoneLibrary();
    await phone.refresh(askPermissions: true, permissionKinds: ['audio']);
    expect(calls.first.method, 'requestPermissions');
    expect(calls.first.arguments, {
      'kinds': ['audio'],
    });
    expect(calls.where((c) => c.method == 'scan').single.arguments, {
      'kind': 'audio',
    });
    expect(phone.notificationsGranted, isFalse);
    phone.dispose();
  });

  test('notification permission is separate and does not scan files', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(PhoneLibrary.channel, (call) async {
      calls.add(call);
      return {
        'notifications': true,
        'audio': false,
        'video': false,
        'image': false,
      };
    });
    final phone = PhoneLibrary();
    await phone.requestNotifications();
    expect(calls.single.arguments, {
      'kinds': ['notifications'],
    });
    expect(phone.notificationsGranted, isTrue);
    phone.dispose();
  });

  test('simultaneous artwork requests share one native call', () async {
    final response = Completer<Uint8List>();
    var calls = 0;
    messenger.setMockMethodCallHandler(PhoneLibrary.channel, (call) async {
      calls++;
      return response.future;
    });
    final phone = PhoneLibrary();
    final first = phone.artwork('content://media/1');
    final second = phone.artwork('content://media/1');
    await Future<void>.delayed(Duration.zero);
    response.complete(Uint8List.fromList([1, 2, 3]));
    await Future.wait([first, second]);
    await phone.artwork('content://media/1');
    expect(calls, 1);
    phone.dispose();
  });

  test('revoking media access removes records and cached artwork', () async {
    messenger.setMockMethodCallHandler(PhoneLibrary.channel, (call) async {
      if (call.method == 'scan') fail('Denied collections must not be scanned');
      return {
        'audio': false,
        'video': false,
        'image': false,
        'notifications': false,
      };
    });
    final phone = PhoneLibrary();
    phone.permissions = {'audio': true};
    phone.audio.add(
      const PhoneMedia(
        id: 1,
        uri: 'content://media/1',
        name: 'song',
        kind: 'audio',
        size: 1,
        duration: 1,
        date: 1,
        mime: 'audio/mpeg',
      ),
    );
    phone.thumbs['content://media/1'] = Uint8List.fromList([1]);
    await phone.refresh();
    expect(phone.audio, isEmpty);
    expect(phone.thumbs, isEmpty);
    phone.dispose();
  });
}

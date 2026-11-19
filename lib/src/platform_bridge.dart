import 'package:flutter/services.dart';

/// Android media actions and user-requested HTTPS file downloads.
class PlatformMediaBridge {
  static const channel=MethodChannel('ibetoo.media/platform');
  static Future<int> downloadUrl(String url) async =>
    await channel.invokeMethod<int>('downloadUrl',{'url':url})??-1;
  static Future<void> openDownloads() =>
    channel.invokeMethod<void>('openDownloads');
  static Future<bool> enterPip() async=>
    await channel.invokeMethod<bool>('pip')??false;
  static Future<void> shareLocal(String path,String name)=>
    channel.invokeMethod<void>('shareLocal',{'path':path,'name':name});
}

import 'package:flutter/services.dart';

/// Only Android media UI actions. Intentionally has no download methods.
class PlatformMediaBridge {
  static const channel=MethodChannel('ibetoo.media/platform');
  static Future<bool> enterPip() async=>
    await channel.invokeMethod<bool>('pip')??false;
  static Future<void> shareLocal(String path,String name)=>
    channel.invokeMethod<void>('shareLocal',{'path':path,'name':name});
}

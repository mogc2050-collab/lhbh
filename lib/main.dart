import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'src/library.dart';
import 'src/player.dart';
import 'src/shell.dart';
import 'src/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await JustAudioBackground.init(
    androidNotificationChannelId:'com.ibetoo.media.audio',
    androidNotificationChannelName:'iBetoo Media - مشغّل الصوت',
    androidNotificationOngoing:true,
  );
  final library=await MediaLibrary.load();
  runApp(IbetooMediaApp(library:library));
}

class IbetooMediaApp extends StatefulWidget {
  const IbetooMediaApp({super.key,required this.library});
  final MediaLibrary library;
  @override
  State<IbetooMediaApp> createState()=>_IbetooMediaAppState();
}

class _IbetooMediaAppState extends State<IbetooMediaApp> {
  late final BackgroundMusic music=BackgroundMusic(library:widget.library);

  @override
  void dispose() {
    music.dispose();
    widget.library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context)=>AnimatedBuilder(
    animation:widget.library,
    builder:(context,_)=>MaterialApp(
      title:'iBetoo Media',
      debugShowCheckedModeBanner:false,
      theme:mediaTheme(Brightness.light),
      darkTheme:mediaTheme(Brightness.dark),
      themeMode:widget.library.darkMode?ThemeMode.dark:ThemeMode.light,
      locale:const Locale('ar','EG'),
      builder:(context,child)=>Directionality(
        textDirection:TextDirection.rtl,child:child!),
      home:MediaShell(library:widget.library,music:music),
    ),
  );
}

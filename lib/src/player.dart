import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'library.dart';
import 'media_utils.dart';
import 'theme.dart';

/// Single global player keeps playing when user changes screens or locks phone.
class BackgroundMusic extends ChangeNotifier {
  final player=AudioPlayer();
  String? currentTitle;
  String? currentPath;

  Future<void> open(String path,{String? title}) async {
    final name=title ?? path.split('/').last;
    currentTitle=name;
    currentPath=path;
    notifyListeners();
    await player.setAudioSource(AudioSource.uri(
      Uri.file(path),
      tag:MediaItem(id:path,title:name,album:'iBetoo Media'),
    ));
    unawaited(player.play());
  }

  Future<void> toggle() async {
    if(player.playing) {await player.pause();}
    else {unawaited(player.play());}
    notifyListeners();
  }

  @override
  void dispose(){unawaited(player.dispose());super.dispose();}
}

class MiniMusic extends StatelessWidget {
  const MiniMusic({super.key,required this.music,required this.open});
  final BackgroundMusic music;
  final VoidCallback open;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation:music,builder:(ctx,_) {
      if(music.currentTitle==null)return const SizedBox.shrink();
      return Material(
        color:Theme.of(ctx).colorScheme.surface,
        child:Container(
          padding:const EdgeInsets.symmetric(horizontal:12,vertical:5),
          decoration:BoxDecoration(
            border:Border(top:BorderSide(
              color:Theme.of(ctx).dividerColor))),
          child:Row(children:[
            Container(width:35,height:35,alignment:Alignment.center,
              decoration:BoxDecoration(
                color:MediaPalette.orange.withValues(alpha:.12),
                borderRadius:BorderRadius.circular(10)),
              child:const Icon(Icons.music_note,
                color:MediaPalette.orange,size:22)),
            const SizedBox(width:10),
            Expanded(child:InkWell(onTap:open,
              child:Text(music.currentTitle!,maxLines:1,
                overflow:TextOverflow.ellipsis,
                style:const TextStyle(fontWeight:FontWeight.w700)))),
            StreamBuilder<PlayerState>(
              stream:music.player.playerStateStream,
              builder:(ctx,snapshot)=>IconButton(
                tooltip:'تشغيل وإيقاف',
                onPressed:music.toggle,
                icon:Icon(snapshot.data?.playing==true ?
                  Icons.pause_rounded:Icons.play_arrow_rounded),
              )),
          ]),
        ),
      );
    },
  );
}

class AudioDetail extends StatelessWidget {
  const AudioDetail({super.key,required this.music});
  final BackgroundMusic music;

  String stamp(Duration v){
    final m=v.inMinutes.remainder(60).toString().padLeft(2,'0');
    final s=v.inSeconds.remainder(60).toString().padLeft(2,'0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('مشغّل الصوت')),
    body:Padding(
      padding:const EdgeInsets.all(24),
      child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        Expanded(child:Center(child:Container(
          width:230,height:230,
          decoration:BoxDecoration(
            borderRadius:BorderRadius.circular(36),
            gradient:const LinearGradient(
              colors:[Color(0xffff7a30),Color(0xff9d3414)],
              begin:Alignment.topLeft,end:Alignment.bottomRight)),
          child:const Icon(Icons.graphic_eq_rounded,
            size:110,color:Colors.white)))),
        Text(music.currentTitle??'لا يوجد ملف قيد التشغيل',
          textAlign:TextAlign.center,
          style:Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight:FontWeight.w900)),
        const SizedBox(height:25),
        StreamBuilder<Duration>(
          stream:music.player.positionStream,
          builder:(ctx,snapshot) {
            final pos=snapshot.data??Duration.zero;
            final total=music.player.duration??Duration.zero;
            final maxMs=total.inMilliseconds<=0?1:total.inMilliseconds;
            return Column(children:[
              Slider(
                value:pos.inMilliseconds.clamp(0,maxMs).toDouble(),
                max:maxMs.toDouble(),onChanged:(n){
                  music.player.seek(Duration(milliseconds:n.toInt()));
                }),
              Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
                Text(stamp(pos)),Text(stamp(total)),
              ]),
            ]);
          }),
        const SizedBox(height:20),
        StreamBuilder<PlayerState>(
          stream:music.player.playerStateStream,
          builder:(ctx,snapshot)=>IconButton.filled(
            style:IconButton.styleFrom(
              minimumSize:const Size(70,70),
              backgroundColor:MediaPalette.orange),
            icon:Icon(snapshot.data?.playing==true ?
              Icons.pause_rounded:Icons.play_arrow_rounded,size:35),
            onPressed:music.toggle,
          )),
        const SizedBox(height:24),
        const Text('التشغيل يستمر في الخلفية مع أزرار من شاشة القفل.',
          textAlign:TextAlign.center),
      ]),
    ),
  );
}

class VideoDetail extends StatefulWidget {
  const VideoDetail({super.key,required this.source,
    required this.title,this.network=false});
  final String source;
  final String title;
  final bool network;
  @override
  State<VideoDetail> createState()=>_VideoDetailState();
}

class _VideoDetailState extends State<VideoDetail> {
  VideoPlayerController? controller;
  Object? failure;
  bool loading=true;

  @override
  void initState(){
    super.initState();
    _init();
  }
  Future<void> _init() async {
    VideoPlayerController? video;
    try {
      video=widget.network ?
        VideoPlayerController.networkUrl(Uri.parse(widget.source)) :
        VideoPlayerController.file(File(widget.source));
      await video.initialize();
      if(!mounted){await video.dispose();return;}
      controller=video;
      await video.setLooping(false);
      unawaited(video.play());
      setState(()=>loading=false);
    } catch(e) {
      if(video!=null){await video.dispose();}
      if(mounted)setState((){
        failure=e;
        loading=false;
      });
    }
  }
  @override
  void dispose(){controller?.dispose();super.dispose();}

  @override
  Widget build(BuildContext context) {
    final video=controller;
    return Scaffold(
      appBar:AppBar(title:Text(widget.title,maxLines:1),
        actions:[
          if(video!=null)IconButton(
            tooltip:'صورة داخل صورة',
            icon:const Icon(Icons.picture_in_picture_alt_rounded),
            onPressed:() async {
              try {
                final ok=await DownloadBridge.enterPip();
                if(!ok && context.mounted){
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content:Text('الصورة داخل صورة غير متاحة على هذا الجهاز.')));
                }
              } catch(e){
                if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content:Text('تعذر تفعيل الصورة المصغّرة: $e')));
              }
            }),
        ]),
      body:loading ? const Center(child:CircularProgressIndicator()) :
        failure!=null ?
        Center(child:Padding(padding:const EdgeInsets.all(22),
          child:Text('تعذر تشغيل هذا الترميز أو الملف: $failure',
            textAlign:TextAlign.center))) :
        Column(children:[
          Expanded(child:Center(child:AspectRatio(
            aspectRatio:video!.value.aspectRatio,
            child:VideoPlayer(video)))),
          Padding(padding:const EdgeInsets.all(12),child:Column(children:[
            AnimatedBuilder(animation:video,builder:(context,_) {
              final dur=video.value.duration.inMilliseconds;
              final pos=video.value.position.inMilliseconds;
              return Slider(
                max:dur<=0?1:dur.toDouble(),
                value:pos.clamp(0,dur<=0?1:dur).toDouble(),
                onChanged:(n)=>video.seekTo(Duration(milliseconds:n.toInt())));
            }),
            Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
              IconButton(onPressed:()=>video.seekTo(
                video.value.position-const Duration(seconds:10)),
                icon:const Icon(Icons.replay_10)),
              IconButton.filled(onPressed:(){
                if(video.value.isPlaying){video.pause();}
                else{video.play();}
                setState((){});
              },icon:Icon(video.value.isPlaying ?
                Icons.pause:Icons.play_arrow)),
              IconButton(onPressed:()=>video.seekTo(
                video.value.position+const Duration(seconds:10)),
                icon:const Icon(Icons.forward_10)),
            ]),
          ])),
        ]),
    );
  }
}

class ImageDetail extends StatelessWidget {
  const ImageDetail({super.key,required this.path,required this.title});
  final String path,title;
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(title)),
    body:Center(child:InteractiveViewer(
      minScale:.5,maxScale:5,
      child:Image.file(File(path),fit:BoxFit.contain,
        errorBuilder:(_,error,stack)=>Text('تعذر فتح الصورة: $error')),
    )),
  );
}

Future<void> openMedia(BuildContext context,BackgroundMusic music,
  String path,String title) async {
  if(MediaUtils.isAudio(title)){
    try {
      await music.open(path,title:title);
      if(context.mounted)Navigator.of(context).push(MaterialPageRoute(
        builder:(_)=>AudioDetail(music:music)));
    } catch(e){
      if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('فشل تشغيل الصوت: $e')));
    }
  }else if(MediaUtils.isVideo(title)){
    if(context.mounted)Navigator.of(context).push(MaterialPageRoute(
      builder:(_)=>VideoDetail(source:path,title:title)));
  }else if(MediaUtils.isImage(title)){
    if(context.mounted)Navigator.of(context).push(MaterialPageRoute(
      builder:(_)=>ImageDetail(path:path,title:title)));
  }else{
    if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content:Text('الملف ليس فيديو أو صوتًا أو صورة مدعومة. افتحه بتطبيق مناسب.')));
  }
}

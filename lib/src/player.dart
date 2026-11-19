import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'device_media.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'library.dart';
import 'media_utils.dart';
import 'theme.dart';

/// A physical file or a user-selected phone media URI, not a stream extractor.
class MediaTrack {
  const MediaTrack({required this.source,required this.title,this.album='من هاتفي'});
  final String source,title,album;
}

class BackgroundMusic extends ChangeNotifier {
  final player=AudioPlayer();
  String? currentTitle;
  String? currentPath;
  List<MediaTrack> queue=[];
  int queueIndex=0;
  bool shuffle=false;
  bool repeatOne=false;
  bool _changing=false;
  late final StreamSubscription<PlayerState> _completed;
  final _random=Random();

  BackgroundMusic(){
    _completed=player.playerStateStream.listen((state){
      if(state.processingState==ProcessingState.completed && !_changing){
        unawaited(next());
      }
      notifyListeners();
    });
  }

  Future<void> open(String path,{String? title}) async {
    await playQueue([MediaTrack(source:path,
      title:title??path.split('/').last)],0);
  }
  Future<void> playQueue(List<MediaTrack> items,int startIndex) async {
    if(items.isEmpty)return;
    queue=List<MediaTrack>.from(items);
    await _openIndex(startIndex.clamp(0,items.length-1).toInt());
  }

  Future<void> _openIndex(int index) async {
    if(index<0||index>=queue.length)return;
    _changing=true;
    try{
      final track=queue[index];
      await player.stop();
      final original=track.source;
      Uri sourceUri(String source)=>
        source.startsWith('content://')||source.startsWith('https://')?
          Uri.parse(source):Uri.file(source);
      AudioSource sourceFor(String source)=>AudioSource.uri(
        sourceUri(source),
        tag:MediaItem(id:original,title:track.title,album:track.album));
      try {
        // MediaStore content URI playback may work directly with ExoPlayer.
        // Avoid duplicating large files if it does.
        await player.setAudioSource(sourceFor(original));
      }catch(e) {
        if(!original.startsWith('content://'))rethrow;
        // SAF/content URI support differs between player implementations.
        // Only then create an app-owned temporary copy of this track.
        final copied=await PhoneLibrary.playableAudio(original);
        await player.setAudioSource(sourceFor(copied));
      }
      queueIndex=index;
      currentTitle=track.title;
      currentPath=track.source;
      notifyListeners();
      unawaited(player.play());
    }finally{
      _changing=false;
    }
  }

  Future<void> next() async {
    if(_changing||queue.isEmpty)return;
    if(repeatOne){
      await player.seek(Duration.zero);
      unawaited(player.play());
      return;
    }
    if(shuffle&&queue.length>1) {
      var randomIndex=_random.nextInt(queue.length);
      if(randomIndex==queueIndex)randomIndex=(randomIndex+1)%queue.length;
      await _openIndex(randomIndex);
      return;
    }
    if(queueIndex+1<queue.length){
      await _openIndex(queueIndex+1);
    }else{
      await player.pause();
      await player.seek(Duration.zero);
    }
  }
  Future<void> previous() async {
    if(queue.isEmpty)return;
    if(player.position>const Duration(seconds:4)){
      await player.seek(Duration.zero);
      return;
    }
    await _openIndex(queueIndex>0?queueIndex-1:0);
  }
  Future<void> toggle() async {
    if(player.playing){await player.pause();}
    else if(player.processingState==ProcessingState.completed){
      await player.seek(Duration.zero);
      unawaited(player.play());
    }else{unawaited(player.play());}
    notifyListeners();
  }
  void toggleShuffle(){shuffle=!shuffle;notifyListeners();}
  void toggleRepeat(){repeatOne=!repeatOne;notifyListeners();}

  @override
  void dispose(){
    unawaited(_completed.cancel());
    unawaited(player.dispose());
    super.dispose();
  }
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
            IconButton(onPressed:music.previous,
              icon:const Icon(Icons.skip_previous_rounded),tooltip:'السابق'),
            StreamBuilder<PlayerState>(
              stream:music.player.playerStateStream,
              builder:(ctx,snapshot)=>IconButton(
                tooltip:'تشغيل وإيقاف',
                onPressed:music.toggle,
                icon:Icon(snapshot.data?.playing==true ?
                  Icons.pause_rounded:Icons.play_arrow_rounded),
              )),
            IconButton(onPressed:music.next,
              icon:const Icon(Icons.skip_next_rounded),tooltip:'التالي'),
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
  Widget build(BuildContext context)=>AnimatedBuilder(
    animation:music,
    builder:(context,_)=>Scaffold(
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
        AnimatedBuilder(animation:music,builder:(ctx,_)=>Row(
          mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
            IconButton(onPressed:music.toggleShuffle,
              icon:Icon(Icons.shuffle,color:music.shuffle?MediaPalette.orange:null)),
            IconButton(onPressed:music.previous,iconSize:33,
              icon:const Icon(Icons.skip_previous_rounded)),
            StreamBuilder<PlayerState>(stream:music.player.playerStateStream,
              builder:(ctx,snapshot)=>IconButton.filled(
                style:IconButton.styleFrom(minimumSize:const Size(70,70),
                  backgroundColor:MediaPalette.orange),
                icon:Icon(snapshot.data?.playing==true?
                  Icons.pause_rounded:Icons.play_arrow_rounded,size:35),
                onPressed:music.toggle)),
            IconButton(onPressed:music.next,iconSize:33,
              icon:const Icon(Icons.skip_next_rounded)),
            IconButton(onPressed:music.toggleRepeat,
              icon:Icon(Icons.repeat_one,
                color:music.repeatOne?MediaPalette.orange:null)),
          ])),
        const SizedBox(height:10),
        AnimatedBuilder(animation:music,builder:(_,__)=>Text(
          music.queue.isEmpty?'': 'المقطع '+
          (music.queueIndex+1).toString()+' من '+music.queue.length.toString(),
          style:Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height:24),
        const Text('التشغيل يستمر في الخلفية مع أزرار من شاشة القفل.',
          textAlign:TextAlign.center),
      ]),
    ),
    ),
  );
}

class VideoDetail extends StatefulWidget {
  const VideoDetail({super.key,required this.source,
    required this.title,this.network=false,
    this.music,this.playlist=const [],this.startIndex=0});
  final String source;
  final String title;
  final bool network;
  final BackgroundMusic? music;
  final List<MediaTrack> playlist;
  final int startIndex;
  @override
  State<VideoDetail> createState()=>_VideoDetailState();
}

class _VideoDetailState extends State<VideoDetail> {
  VideoPlayerController? controller;
  Object? failure;
  bool loading=true,changing=false;
  late int index;
  late String currentSource,currentTitle;

  @override
  void initState(){
    super.initState();
    index=widget.startIndex;
    currentSource=widget.source;
    currentTitle=widget.title;
    _init();
  }
  void _onVideoChanged() {
    final p=controller;
    if(p==null||changing||loading||!p.value.isInitialized)return;
    if(widget.playlist.isNotEmpty&&index+1<widget.playlist.length&&
        p.value.duration>Duration.zero&&
        p.value.position>=p.value.duration&&
        !p.value.isPlaying) {
      _nextVideo();
    }
  }
  Future<void> _nextVideo() async {
    if(changing||index+1>=widget.playlist.length)return;
    changing=true;
    final old=controller;
    old?.removeListener(_onVideoChanged);
    controller=null;
    if(mounted)setState(()=>loading=true);
    await old?.dispose();
    index++;
    currentSource=widget.playlist[index].source;
    currentTitle=widget.playlist[index].title;
    changing=false;
    await _init();
  }
  Future<void> _init() async {
    VideoPlayerController? video;
    try {
      video=currentSource.startsWith('content://') ?
        VideoPlayerController.contentUri(Uri.parse(currentSource)) :
        (widget.network||currentSource.startsWith('https://')) ?
        VideoPlayerController.networkUrl(Uri.parse(currentSource)) :
        VideoPlayerController.file(File(currentSource));
      await video.initialize();
      if(!mounted){await video.dispose();return;}
      controller=video;
      video.addListener(_onVideoChanged);
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
  void dispose(){
    controller?.removeListener(_onVideoChanged);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video=controller;
    return Scaffold(
      appBar:AppBar(title:Text(currentTitle,maxLines:1),
        actions:[
          if(video!=null&&widget.music!=null)
            IconButton(
              tooltip:'استمر في الاستماع والشاشة مقفولة',
              icon:const Icon(Icons.headphones_rounded),
              onPressed:() async {
                try{
                  await video.pause();
                  if(widget.playlist.isNotEmpty){
                    await widget.music!.playQueue(widget.playlist,index);
                  }else{
                    await widget.music!.open(currentSource,title:currentTitle);
                  }
                  if(context.mounted)Navigator.of(context).pop();
                }catch(e){
                  if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content:Text('تعذر تشغيل صوت الفيديو في الخلفية: $e')));
                }
              }),
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
              if(widget.playlist.isNotEmpty)IconButton(
                onPressed:index+1<widget.playlist.length?_nextVideo:null,
                tooltip:'الفيديو التالي',
                icon:const Icon(Icons.skip_next_rounded)),
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
      builder:(_)=>VideoDetail(source:path,title:title,music:music)));
  }else if(MediaUtils.isImage(title)){
    if(context.mounted)Navigator.of(context).push(MaterialPageRoute(
      builder:(_)=>ImageDetail(path:path,title:title)));
  }else{
    if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content:Text('الملف ليس فيديو أو صوتًا أو صورة مدعومة. افتحه بتطبيق مناسب.')));
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'device_media.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'library.dart';
import 'platform_bridge.dart';
import 'captions.dart';
import 'package:file_picker/file_picker.dart';
import 'media_utils.dart';
import 'theme.dart';

/// A physical file or a user-selected phone media URI, not a stream extractor.
class MediaTrack {
  const MediaTrack({required this.source,required this.title,this.album='من هاتفي'});
  final String source,title,album;
}

class BackgroundMusic extends ChangeNotifier {
  BackgroundMusic({this.library}){
    _completed=player.playerStateStream.listen((state){
      if(state.processingState==ProcessingState.completed && !_changing){
        unawaited(next());
      }
      notifyListeners();
    });
    _positionSub=player.positionStream.listen((position){
      final uri=currentPath;
      if(uri==null)return;
      if(position.inSeconds!=_savedSecond && position.inSeconds%8==0){
        _savedSecond=position.inSeconds;
        library?.saveResume(uri,position);
      }
    });
    if(library!=null)unawaited(player.setSpeed(library!.musicSpeed));
    _initEq();
  }
  final MediaLibrary? library;
  final equalizer=AndroidEqualizer();
  late final AudioPlayer player=AudioPlayer(
    audioPipeline:AudioPipeline(androidAudioEffects:[equalizer]));
  StreamSubscription<Duration>? _positionSub;
  Timer? _sleepTimer;
  int _savedSecond=-1;
  Future<void> _initEq() async{
    if(library!=null){
      try{await setEqualizer(library!.eqPreset);}catch(_){}
    }
  }
  Future<void> setEqualizer(String preset) async{
    if(preset=='مخصص'){
      library?.setEqualizer('مخصص');
      notifyListeners();
      return;
    }
    final values=<String,List<double>>{
      'طبيعي':[0,0,0,0,0],
      'Bass':[7,5,2,-1,-2],
      'Rock':[5,3,-2,3,5],
      'صوت بشري':[-3,-1,4,4,1],
      'Cinema':[5,2,1,3,5],
    };
    final gains=values[preset]??values['طبيعي']!;
    await equalizer.setEnabled(preset!='طبيعي');
    if(preset!='طبيعي'){
      final params=await equalizer.parameters;
      for(var i=0;i<params.bands.length;i++){
        final position=(i*gains.length/params.bands.length).floor()
          .clamp(0,gains.length-1).toInt();
        final gain=gains[position].clamp(
          params.minDecibels,params.maxDecibels).toDouble();
        await params.bands[i].setGain(gain);
      }
    }
    library?.setEqualizer(preset);
    notifyListeners();
  }
  void setSleepTimer(int minutes){
    _sleepTimer?.cancel();
    library?.setSleepMinutes(minutes);
    unawaited(player.setVolume(1.0));
    if(minutes>0){
      var remaining=minutes*60;
      _sleepTimer=Timer.periodic(const Duration(seconds:1),(timer){
        remaining--;
        if(remaining<=10 && remaining>0){
          unawaited(player.setVolume((remaining/10).clamp(0.0,1.0).toDouble()));
        }
        if(remaining<=0){
          timer.cancel();
          unawaited(player.pause());
          unawaited(player.setVolume(1.0));
          library?.setSleepMinutes(0);
          notifyListeners();
        }
      });
    }
    notifyListeners();
  }
  Future<void> setSpeed(double speed) async{
    await player.setSpeed(speed);
    library?.setMusicSpeed(speed);
    notifyListeners();
  }
  String? currentTitle;
  String? currentPath;
  List<MediaTrack> queue=[];
  int queueIndex=0;
  bool shuffle=false;
  bool repeatOne=false;
  bool _changing=false;
  late final StreamSubscription<PlayerState> _completed;
  final _random=Random();

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
      library?.recordPlay(track.source);
      final resume=library?.positionFor(track.source)??Duration.zero;
      if(resume>const Duration(seconds:5) &&
        resume<((player.duration??Duration.zero)-const Duration(seconds:8))){
        await player.seek(resume);
      }
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
  void moveQueue(int oldIndex,int newIndex){
    if(oldIndex<0||oldIndex>=queue.length)return;
    if(newIndex>oldIndex)newIndex--;
    newIndex=newIndex.clamp(0,queue.length-1).toInt();
    final playingItem=queue[queueIndex];
    final item=queue.removeAt(oldIndex);
    queue.insert(newIndex,item);
    queueIndex=queue.indexOf(playingItem);
    notifyListeners();
  }

  Future<void> setBandGain(AndroidEqualizerBand band,double gain) async{
    await equalizer.setEnabled(true);
    await band.setGain(gain);
    library?.setEqualizer('مخصص');
    notifyListeners();
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
    _sleepTimer?.cancel();
    unawaited(_positionSub?.cancel());
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

  void showQueue(BuildContext context){
    showModalBottomSheet<void>(context:context,isScrollControlled:true,
      builder:(ctx)=>SafeArea(child:FractionallySizedBox(
        heightFactor:.75,child:Column(children:[
          Padding(padding:const EdgeInsets.all(15),
            child:Text('طابور التشغيل',
              style:Theme.of(ctx).textTheme.titleLarge)),
          Expanded(child:AnimatedBuilder(animation:music,builder:(ctx,_)=>
            ReorderableListView.builder(
              itemCount:music.queue.length,
              onReorder:music.moveQueue,
              itemBuilder:(ctx,i){
                final item=music.queue[i];
                return ListTile(key:ValueKey(item.source),
                  leading:Icon(i==music.queueIndex?
                    Icons.equalizer:Icons.drag_handle,
                    color:MediaPalette.orange),
                  title:Text(item.title,maxLines:1),
                  subtitle:Text(item.album,maxLines:1),
                  onTap:()async{
                    await music.playQueue(List<MediaTrack>.of(music.queue),i);
                  });
              }))),
        ]))));
  }

  void showEqualizer(BuildContext context){
    showModalBottomSheet<void>(context:context,isScrollControlled:true,
      builder:(ctx)=>SafeArea(child:Padding(
        padding:const EdgeInsets.all(16),
        child:FutureBuilder<AndroidEqualizerParameters>(
          future:music.equalizer.parameters,
          builder:(ctx,snapshot){
            if(snapshot.hasError)return Text('المعادل غير مدعوم: ${snapshot.error}');
            if(!snapshot.hasData)return const Center(
              child:CircularProgressIndicator());
            final parameters=snapshot.data!;
            return StatefulBuilder(builder:(ctx,update)=>Column(
              mainAxisSize:MainAxisSize.min,children:[
                Text('معادل الصوت',
                  style:Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height:10),
                for(final band in parameters.bands)
                  Row(children:[
                    SizedBox(width:69,child:Text(
                      '${band.centerFrequency.round()} Hz',
                      style:const TextStyle(fontSize:10))),
                    Expanded(child:Slider(
                      value:band.gain.clamp(parameters.minDecibels,
                        parameters.maxDecibels).toDouble(),
                      min:parameters.minDecibels,
                      max:parameters.maxDecibels,
                      onChanged:(gain)async{
                        await music.setBandGain(band,gain);
                        update((){});
                      })),
                    SizedBox(width:38,child:Text(
                      band.gain.toStringAsFixed(1))),
                  ]),
              ]));
          }),
      )));
  }


  String stamp(Duration v){
    final m=v.inMinutes.remainder(60).toString().padLeft(2,'0');
    final s=v.inSeconds.remainder(60).toString().padLeft(2,'0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context)=>AnimatedBuilder(
    animation:music,
    builder:(context,_)=>Scaffold(
    appBar:AppBar(title:const Text('مشغّل الصوت'),actions:[
      IconButton(icon:const Icon(Icons.queue_music),
        tooltip:'ترتيب قائمة التشغيل',onPressed:()=>showQueue(context)),
      IconButton(icon:const Icon(Icons.equalizer),
        tooltip:'ضبط ترددات الصوت',onPressed:()=>showEqualizer(context)),
    ]),
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
    this.music,this.playlist=const [],this.startIndex=0,this.library});
  final String source;
  final String title;
  final bool network;
  final BackgroundMusic? music;
  final MediaLibrary? library;
  final List<MediaTrack> playlist;
  final int startIndex;
  @override
  State<VideoDetail> createState()=>_VideoDetailState();
}

class _VideoDetailState extends State<VideoDetail> {
  VideoPlayerController? controller;
  Object? failure;
  bool loading=true,changing=false,fullscreen=false;
  bool locked=false;
  double brightness=.65;
  List<CaptionCue> cues=[];
  Duration subtitleOffset=Duration.zero;
  DateTime? _lastSave;
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
    final now=DateTime.now();
    if(widget.library!=null && (_lastSave==null ||
        now.difference(_lastSave!).inSeconds>=8)){
      _lastSave=now;
      widget.library!.saveResume(currentSource,p.value.position);
    }
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
      await video.setPlaybackSpeed(widget.library?.videoSpeed??1.0);
      final resume=widget.library?.positionFor(currentSource)??Duration.zero;
      if(resume>const Duration(seconds:5)&&
          resume<video.value.duration-const Duration(seconds:8)){
        await video.seekTo(resume);
      }
      widget.library?.recordPlay(currentSource);
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
  Future<void> _pickSubtitle() async{
    final files=await FilePicker.pickFiles(type:FileType.custom,
      allowedExtensions:['srt','vtt']);
    if(files.isEmpty||files.first.path==null)return;
    try{
      cues=await Captions.fromFile(files.first.path!);
      if(mounted)setState((){});
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text('تعذر فتح ملف الترجمة: $e')));}
  }
  Future<void> _changeSpeed() async{
    final value=await showModalBottomSheet<double>(context:context,
      builder:(ctx)=>SafeArea(child:Column(
        mainAxisSize:MainAxisSize.min,children:[
          for(final speed in [.5,.75,1.0,1.25,1.5,1.75,2.0,3.0])
            ListTile(title:Text('${speed}×'),
              onTap:()=>Navigator.pop(ctx,speed)),
        ])));
    if(value!=null&&controller!=null){
      await controller!.setPlaybackSpeed(value);
      widget.library?.setVideoSpeed(value);
      if(mounted)setState((){});
    }
  }
  void _gesture(DragUpdateDetails update,Size size){
    if(locked||controller==null)return;
    if(update.delta.dx.abs()>update.delta.dy.abs()){
      final total=controller!.value.duration.inMilliseconds;
      final target=controller!.value.position.inMilliseconds+
        (update.delta.dx*total/size.width).round();
      controller!.seekTo(Duration(milliseconds:target.clamp(0,total).toInt()));
    }else{
      if(update.localPosition.dx<size.width/2){
        brightness=(brightness-update.delta.dy/size.height)
          .clamp(.12,1.0).toDouble();
      }else{
        final next=(controller!.value.volume-update.delta.dy/size.height)
          .clamp(0.0,1.0).toDouble();
        controller!.setVolume(next);
      }
      setState((){});
    }
  }

  Future<void> _toggleFullscreen() async {
    fullscreen=!fullscreen;
    await SystemChrome.setPreferredOrientations(
      fullscreen?
        [DeviceOrientation.landscapeLeft,DeviceOrientation.landscapeRight]:
        [DeviceOrientation.portraitUp]);
    if(mounted)setState((){});
  }

  @override
  void dispose(){
    controller?.removeListener(_onVideoChanged);
    controller?.dispose();
    if(fullscreen){
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video=controller;
    return Scaffold(
      appBar:AppBar(title:Text(currentTitle,maxLines:1),
        actions:[
          if(video!=null)IconButton(
            tooltip:'قفل لمس الشاشة',
            icon:Icon(locked?Icons.lock:Icons.lock_open),
            onPressed:()=>setState(()=>locked=!locked)),
          if(video!=null)IconButton(
            tooltip:'سرعة التشغيل',icon:const Icon(Icons.speed),
            onPressed:_changeSpeed),
          if(video!=null&&cues.isNotEmpty)PopupMenuButton<int>(
            tooltip:'ضبط توقيت الترجمة',
            icon:const Icon(Icons.sync),
            onSelected:(ms)=>setState(()=>
              subtitleOffset+=Duration(milliseconds:ms)),
            itemBuilder:(ctx)=>const [
              PopupMenuItem(value:-500,child:Text('الترجمة قبل 0.5 ثانية')),
              PopupMenuItem(value:500,child:Text('الترجمة بعد 0.5 ثانية')),
            ]),
          if(video!=null)IconButton(
            tooltip:'إضافة ترجمة SRT أو VTT',
            icon:const Icon(Icons.closed_caption),
            onPressed:_pickSubtitle),
          if(video!=null)IconButton(
            tooltip:fullscreen?'عودة للوضع الرأسي':'ملء الشاشة',
            icon:Icon(fullscreen?Icons.fullscreen_exit:Icons.fullscreen),
            onPressed:_toggleFullscreen),
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
                final ok=await PlatformMediaBridge.enterPip();
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
        video == null ? const Center(child:CircularProgressIndicator()) :
        Column(children:[
          Expanded(child:LayoutBuilder(builder:(ctx,limits)=>
            GestureDetector(
              onPanUpdate:(e)=>_gesture(e,limits.biggest),
              onDoubleTapDown:(e){
                if(locked)return;
                final jump=e.localPosition.dx<limits.maxWidth/2?-10:10;
                final target=video.value.position+Duration(seconds:jump);
                video.seekTo(target<Duration.zero?Duration.zero:target);
              },
              child:Stack(children:[
                Center(child:AspectRatio(
                  aspectRatio:video.value.aspectRatio,
                  child:VideoPlayer(video))),
                if(brightness<.99)IgnorePointer(child:Container(
                  color:Colors.black.withValues(alpha:(1-brightness)*.65))),
                if(cues.isNotEmpty)Positioned(
                  bottom:30,left:12,right:12,
                  child:AnimatedBuilder(animation:video,builder:(ctx,_){
                    final text=Captions.at(cues,video.value.position,
                      offset:subtitleOffset);
                    return text.isEmpty?const SizedBox.shrink():
                      Container(
                        color:Colors.black54,
                        padding:const EdgeInsets.all(5),
                        child:Text(text,textAlign:TextAlign.center,
                          style:TextStyle(color:Colors.white,
                            fontSize:widget.library?.subtitleSize??18)));
                  })),
                if(locked)const Positioned(top:16,right:16,
                  child:Icon(Icons.lock,color:Colors.white)),
              ]),
            ))),
          if(!locked)Padding(padding:const EdgeInsets.all(12),
            child:Column(children:[
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'library.dart';
import 'media_utils.dart';
import 'player.dart';
import 'theme.dart';

enum LinkKind { youtube, webpage, audio, video, file, hls, invalid }

class LinkVariant {
  const LinkVariant(this.url,this.label,{this.downloadable=false});
  final Uri url;
  final String label;
  final bool downloadable;
}

class LinkInspection {
  LinkInspection({required this.original,required this.kind,
    required this.title,this.mime='',this.size=-1,this.variants=const []});
  final Uri original;
  final LinkKind kind;
  final String title,mime;
  final int size;
  final List<LinkVariant> variants;
}

/// Inspects direct HTTPS sources and openly linked HLS variants.
/// It does not decrypt DRM, scrape YouTube, or promise a bitrate not present
/// in the media source. Real quality choices only appear when supplied.
class MediaLinkInspector {
  static bool _directAudio(String mime)=>mime.startsWith('audio/');
  static bool _directVideo(String mime)=>mime.startsWith('video/');

  static Future<LinkInspection> inspect(String text) async {
    final uri=MediaUtils.interpretAddress(text);
    if(uri.scheme!='https'||uri.host.isEmpty){
      return LinkInspection(original:uri,kind:LinkKind.invalid,
        title:'رابط غير صالح');
    }
    if(MediaUtils.isYouTube(uri)){
      return LinkInspection(original:uri,kind:LinkKind.youtube,
        title:'رابط YouTube');
    }
    if(uri.path.toLowerCase().endsWith('.m3u8')){
      return _inspectHls(uri);
    }
    final extension=MediaUtils.extension(uri.path);
    final client=HttpClient()..connectionTimeout=const Duration(seconds:12);
    String mime='';
    int size=-1;
    String filename=MediaUtils.fileTitle(uri);
    try{
      final req=await client.openUrl('HEAD',uri).timeout(const Duration(seconds:13));
      req.followRedirects=true;
      req.maxRedirects=4;
      final response=await req.close().timeout(const Duration(seconds:15));
      if(response.statusCode>=200&&response.statusCode<400){
        mime=response.headers.contentType?.mimeType.toLowerCase()??'';
        size=response.contentLength;
        final disposition=response.headers.value('content-disposition')??'';
        final match=RegExp(r'filename="?([^";]+)"?',caseSensitive:false)
            .firstMatch(disposition);
        if(match!=null&&match.group(1)!=null){
          filename=match.group(1)!.trim();
        }
      }
      await response.drain<void>();
    }catch(_){
      // HEAD may be blocked by CDNs. If URI has a real media extension,
      // we can still offer its exact direct resource without pretending
      // to know its size, quality or transcoding ability.
    }finally{client.close(force:true);}

    final audio=_directAudio(mime)||MediaUtils.audio.contains(extension);
    final video=_directVideo(mime)||MediaUtils.video.contains(extension);
    final file=MediaUtils.supported.contains(extension);
    final type=audio?LinkKind.audio:video?LinkKind.video:
      file?LinkKind.file:LinkKind.webpage;
    return LinkInspection(original:uri,kind:type,
      title:filename,mime:mime,size:size,
      variants:(type==LinkKind.audio||type==LinkKind.video||type==LinkKind.file)?
        [LinkVariant(uri,'الجودة الأصلية • من المصدر',downloadable:true)]:
        const []);
  }

  static Future<LinkInspection> _inspectHls(Uri uri) async {
    final client=HttpClient()..connectionTimeout=const Duration(seconds:10);
    final variants=<LinkVariant>[];
    try{
      final req=await client.getUrl(uri);
      final response=await req.close().timeout(const Duration(seconds:12));
      if(response.statusCode!=200)throw StateError('Source is unavailable');
      final chunks=<int>[];
      await for(final chunk in response) {
        chunks.addAll(chunk);
        if(chunks.length>300000)break;
      }
      final lines=utf8.decode(chunks,allowMalformed:true).split(RegExp(r'\r?\n'));
      for(var i=0;i<lines.length;i++){
        if(!lines[i].startsWith('#EXT-X-STREAM-INF:'))continue;
        final resolution=RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(lines[i]);
        final bandwidth=RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i]);
        String label=resolution!=null?
          resolution.group(1)!+'p':
          bandwidth!=null?'سرعة '+bandwidth.group(1)!+' بت/ث':'نسخة متاحة';
        for(var j=i+1;j<lines.length;j++){
          final next=lines[j].trim();
          if(next.isEmpty)continue;
          if(next.startsWith('#'))break;
          final child=uri.resolve(next);
          if(child.scheme=='https'){
            variants.add(LinkVariant(child,label+' • تشغيل فقط'));
          }
          break;
        }
      }
    }catch(_){
      // Source can still be opened in the media player for a playback attempt.
    }finally{client.close(force:true);}
    if(variants.isEmpty){
      variants.add(LinkVariant(uri,'جودة تلقائية • تشغيل فقط'));
    }
    return LinkInspection(original:uri,kind:LinkKind.hls,
      title:MediaUtils.fileTitle(uri),mime:'application/vnd.apple.mpegurl',
      variants:variants);
  }
}

class SmartLinkScreen extends StatefulWidget {
  const SmartLinkScreen({super.key,required this.library,
    required this.music,required this.browse});
  final MediaLibrary library;
  final BackgroundMusic music;
  final ValueChanged<String> browse;
  @override
  State<SmartLinkScreen> createState()=>_SmartLinkScreenState();
}

class _SmartLinkScreenState extends State<SmartLinkScreen> {
  final input=TextEditingController();
  bool loading=false;
  LinkInspection? info;
  String? error;
  @override
  void dispose(){input.dispose();super.dispose();}

  Future<void> paste() async {
    final clipboard=await Clipboard.getData('text/plain');
    if(clipboard?.text!=null){
      input.text=clipboard!.text!.trim();
      await analyze();
    }
  }
  Future<void> analyze() async {
    final text=input.text.trim();
    if(text.isEmpty)return;
    setState(()=>loading=true);
    try{
      final inspected=await MediaLinkInspector.inspect(text);
      if(mounted)setState(()=>info=inspected);
    }catch(e){
      if(mounted)setState(()=>error='تعذر فحص الرابط: $e');
    }finally{if(mounted)setState(()=>loading=false);}
  }
  void browse(Uri uri){
    widget.browse(uri.toString());
    Navigator.of(context).pop();
  }
  Future<void> download(LinkVariant variant) async {
    try{
      final record=await widget.library.addDownload(
        variant.url.toString(),
        filename:MediaUtils.fileTitle(variant.url));
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('التنزيل بدأ في الخلفية: ${record.title}')));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('فشل بدء التنزيل: $e')));
    }
  }
  void play(LinkVariant variant) {
    final x=info!;
    if(x.kind==LinkKind.audio){
      widget.music.open(variant.url.toString(),title:x.title).then((_){
        if(mounted)Navigator.of(context).push(MaterialPageRoute(
          builder:(_)=>AudioDetail(music:widget.music)));
      }).catchError((Object e){
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text('تعذر تشغيل الصوت: $e')));
      });
    }else {
      Navigator.of(context).push(MaterialPageRoute(
        builder:(_)=>VideoDetail(source:variant.url.toString(),
          title:x.title,network:true,music:widget.music)));
    }
  }

  @override
  Widget build(BuildContext context){
    final current=info;
    final theme=Theme.of(context);
    return Scaffold(
      appBar:AppBar(title:const Text('رابط واحد، خيارات واضحة')),
      body:ListView(padding:const EdgeInsets.all(18),children:[
        Container(padding:const EdgeInsets.all(20),
          decoration:BoxDecoration(
            color:theme.colorScheme.surfaceContainerLow,
            border:Border.all(color:theme.dividerColor),
            borderRadius:BorderRadius.circular(26)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('الصق رابطك هنا',
              style:TextStyle(fontSize:24,fontWeight:FontWeight.w900)),
            const SizedBox(height:7),
            Text('هنفحص الرابط، ونوضح هل المصدر فيديو أو صوت أو صفحة، '
              'ونعرض الجودات الحقيقية لما تكون متاحة.',
              style:theme.textTheme.bodyMedium),
            const SizedBox(height:17),
            TextField(controller:input,maxLines:2,minLines:1,
              keyboardType:TextInputType.url,textDirection:TextDirection.ltr,
              decoration:const InputDecoration(
                prefixIcon:Icon(Icons.link_rounded),
                hintText:'https://example.com/video.mp4'),
              onSubmitted:(_)=>analyze()),
            const SizedBox(height:11),
            Row(children:[
              Expanded(child:FilledButton.icon(onPressed:loading?null:paste,
                icon:const Icon(Icons.content_paste_rounded),
                label:const Text('لصق الرابط'))),
              const SizedBox(width:9),
              Expanded(child:OutlinedButton.icon(onPressed:loading?null:analyze,
                icon:const Icon(Icons.manage_search_rounded),
                label:const Text('تحليل الرابط'))),
            ]),
          ]),
        ),
        if(loading)...[
          const SizedBox(height:20),
          const LinearProgressIndicator(color:MediaPalette.orange),
          const SizedBox(height:12),
          const Text('جارٍ فحص المصدر والملفات المتاحة...'),
        ],
        if(error!=null)Padding(padding:const EdgeInsets.all(12),
          child:Text(error!,style:const TextStyle(color:Colors.red))),
        if(current!=null)...[
          const SizedBox(height:23),
          Text('نتيجة التحليل',
            style:theme.textTheme.titleLarge?.copyWith(fontWeight:FontWeight.w900)),
          const SizedBox(height:12),
          Card(child:Padding(padding:const EdgeInsets.all(15),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                Container(width:50,height:50,
                  decoration:BoxDecoration(
                    color:MediaPalette.orange.withValues(alpha:.12),
                    borderRadius:BorderRadius.circular(14)),
                  child:Icon(switch(current.kind){
                    LinkKind.audio=>Icons.music_note,
                    LinkKind.video||LinkKind.hls=>Icons.movie_creation_outlined,
                    LinkKind.youtube=>Icons.smart_display,
                    _=>Icons.language,
                  },color:MediaPalette.orange,size:28)),
                const SizedBox(width:11),
                Expanded(child:Column(
                  crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(current.title,style:const TextStyle(
                      fontSize:16,fontWeight:FontWeight.w900),
                      maxLines:2,overflow:TextOverflow.ellipsis),
                    Text(switch(current.kind){
                      LinkKind.audio=>'مصدر صوت مباشر',
                      LinkKind.video=>'مصدر فيديو مباشر',
                      LinkKind.file=>'ملف قابل للتنزيل',
                      LinkKind.hls=>'بث HLS • جودات تشغيل',
                      LinkKind.youtube=>'YouTube • تشغيل رسمي',
                      _=>'صفحة ويب',
                    },style:theme.textTheme.bodySmall),
                  ])),
              ]),
              if(current.size>0)Padding(
                padding:const EdgeInsets.only(top:10),
                child:Text('الحجم: ${MediaUtils.displaySize(current.size)}')),
            ]),
          )),
          const SizedBox(height:12),
          if(current.kind==LinkKind.youtube)...[
            const Text('يوتيوب لا يوفّر عبر هذا التطبيق تنزيل فيديوهات أو فصل الصوت '
              'إلى MP3. تقدر تفتح الرابط وتشغّله في المتصفح؛ '
              'التنزيل دون اتصال يستخدم خيارات يوتيوب الرسمية.'),
            const SizedBox(height:12),
            FilledButton.icon(onPressed:()=>browse(current.original),
              icon:const Icon(Icons.play_circle_outline),
              label:const Text('فتح يوتيوب في المتصفح')),
          ]else if(current.kind==LinkKind.webpage||current.kind==LinkKind.invalid)...[
            const Text('ده رابط صفحة، مش رابط ملف صوت أو فيديو مباشر. '
              'افتح الصفحة، واستخدم اكتشاف روابط الملفات الظاهرة فيها '
              'لو الموقع بيسمح بتنزيلها.'),
            const SizedBox(height:12),
            FilledButton.icon(onPressed:()=>browse(current.original),
              icon:const Icon(Icons.language),label:const Text('فتح الموقع')),
          ]else...[
            const Text('الجودة لا يمكن تغييرها في الملف نفسه من غير تحويل '
              'حقيقي. الجودات اللي تحت هي الجودات اللي المصدر قدّمها.'),
            const SizedBox(height:10),
            for(final option in current.variants)
              Card(child:Padding(padding:const EdgeInsets.all(11),
                child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,
                  children:[
                    Text(option.label,style:const TextStyle(
                      fontWeight:FontWeight.w800)),
                    const SizedBox(height:10),
                    Row(children:[
                      if(current.kind==LinkKind.audio||
                          current.kind==LinkKind.video||
                          current.kind==LinkKind.hls)
                        Expanded(child:OutlinedButton.icon(
                          onPressed:()=>play(option),
                          icon:const Icon(Icons.play_arrow),
                          label:const Text('تشغيل'))),
                      if(option.downloadable)...[
                        const SizedBox(width:9),
                        Expanded(child:FilledButton.icon(
                          onPressed:()=>download(option),
                          icon:const Icon(Icons.download_rounded),
                          label:const Text('تنزيل'))),
                      ],
                    ]),
                  ]),
              )),
            if(current.kind==LinkKind.audio)
              const Padding(padding:EdgeInsets.all(10),
                child:Text('ملفات MP3 تُحفظ بصيغتها الأصلية. '
                  'لا يتم الادعاء بتحويلها إلى 320kbps إذا المصدر لا يوفر ذلك.',
                  style:TextStyle(fontSize:12))),
          ],
        ],
      ]),
    );
  }
}

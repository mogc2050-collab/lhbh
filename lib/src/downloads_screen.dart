import 'dart:async';
import 'package:flutter/material.dart';
import 'library.dart';
import 'media_utils.dart';
import 'player.dart';
import 'theme.dart';

class DownloadScreen extends StatefulWidget {
  const DownloadScreen({super.key,required this.library,required this.music});
  final MediaLibrary library;
  final BackgroundMusic music;
  @override
  State<DownloadScreen> createState()=>_DownloadScreenState();
}
class _DownloadScreenState extends State<DownloadScreen> {
  Timer? refresh;
  @override
  void initState(){
    super.initState();
    widget.library.refreshDownloads();
    refresh=Timer.periodic(const Duration(seconds:2),
      (_)=>widget.library.refreshDownloads());
  }
  @override
  void dispose(){refresh?.cancel();super.dispose();}
  String _status(String s)=>switch(s){
    'success'=>'اكتمل',
    'running'=>'جارٍ التنزيل',
    'pending'=>'في الانتظار',
    'paused'=>'متوقف مؤقتًا (الشبكة)',
    'failed'=>'فشل التنزيل',
    _=>'جارٍ الاستعلام',
  };

  Future<void> _play(DownloadRecord record) async {
    if(record.status!='success')return;
    try {
      final path=await DownloadBridge.copyToCache(record.id);
      if(mounted)await openMedia(context,widget.music,path,record.title);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('تعذر فتح الملف: $e')));
    }
  }
  Future<void> _action(DownloadRecord r,String item) async {
    try {
      if(item=='play')await _play(r);
      else if(item=='open')await DownloadBridge.open(r.id);
      else if(item=='share')await DownloadBridge.share(r.id);
      else if(item=='delete') {
        final yes=await showDialog<bool>(context:context,
          builder:(ctx)=>AlertDialog(
            title:const Text('حذف التنزيل؟'),
            content:Text('سيُحذف الملف الذي نزّله التطبيق: ${r.title}'),
            actions:[
              TextButton(onPressed:()=>Navigator.pop(ctx,false),
                child:const Text('إلغاء')),
              FilledButton(onPressed:()=>Navigator.pop(ctx,true),
                child:const Text('حذف')),
            ]),
        );
        if(yes==true)await widget.library.removeDownload(r);
      }
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('تعذر تنفيذ الإجراء: $e')));
    }
  }
  Future<void> _addLink() async {
    final url=TextEditingController();
    final name=TextEditingController();
    final result=await showDialog<bool>(context:context,
      builder:(ctx)=>AlertDialog(
        title:const Text('تنزيل رابط مباشر'),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          TextField(controller:url,keyboardType:TextInputType.url,
            decoration:const InputDecoration(hintText:'https://example.com/movie.mp4',
              labelText:'رابط ملف HTTPS')),
          const SizedBox(height:12),
          TextField(controller:name,decoration:const InputDecoration(
            labelText:'اسم الملف (اختياري)')),
          const SizedBox(height:12),
          const Text('يُقبل رابط ملف مباشر يسمح الموقع بتنزيله. '
            'لا يدعم استخراج البث المشفّر أو فيديوهات يوتيوب.'),
        ]),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:const Text('ابدأ التنزيل')),
        ]),
    );
    final link=url.text.trim(), filename=name.text.trim();
    url.dispose();name.dispose();
    if(result!=true || link.isEmpty)return;
    final valid=MediaUtils.validateDownload(link);
    if(valid!=null){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text(valid)));
      return;
    }
    try {
      final record=await widget.library.addDownload(link,
        filename:filename.isEmpty?null:filename);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('تمت إضافة ${record.title} إلى قائمة التنزيلات.')));
    }catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('فشل التنزيل: $e')));
    }
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('التنزيلات'),
      actions:[
        IconButton(tooltip:'تحديث',icon:const Icon(Icons.refresh),
          onPressed:widget.library.refreshDownloads),
        IconButton(tooltip:'تنزيلات أندرويد',
          icon:const Icon(Icons.folder_open),
          onPressed:() async {
            try{await DownloadBridge.showSystemDownloads();}
            catch(e){if(context.mounted)ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content:Text('$e')));}
          }),
      ]),
    floatingActionButton:FloatingActionButton.extended(
      onPressed:_addLink,label:const Text('رابط جديد'),
      icon:const Icon(Icons.add_link),
      backgroundColor:MediaPalette.orange,foregroundColor:Colors.white),
    body:AnimatedBuilder(animation:widget.library,builder:(ctx,child)=>
      widget.library.downloads.isEmpty ?
        Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Icon(Icons.cloud_download_outlined,size:75,
            color:MediaPalette.orange),
          const SizedBox(height:16),
          const Text('لحد دلوقتي مفيش تنزيلات',
            style:TextStyle(fontSize:18,fontWeight:FontWeight.w800)),
          const SizedBox(height:7),
          const Padding(padding:EdgeInsets.symmetric(horizontal:30),
            child:Text('ابدأ بتنزيل رابط ملف مباشر من المتصفح أو من زر رابط جديد.',
              textAlign:TextAlign.center)),
        ])):
        RefreshIndicator(onRefresh:widget.library.refreshDownloads,
          child:ListView.separated(
            padding:const EdgeInsets.fromLTRB(14,12,14,110),
            itemCount:widget.library.downloads.length,
            separatorBuilder:(_,__)=>const SizedBox(height:11),
            itemBuilder:(ctx,i) {
              final record=widget.library.downloads[i];
              final ready=record.status=='success';
              final isMedia=MediaUtils.isAudio(record.title)||
                MediaUtils.isVideo(record.title)||
                MediaUtils.isImage(record.title);
              return Card(child:Padding(
                padding:const EdgeInsets.all(13),child:Column(
                  children:[
                    Row(children:[
                      Container(
                        width:49,height:49,alignment:Alignment.center,
                        decoration:BoxDecoration(
                          color:MediaPalette.orange.withValues(alpha:.1),
                          borderRadius:BorderRadius.circular(13)),
                        child:Icon(
                          MediaUtils.isVideo(record.title)?
                             Icons.movie_rounded:
                          MediaUtils.isAudio(record.title)?
                             Icons.audiotrack_rounded:
                          MediaUtils.isImage(record.title)?
                             Icons.image_rounded:
                             Icons.insert_drive_file_rounded,
                          color:MediaPalette.orange,size:28)),
                      const SizedBox(width:11),
                      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
                        children:[
                          Text(record.title,maxLines:2,overflow:TextOverflow.ellipsis,
                            style:const TextStyle(fontWeight:FontWeight.w900)),
                          Text(_status(record.status)+' • '+
                            MediaUtils.displaySize(record.downloaded)+
                            (record.total>0 ? ' / '+MediaUtils.displaySize(record.total):''),
                            style:Theme.of(context).textTheme.bodySmall),
                        ])),
                      PopupMenuButton<String>(
                        tooltip:'خيارات الملف',
                        onSelected:(s)=>_action(record,s),
                        itemBuilder:(ctx)=>[
                          if(ready && isMedia)const PopupMenuItem(
                            value:'play',child:Text('تشغيل')),
                          if(ready)const PopupMenuItem(
                            value:'open',child:Text('افتح بالتطبيق المناسب')),
                          if(ready)const PopupMenuItem(
                            value:'share',child:Text('مشاركة')),
                          const PopupMenuItem(value:'delete',
                            child:Text('حذف الملف',style:TextStyle(color:Colors.red))),
                        ]),
                    ]),
                    if(!ready)...[
                      const SizedBox(height:10),
                      LinearProgressIndicator(
                        value:record.progress,minHeight:5,
                        borderRadius:BorderRadius.circular(8)),
                    ],
                    if(ready && isMedia)Align(alignment:Alignment.centerLeft,
                      child:TextButton.icon(
                        onPressed:()=>_play(record),
                        icon:const Icon(Icons.play_arrow_rounded),
                        label:const Text('شغّل الملف'))),
                  ],
                ),
              ));
            },
          )),
    ),
  );
}

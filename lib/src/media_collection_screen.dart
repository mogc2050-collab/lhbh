import 'package:flutter/material.dart';
import 'device_media.dart';
import 'library.dart';
import 'library_screen.dart';
import 'media_utils.dart';
import 'player.dart';
import 'theme.dart';

/// Real system media catalog. No need to import or duplicate every song/video.
class MediaCollectionScreen extends StatelessWidget {
  const MediaCollectionScreen({
    super.key,required this.phone,required this.library,required this.music,
  });
  final PhoneLibrary phone;
  final MediaLibrary library;
  final BackgroundMusic music;

  @override
  Widget build(BuildContext context)=>DefaultTabController(
    length:3,
    child:Scaffold(
      appBar:AppBar(title:const Text('مكتبة الوسائط'),
        actions:[
          IconButton(
            tooltip:'إعادة فحص وسائط الهاتف',
            onPressed:phone.refresh,icon:const Icon(Icons.refresh_rounded)),
        ],
        bottom:const TabBar(
          indicatorColor:MediaPalette.orange,
          labelColor:MediaPalette.orange,
          tabs:[
            Tab(text:'الأغاني',icon:Icon(Icons.library_music_outlined)),
            Tab(text:'الفيديو',icon:Icon(Icons.video_library_outlined)),
            Tab(text:'ملفات مستوردة',icon:Icon(Icons.folder_copy_outlined)),
          ],
        ),
      ),
      body:TabBarView(children:[
        _PhoneMediaList(phone:phone,music:music,type:'audio'),
        _PhoneMediaList(phone:phone,music:music,type:'video'),
        LibraryScreen(library:library,music:music),
      ]),
    ),
  );
}

class _PhoneMediaList extends StatefulWidget {
  const _PhoneMediaList({
    required this.phone,required this.music,required this.type,
  });
  final PhoneLibrary phone;
  final BackgroundMusic music;
  final String type;

  @override
  State<_PhoneMediaList> createState()=>_PhoneMediaListState();
}

class _PhoneMediaListState extends State<_PhoneMediaList> {
  final text=TextEditingController();
  String sort='new';
  @override
  void dispose(){text.dispose();super.dispose();}

  List<PhoneMedia> filtered(){
    final list=List<PhoneMedia>.of(
      widget.type=='audio'?widget.phone.audio:widget.phone.videos);
    final keyword=text.text.trim().toLowerCase();
    if(keyword.isNotEmpty){
      list.removeWhere((v)=>!v.name.toLowerCase().contains(keyword));
    }
    if(sort=='name'){
      list.sort((a,b)=>a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }else if(sort=='long'){
      list.sort((a,b)=>b.duration.compareTo(a.duration));
    }else{
      list.sort((a,b)=>b.date.compareTo(a.date));
    }
    return list;
  }

  void _open(List<PhoneMedia> items,int index) async {
    if(items.isEmpty)return;
    final queue=items.map((x)=>MediaTrack(
      source:x.uri,title:x.name,album:'مكتبة الهاتف')).toList();
    try {
      if(widget.type=='audio'){
        await widget.music.playQueue(queue,index);
        if(mounted)Navigator.of(context).push(MaterialPageRoute<void>(
          builder:(_)=>AudioDetail(music:widget.music)));
      }else{
        if(mounted)Navigator.of(context).push(MaterialPageRoute<void>(
          builder:(_)=>VideoDetail(
            source:items[index].uri,title:items[index].name,
            music:widget.music,playlist:queue,startIndex:index)));
      }
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('تعذّر تشغيل الملف: $e')));
    }
  }

  String duration(int ms) {
    if(ms<=0)return '--:--';
    final d=Duration(milliseconds:ms);
    final seconds=d.inSeconds.remainder(60).toString().padLeft(2,'0');
    return '${d.inMinutes}:$seconds';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation:widget.phone,
    builder:(context,_) {
      final isAudio=widget.type=='audio';
      final allowed=isAudio?widget.phone.audioGranted:widget.phone.videoGranted;
      final items=filtered();
      if(!allowed){
        return Center(child:Padding(
          padding:const EdgeInsets.all(25),
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            Container(width:104,height:104,decoration:BoxDecoration(
              color:MediaPalette.orange.withValues(alpha:.11),
              borderRadius:BorderRadius.circular(28)),
              child:Icon(isAudio?Icons.library_music:Icons.video_library,
                color:MediaPalette.orange,size:55)),
            const SizedBox(height:22),
            Text(isAudio?'تفعيل الوصول للأغاني':'تفعيل الوصول للفيديوهات',
              style:const TextStyle(fontSize:23,fontWeight:FontWeight.w900),
              textAlign:TextAlign.center),
            const SizedBox(height:9),
            Text('اسمح للتطبيق بقراءة ${isAudio?'ملفات الصوت':'مقاطع الفيديو'} '
              'اللي نظام أندرويد بيفهرسها. مش هنرفعها لسيرفر، '
              'ومش هنحذف ملفاتك الأصلية.',
              textAlign:TextAlign.center,
              style:Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height:20),
            FilledButton.icon(
              onPressed:widget.phone.loading?null:()=>
                widget.phone.refresh(askPermissions:true),
              icon:const Icon(Icons.shield_outlined),
              label:const Text('السماح بالوصول والاشعارات')),
            if(widget.phone.error!=null)Padding(
              padding:const EdgeInsets.all(8),
              child:Text(widget.phone.error!,style:const TextStyle(color:Colors.red))),
          ]),
        ));
      }
      return Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,12,16,6),
          child:Row(children:[
            Expanded(child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(isAudio?'أغانيك من الموبايل':'فيديوهاتك من الموبايل',
                  style:Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight:FontWeight.w900)),
                Text('${items.length} ملف • محدث تلقائيًا عند إعادة الفحص',
                  style:Theme.of(context).textTheme.bodySmall),
              ])),
            PopupMenuButton<String>(
              initialValue:sort,
              tooltip:'ترتيب الملفات',
              onSelected:(value)=>setState(()=>sort=value),
              itemBuilder:(ctx)=>const [
                PopupMenuItem(value:'new',child:Text('الأحدث')),
                PopupMenuItem(value:'name',child:Text('الاسم')),
                PopupMenuItem(value:'long',child:Text('المدة')),
              ],
              child:const Icon(Icons.sort_rounded,color:MediaPalette.orange)),
          ]),
        ),
        Padding(padding:const EdgeInsets.fromLTRB(14,8,14,10),
          child:TextField(controller:text,onChanged:(_)=>setState((){}),
            decoration:InputDecoration(
              hintText:isAudio?'ابحث عن أغنية':'ابحث عن فيديو',
              prefixIcon:const Icon(Icons.search_rounded),
              suffixIcon:text.text.isNotEmpty?IconButton(
                icon:const Icon(Icons.close),
                onPressed:()=>setState(()=>text.clear())):null)),
        ),
        if(widget.phone.loading)const LinearProgressIndicator(),
        if(widget.phone.error!=null)Padding(
          padding:const EdgeInsets.all(10),
          child:Text(widget.phone.error!,
            style:const TextStyle(color:Colors.red))),
        Expanded(child:items.isEmpty?
          Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
            Icon(isAudio?Icons.music_off:Icons.video_file_outlined,
              size:60,color:MediaPalette.orange),
            const SizedBox(height:12),
            Text('مفيش ملفات مطابقة في فهرس أندرويد',
              style:Theme.of(context).textTheme.titleMedium),
            const SizedBox(height:8),
            TextButton.icon(onPressed:widget.phone.refresh,
              icon:const Icon(Icons.refresh),label:const Text('إعادة الفحص')),
          ])):
          RefreshIndicator(
            onRefresh:widget.phone.refresh,
            child:ListView.separated(
              padding:const EdgeInsets.fromLTRB(12,4,12,90),
              itemCount:items.length,
              separatorBuilder:(_,__)=>const SizedBox(height:7),
              itemBuilder:(ctx,index){
                final item=items[index];
                return Card(child:ListTile(
                  onTap:()=>_open(items,index),
                  contentPadding:const EdgeInsets.symmetric(
                    horizontal:10,vertical:4),
                  leading:Container(
                    width:52,height:52,
                    decoration:BoxDecoration(
                      color:MediaPalette.orange.withValues(alpha:.12),
                      borderRadius:BorderRadius.circular(14)),
                    child:Icon(isAudio?Icons.music_note_rounded:
                        Icons.play_circle_outline_rounded,
                      size:28,color:MediaPalette.orange)),
                  title:Text(item.name,maxLines:2,overflow:TextOverflow.ellipsis,
                    style:const TextStyle(fontWeight:FontWeight.w800,fontSize:13)),
                  subtitle:Text('${duration(item.duration)} • '
                    '${MediaUtils.displaySize(item.size)}',
                    maxLines:1),
                  trailing:IconButton(onPressed:()=>_open(items,index),
                    icon:const Icon(Icons.play_arrow_rounded,
                      color:MediaPalette.orange)),
                ));
              },
            ),
          )),
      ]);
    },
  );
}

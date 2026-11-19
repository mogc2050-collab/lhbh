import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'device_media.dart';
import 'library.dart';
import 'library_screen.dart';
import 'media_utils.dart';
import 'player.dart';
import 'theme.dart';

class MediaCollectionScreen extends StatefulWidget {
  const MediaCollectionScreen({super.key,required this.phone,
    required this.library,required this.music});
  final PhoneLibrary phone;
  final MediaLibrary library;
  final BackgroundMusic music;
  @override State<MediaCollectionScreen> createState()=>_MediaCollectionScreenState();
}

class _MediaCollectionScreenState extends State<MediaCollectionScreen> {
  int selected=0;
  final search=TextEditingController();
  String sort='الأحدث';
  @override void dispose(){search.dispose();super.dispose();}

  List<PhoneMedia> get current {
    final raw=switch(selected){
      1=>widget.phone.audio,
      2=>widget.phone.videos,
      3=>widget.phone.images,
      _=>widget.phone.all,
    };
    final list=List<PhoneMedia>.of(raw);
    final q=search.text.trim().toLowerCase();
    if(q.isNotEmpty)list.removeWhere((m)=>
      !('${m.name} ${m.artist} ${m.album} ${m.folder}')
        .toLowerCase().contains(q));
    if(sort=='الاسم')list.sort((a,b)=>a.name.compareTo(b.name));
    if(sort=='المدة')list.sort((a,b)=>b.duration.compareTo(a.duration));
    if(sort=='الحجم')list.sort((a,b)=>b.size.compareTo(a.size));
    if(sort=='الأكثر تشغيلًا')list.sort((a,b)=>
      (widget.library.playCount[b.uri]??0).compareTo(
        widget.library.playCount[a.uri]??0));
    if(sort=='الأحدث')list.sort((a,b)=>b.date.compareTo(a.date));
    return list;
  }
  List<MediaTrack> tracks(Iterable<PhoneMedia> items)=>items.map((m)=>
    MediaTrack(source:m.uri,title:widget.library.customTitles[m.uri]??m.name,
      album:m.album.isNotEmpty?m.album:'من الهاتف')).toList();

  Future<void> playMedia(PhoneMedia media,[List<PhoneMedia>? group]) async{
    try{
      if(media.audio){
        final list=(group??widget.phone.audio).where((e)=>e.audio).toList();
        final index=list.indexWhere((e)=>e.uri==media.uri);
        await widget.music.playQueue(tracks(list),index<0?0:index);
        if(mounted)Navigator.of(context).push(MaterialPageRoute<void>(
          builder:(_)=>AudioDetail(music:widget.music)));
      }else if(media.video){
        final videos=(group??widget.phone.videos).where((e)=>e.video).toList();
        final index=videos.indexWhere((e)=>e.uri==media.uri);
        if(mounted)Navigator.of(context).push(MaterialPageRoute<void>(
          builder:(_)=>VideoDetail(source:media.uri,
            title:media.name,music:widget.music,library:widget.library,
            startIndex:index<0?0:index,playlist:tracks(videos))));
      }else if(media.image){
        final bytes=await widget.phone.imagePreview(media.uri);
        if(bytes==null||bytes.isEmpty)throw StateError(
          'تعذر قراءة الصورة من الهاتف');
        if(mounted)Navigator.of(context).push(MaterialPageRoute<void>(
          builder:(_)=>Scaffold(appBar:AppBar(title:Text(media.name)),
            body:InteractiveViewer(minScale:.5,maxScale:7,
              child:Center(child:Image.memory(bytes,fit:BoxFit.contain))))));
      }
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text('تعذر فتح الوسائط: $e')));}
  }

  void showItems(String title,List<PhoneMedia> items){
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder:(ctx)=>Scaffold(
        appBar:AppBar(title:Text(title)),
        body:ListView.builder(itemCount:items.length,
          itemBuilder:(ctx,i)=>ListTile(
            leading:_thumb(items[i]),
            title:Text(items[i].name,maxLines:2),
            subtitle:Text(items[i].artist.isNotEmpty?
              items[i].artist:MediaUtils.displaySize(items[i].size)),
            onTap:()=>playMedia(items[i],items),
            trailing:IconButton(
              icon:Icon(widget.library.isFavorite(items[i].uri)?
                Icons.favorite:Icons.favorite_outline,
                color:MediaPalette.orange),
              onPressed:(){
                widget.library.toggleFavorite(items[i].uri);
                setState((){});
              }),
          )),
      )));
  }

  Widget _thumb(PhoneMedia m){
    final cached=widget.phone.thumbs[m.uri];
    if(cached!=null)return ClipRRect(
      borderRadius:BorderRadius.circular(10),
      child:Image.memory(cached,width:46,height:46,fit:BoxFit.cover));
    return FutureBuilder<Uint8List?>(
      future:widget.phone.artwork(m.uri),
      builder:(ctx,snapshot){
        if(snapshot.data!=null&&snapshot.data!.isNotEmpty){
          return ClipRRect(borderRadius:BorderRadius.circular(10),
            child:Image.memory(snapshot.data!,width:46,height:46,
              fit:BoxFit.cover));
        }
        return Container(width:46,height:46,
          decoration:BoxDecoration(
            borderRadius:BorderRadius.circular(10),
            color:MediaPalette.orange.withValues(alpha:.12)),
          child:Icon(m.audio?Icons.music_note_rounded:
            m.video?Icons.ondemand_video_rounded:Icons.image_outlined,
            color:MediaPalette.orange));
      });
  }
  Widget _tile(PhoneMedia m,List<PhoneMedia> group)=>Card(
    child:ListTile(contentPadding:const EdgeInsets.symmetric(
      horizontal:10,vertical:4),
      leading:_thumb(m),
      title:Text(widget.library.customTitles[m.uri]??m.name,
        maxLines:2,overflow:TextOverflow.ellipsis,
        style:const TextStyle(fontWeight:FontWeight.w800,fontSize:13)),
      subtitle:Text(
        '${m.artist.isNotEmpty?m.artist+' • ':''}'
        '${m.folder.isNotEmpty?m.folder+' • ':''}'
        '${MediaUtils.displaySize(m.size)}',
        maxLines:1,overflow:TextOverflow.ellipsis),
      onTap:()=>playMedia(m,group),
      trailing:PopupMenuButton<String>(
        onSelected:(value){
          if(value=='favorite'){widget.library.toggleFavorite(m.uri);}
          if(value=='playlist')_addToPlaylist(m.uri);
          if(value=='info')_info(m);
        },
        itemBuilder:(ctx)=>[
          PopupMenuItem(value:'favorite',
            child:Text(widget.library.isFavorite(m.uri)?
              'إزالة من المفضلة':'أضف للمفضلة')),
          if(m.audio)const PopupMenuItem(value:'playlist',
            child:Text('إضافة لقائمة تشغيل')),
          const PopupMenuItem(value:'info',
            child:Text('تفاصيل الملف')),
        ]),
    ),
  );
  void _info(PhoneMedia m){
    showModalBottomSheet<void>(context:context,builder:(ctx)=>SafeArea(
      child:Padding(padding:const EdgeInsets.all(18),
        child:Column(mainAxisSize:MainAxisSize.min,
          crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(m.name,style:Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height:12),
          for(final line in [
            'المجلد: ${m.folder}','الفنان: ${m.artist}',
            'الألبوم: ${m.album}','النوع: ${m.mime}',
            'الحجم: ${MediaUtils.displaySize(m.size)}',
            'مرات التشغيل: ${widget.library.playCount[m.uri]??0}'
          ])Padding(padding:const EdgeInsets.symmetric(vertical:3),
            child:Text(line)),
          const SizedBox(height:10),
          FilledButton(onPressed:()=>Navigator.pop(ctx),
            child:const Text('إغلاق')),
        ]))));
  }
  void _addToPlaylist(String uri){
    showModalBottomSheet<void>(context:context,builder:(ctx)=>SafeArea(
      child:ListView(shrinkWrap:true,padding:const EdgeInsets.all(15),children:[
        Text('اختر قائمة التشغيل',
          style:Theme.of(ctx).textTheme.titleLarge),
        for(final p in widget.library.playlists)
          ListTile(title:Text(p.name),
            onTap:(){widget.library.appendToPlaylist(p,uri);
              Navigator.pop(ctx);}),
        TextButton.icon(icon:const Icon(Icons.add),
          label:const Text('إنشاء قائمة جديدة'),
          onPressed:(){Navigator.pop(ctx);_createPlaylist(uri);}),
      ])));
  }
  Future<void> _createPlaylist([String? initial]) async {
    final controller=TextEditingController();
    final name=await showDialog<String>(context:context,builder:(ctx)=>
      AlertDialog(title:const Text('قائمة تشغيل جديدة'),
        content:TextField(controller:controller,
          decoration:const InputDecoration(hintText:'اسم القائمة')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),
            child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text),
            child:const Text('إنشاء')),
        ]));
    controller.dispose();
    if(name==null||name.trim().isEmpty)return;
    try{
      final p=widget.library.createPlaylist(name);
      if(initial!=null)widget.library.appendToPlaylist(p,initial);
      setState((){});
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text('$e')));}
  }
  void _openPlaylist(Playlist p){
    final items=p.items.map(widget.phone.byUri)
      .whereType<PhoneMedia>().toList();
    Navigator.of(context).push(MaterialPageRoute<void>(builder:(ctx)=>
      Scaffold(appBar:AppBar(title:Text(p.name),actions:[
        IconButton(tooltip:'تشغيل الكل',
          icon:const Icon(Icons.play_circle),
          onPressed:items.isEmpty?null:()=>playMedia(items.first,items)),
      ]),
      body:ReorderableListView.builder(
        itemCount:p.items.length,
        onReorder:(a,b){widget.library.reorder(p,a,b);
          setState((){});},
        itemBuilder:(ctx,i){
          final uri=p.items[i],item=widget.phone.byUri(uri);
          return ListTile(key:ValueKey(uri),title:Text(item?.name??'ملف غير موجود'),
            leading:const Icon(Icons.drag_handle),
            subtitle:Text(item?.artist??uri,maxLines:1),
            onTap:item==null?null:()=>playMedia(item,items),
            trailing:IconButton(icon:const Icon(Icons.remove_circle_outline),
              onPressed:(){widget.library.removeFromPlaylist(p,uri);
                Navigator.pop(ctx);_openPlaylist(p);}),
          );
        }),
    )));
  }
  Widget _dashboard(){
    final recent=widget.phone.all.take(14).toList();
    final favorites=widget.phone.all.where((x)=>
      widget.library.isFavorite(x.uri)).toList();
    final most=widget.library.mostPlayed().map(widget.phone.byUri)
      .whereType<PhoneMedia>().toList();
    final pending=widget.phone.videos.where((x)=>
      (widget.library.resume[x.uri]??0)>0).toList();
    return ListView(padding:const EdgeInsets.all(14),children:[
      Row(children:[
        Expanded(child:_stat('الصوت',widget.phone.audio.length,
          Icons.music_note,()=>setState(()=>selected=1))),
        const SizedBox(width:9),
        Expanded(child:_stat('الفيديو',widget.phone.videos.length,
          Icons.movie_outlined,()=>setState(()=>selected=2))),
        const SizedBox(width:9),
        Expanded(child:_stat('الصور',widget.phone.images.length,
          Icons.image_outlined,()=>setState(()=>selected=3))),
      ]),
      const SizedBox(height:18),
      _section('أكمل المشاهدة',pending),
      _section('المفضلة',favorites),
      _section('الأكثر تشغيلًا',most),
      _section('المضافة حديثًا',recent),
      const SizedBox(height:16),
      _group('قوائم التشغيل',Icons.queue_music,widget.library.playlists.length,
        _playlists),
      _group('الفنانون',Icons.person_outline,widget.phone.artists.length,
        ()=>_groups('الفنانون',widget.phone.artists)),
      _group('الألبومات',Icons.album_outlined,widget.phone.albums.length,
        ()=>_groups('الألبومات',widget.phone.albums)),
      _group('مجلدات الهاتف',Icons.folder_outlined,widget.phone.folders.length,
        ()=>_groups('المجلدات',widget.phone.folders)),
      _group('البحث عن ملفات مكررة',Icons.copy_all_outlined,0,_duplicates),
      const SizedBox(height:80),
    ]);
  }
  Widget _stat(String label,int count,IconData icon,VoidCallback onTap)=>
    InkWell(onTap:onTap,borderRadius:BorderRadius.circular(18),
      child:Container(padding:const EdgeInsets.symmetric(vertical:14),
        decoration:BoxDecoration(
          color:Theme.of(context).colorScheme.surfaceContainerLow,
          border:Border.all(color:Theme.of(context).dividerColor),
          borderRadius:BorderRadius.circular(18)),
        child:Column(children:[
          Icon(icon,color:MediaPalette.orange,size:27),
          const SizedBox(height:8),
          Text(count.toString(),style:const TextStyle(
            fontWeight:FontWeight.w900,fontSize:19)),
          Text(label,style:const TextStyle(fontSize:11)),
        ])));
  Widget _section(String title,List<PhoneMedia> list){
    if(list.isEmpty)return const SizedBox.shrink();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Padding(padding:const EdgeInsets.symmetric(vertical:12),
        child:Text(title,style:Theme.of(context).textTheme.titleLarge)),
      SizedBox(height:118,child:ListView.separated(
        scrollDirection:Axis.horizontal,itemCount:list.take(15).length,
        separatorBuilder:(_,__)=>const SizedBox(width:9),
        itemBuilder:(ctx,i){
          final m=list[i];
          return InkWell(onTap:()=>playMedia(m,list),
            child:SizedBox(width:100,child:Column(children:[
              SizedBox(width:89,height:78,child:Center(child:_thumb(m))),
              const SizedBox(height:6),
              Text(m.name,maxLines:1,overflow:TextOverflow.ellipsis,
                style:const TextStyle(fontSize:11,fontWeight:FontWeight.w700)),
            ])));
        })),
    ]);
  }
  Widget _group(String title,IconData icon,int count,VoidCallback tap)=>
    Card(child:ListTile(
      leading:Icon(icon,color:MediaPalette.orange),
      title:Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),
      subtitle:count>0?Text('$count'):null,
      trailing:const Icon(Icons.chevron_left),
      onTap:tap,
    ));
  void _groups(String title,Map<String,List<PhoneMedia>> groups){
    Navigator.push(context,MaterialPageRoute<void>(builder:(ctx)=>
      Scaffold(appBar:AppBar(title:Text(title)),
        body:ListView(children:[
          for(final entry in groups.entries)
            ListTile(leading:const Icon(Icons.folder_outlined,
              color:MediaPalette.orange),
              title:Text(entry.key),
              subtitle:Text('${entry.value.length} ملف'),
              onTap:()=>showItems(entry.key,entry.value)),
        ]))));
  }
  void _playlists(){
    Navigator.push(context,MaterialPageRoute<void>(builder:(ctx)=>
      Scaffold(appBar:AppBar(title:const Text('قوائم التشغيل'),
        actions:[IconButton(icon:const Icon(Icons.add),
          onPressed:_createPlaylist)]),
        body:AnimatedBuilder(animation:widget.library,builder:(ctx,_)=>
          ListView(children:[
            for(final p in widget.library.playlists)
              ListTile(
                leading:const Icon(Icons.queue_music,color:MediaPalette.orange),
                title:Text(p.name),
                subtitle:Text('${p.items.length} عنصر'),
                onTap:()=>_openPlaylist(p),
                trailing:IconButton(icon:const Icon(Icons.delete_outline),
                  onPressed:(){widget.library.deletePlaylist(p);}),
              ),
            ListTile(leading:const Icon(Icons.add_circle_outline),
              title:const Text('قائمة جديدة'),onTap:_createPlaylist),
          ])))));
  }
  void _duplicates() async {
    showDialog<void>(context:context,barrierDismissible:false,
      builder:(ctx)=>const Center(child:CircularProgressIndicator()));
    try {
      final groups=await widget.phone.findDuplicates();
      if(!mounted)return;
      Navigator.pop(context);
      Navigator.push(context,MaterialPageRoute<void>(builder:(ctx)=>
        Scaffold(appBar:AppBar(title:const Text('الملفات المكررة')),
          body:ListView(children:[
            const Padding(padding:EdgeInsets.all(16),
              child:Text('المقارنة هنا ببصمة SHA-256، ولا يتم حذف الملفات '
                'الأصلية تلقائيًا. يمكنك فتح الملفات للتحقق منها.')),
            if(groups.isEmpty)const ListTile(
              title:Text('لم يُكتشف تكرار في الملفات المفحوصة')),
            for(final group in groups)
              Card(child:Column(children:[
                ListTile(title:Text('${group.length} نسخ متطابقة')),
                for(final uri in group)
                  ListTile(title:Text(widget.phone.byUri(uri)?.name??uri),
                    subtitle:Text(widget.phone.byUri(uri)?.folder??''),
                    onTap:(){
                      final media=widget.phone.byUri(uri);
                      if(media!=null)playMedia(media);
                    }),
              ])),
          ]))));
    }catch(e){
      if(mounted){Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text('فشل فحص التكرار: $e')));}
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('المكتبة'),
      actions:[
        IconButton(icon:const Icon(Icons.refresh),
          tooltip:'تحديث فهرس الهاتف',onPressed:widget.phone.refresh),
        IconButton(icon:const Icon(Icons.queue_music),
          tooltip:'قوائم التشغيل',onPressed:_playlists),
      ]),
    body:AnimatedBuilder(animation:Listenable.merge([
      widget.phone,widget.library]),builder:(ctx,_){
      if(!widget.phone.audioGranted&&!widget.phone.videoGranted&&
          !widget.phone.imageGranted){
        return Center(child:Padding(padding:const EdgeInsets.all(25),
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.perm_media_outlined,size:80,
              color:MediaPalette.orange),
            const SizedBox(height:17),
            const Text('مكتبتك كلها في مكان واحد',
              style:TextStyle(fontSize:23,fontWeight:FontWeight.w900)),
            const SizedBox(height:9),
            const Text('اسمح بالوصول للصور والصوت والفيديو '
              'عشان يظهروا تلقائيًا من فهرس أندرويد.',
              textAlign:TextAlign.center),
            const SizedBox(height:19),
            FilledButton.icon(
              onPressed:()=>widget.phone.refresh(askPermissions:true),
              icon:const Icon(Icons.shield_outlined),
              label:const Text('تفعيل أذونات المكتبة')),
            if(widget.phone.error!=null)Text(widget.phone.error!),
          ])));
      }
      return Column(children:[
        Padding(padding:const EdgeInsets.symmetric(horizontal:12),
          child:TextField(controller:search,
            onChanged:(_)=>setState((){}),
            decoration:const InputDecoration(
              prefixIcon:Icon(Icons.search),
              hintText:'ابحث عن ملف، فنان، ألبوم أو مجلد')),
        ),
        const SizedBox(height:8),
        SingleChildScrollView(scrollDirection:Axis.horizontal,
          padding:const EdgeInsets.symmetric(horizontal:8),
          child:Row(children:[
            for(final entry in [
              ('الرئيسية',0),('الأغاني',1),('الفيديو',2),
              ('الصور',3),('الملفات',4)])
              Padding(padding:const EdgeInsets.symmetric(horizontal:3),
                child:ChoiceChip(label:Text(entry.$1),
                  selected:selected==entry.$2,
                  onSelected:(_)=>setState(()=>selected=entry.$2))),
          ])),
        if(widget.phone.loading)const LinearProgressIndicator(),
        if(widget.phone.error!=null)Text(widget.phone.error!),
        Expanded(child:selected==0?_dashboard():
          selected==4?LibraryScreen(
            library:widget.library,music:widget.music):
          Column(children:[
            Padding(padding:const EdgeInsets.symmetric(horizontal:12),
              child:Row(children:[
                Text('${current.length} عنصر'),
                const Spacer(),
                DropdownButton<String>(
                  value:sort,underline:const SizedBox.shrink(),
                  items:const ['الأحدث','الاسم','الحجم','المدة','الأكثر تشغيلًا']
                    .map((x)=>DropdownMenuItem(value:x,child:Text(x)))
                    .toList(),
                  onChanged:(v)=>setState(()=>sort=v??'الأحدث')),
              ])),
            Expanded(child:RefreshIndicator(
              onRefresh:widget.phone.refresh,
              child:ListView.separated(
                padding:const EdgeInsets.fromLTRB(12,3,12,95),
                itemCount:current.length,
                separatorBuilder:(_,__)=>const SizedBox(height:7),
                itemBuilder:(ctx,i)=>_tile(current[i],current),
              ))),
          ])),
      ]);
    }),
  );
}

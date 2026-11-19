import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'library.dart';
import 'media_utils.dart';
import 'player.dart';
import 'theme.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key,required this.library,required this.music});
  final MediaLibrary library;
  final BackgroundMusic music;
  @override
  State<LibraryScreen> createState()=>_LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final search=TextEditingController();
  String kind='all';
  bool loading=false;
  @override
  void dispose(){search.dispose();super.dispose();}

  Future<void> _import() async {
    setState(()=>loading=true);
    try {
      final picked=await FilePicker.pickFiles(type:FileType.any);
      if(picked.isEmpty)return;
      var count=0;
      for(final file in picked){
        if(file.path!=null){
          await widget.library.importFile(file.path!,file.name);
          count++;
        }
      }
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('تمت إضافة $count ملف إلى مكتبتك الخاصة.')));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('تعذر استيراد الملفات: $e')));
    }finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> _remove(SavedMedia file) async {
    final yes=await showDialog<bool>(context:context,
      builder:(ctx)=>AlertDialog(
        title:const Text('حذف النسخة المستوردة؟'),
        content:Text('هتحذف نسخة ${file.name} من مكتبة التطبيق فقط. '
          'الأصل الموجود في الهاتف لن يتأثر.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:const Text('حذف')),
        ]),
    );
    if(yes==true) {
      await widget.library.removeFile(file);
    }
  }
  Future<void> _open(SavedMedia file) async =>
    openMedia(context,widget.music,file.path,file.name);

  bool _visible(SavedMedia m){
    final name=m.name.toLowerCase();
    if(!name.contains(search.text.trim().toLowerCase()))return false;
    return switch(kind){
      'video'=>MediaUtils.isVideo(name),
      'audio'=>MediaUtils.isAudio(name),
      'image'=>MediaUtils.isImage(name),
      'files'=>!MediaUtils.isVideo(name)&&
        !MediaUtils.isAudio(name)&&!MediaUtils.isImage(name),
      _=>true,
    };
  }
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('مكتبتي'),
      actions:[
        IconButton(tooltip:'أضف ملفات من الهاتف',
          onPressed:loading?null:_import,
          icon:const Icon(Icons.add_circle_outline)),
      ]),
    floatingActionButton:FloatingActionButton.extended(
      onPressed:loading?null:_import,
      backgroundColor:MediaPalette.orange,foregroundColor:Colors.white,
      icon:const Icon(Icons.add),
      label:const Text('استيراد ملفات')),
    body:AnimatedBuilder(animation:widget.library,builder:(context,_) {
      final records=widget.library.files.where(_visible).toList();
      return Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(14,4,14,12),
          child:TextField(
            controller:search,onChanged:(_)=>setState((){}),
            decoration:const InputDecoration(
              hintText:'ابحث بين ملفاتك',
              prefixIcon:Icon(Icons.search_rounded)),
          )),
        SingleChildScrollView(scrollDirection:Axis.horizontal,
          padding:const EdgeInsets.symmetric(horizontal:12),
          child:Row(children:[
            for(final item in [
              ('all','الكل',Icons.apps),
              ('video','فيديو',Icons.movie),
              ('audio','صوت',Icons.music_note),
              ('image','صور',Icons.image),
              ('files','ملفات',Icons.insert_drive_file),
            ])
              Padding(padding:const EdgeInsets.only(left:6),child:ChoiceChip(
                selected:kind==item.$1,
                onSelected:(_)=>setState(()=>kind=item.$1),
                label:Text(item.$2),
                avatar:Icon(item.$3,size:16,
                  color:kind==item.$1?MediaPalette.orange:null))),
          ]),
        ),
        const SizedBox(height:10),
        Expanded(child:loading?
          const Center(child:CircularProgressIndicator()) :
          records.isEmpty?
          Center(child:Padding(padding:const EdgeInsets.all(28),
            child:Column(mainAxisSize:MainAxisSize.min,children:[
              Icon(Icons.perm_media_outlined,size:72,
                color:MediaPalette.orange.withValues(alpha:.8)),
              const SizedBox(height:18),
              const Text('مكتبتك جاهزة للملفات',
                style:TextStyle(fontWeight:FontWeight.w900,fontSize:19)),
              const SizedBox(height:7),
              const Text('اختار صور وفيديوهات وأغاني وملفات من مدير ملفات '
                'أندرويد. التطبيق بيحفظ نسخة خاصة تقدر تشغّلها وتنظّمها.',
                textAlign:TextAlign.center),
            ]),
          )):
          ListView.separated(
            padding:const EdgeInsets.fromLTRB(14,3,14,115),
            itemCount:records.length,
            separatorBuilder:(_,__)=>const SizedBox(height:9),
            itemBuilder:(ctx,i){
              final m=records[i];
              return Card(child:Padding(padding:const EdgeInsets.all(8),
                child:Row(children:[
                  ClipRRect(borderRadius:BorderRadius.circular(12),
                    child:SizedBox(width:64,height:64,
                      child:MediaUtils.isImage(m.name)?
                        Image.file(File(m.path),fit:BoxFit.cover,
                          errorBuilder:(_,__,___)=>const Icon(Icons.image)):
                        ColoredBox(
                          color:MediaPalette.orange.withValues(alpha:.12),
                          child:Icon(MediaUtils.isVideo(m.name)?
                            Icons.movie_rounded:
                            MediaUtils.isAudio(m.name)?
                              Icons.graphic_eq_rounded:
                              Icons.insert_drive_file_rounded,
                            size:33,color:MediaPalette.orange)),
                    )),
                  const SizedBox(width:11),
                  Expanded(child:Column(
                    crossAxisAlignment:CrossAxisAlignment.start,
                    children:[
                      Text(m.name,maxLines:2,overflow:TextOverflow.ellipsis,
                        style:const TextStyle(fontWeight:FontWeight.w900)),
                      const SizedBox(height:4),
                      FutureBuilder<int>(
                        future:File(m.path).length(),
                        builder:(ctx,size)=>Text(
                          size.hasData?MediaUtils.displaySize(size.data!):
                            'ملف محلي',
                          style:Theme.of(ctx).textTheme.bodySmall),
                      ),
                    ])),
                  IconButton(tooltip:'فتح الملف',
                    onPressed:()=>_open(m),
                    icon:const Icon(Icons.play_circle_outline,
                      color:MediaPalette.orange)),
                  PopupMenuButton<String>(
                    onSelected:(v)async {
                      if(v=='delete')await _remove(m);
                      else if(v=='share') {
                        try { await DownloadBridge.shareLocal(m.path,m.name); }
                        catch(e){if(context.mounted)ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content:Text('$e')));}
                      }
                    },
                    itemBuilder:(_)=>const [
                      PopupMenuItem(value:'share',child:Text('مشاركة نسخة الملف')),
                      PopupMenuItem(value:'delete',child:Text('حذف النسخة المستوردة')),
                    ],
                  ),
                ]),
              ));
            },
          )),
      ]);
    }),
  );
}

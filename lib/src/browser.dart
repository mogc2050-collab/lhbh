import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'link_inspector.dart';
import 'library.dart';
import 'media_utils.dart';
import 'player.dart';
import 'theme.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key,required this.library,
    required this.music,this.initialUrl});
  final MediaLibrary library;
  final BackgroundMusic music;
  final String? initialUrl;
  @override
  State<BrowserScreen> createState()=>_BrowserScreenState();
}

class _TabData {
  _TabData(this.controller,this.url);
  final WebViewController controller;
  String url;
  String title='صفحة جديدة';
  bool loading=false;
  int progress=0;
}

class _BrowserScreenState extends State<BrowserScreen> {
  final address=TextEditingController();
  final List<_TabData> tabs=[];
  int active=0;
  String? loadError;
  _TabData get tab=>tabs[active];

  @override
  void initState() {
    super.initState();
    _newTab(widget.initialUrl ?? 'https://www.google.com/');
  }
  @override
  void dispose(){address.dispose();super.dispose();}

  void _newTab(String url){
    late final _TabData item;
    final controller=WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xffffffff));
    item=_TabData(controller,url);
    if(controller.platform is AndroidWebViewController){
      (controller.platform as AndroidWebViewController)
        .setMediaPlaybackRequiresUserGesture(false);
    }
    controller.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest:(request) {
        final uri=Uri.tryParse(request.url);
        if(uri!=null && MediaUtils.isDirectFile(uri) &&
            MediaUtils.canDownload(uri)){
          WidgetsBinding.instance.addPostFrameCallback((_){
            if(mounted)_fileLink(uri);
          });
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      },
      onProgress:(value) {
        item.progress=value;
        if(mounted && tab==item)setState((){});
      },
      onPageStarted:(url) {
        item.loading=true;item.url=url;
        if(mounted && tab==item){
          setState(()=>loadError=null);
          address.text=url;
        }
      },
      onPageFinished:(url) async {
        item.loading=false;item.url=url;
        final title=await controller.getTitle();
        item.title=title??Uri.tryParse(url)?.host??'صفحة ويب';
        widget.library.visited(url);
        if(mounted && tab==item){
          address.text=url;
          setState((){});
        }
      },
      onWebResourceError:(error){
        if(error.isForMainFrame == true && mounted && tab==item){
          setState(()=>loadError=error.description);
        }
      },
    ));
    tabs.add(item);active=tabs.length-1;
    address.text=url;
    if(mounted)setState((){});
    controller.loadRequest(MediaUtils.interpretAddress(url));
  }
  void _switchTab(int i){
    if(i<0||i>=tabs.length)return;
    setState((){
      active=i;address.text=tab.url;loadError=null;
    });
  }
  void _closeTab(int i){
    if(tabs.length==1){
      _go('https://www.google.com/');
      return;
    }
    setState((){
      tabs.removeAt(i);
      active=active.clamp(0,tabs.length-1).toInt();
      address.text=tab.url;
    });
  }
  void _go(String query) {
    final url=MediaUtils.interpretAddress(query);
    if(MediaUtils.isYouTube(url) && url.host.contains('youtube.com')) {
      // Browsing as guest is supported; Google OAuth is NOT supported in
      // Android WebView. An explicit external sign-in button is provided.
    }
    FocusScope.of(context).unfocus();
    address.text=url.toString();
    tab.url=url.toString();
    tab.controller.loadRequest(url);
    widget.library.visited(url.toString());
  }
  Future<void> _fileLink(Uri uri) async {
    if(!mounted)return;
    showModalBottomSheet<void>(context:context,builder:(sheet)=>SafeArea(
      child:Padding(padding:const EdgeInsets.all(18),child:Column(
        mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,
        children:[
          Text(MediaUtils.fileTitle(uri),maxLines:2,overflow:TextOverflow.ellipsis,
            style:Theme.of(sheet).textTheme.titleLarge),
          const SizedBox(height:6),
          const Text('اختر إجراءً لهذا الملف المباشر. المحتوى المحمي أو غير المسموح '
            'بتنزيله ليس مدعومًا.'),
          const SizedBox(height:14),
          FilledButton.icon(
            icon:const Icon(Icons.download),
            label:const Text('تنزيل في الخلفية'),
            onPressed:() async {
              Navigator.pop(sheet);
              await _download(uri);
            }),
          if(MediaUtils.isVideo(uri.path)) TextButton.icon(
            icon:const Icon(Icons.play_circle),
            label:const Text('شغّل الفيديو من الرابط'),
            onPressed:(){
              Navigator.pop(sheet);
              Navigator.of(context).push(MaterialPageRoute(
                builder:(_)=>VideoDetail(source:uri.toString(),
                  title:MediaUtils.fileTitle(uri),network:true)));
            }),
          TextButton(onPressed:()=>Navigator.pop(sheet),
            child:const Text('إلغاء')),
        ],
      )),
    ));
  }

  Future<void> _download(Uri uri) async {
    try {
      final record=await widget.library.addDownload(
        uri.toString(),filename:MediaUtils.fileTitle(uri));
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('بدأ تنزيل ${record.title} في الخلفية.')));
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('لم يبدأ التنزيل: $e')));
    }
  }

  Future<void> _scanPage() async {
    try{
      // Lists user-visible direct anchors only; does not extract streams,
      // decrypt DRM, or access any site-protected media.
      final result=await tab.controller.runJavaScriptReturningResult(
        r"""JSON.stringify(Array.from(document.querySelectorAll('a[href]'))
          .map(a => ({name:(a.textContent||'').trim().slice(0,70),
                       url:a.href}))
          .filter(x => /\\.(mp3|m4a|wav|ogg|mp4|m4v|webm|mov|pdf|zip|png|jpg|jpeg|gif|epub)(\\?|#|$)/i.test(x.url))
          .slice(0,100))"""
      );
      dynamic parsed=jsonDecode(result.toString());
      if(parsed is String)parsed=jsonDecode(parsed);
      final links=(parsed as List? ?? []).whereType<Map>().map((m)=>(
        title:(m['name'] as String? ?? '').trim(),
        url:m['url'] as String? ?? '',
      )).where((m){
        final u=Uri.tryParse(m.url);
        return u!=null&&MediaUtils.canDownload(u);
      }).toList();
      if(!mounted)return;
      showModalBottomSheet<void>(context:context,isScrollControlled:true,
        builder:(ctx)=>SafeArea(child:FractionallySizedBox(
          heightFactor:.74,child:Padding(
            padding:const EdgeInsets.all(16),
            child:Column(children:[
              Text('الملفات المباشرة في الصفحة',
                style:Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height:8),
              const Text('الروابط المسموح بها والظاهرة في الصفحة فقط. '
                'مواقع البث المشفّر ليست مصادر تنزيل مباشرة.'),
              const SizedBox(height:10),
              Expanded(child:links.isEmpty?
                const Center(child:Text('لا توجد روابط ملفات مباشرة قابلة للتنزيل.')):
                ListView.builder(itemCount:links.length,
                  itemBuilder:(ctx,i){
                    final link=links[i];
                    return ListTile(
                      leading:const Icon(Icons.insert_drive_file_outlined,
                        color:MediaPalette.orange),
                      title:Text(link.title.isEmpty?
                        MediaUtils.fileTitle(Uri.parse(link.url)):link.title,
                        maxLines:2,overflow:TextOverflow.ellipsis),
                      subtitle:Text(link.url,maxLines:1,
                        overflow:TextOverflow.ellipsis),
                      trailing:IconButton(
                        icon:const Icon(Icons.download_rounded),
                        onPressed:(){
                          Navigator.pop(ctx);
                          _download(Uri.parse(link.url));
                        }),
                    );
                  }),
              ),
            ]),
          ),
        )));
    } catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('تعذر قراءة روابط الصفحة: $e')));
    }
  }

  Future<void> _openYouTubeAccount() async {
    final url=Uri.parse('https://www.youtube.com/');
    final success=await launchUrl(url,mode:LaunchMode.externalApplication);
    if(!success && mounted)ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content:Text('لم يتوفر متصفح آمن لفتح يوتيوب.')));
  }

  void _tabsSheet(){
    showModalBottomSheet<void>(context:context,builder:(ctx)=>SafeArea(
      child:Padding(padding:const EdgeInsets.all(16),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          Row(children:[
            Text('علامات التبويب',style:Theme.of(ctx).textTheme.titleLarge),
            const Spacer(),
            IconButton(icon:const Icon(Icons.add),
              onPressed:(){
                Navigator.pop(ctx);
                _newTab('https://www.google.com/');
              }),
          ]),
          Flexible(child:ListView.builder(
            shrinkWrap:true,itemCount:tabs.length,
            itemBuilder:(ctx,i)=>ListTile(
              selected:i==active,
              leading:const Icon(Icons.language),
              title:Text(tabs[i].title,maxLines:1,
                overflow:TextOverflow.ellipsis),
              subtitle:Text(tabs[i].url,maxLines:1,
                overflow:TextOverflow.ellipsis),
              trailing:IconButton(icon:const Icon(Icons.close),
                onPressed:(){
                  _closeTab(i);
                  Navigator.pop(ctx);
                }),
              onTap:(){_switchTab(i);Navigator.pop(ctx);},
            ),
          )),
        ]),
      ),
    ));
  }

  void _menu(){
    showModalBottomSheet<void>(context:context,builder:(ctx)=>SafeArea(
      child:Column(mainAxisSize:MainAxisSize.min,children:[
        ListTile(leading:const Icon(Icons.youtube_searched_for),
          title:const Text('افتح يوتيوب بحساب Google في المتصفح الآمن'),
          subtitle:const Text('تسجيل Google داخل WebView غير مدعوم.'),
          onTap:(){Navigator.pop(ctx);_openYouTubeAccount();}),
        ListTile(leading:const Icon(Icons.search_rounded),
          title:const Text('اكتشف روابط الملفات المباشرة'),
          onTap:(){Navigator.pop(ctx);_scanPage();}),
        ListTile(leading:const Icon(Icons.open_in_browser),
          title:const Text('افتح الصفحة في متصفح النظام'),
          onTap:(){
            Navigator.pop(ctx);
            launchUrl(Uri.parse(tab.url),mode:LaunchMode.externalApplication);
          }),
        ListTile(leading:const Icon(Icons.content_paste_search_rounded),
          title:const Text('حلّل رابط فيديو أو صوت'),
          onTap:(){
            Navigator.pop(ctx);
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder:(_)=>SmartLinkScreen(
                library:widget.library,music:widget.music,
                browse:_go)));
          }),
        ListTile(leading:const Icon(Icons.file_download_outlined),
          title:const Text('تنزيل من رابط مباشر'),
          onTap:(){
            Navigator.pop(ctx);
            _linkDialog();
          }),
        ListTile(leading:const Icon(Icons.add_box_outlined),
          title:const Text('تبويب جديد'),
          onTap:(){Navigator.pop(ctx);_newTab('https://www.google.com/');}),
      ]),
    ));
  }

  Future<void> _linkDialog() async {
    final input=TextEditingController();
    final result=await showDialog<String>(context:context,
      builder:(ctx)=>AlertDialog(
        title:const Text('تنزيل ملف مباشر'),
        content:TextField(controller:input,
          keyboardType:TextInputType.url,
          decoration:const InputDecoration(
            labelText:'رابط HTTPS للملف',hintText:'https://site.com/file.mp4')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx),
            child:const Text('إلغاء')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,input.text.trim()),
            child:const Text('تنزيل')),
        ],
      ));
    input.dispose();
    if(result==null||result.isEmpty)return;
    final uri=Uri.tryParse(result);
    if(uri==null||!MediaUtils.canDownload(uri)){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('ضع رابطًا مباشرًا مسموحًا بتنزيله.')));
      return;
    }
    await _download(uri);
  }

  @override
  Widget build(BuildContext context) {
    final colors=Theme.of(context).colorScheme;
    return Scaffold(
      appBar:AppBar(title:const Text('المتصفح'),
        actions:[
          IconButton(tooltip:'المفضلة',
            onPressed:()=>widget.library.toggleBookmark(tab.url),
            icon:Icon(widget.library.starred(tab.url)?
              Icons.bookmark:Icons.bookmark_border,
              color:MediaPalette.orange)),
          IconButton(tooltip:'القائمة',
            onPressed:_menu,icon:const Icon(Icons.more_vert)),
        ]),
      body:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(12,0,12,10),
          child:Row(children:[
            Expanded(child:TextField(
              controller:address,
              keyboardType:TextInputType.url,
              textInputAction:TextInputAction.go,
              onSubmitted:_go,
              textDirection:TextDirection.ltr,
              decoration:InputDecoration(
                prefixIcon:const Icon(Icons.lock_outline_rounded,size:19),
                suffixIcon:IconButton(
                  tooltip:'افتح الرابط',
                  icon:const Icon(Icons.arrow_forward_rounded),
                  onPressed:()=>_go(address.text)),
                hintText:'ابحث أو الصق رابط موقع',
              ),
            )),
            const SizedBox(width:6),
            IconButton(onPressed:()=>_go(address.text),
              tooltip:'بحث',icon:const Icon(Icons.search)),
          ]),
        ),
        if(tab.loading)LinearProgressIndicator(
          value:tab.progress/100,minHeight:2,
          color:MediaPalette.orange),
        Expanded(child:Stack(children:[
          // IndexedStack retains actual WebView navigation state per tab.
          Positioned.fill(child:IndexedStack(index:active,children:[
            for(final page in tabs)WebViewWidget(controller:page.controller),
          ])),
          if(loadError!=null) Positioned(
            left:12,right:12,top:14,
            child:Card(child:ListTile(
              leading:const Icon(Icons.error_outline),
              title:const Text('الصفحة لم تُحمّل بالكامل'),
              subtitle:Text(loadError!),
              trailing:IconButton(icon:const Icon(Icons.refresh),
                onPressed:()=>tab.controller.reload()),
            )),
          ),
        ])),
        Container(
          decoration:BoxDecoration(
            color:colors.surface,
            border:Border(top:BorderSide(color:Theme.of(context).dividerColor)),
          ),
          child:SafeArea(top:false,
            child:Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,
              children:[
                IconButton(tooltip:'رجوع',icon:const Icon(Icons.arrow_back),
                  onPressed:() async {
                    if(await tab.controller.canGoBack()){
                      await tab.controller.goBack();
                    }
                  }),
                IconButton(tooltip:'التالي',
                  icon:const Icon(Icons.arrow_forward),
                  onPressed:() async {
                    if(await tab.controller.canGoForward()){
                      await tab.controller.goForward();
                    }
                  }),
                IconButton(tooltip:'تحديث',
                  icon:Icon(tab.loading?Icons.close:Icons.refresh),
                  onPressed:(){
                    if(tab.loading){tab.controller.runJavaScript('window.stop()');}
                    else{tab.controller.reload();}
                  }),
                IconButton(tooltip:'تنزيلات الصفحة',
                  icon:const Icon(Icons.download_for_offline_outlined),
                  onPressed:_scanPage),
                Badge(label:Text('${tabs.length}'),
                  child:IconButton(tooltip:'التبويبات',
                    icon:const Icon(Icons.tab),onPressed:_tabsSheet)),
              ]),
          ),
        ),
      ]),
    );
  }
}

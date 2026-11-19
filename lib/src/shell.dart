import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:url_launcher/url_launcher.dart';
import 'browser.dart';
import 'device_media.dart';
import 'media_collection_screen.dart';
import 'link_inspector.dart';
import 'downloads_screen.dart';
import 'library.dart';
import 'library_screen.dart';
import 'media_utils.dart';
import 'player.dart';
import 'theme.dart';

class MediaShell extends StatefulWidget {
  const MediaShell({super.key,required this.library,required this.music});
  final MediaLibrary library;
  final BackgroundMusic music;
  @override
  State<MediaShell> createState()=>_MediaShellState();
}

class _MediaShellState extends State<MediaShell> {
  int selected=0;
  int browserGeneration=0;
  String browserUrl='https://www.google.com/';
  GoogleSignInAccount? account;
  bool googleBusy=false;
  bool googleReady=false;
  final PhoneLibrary phone=PhoneLibrary();

  @override
  void initState(){
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_){
      if(mounted)phone.refresh();
    });
  }
  @override
  void dispose(){
    phone.dispose();
    super.dispose();
  }

  void analyzeLink(){
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder:(_)=>SmartLinkScreen(
        library:widget.library,music:widget.music,browse:browse)));
  }

  static const webClientId=String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',defaultValue:'');

  void browse(String url){
    setState((){
      selected=1;browserUrl=url;browserGeneration++;
    });
  }

  Future<void> googleLogin() async {
    if(webClientId.isEmpty){
      if(!mounted)return;
      showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('إعداد تسجيل Google'),
        content:const Text('الكود جاهز لتسجيل الدخول بحساب Google بشكل رسمي، '
          'لكن لازم تضيف Google OAuth Web Client ID إلى GitHub Actions Secrets، '
          'وتسجّل بصمة SHA-1 الخاصة بتوقيع Android في Google Cloud. '
          'بدون ده، تسجيل الدخول مش هيشتغل. '
          'يوتيوب بحسابك يفتح من متصفح النظام الآمن.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),
          child:const Text('فهمت'))],
      ));
      return;
    }
    setState(()=>googleBusy=true);
    try{
      if(!googleReady){
        await GoogleSignIn.instance.initialize(serverClientId:webClientId);
        googleReady=true;
      }
      final signed=await GoogleSignIn.instance.authenticate();
      if(mounted)setState(()=>account=signed);
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text('تعذر تسجيل Google: $e')));
    }finally{if(mounted)setState(()=>googleBusy=false);}
  }

  Future<void> signOut() async {
    try{await GoogleSignIn.instance.signOut();}
    catch(e){debugPrint('Google sign-out: $e');}
    if(mounted)setState(()=>account=null);
  }

  Future<void> youtube() async {
    final ok=await launchUrl(Uri.parse('https://www.youtube.com/'),
        mode:LaunchMode.externalApplication);
    if(!ok && mounted)ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content:Text('متصفح النظام غير متاح.')));
  }

  void settings() {
    showModalBottomSheet<void>(context:context,
      isScrollControlled:true,showDragHandle:true,
      builder:(sheet)=>SafeArea(child:Padding(
        padding:const EdgeInsets.all(16),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          Text('الإعدادات',style:Theme.of(sheet).textTheme.headlineSmall
            ?.copyWith(fontWeight:FontWeight.w900)),
          const SizedBox(height:15),
          AnimatedBuilder(animation:widget.library,
            builder:(ctx,_)=>SwitchListTile.adaptive(
              value:widget.library.darkMode,
              onChanged:widget.library.setTheme,
              title:const Text('الوضع الليلي'),
              subtitle:const Text('تغيير الألوان بين النهار والليل'),
              secondary:const Icon(Icons.dark_mode_outlined),
            )),
          ListTile(
            leading:const Icon(Icons.account_circle_outlined),
            title:Text(account==null?'تسجيل Google الرسمي':
              'مرحبًا ${account!.displayName ?? account!.email}'),
            subtitle:Text(account==null ?
              'يتطلب إعداد OAuth في حساب Google Cloud' : account!.email),
            trailing:googleBusy ? const CircularProgressIndicator() :
              const Icon(Icons.chevron_left),
            onTap:googleBusy?null:() {
              Navigator.pop(sheet);
              if(account==null){googleLogin();}
              else{signOut();}
            }),
          ListTile(leading:const Icon(Icons.play_circle_outline),
            title:const Text('افتح يوتيوب وسجّل دخولك في المتصفح'),
            subtitle:const Text('تسجيل آمن خارج WebView؛ إعلانات يوتيوب تتبع يوتيوب.'),
            onTap:(){Navigator.pop(sheet);youtube();}),
          ListTile(leading:const Icon(Icons.history),
            title:const Text('امسح سجل تصفح التطبيق'),
            onTap:(){
              widget.library.clearHistory();
              Navigator.pop(sheet);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content:Text('تم حذف السجل المحفوظ محليًا.')));
            }),
          const Divider(),
          const Text('iBetoo Media مفيهوش أي شبكة إعلانات أو تتبع إعلاني داخل التطبيق. '
            'لكن المواقع الخارجية، ومنها يوتيوب، ليها إعلاناتها وشروطها. '
            'التنزيل بيشتغل للروابط المباشرة المصرّح بها فقط، '
            'والمكتبة بتتعامل مع الملفات اللي اخترتها أو نزّلتها أنت.',
            textAlign:TextAlign.center,
            style:TextStyle(fontSize:12,height:1.7)),
        ]),
      )));
  }

  @override
  Widget build(BuildContext context) {
    final pages=[
      _HomeFeed(
        library:widget.library,
        browse:browse,
        youtube:()=>browse('https://m.youtube.com/'),
        settings:settings,
        smartLink:analyzeLink,
        phone:phone,
        google:googleLogin,
        account:account,
        googleBusy:googleBusy,
        openDownloads:()=>setState(()=>selected=2),
        openLibrary:()=>setState(()=>selected=3),
      ),
      BrowserScreen(
        key:ValueKey('browser-$browserGeneration'),
        library:widget.library,music:widget.music,
        initialUrl:browserUrl),
      DownloadScreen(library:widget.library,music:widget.music),
      MediaCollectionScreen(
        phone:phone,library:widget.library,music:widget.music),
    ];
    return Scaffold(
      body:IndexedStack(index:selected,children:pages),
      bottomNavigationBar:Column(mainAxisSize:MainAxisSize.min,children:[
        MiniMusic(music:widget.music,
          open:()=>Navigator.of(context).push(MaterialPageRoute(
            builder:(_)=>AudioDetail(music:widget.music)))),
        NavigationBar(
          selectedIndex:selected,
          onDestinationSelected:(v)=>setState(()=>selected=v),
          destinations:const [
            NavigationDestination(icon:Icon(Icons.home_outlined),
              selectedIcon:Icon(Icons.home),label:'الرئيسية'),
            NavigationDestination(icon:Icon(Icons.language_outlined),
              selectedIcon:Icon(Icons.language),label:'المتصفح'),
            NavigationDestination(icon:Icon(Icons.download_outlined),
              selectedIcon:Icon(Icons.download),label:'التنزيلات'),
            NavigationDestination(icon:Icon(Icons.perm_media_outlined),
              selectedIcon:Icon(Icons.perm_media),label:'المكتبة'),
          ],
        ),
      ]),
    );
  }
}

class _HomeFeed extends StatefulWidget {
  const _HomeFeed({
    required this.library,required this.browse,required this.youtube,
    required this.settings,required this.google,
    required this.smartLink,required this.phone,
    required this.account,required this.googleBusy,
    required this.openDownloads,required this.openLibrary,
  });
  final MediaLibrary library;
  final PhoneLibrary phone;
  final ValueChanged<String> browse;
  final VoidCallback youtube,settings,google,smartLink,openDownloads,openLibrary;
  final GoogleSignInAccount? account;
  final bool googleBusy;
  @override
  State<_HomeFeed> createState()=>_HomeFeedState();
}

class _HomeFeedState extends State<_HomeFeed> {
  final query=TextEditingController();
  @override
  void dispose(){query.dispose();super.dispose();}

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Row(children:[
      Container(width:34,height:34,
        alignment:Alignment.center,
        decoration:BoxDecoration(
          color:MediaPalette.orange,
          borderRadius:BorderRadius.circular(10)),
        child:const Icon(Icons.play_arrow_rounded,color:Colors.white,size:27)),
      const SizedBox(width:8),
      const Text('iBetoo',style:TextStyle(fontSize:25,
        fontWeight:FontWeight.w900,letterSpacing:-.6)),
      const SizedBox(width:5),
      Text('MEDIA',style:TextStyle(fontSize:10,
        fontWeight:FontWeight.w900,color:MediaPalette.orange)),
    ]),
      actions:[
        IconButton(tooltip:'الوضع الليلي',
          icon:Icon(widget.library.darkMode?
            Icons.light_mode_outlined:Icons.dark_mode_outlined),
          onPressed:()=>widget.library.setTheme(!widget.library.darkMode)),
        IconButton(tooltip:'الإعدادات',icon:const Icon(Icons.settings_outlined),
          onPressed:widget.settings),
      ],
    ),
    body:AnimatedBuilder(animation:widget.library,builder:(ctx,_) =>
      ListView(padding:const EdgeInsets.fromLTRB(17,18,17,24),children:[
        Container(
          padding:const EdgeInsets.all(21),
          decoration:BoxDecoration(
            color:Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius:BorderRadius.circular(26),
            border:Border.all(color:Theme.of(context).dividerColor)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('كل وسائطك. مكان واحد.',
              style:TextStyle(fontSize:27,fontWeight:FontWeight.w900,height:1.3)),
            const SizedBox(height:7),
            Text('تصفح. احفظ روابط الملفات المسموح بها. شغّل موسيقاك '
              'وفيديوهاتك بعيدًا عن زحمة التطبيقات.',
              style:Theme.of(context).textTheme.bodyMedium?.copyWith(
                height:1.65)),
            const SizedBox(height:18),
            TextField(
              controller:query,
              textInputAction:TextInputAction.search,
              onSubmitted:widget.browse,
              decoration:InputDecoration(
                hintText:'ابحث في الويب أو الصق رابط',
                prefixIcon:const Icon(Icons.search),
                suffixIcon:IconButton(
                  icon:const Icon(Icons.arrow_forward_rounded),
                  onPressed:()=>widget.browse(query.text)),
              ),
            ),
          ]),
        ),
        const SizedBox(height:13),
        InkWell(onTap:widget.smartLink,
          borderRadius:BorderRadius.circular(22),
          child:Container(
            padding:const EdgeInsets.all(16),
            decoration:BoxDecoration(
              gradient:const LinearGradient(
                begin:Alignment.topRight,end:Alignment.bottomLeft,
                colors:[Color(0xffff782e),Color(0xffbb390f)]),
              borderRadius:BorderRadius.circular(22)),
            child:Row(children:[
              Container(width:55,height:55,
                decoration:BoxDecoration(
                  color:Colors.white.withValues(alpha:.18),
                  borderRadius:BorderRadius.circular(15)),
                child:const Icon(Icons.content_paste_search_rounded,
                  color:Colors.white,size:31)),
              const SizedBox(width:12),
              const Expanded(child:Column(
                crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text('انسخ الرابط وحلّله',
                    style:TextStyle(color:Colors.white,
                      fontWeight:FontWeight.w900,fontSize:18)),
                  SizedBox(height:3),
                  Text('الصق رابط • اعرف النوع • شغّل أو نزّل',
                    style:TextStyle(color:Colors.white,fontSize:11)),
                ])),
              const Icon(Icons.arrow_back_ios_new_rounded,
                color:Colors.white,size:18),
            ]),
          ),
        ),
        const SizedBox(height:23),
        _section('مواقعك المفضلة'),
        const SizedBox(height:10),
        Wrap(spacing:10,runSpacing:10,children:[
          _website('YouTube',Icons.play_circle_fill,Colors.red,
            widget.youtube,'فتح آمن بالحساب'),
          _website('Google',Icons.search_rounded,
            const Color(0xff4384f2),
            ()=>widget.browse('https://www.google.com/'),'بحث'),
          _website('Vimeo',Icons.ondemand_video_rounded,
            const Color(0xff1ab7ea),
            ()=>widget.browse('https://vimeo.com/'),'فيديو'),
          _website('Archive',Icons.account_balance_rounded,
            const Color(0xff8c6e47),
            ()=>widget.browse('https://archive.org/'),'مكتبة عامة'),
          _website('SoundCloud',Icons.graphic_eq_rounded,
            MediaPalette.orange,
            ()=>widget.browse('https://soundcloud.com/'),'صوت'),
          _website('Dailymotion',Icons.tv,
            const Color(0xff2978eb),
            ()=>widget.browse('https://www.dailymotion.com/'),'مشاهدة'),
        ]),
        const SizedBox(height:25),
        _section('ماذا تريد تعمل دلوقتي؟'),
        const SizedBox(height:12),
        AnimatedBuilder(animation:widget.phone,builder:(ctx,_)=>Card(
          child:ListTile(
            contentPadding:const EdgeInsets.all(12),
            leading:Container(width:49,height:49,
              decoration:BoxDecoration(
                color:MediaPalette.orange.withValues(alpha:.13),
                borderRadius:BorderRadius.circular(14)),
              child:const Icon(Icons.library_music,
                color:MediaPalette.orange,size:27)),
            title:const Text('ملفات الموبايل تلقائيًا',
              style:TextStyle(fontWeight:FontWeight.w900)),
            subtitle:Text(
              '${widget.phone.audio.length} صوت • '
              '${widget.phone.videos.length} فيديو  '
              '${widget.phone.audioGranted||widget.phone.videoGranted?"":"• يحتاج صلاحية"}'),
            trailing:const Icon(Icons.chevron_left),
            onTap:widget.openLibrary,
          ),
        )),

        const SizedBox(height:12),
        Row(children:[
          Expanded(child:_actionCard(
            Icons.cloud_download_outlined,'تنزيل ملف',
            'روابط مباشرة وخلفية',
            widget.openDownloads)),
          const SizedBox(width:10),
          Expanded(child:_actionCard(
            Icons.folder_copy_outlined,'ملفاتي',
            'صور وأغاني وفيديو',
            widget.openLibrary)),
        ]),
        const SizedBox(height:23),
        _section('تصفحك الخاص'),
        const SizedBox(height:8),
        if(widget.library.bookmarks.isEmpty)
          const Padding(padding:EdgeInsets.symmetric(vertical:13),
            child:Text('لسه مفيش مفضلة. احفظ أي موقع من المتصفح.'))
        else for(final url in widget.library.bookmarks.take(5))
          _linkRow(url,Icons.bookmark,()=>widget.browse(url)),
        const SizedBox(height:12),
        _section('آخر زيارة'),
        const SizedBox(height:8),
        if(widget.library.history.isEmpty)
          const Padding(padding:EdgeInsets.symmetric(vertical:13),
            child:Text('هنا هتظهر المواقع اللي زرتها.'))
        else for(final url in widget.library.history.take(6))
          _linkRow(url,Icons.history,()=>widget.browse(url)),
        const SizedBox(height:22),
        Card(child:ListTile(
          leading:const Icon(Icons.account_circle_rounded,
            color:MediaPalette.orange,size:32),
          title:Text(widget.account==null?
            'ربط حساب Google':'أهلًا ${widget.account!.displayName}'),
          subtitle:Text(widget.account==null?
            'تفعيل الحساب يتطلب إعداد OAuth الرسمي.':'متصل بحساب التطبيق'),
          trailing:widget.googleBusy?const CircularProgressIndicator():
            const Icon(Icons.chevron_left),
          onTap:widget.google)),
        const SizedBox(height:18),
        const Center(child:Text('بدون إعلانات داخل التطبيق • وسائطك تحت تحكمك',
          style:TextStyle(color:Colors.grey,fontSize:11))),
      ]),
    ),
  );

  Widget _section(String title)=>Text(title,
    style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900));

  Widget _website(String title,IconData icon,Color color,
      VoidCallback onTap,String caption)=>InkWell(
    onTap:onTap,borderRadius:BorderRadius.circular(17),
    child:Container(width:103,height:107,
      padding:const EdgeInsets.all(10),
      decoration:BoxDecoration(
        color:Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius:BorderRadius.circular(17),
        border:Border.all(color:Theme.of(context).dividerColor)),
      child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        Icon(icon,color:color,size:32),
        const SizedBox(height:7),
        Text(title,maxLines:1,
          style:const TextStyle(fontWeight:FontWeight.w800,fontSize:13)),
        Text(caption,maxLines:1,
          style:const TextStyle(color:Colors.grey,fontSize:9)),
      ])),
  );

  Widget _actionCard(IconData icon,String title,String subtitle,
      VoidCallback onTap)=>InkWell(
    onTap:onTap,borderRadius:BorderRadius.circular(20),
    child:Container(
      height:133,padding:const EdgeInsets.all(14),
      decoration:BoxDecoration(
        borderRadius:BorderRadius.circular(20),
        gradient:LinearGradient(colors:[
          MediaPalette.orange.withValues(alpha:.13),
          MediaPalette.orange.withValues(alpha:.035)]),
        border:Border.all(color:MediaPalette.orange.withValues(alpha:.3))),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Icon(icon,color:MediaPalette.orange,size:30),
        const Spacer(),
        Text(title,style:const TextStyle(fontSize:17,
          fontWeight:FontWeight.w900)),
        Text(subtitle,style:const TextStyle(fontSize:11)),
      ])),
  );
  Widget _linkRow(String url,IconData icon,VoidCallback onTap)=>
    ListTile(
      contentPadding:EdgeInsets.zero,dense:true,
      leading:Icon(icon,color:MediaPalette.orange,size:19),
      title:Text(Uri.tryParse(url)?.host ?? url,
        maxLines:1,overflow:TextOverflow.ellipsis),
      subtitle:Text(url,maxLines:1,overflow:TextOverflow.ellipsis,
        textDirection:TextDirection.ltr),
      onTap:onTap,
      trailing:const Icon(Icons.arrow_outward_rounded,size:17),
    );
}

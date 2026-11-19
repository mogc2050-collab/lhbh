import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'device_media.dart';
import 'library.dart';
import 'library_screen.dart';
import 'media_utils.dart';
import 'player.dart';
import 'photo_gallery.dart';
import 'permission_panel.dart';
import 'theme.dart';

class MediaCollectionScreen extends StatefulWidget {
  const MediaCollectionScreen({
    super.key,
    required this.phone,
    required this.library,
    required this.music,
    this.onOpenNavigation,
  });
  final PhoneLibrary phone;
  final MediaLibrary library;
  final BackgroundMusic music;
  final VoidCallback? onOpenNavigation;
  @override
  State<MediaCollectionScreen> createState() => _MediaCollectionScreenState();
}

class _MediaCollectionScreenState extends State<MediaCollectionScreen>
    with SingleTickerProviderStateMixin {
  int selected = 0;
  final search = TextEditingController();
  String sort = 'الأحدث';
  late final TabController sections;
  @override
  void initState() {
    super.initState();
    sections = TabController(length: 5, vsync: this);
    sections.addListener(() {
      if (selected != sections.index && mounted) {
        FocusScope.of(context).unfocus();
        setState(() => selected = sections.index);
      }
    });
  }

  void _select(int index) => sections.animateTo(index);
  @override
  void dispose() {
    sections.dispose();
    search.dispose();
    super.dispose();
  }

  List<PhoneMedia> itemsFor(int section) {
    final raw = switch (section) {
      1 => widget.phone.audio,
      2 => widget.phone.videos,
      3 => widget.phone.images,
      _ => widget.phone.all,
    };
    final list = List<PhoneMedia>.of(raw);
    final q = search.text.trim().toLowerCase();
    if (q.isNotEmpty)
      list.removeWhere(
        (m) => !('${m.name} ${m.artist} ${m.album} ${m.folder}')
            .toLowerCase()
            .contains(q),
      );
    if (sort == 'الاسم') list.sort((a, b) => a.name.compareTo(b.name));
    if (sort == 'المدة') list.sort((a, b) => b.duration.compareTo(a.duration));
    if (sort == 'الحجم') list.sort((a, b) => b.size.compareTo(a.size));
    if (sort == 'الأكثر تشغيلًا')
      list.sort(
        (a, b) => (widget.library.playCount[b.uri] ?? 0).compareTo(
          widget.library.playCount[a.uri] ?? 0,
        ),
      );
    if (sort == 'الأحدث') list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  List<MediaTrack> tracks(Iterable<PhoneMedia> items) => items
      .map(
        (m) => MediaTrack(
          source: m.uri,
          title: widget.library.customTitles[m.uri] ?? m.name,
          album: m.album.isNotEmpty ? m.album : 'من الهاتف',
        ),
      )
      .toList();

  Future<void> playMedia(PhoneMedia media, [List<PhoneMedia>? group]) async {
    try {
      if (media.audio) {
        final list = (group ?? widget.phone.audio)
            .where((e) => e.audio)
            .toList();
        final index = list.indexWhere((e) => e.uri == media.uri);
        await widget.music.playQueue(tracks(list), index < 0 ? 0 : index);
        if (mounted)
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AudioDetail(music: widget.music),
            ),
          );
      } else if (media.video) {
        await widget.music.player.pause();
        final videos = (group ?? widget.phone.videos)
            .where((e) => e.video)
            .toList();
        final index = videos.indexWhere((e) => e.uri == media.uri);
        if (mounted)
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => VideoDetail(
                source: media.uri,
                title: media.name,
                music: widget.music,
                library: widget.library,
                startIndex: index < 0 ? 0 : index,
                playlist: tracks(videos),
              ),
            ),
          );
      } else if (media.image) {
        final images = (group ?? widget.phone.images)
            .where((m) => m.image)
            .toList();
        final start = images.indexWhere((m) => m.uri == media.uri);
        if (images.isNotEmpty && mounted)
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PhotoGallery(
                initialIndex: start < 0 ? 0 : start,
                images: images
                    .map((m) => GalleryImage(source: m.uri, title: m.name))
                    .toList(),
              ),
            ),
          );
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر فتح الوسائط: $e')));
    }
  }

  void showItems(String title, List<PhoneMedia> items) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ListView.builder(
            itemCount: items.length,
            itemBuilder: (ctx, i) => ListTile(
              leading: _thumb(items[i]),
              title: Text(items[i].name, maxLines: 2),
              subtitle: Text(
                items[i].artist.isNotEmpty
                    ? items[i].artist
                    : MediaUtils.displaySize(items[i].size),
              ),
              onTap: () => playMedia(items[i], items),
              trailing: IconButton(
                icon: Icon(
                  widget.library.isFavorite(items[i].uri)
                      ? Icons.favorite
                      : Icons.favorite_outline,
                  color: MediaPalette.orange,
                ),
                onPressed: () {
                  widget.library.toggleFavorite(items[i].uri);
                  setState(() {});
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb(PhoneMedia m, {double width = 56, double height = 56}) {
    Widget placeholder() => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            MediaPalette.orange.withValues(alpha: .2),
            Theme.of(context).colorScheme.surfaceContainerHigh,
          ],
        ),
      ),
      child: Icon(
        m.audio
            ? Icons.music_note_rounded
            : m.video
            ? Icons.ondemand_video_rounded
            : Icons.image_outlined,
        size: height > 75 ? 36 : 24,
        color: MediaPalette.orange,
      ),
    );
    Widget image(Uint8List bytes) => Image.memory(
      bytes,
      width: width,
      height: height,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => placeholder(),
    );
    final cached = widget.phone.thumbs[m.uri];
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: cached != null
          ? image(cached)
          : FutureBuilder<Uint8List?>(
              future: widget.phone.artwork(m.uri),
              builder: (_, snapshot) =>
                  snapshot.data != null && snapshot.data!.isNotEmpty
                  ? image(snapshot.data!)
                  : placeholder(),
            ),
    );
  }

  Widget _actions(PhoneMedia m) => PopupMenuButton<String>(
    tooltip: 'خيارات الملف',
    onSelected: (value) {
      if (value == 'favorite') widget.library.toggleFavorite(m.uri);
      if (value == 'playlist') _addToPlaylist(m.uri);
      if (value == 'info') _info(m);
    },
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'favorite',
        child: Text(
          widget.library.isFavorite(m.uri) ? 'إزالة من المفضلة' : 'أضف للمفضلة',
        ),
      ),
      if (m.audio)
        const PopupMenuItem(
          value: 'playlist',
          child: Text('إضافة لقائمة تشغيل'),
        ),
      const PopupMenuItem(value: 'info', child: Text('تفاصيل الملف')),
    ],
  );
  String _duration(PhoneMedia m) {
    final seconds = m.duration ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _tile(PhoneMedia m, List<PhoneMedia> group) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(16),
    child: ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 10, end: 0),
      minVerticalPadding: 10,
      leading: _thumb(m),
      title: Text(
        widget.library.customTitles[m.uri] ?? m.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
      subtitle: Text(
        '${m.artist.isNotEmpty ? m.artist : 'من الهاتف'} • '
        '${m.duration > 0 ? _duration(m) : MediaUtils.displaySize(m.size)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => playMedia(m, group),
      trailing: _actions(m),
    ),
  );

  Widget _visualCard(PhoneMedia m, List<PhoneMedia> group) => Material(
    clipBehavior: Clip.antiAlias,
    borderRadius: BorderRadius.circular(m.image ? 7 : 18),
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: InkWell(
      onTap: () => playMedia(m, group),
      onLongPress: () => _info(m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _thumb(m, width: double.infinity, height: double.infinity),
                if (m.video)
                  const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                if (m.video)
                  Positioned(
                    bottom: 7,
                    left: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xa6000000),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _duration(m),
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                if (widget.library.isFavorite(m.uri))
                  const Positioned(
                    top: 7,
                    right: 7,
                    child: Icon(
                      Icons.favorite_rounded,
                      color: Colors.white,
                      size: 19,
                    ),
                  ),
              ],
            ),
          ),
          if (!m.image)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 0, 5),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          MediaUtils.displaySize(m.size),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  _actions(m),
                ],
              ),
            ),
        ],
      ),
    ),
  );
  void _info(PhoneMedia m) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m.name, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final line in [
                'المجلد: ${m.folder}',
                'الفنان: ${m.artist}',
                'الألبوم: ${m.album}',
                'النوع: ${m.mime}',
                'الحجم: ${MediaUtils.displaySize(m.size)}',
                'مرات التشغيل: ${widget.library.playCount[m.uri] ?? 0}',
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(line),
                ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addToPlaylist(String uri) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(15),
          children: [
            Text(
              'اختر قائمة التشغيل',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            for (final p in widget.library.playlists)
              ListTile(
                title: Text(p.name),
                onTap: () {
                  widget.library.appendToPlaylist(p, uri);
                  Navigator.pop(ctx);
                },
              ),
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('إنشاء قائمة جديدة'),
              onPressed: () {
                Navigator.pop(ctx);
                _createPlaylist(uri);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createPlaylist([String? initial]) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('قائمة تشغيل جديدة'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'اسم القائمة'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      final p = widget.library.createPlaylist(name);
      if (initial != null) widget.library.appendToPlaylist(p, initial);
      setState(() {});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  void _openPlaylist(Playlist p) {
    final items = p.items
        .map(widget.phone.byUri)
        .whereType<PhoneMedia>()
        .toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text(p.name),
            actions: [
              IconButton(
                tooltip: 'تشغيل الكل',
                icon: const Icon(Icons.play_circle),
                onPressed: items.isEmpty
                    ? null
                    : () => playMedia(items.first, items),
              ),
            ],
          ),
          body: ReorderableListView.builder(
            itemCount: p.items.length,
            onReorder: (a, b) {
              widget.library.reorder(p, a, b);
              setState(() {});
            },
            itemBuilder: (ctx, i) {
              final uri = p.items[i], item = widget.phone.byUri(uri);
              return ListTile(
                key: ValueKey(uri),
                title: Text(item?.name ?? 'ملف غير موجود'),
                leading: const Icon(Icons.drag_handle),
                subtitle: Text(item?.artist ?? uri, maxLines: 1),
                onTap: item == null ? null : () => playMedia(item, items),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () {
                    widget.library.removeFromPlaylist(p, uri);
                    Navigator.pop(ctx);
                    _openPlaylist(p);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _dashboard() {
    final recent = widget.phone.all.take(14).toList();
    final favorites = widget.phone.all
        .where((x) => widget.library.isFavorite(x.uri))
        .toList();
    final most = widget.library
        .mostPlayed()
        .map(widget.phone.byUri)
        .whereType<PhoneMedia>()
        .toList();
    final pending = widget.phone.videos
        .where((x) => (widget.library.resume[x.uri] ?? 0) > 0)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(
              child: _stat(
                'الصوت',
                widget.phone.audio.length,
                Icons.music_note,
                () => _select(1),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _stat(
                'الفيديو',
                widget.phone.videos.length,
                Icons.movie_outlined,
                () => _select(2),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _stat(
                'الصور',
                widget.phone.images.length,
                Icons.image_outlined,
                () => _select(3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _section('أكمل المشاهدة', pending),
        _section('المفضلة', favorites),
        _section('الأكثر تشغيلًا', most),
        _section('المضافة حديثًا', recent),
        const SizedBox(height: 16),
        _group(
          'قوائم التشغيل',
          Icons.queue_music,
          widget.library.playlists.length,
          _playlists,
        ),
        _group(
          'الفنانون',
          Icons.person_outline,
          widget.phone.artists.length,
          () => _groups('الفنانون', widget.phone.artists),
        ),
        _group(
          'الألبومات',
          Icons.album_outlined,
          widget.phone.albums.length,
          () => _groups('الألبومات', widget.phone.albums),
        ),
        _group(
          'مجلدات الهاتف',
          Icons.folder_outlined,
          widget.phone.folders.length,
          () => _groups('المجلدات', widget.phone.folders),
        ),
        _group('البحث عن ملفات مكررة', Icons.copy_all_outlined, 0, _duplicates),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _stat(String label, int count, IconData icon, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Icon(icon, color: MediaPalette.orange, size: 27),
              const SizedBox(height: 8),
              Text(
                count.toString(),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );
  Widget _section(String title, List<PhoneMedia> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        SizedBox(
          height: 155,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.take(15).length,
            separatorBuilder: (_, __) => const SizedBox(width: 9),
            itemBuilder: (ctx, i) {
              final m = list[i];
              return InkWell(
                onTap: () => playMedia(m, list),
                child: SizedBox(
                  width: 143,
                  child: Column(
                    children: [
                      _thumb(m, width: 143, height: 112),
                      const SizedBox(height: 6),
                      Text(
                        m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _group(String title, IconData icon, int count, VoidCallback tap) =>
      Card(
        child: ListTile(
          leading: Icon(icon, color: MediaPalette.orange),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: count > 0 ? Text('$count') : null,
          trailing: const Icon(Icons.chevron_left),
          onTap: tap,
        ),
      );
  void _groups(String title, Map<String, List<PhoneMedia>> groups) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ListView(
            children: [
              for (final entry in groups.entries)
                ListTile(
                  leading: const Icon(
                    Icons.folder_outlined,
                    color: MediaPalette.orange,
                  ),
                  title: Text(entry.key),
                  subtitle: Text('${entry.value.length} ملف'),
                  onTap: () => showItems(entry.key, entry.value),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _playlists() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: const Text('قوائم التشغيل'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _createPlaylist,
              ),
            ],
          ),
          body: AnimatedBuilder(
            animation: widget.library,
            builder: (ctx, _) => ListView(
              children: [
                for (final p in widget.library.playlists)
                  ListTile(
                    leading: const Icon(
                      Icons.queue_music,
                      color: MediaPalette.orange,
                    ),
                    title: Text(p.name),
                    subtitle: Text('${p.items.length} عنصر'),
                    onTap: () => _openPlaylist(p),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        widget.library.deletePlaylist(p);
                      },
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('قائمة جديدة'),
                  onTap: _createPlaylist,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _duplicates() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final groups = await widget.phone.findDuplicates();
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (ctx) => Scaffold(
            appBar: AppBar(title: const Text('الملفات المكررة')),
            body: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'المقارنة هنا ببصمة SHA-256، ولا يتم حذف الملفات '
                    'الأصلية تلقائيًا. يمكنك فتح الملفات للتحقق منها.',
                  ),
                ),
                if (groups.isEmpty)
                  const ListTile(
                    title: Text('لم يُكتشف تكرار في الملفات المفحوصة'),
                  ),
                for (final group in groups)
                  Card(
                    child: Column(
                      children: [
                        ListTile(title: Text('${group.length} نسخ متطابقة')),
                        for (final uri in group)
                          ListTile(
                            title: Text(widget.phone.byUri(uri)?.name ?? uri),
                            subtitle: Text(
                              widget.phone.byUri(uri)?.folder ?? '',
                            ),
                            onTap: () {
                              final media = widget.phone.byUri(uri);
                              if (media != null) playMedia(media);
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فشل فحص التكرار: $e')));
      }
    }
  }

  Widget _empty(int section) {
    final kind = section == 1
        ? 'audio'
        : section == 2
        ? 'video'
        : 'image';
    final granted = widget.phone.permissions[kind] == true;
    return LayoutBuilder(
      builder: (_, limits) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: limits.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    section == 1
                        ? Icons.library_music_outlined
                        : section == 2
                        ? Icons.video_library_outlined
                        : Icons.photo_library_outlined,
                    size: 58,
                    color: MediaPalette.orange,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    search.text.isNotEmpty
                        ? 'مفيش نتائج للبحث'
                        : granted
                        ? 'مفيش ملفات في القسم ده حاليًا'
                        : 'اسمح بعرض ملفات القسم ده',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (!granted) ...[
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: widget.phone.loading
                          ? null
                          : () => widget.phone.refresh(
                              askPermissions: true,
                              permissionKinds: [kind],
                            ),
                      child: const Text('السماح بالوصول'),
                    ),
                    TextButton(
                      onPressed: () =>
                          showPermissionPanel(context, widget.phone),
                      child: const Text('إدارة الأذونات'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mediaPage(int section) {
    final items = itemsFor(section);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                Text(
                  '${items.length} عنصر',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  tooltip: 'ترتيب الملفات',
                  initialValue: sort,
                  onSelected: (value) => setState(() => sort = value),
                  itemBuilder: (_) => [
                    for (final value in [
                      'الأحدث',
                      'الاسم',
                      'الحجم',
                      'المدة',
                      'الأكثر تشغيلًا',
                    ])
                      CheckedPopupMenuItem(
                        value: value,
                        checked: sort == value,
                        child: Text(value),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Text(sort, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 5),
                        const Icon(Icons.sort_rounded, size: 19),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: widget.phone.refresh,
            child: items.isEmpty
                ? _empty(section)
                : section == 1
                ? ListView.separated(
                    key: const PageStorageKey('audio-list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 20),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 5),
                    itemBuilder: (_, i) => _tile(items[i], items),
                  )
                : GridView.builder(
                    key: PageStorageKey('media-grid-$section'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      section == 3 ? 3 : 10,
                      2,
                      section == 3 ? 3 : 10,
                      20,
                    ),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: section == 3 ? 150 : 300,
                      childAspectRatio: section == 3 ? 1 : 1.12,
                      crossAxisSpacing: section == 3 ? 3 : 10,
                      mainAxisSpacing: section == 3 ? 3 : 10,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) => _visualCard(items[i], items),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _overview() {
    if (search.text.trim().isNotEmpty) {
      final found = itemsFor(0);
      return found.isEmpty
          ? const Center(child: Text('مفيش نتائج للبحث'))
          : ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: found.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _tile(found[i], found),
            );
    }
    if (!widget.phone.audioGranted &&
        !widget.phone.videoGranted &&
        !widget.phone.imageGranted) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.perm_media_outlined,
                size: 64,
                color: MediaPalette.orange,
              ),
              const SizedBox(height: 16),
              Text(
                'مكتبتك في مكان واحد',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'اختار أقسام الوسائط اللي تحب تعرضها، أو استورد ملفاتك بنفسك.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                icon: const Icon(Icons.shield_outlined),
                onPressed: () => showPermissionPanel(context, widget.phone),
                label: const Text('اختيار الأذونات'),
              ),
              TextButton(
                onPressed: () => _select(4),
                child: const Text('استيراد ملفات يدويًا'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: widget.phone.refresh,
      child: _dashboard(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('المكتبة'),
      toolbarHeight: 48,
      leading: IconButton(
        tooltip: 'أقسام التطبيق',
        onPressed: widget.onOpenNavigation,
        icon: const Icon(Icons.apps_rounded),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'تحديث فهرس الهاتف',
          onPressed: widget.phone.refresh,
        ),
        IconButton(
          icon: const Icon(Icons.queue_music_rounded),
          tooltip: 'قوائم التشغيل',
          onPressed: _playlists,
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: Listenable.merge([widget.phone, widget.library]),
      builder: (context, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: SizedBox(
              height: 44,
              child: TextField(
                key: const ValueKey('library-search'),
                controller: search,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: 'ابحث عن ملف، فنان أو ألبوم',
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح البحث',
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            search.clear();
                            setState(() {});
                          },
                        ),
                ),
              ),
            ),
          ),
          TabBar(
            controller: sections,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 17),
            tabs: const [
              Tab(text: 'الرئيسية', height: 40),
              Tab(text: 'الأغاني', height: 40),
              Tab(text: 'الفيديو', height: 40),
              Tab(text: 'الصور', height: 40),
              Tab(text: 'الملفات', height: 40),
            ],
          ),
          if (widget.phone.loading) const LinearProgressIndicator(minHeight: 2),
          if (widget.phone.error != null)
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                widget.phone.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: sections,
              children: [
                _overview(),
                _mediaPage(1),
                _mediaPage(2),
                _mediaPage(3),
                LibraryScreen(
                  library: widget.library,
                  music: widget.music,
                  embedded: true,
                  searchQuery: search.text,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

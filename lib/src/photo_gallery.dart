import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'device_media.dart';

class GalleryImage {
  const GalleryImage({required this.source, required this.title});
  final String source, title;
}

/// A paged gallery; dragging pans a zoomed image and changes an unzoomed one.
class PhotoGallery extends StatefulWidget {
  PhotoGallery({super.key, required this.images, this.initialIndex = 0})
    : assert(images.length > 0);
  final List<GalleryImage> images;
  final int initialIndex;

  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  late final PageController pages;
  late int index;
  bool zoomed = false;

  @override
  void initState() {
    super.initState();
    index = widget.initialIndex.clamp(0, widget.images.length - 1).toInt();
    pages = PageController(initialPage: index);
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void move(int delta) {
    final target = index + delta;
    if (target < 0 || target >= widget.images.length) return;
    setState(() => zoomed = false);
    pages.animateToPage(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(
        widget.images[index].title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(child: Text('${index + 1} / ${widget.images.length}')),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              key: const ValueKey('photo-pager'),
              controller: pages,
              physics: zoomed ? const NeverScrollableScrollPhysics() : null,
              itemCount: widget.images.length,
              onPageChanged: (value) => setState(() {
                index = value;
                zoomed = false;
              }),
              itemBuilder: (_, i) => _GalleryPage(
                key: ValueKey(widget.images[i].source),
                image: widget.images[i],
                active: i == index,
                onZoom: (value) {
                  if (i == index && value != zoomed && mounted) {
                    setState(() => zoomed = value);
                  }
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'الصورة السابقة',
                  color: Colors.white,
                  onPressed: index > 0 ? () => move(-1) : null,
                  icon: const Icon(Icons.navigate_before_rounded),
                ),
                Text(
                  zoomed
                      ? 'اضغط مرتين لتصغير الصورة'
                      : 'اسحب للتنقّل • اضغط مرتين للتكبير',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                IconButton(
                  tooltip: 'الصورة التالية',
                  color: Colors.white,
                  onPressed: index + 1 < widget.images.length
                      ? () => move(1)
                      : null,
                  icon: const Icon(Icons.navigate_next_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _GalleryPage extends StatefulWidget {
  const _GalleryPage({
    super.key,
    required this.image,
    required this.active,
    required this.onZoom,
  });
  final GalleryImage image;
  final bool active;
  final ValueChanged<bool> onZoom;
  @override
  State<_GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPage> {
  final transform = TransformationController();
  late final Future<Uint8List?> bytes;
  bool zoomed = false;

  @override
  void initState() {
    super.initState();
    bytes = widget.image.source.startsWith('content://')
        ? PhoneLibrary.channel.invokeMethod<Uint8List>('imagePreview', {
            'uri': widget.image.source,
          })
        : File(widget.image.source).readAsBytes();
  }

  @override
  void didUpdateWidget(covariant _GalleryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) {
      transform.value = Matrix4.identity();
      zoomed = false;
    }
  }

  void syncZoom() {
    final value = transform.value.getMaxScaleOnAxis() > 1.02;
    if (zoomed != value) {
      setState(() => zoomed = value);
      widget.onZoom(value);
    }
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: bytes,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError ||
          snapshot.data == null ||
          snapshot.data!.isEmpty) {
        return const Center(
          child: Text(
            'تعذر قراءة الصورة. يمكنك الانتقال للصورة التالية.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
        );
      }
      return LayoutBuilder(
        builder: (_, size) => GestureDetector(
          onDoubleTap: () {
            transform.value = zoomed
                ? Matrix4.identity()
                : (Matrix4.identity()
                    ..translateByDouble(
                      -size.maxWidth * .75,
                      -size.maxHeight * .75,
                      0,
                      1,
                    )
                    ..scaleByDouble(2.5, 2.5, 1, 1));
            syncZoom();
          },
          child: InteractiveViewer(
            transformationController: transform,
            panEnabled: zoomed,
            minScale: 1,
            maxScale: 6,
            onInteractionEnd: (_) => syncZoom(),
            child: SizedBox.expand(
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white70,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

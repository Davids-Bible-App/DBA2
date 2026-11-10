import 'dart:io';

import 'package:flutter/material.dart';

import 'meme_controller.dart';
import 'meme_io.dart';
import 'meme_storage.dart';
import 'meme_theme.dart';
import 'meme_widgets.dart';

/// Horizontal, lazily-built strip of background images.
/// Thumbnails are decoded small by Flutter (cacheWidth) from the original.
class MemeImageStrip extends StatelessWidget {
  const MemeImageStrip({super.key, required this.c});
  final MemeMakerController c;

  static Widget thumb(MemeMakerController c, String src, {int width = 160}) {
    if (MemeStorage.isRemote(src)) {
      return _RemoteThumb(key: ValueKey(src), c: c, src: src);
    }
    return Image.file(
      c.storage.file(src),
      fit: BoxFit.cover,
      cacheWidth: width,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = MemeTheme.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final imgs = c.images;
        final sel = c.state.selectedImage;
        return MemePanel(
          title: 'Background images',
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    SizedBox(
                      width: 92,
                      height: 30,
                      child: MemeButton(
                        'Upload',
                        icon: Icons.upload,
                        onPressed: () async {
                          final paths = await pickImagePaths();
                          if (paths.isNotEmpty) await c.addImagePaths(paths);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 92,
                      height: 30,
                      child: MemeButton(
                        'URL',
                        icon: Icons.link,
                        onPressed: () async {
                          final url = await memePrompt(
                            context,
                            title: 'Paste the image URL',
                            hint: 'https://...',
                          );
                          if (url == null || url.trim().isEmpty) return;
                          final err = await c.addImageUrl(url);
                          if (err != null && context.mounted) {
                            await memeInfo(context, 'Could not add image', err);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: imgs.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final Widget face;
                      final bool active;
                      VoidCallback? onDelete;
                      if (i == 0) {
                        active = sel == null;
                        face = Container(
                          color: c.state.bgColor,
                          alignment: Alignment.center,
                          child: Text(
                            'Colour\nonly',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: c.state.bgColor.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                            ),
                          ),
                        );
                      } else {
                        final src = imgs[i - 1];
                        active = sel == src;
                        face = thumb(c, src);
                        onDelete = () async {
                          if (c.isImageProtected(src)) {
                            await memeInfo(
                              context,
                              'Image in use',
                              'This image is used by a saved template, so it cannot be deleted.',
                            );
                            return;
                          }
                          if (await memeConfirm(
                            context,
                            title: 'Delete image?',
                            message: 'Remove this image from the strip?',
                            ok: 'Delete',
                          )) {
                            await c.removeImage(src);
                          }
                        };
                      }
                      return SizedBox(
                        width: 76,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: GestureDetector(
                                onTap: () =>
                                    c.selectImage(i == 0 ? null : imgs[i - 1]),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      t.radiusS,
                                    ),
                                    border: Border.all(
                                      color: active ? t.accent : t.border,
                                      width: active ? 3 : 1,
                                    ),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: face,
                                ),
                              ),
                            ),
                            if (onDelete != null)
                              Positioned(
                                top: 3,
                                right: 3,
                                child: GestureDetector(
                                  onTap: onDelete,
                                  child: CircleAvatar(
                                    radius: 9,
                                    backgroundColor: t.danger,
                                    child: const Icon(
                                      Icons.close,
                                      size: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Remote thumbnail: downloaded once, then read from disk on every later open.
class _RemoteThumb extends StatefulWidget {
  const _RemoteThumb({super.key, required this.c, required this.src});
  final MemeMakerController c;
  final String src;
  @override
  State<_RemoteThumb> createState() => _RemoteThumbState();
}

class _RemoteThumbState extends State<_RemoteThumb> {
  late final Future<File?> _file = widget.c.storage.thumbFile(widget.src);

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (_, snap) {
      final f = snap.data;
      if (f != null) {
        return Image.file(
          f,
          fit: BoxFit.cover,
          cacheWidth: 200,
          gaplessPlayback: true,
        );
      }
      if (snap.connectionState == ConnectionState.done) {
        return const Icon(Icons.cloud_off_outlined);
      }
      return const SizedBox.shrink();
    },
  );
}

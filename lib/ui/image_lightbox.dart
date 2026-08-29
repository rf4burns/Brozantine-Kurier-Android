import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/l10n.dart';
import 'image_fullscreen.dart';
import 'shared.dart';

const kImageLightbox = ValueKey<String>('image-lightbox');
const kCloseImageLightbox = ValueKey<String>('close-image-lightbox');
const kFullscreenImage = ValueKey<String>('fullscreen-image');
const kExitFullscreenImage = ValueKey<String>('exit-fullscreen-image');

Key imageAttachmentKey(int id) => Key('image-attachment-$id');

const _barrierColor = Color(0xD9000000);
const _zoomedScale = 2.5;

Future<void> showImageLightbox(BuildContext context, {required String url}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: _barrierColor,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, animation, secondaryAnimation) {
      return ImageLightbox(url: url);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
  );
}

class ImageLightbox extends StatefulWidget {
  const ImageLightbox({super.key, required this.url});

  final String url;

  @override
  State<ImageLightbox> createState() => _ImageLightboxState();
}

class _ImageLightboxState extends State<ImageLightbox> {
  final _transform = TransformationController();
  bool _wantFullscreen = false;

  bool get _fullscreen => _wantFullscreen || imageFullscreenActive;

  @override
  void initState() {
    super.initState();
    subscribeImageFullscreen(_onFullscreenChanged);
  }

  @override
  void dispose() {
    unsubscribeImageFullscreen();
    if (imageFullscreenActive) {
      unawaited(exitImageFullscreen());
    }
    _transform.dispose();
    super.dispose();
  }

  void _onFullscreenChanged() {
    if (!imageFullscreenActive) _wantFullscreen = false;
    if (mounted) setState(() {});
  }

  void _close() {
    Navigator.of(context).pop();
  }

  Future<void> _toggleFullscreen() async {
    if (_fullscreen) {
      _wantFullscreen = false;
      await exitImageFullscreen();
    } else {
      _wantFullscreen = true;
      await enterImageFullscreen();
    }
    if (mounted) setState(() {});
  }

  void _toggleZoom(Size viewport) {
    final current = _transform.value.getMaxScaleOnAxis();
    if (current > 1.05) {
      _transform.value = Matrix4.identity();
      return;
    }
    final dx = viewport.width / 2;
    final dy = viewport.height / 2;
    _transform.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(_zoomedScale)
      ..translate(-dx, -dy);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    if (_fullscreen) {
      unawaited(_toggleFullscreen());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final fs = _fullscreen;
    return PopScope(
      canPop: !fs,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (fs) unawaited(_toggleFullscreen());
      },
      child: Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: SafeArea(
        child: Material(
          key: kImageLightbox,
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: fs ? null : _close,
                  child: const SizedBox.expand(),
                ),
              ),
              Padding(
                padding: fs ? EdgeInsets.zero : const EdgeInsets.all(32),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    return GestureDetector(
                      onDoubleTap: () => _toggleZoom(size),
                      child: InteractiveViewer(
                        transformationController: _transform,
                        minScale: 1,
                        maxScale: 8,
                        child: SizedBox(
                          width: size.width,
                          height: size.height,
                          child: widget.url.isEmpty
                              ? const SizedBox.shrink()
                              : Image.network(
                                  widget.url,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: Colors.white54,
                                      size: 64,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CompactIconButton(
                      key: fs ? kExitFullscreenImage : kFullscreenImage,
                      tooltip: fs ? l('exitFullscreen') : l('fullscreenStream'),
                      icon: fs ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                      background: const Color(0x99000000),
                      onPressed: _toggleFullscreen,
                    ),
                    const SizedBox(width: 4),
                    CompactIconButton(
                      key: kCloseImageLightbox,
                      tooltip: l('close'),
                      icon: Icons.close,
                      color: Colors.white,
                      background: const Color(0x99000000),
                      onPressed: _close,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

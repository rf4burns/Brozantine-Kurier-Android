import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';

Widget attachmentVideoView({required String url, required String viewKey}) {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return ColoredBox(
      key: ValueKey('video-el-$viewKey'),
      color: const Color(0xFF000000),
      child: const Center(
        child: Icon(Icons.play_circle_fill, color: Colors.white, size: 64),
      ),
    );
  }
  return _IoVideo(url: url, viewKey: viewKey);
}

Widget attachmentAudioView({required String url, required String viewKey}) {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return ColoredBox(
      key: ValueKey('audio-el-$viewKey'),
      color: const Color(0xFF1F1F1F),
      child: const SizedBox.expand(),
    );
  }
  return _IoAudio(url: url, viewKey: viewKey);
}

class _IoVideo extends StatefulWidget {
  const _IoVideo({required this.url, required this.viewKey});
  final String url;
  final String viewKey;

  @override
  State<_IoVideo> createState() => _IoVideoState();
}

class _IoVideoState extends State<_IoVideo> {
  VideoPlayerController? _ctrl;

  @override
  void initState() {
    super.initState();
    final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _ctrl = ctrl;
    ctrl.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return ColoredBox(
        key: ValueKey('video-el-${widget.viewKey}'),
        color: const Color(0xFF000000),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return GestureDetector(
      key: ValueKey('video-el-${widget.viewKey}'),
      onTap: () {
        ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
        setState(() {});
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          VideoPlayer(ctrl),
          if (!ctrl.value.isPlaying)
            const Icon(Icons.play_circle_fill, color: Colors.white, size: 64),
        ],
      ),
    );
  }
}

class _IoAudio extends StatefulWidget {
  const _IoAudio({required this.url, required this.viewKey});
  final String url;
  final String viewKey;

  @override
  State<_IoAudio> createState() => _IoAudioState();
}

class _IoAudioState extends State<_IoAudio> {
  final _player = AudioPlayer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _player.setUrl(widget.url).then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: ValueKey('audio-el-${widget.viewKey}'),
      color: const Color(0xFF1F1F1F),
      child: IconButton(
        onPressed: !_ready
            ? null
            : () {
                _player.playing ? _player.pause() : _player.play();
                setState(() {});
              },
        icon: Icon(
          _player.playing ? Icons.pause : Icons.play_arrow,
          color: Colors.white,
        ),
      ),
    );
  }
}

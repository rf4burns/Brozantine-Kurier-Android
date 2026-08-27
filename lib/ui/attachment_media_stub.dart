import 'package:flutter/material.dart';

Widget attachmentVideoView({required String url, required String viewKey}) {
  return ColoredBox(
    key: ValueKey('video-el-$viewKey'),
    color: const Color(0xFF000000),
    child: const Center(
      child: Icon(Icons.play_circle_fill, color: Colors.white, size: 64),
    ),
  );
}

Widget attachmentAudioView({required String url, required String viewKey}) {
  return ColoredBox(
    key: ValueKey('audio-el-$viewKey'),
    color: const Color(0xFF1F1F1F),
    child: const SizedBox.expand(),
  );
}

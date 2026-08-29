import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../protocol/platform_io.dart';

Widget mediaStreamView({required String mediaKey, BoxFit fit = BoxFit.cover}) {
  if (!Platform.isAndroid && !Platform.isIOS) {
    return SizedBox.expand(key: ValueKey('media-$mediaKey-$fit'));
  }
  final renderer = PlatformBridge.renderers[mediaKey];
  if (renderer == null) {
    return ColoredBox(
      key: ValueKey('media-$mediaKey-$fit'),
      color: const Color(0xFF000000),
    );
  }
  return RTCVideoView(
    renderer,
    key: ValueKey('media-$mediaKey-$fit'),
    objectFit: fit == BoxFit.contain
        ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
        : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
  );
}

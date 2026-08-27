import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

Widget attachmentVideoView({required String url, required String viewKey}) {
  return HtmlElementView.fromTagName(
    key: ValueKey('video-el-$viewKey'),
    tagName: 'video',
    onElementCreated: (element) {
      final el = element as web.HTMLVideoElement;
      el.controls = true;
      el.preload = 'metadata';
      el.playsInline = true;
      el.setAttribute('playsinline', 'true');
      el.setAttribute('webkit-playsinline', 'true');
      el.style.setProperty('width', '100%');
      el.style.setProperty('height', '100%');
      el.style.setProperty('max-width', '100%');
      el.style.setProperty('object-fit', 'contain');
      el.style.setProperty('background', '#000');
      el.style.setProperty('border', '0');
      el.style.setProperty('border-radius', '8px');
      el.style.setProperty('display', 'block');
      el.src = url;
    },
  );
}

Widget attachmentAudioView({required String url, required String viewKey}) {
  return HtmlElementView.fromTagName(
    key: ValueKey('audio-el-$viewKey'),
    tagName: 'audio',
    onElementCreated: (element) {
      final el = element as web.HTMLAudioElement;
      el.controls = true;
      el.preload = 'metadata';
      el.style.setProperty('width', '100%');
      el.style.setProperty('max-width', '100%');
      el.style.setProperty('display', 'block');
      el.src = url;
    },
  );
}

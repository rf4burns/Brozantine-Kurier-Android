import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../protocol/platform.dart';

Widget mediaStreamView({required String mediaKey, BoxFit fit = BoxFit.cover}) {
  return HtmlElementView.fromTagName(
    key: ValueKey('media-$mediaKey'),
    tagName: 'video',
    onElementCreated: (element) {
      final el = element as web.HTMLVideoElement;
      el.autoplay = true;
      el.muted = true;
      el.setAttribute('playsinline', 'true');
      el.setAttribute('muted', 'true');
      final objectFit = fit == BoxFit.contain ? 'contain' : 'cover';
      el.style.setProperty('width', '100%');
      el.style.setProperty('height', '100%');
      el.style.setProperty('object-fit', objectFit);
      el.style.setProperty('background', '#000');
      el.style.setProperty('pointer-events', 'none');
      el.style.setProperty('border', '0');
      el.style.setProperty('border-radius', 'inherit');
      PlatformBridge.bindMediaElement(mediaKey, el as JSAny);
    },
  );
}

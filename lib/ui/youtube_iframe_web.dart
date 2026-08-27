import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

bool get kCanEmbedYoutubeIFrame => true;

Widget youtubeIFrameView(String videoId) {
  return HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (element) {
      final iframe = element as web.HTMLIFrameElement;
      iframe.src =
          'https://www.youtube-nocookie.com/embed/$videoId?autoplay=1&rel=0';
      iframe.title = 'YouTube video';
      iframe.setAttribute(
        'allow',
        'accelerometer; autoplay; clipboard-write; encrypted-media; '
            'gyroscope; picture-in-picture; web-share',
      );
      iframe.setAttribute('allowfullscreen', 'true');
      iframe.setAttribute(
        'referrerpolicy',
        'strict-origin-when-cross-origin',
      );
      iframe.style.setProperty('border', '0');
      iframe.style.setProperty('width', '100%');
      iframe.style.setProperty('height', '100%');
    },
  );
}

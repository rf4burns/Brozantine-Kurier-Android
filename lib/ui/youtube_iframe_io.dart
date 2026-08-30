import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// App origin used as the WebView [baseUrl] so YouTube receives a Referer.
///
/// Loading the embed URL as the top-level document triggers Error 153.
const kYoutubeNativeEmbedOrigin = 'https://com.brozantine.kurier';

bool get kCanEmbedYoutubeIFrame => Platform.isAndroid || Platform.isIOS;

/// Host page that wraps the privacy-enhanced YouTube iframe.
String youtubeNativePlayerHtml(String videoId) {
  return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <meta name="referrer" content="strict-origin-when-cross-origin">
  <style>
    html, body, iframe {
      margin: 0;
      padding: 0;
      height: 100%;
      width: 100%;
      border: 0;
      background: #000;
      overflow: hidden;
    }
  </style>
</head>
<body>
  <iframe
    src="https://www.youtube-nocookie.com/embed/$videoId?autoplay=1&rel=0&playsinline=1"
    title="YouTube video"
    allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
    allowfullscreen
    referrerpolicy="strict-origin-when-cross-origin">
  </iframe>
</body>
</html>
''';
}

Widget youtubeIFrameView(String videoId) {
  if (!kCanEmbedYoutubeIFrame) return const SizedBox.shrink();
  return _YoutubeWebView(videoId: videoId);
}

class _YoutubeWebView extends StatefulWidget {
  const _YoutubeWebView({required this.videoId});
  final String videoId;

  @override
  State<_YoutubeWebView> createState() => _YoutubeWebViewState();
}

class _YoutubeWebViewState extends State<_YoutubeWebView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _createController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..loadHtmlString(
        youtubeNativePlayerHtml(widget.videoId),
        baseUrl: '$kYoutubeNativeEmbedOrigin/',
      );
  }

  WebViewController _createController() {
    final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params);
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setMediaPlaybackRequiresUserGesture(false);
    }
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

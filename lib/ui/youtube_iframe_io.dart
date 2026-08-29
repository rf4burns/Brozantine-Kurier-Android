import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

bool get kCanEmbedYoutubeIFrame => Platform.isAndroid || Platform.isIOS;

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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(
        Uri.parse(
          'https://www.youtube-nocookie.com/embed/${widget.videoId}?autoplay=1&rel=0',
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}

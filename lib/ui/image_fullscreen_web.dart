import 'dart:js_interop';

import 'package:web/web.dart' as web;

JSFunction? _jsListener;
void Function()? _onChange;

bool get imageFullscreenActive => web.document.fullscreenElement != null;

Future<void> enterImageFullscreen() async {
  final el = web.document.documentElement;
  if (el == null || imageFullscreenActive) return;
  try {
    await (el as web.HTMLElement).requestFullscreen().toDart;
  } catch (_) {}
}

Future<void> exitImageFullscreen() async {
  if (!imageFullscreenActive) return;
  try {
    await web.document.exitFullscreen().toDart;
  } catch (_) {}
}

void subscribeImageFullscreen(void Function() onChange) {
  unsubscribeImageFullscreen();
  _onChange = onChange;
  void handle(web.Event _) {
    _onChange?.call();
  }

  _jsListener = handle.toJS;
  web.document.addEventListener('fullscreenchange', _jsListener);
}

void unsubscribeImageFullscreen() {
  if (_jsListener != null) {
    web.document.removeEventListener('fullscreenchange', _jsListener);
    _jsListener = null;
  }
  _onChange = null;
}

void resetImageFullscreen() {
  unsubscribeImageFullscreen();
}

import 'dart:io';

import 'package:flutter/services.dart';

bool _active = false;
void Function()? _onChange;

bool get imageFullscreenActive => _active;

Future<void> enterImageFullscreen() async {
  _active = true;
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  _onChange?.call();
}

Future<void> exitImageFullscreen() async {
  if (!_active) return;
  _active = false;
  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  _onChange?.call();
}

void subscribeImageFullscreen(void Function() onChange) {
  _onChange = onChange;
}

void unsubscribeImageFullscreen() {
  _onChange = null;
}

void resetImageFullscreen() {
  _active = false;
  _onChange = null;
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

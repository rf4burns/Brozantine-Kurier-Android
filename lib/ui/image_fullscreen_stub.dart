bool _active = false;
void Function()? _onChange;

bool get imageFullscreenActive => _active;

Future<void> enterImageFullscreen() async {
  _active = true;
  _onChange?.call();
}

Future<void> exitImageFullscreen() async {
  if (!_active) return;
  _active = false;
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
}

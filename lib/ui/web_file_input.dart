import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'web_file_input_stub.dart'
    if (dart.library.js_interop) 'web_file_input_web.dart'
    if (dart.library.io) 'web_file_input_stub.dart' as impl;

typedef OverlayPickedFile = ({String name, Uint8List bytes});

Widget overlayAttachControl({
  required String tooltip,
  required Future<void> Function(List<OverlayPickedFile> files) onPicked,
  required VoidCallback onNativePick,
}) {
  return impl.overlayAttachControl(
    tooltip: tooltip,
    onPicked: onPicked,
    onNativePick: onNativePick,
  );
}

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'shared.dart';

Widget overlayAttachControl({
  required String tooltip,
  required Future<void> Function(
    List<({String name, Uint8List bytes})> files,
  )
  onPicked,
  required VoidCallback onNativePick,
}) {
  return CompactIconButton(
    icon: Icons.attach_file,
    iconSize: 20,
    tooltip: tooltip,
    onPressed: onNativePick,
  );
}

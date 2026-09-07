import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../app/breakpoints.dart';
import '../protocol/platform.dart';
import 'shared.dart';

Widget overlayAttachControl({
  required String tooltip,
  required Future<void> Function(
    List<({String name, Uint8List bytes})> files,
  )
  onPicked,
  required VoidCallback onNativePick,
}) {
  return SizedBox(
    width: kCompactBtn,
    height: kCompactBtn,
    child: Stack(
      alignment: Alignment.center,
      children: [
        IgnorePointer(
          child: CompactIconButton(
            icon: Icons.attach_file,
            iconSize: 20,
            tooltip: tooltip,
            onPressed: () {},
          ),
        ),
        Positioned.fill(
          child: HtmlElementView.fromTagName(
            tagName: 'input',
            onElementCreated: (element) {
              final el = element as web.HTMLInputElement;
              el.type = 'file';
              el.accept = 'image/*,video/*,*/*';
              el.multiple = !PlatformBridge.isIos;
              el.title = tooltip;
              el.style
                ..setProperty('position', 'absolute')
                ..setProperty('inset', '0')
                ..setProperty('width', '100%')
                ..setProperty('height', '100%')
                ..setProperty('opacity', '0')
                ..setProperty('cursor', 'pointer')
                ..setProperty('font-size', '32px')
                ..setProperty('border', '0')
                ..setProperty('padding', '0')
                ..setProperty('margin', '0');
              el.addEventListener(
                'change',
                (web.Event _) {
                  final list = el.files;
                  el.value = '';
                  if (list == null || list.length == 0) {
                    onPicked(const []);
                    return;
                  }
                  final n = list.length;
                  () async {
                    final picked = <({String name, Uint8List bytes})>[];
                    for (var i = 0; i < n; i++) {
                      final file = list.item(i);
                      if (file == null) continue;
                      try {
                        final buf = await file.arrayBuffer().toDart;
                        picked.add((
                          name: file.name,
                          bytes: Uint8List.view(buf.toDart),
                        ));
                      } catch (_) {}
                    }
                    await onPicked(picked);
                  }();
                }.toJS,
              );
            },
          ),
        ),
      ],
    ),
  );
}

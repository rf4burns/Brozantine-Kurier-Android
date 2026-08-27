import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/breakpoints.dart';
import '../app/theme.dart';

class PanelResizeHandle extends StatefulWidget {
  const PanelResizeHandle({super.key, required this.onDrag});

  static const channelsKey = ValueKey<String>('panel-resize-channels');
  static const membersKey = ValueKey<String>('panel-resize-members');

  final ValueChanged<double> onDrag;

  @override
  State<PanelResizeHandle> createState() => _PanelResizeHandleState();
}

class _PanelResizeHandleState extends State<PanelResizeHandle> {
  bool _hot = false;

  void _setHot(bool value) {
    if (_hot == value) return;
    setState(() => _hot = value);
  }

  @override
  Widget build(BuildContext context) {
    final color = _hot ? context.k.accent : context.p.divider;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => _setHot(true),
      onExit: (_) => _setHot(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => _setHot(true),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => _setHot(false),
        onHorizontalDragCancel: () => _setHot(false),
        child: SizedBox(
          width: kResizeHandleWidth,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: _hot ? 4 : 1,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

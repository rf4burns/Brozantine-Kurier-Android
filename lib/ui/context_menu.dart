import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';

class MenuAction {
  const MenuAction({
    required this.label,
    required this.onTap,
    this.icon,
    this.danger = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool danger;
  final bool enabled;
}

Future<void> showAppContextMenu(
  BuildContext context,
  Offset globalPosition,
  List<MenuAction> actions,
) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final selected = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    color: context.p.sidebar,
    items: [
      for (var i = 0; i < actions.length; i++)
        PopupMenuItem<int>(
          value: i,
          enabled: actions[i].enabled,
          child: Row(
            children: [
              if (actions[i].icon != null) ...[
                Icon(
                  actions[i].icon,
                  size: 18,
                  color: actions[i].danger ? context.p.dnd : context.p.muted,
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  actions[i].label,
                  style: TextStyle(
                    color: actions[i].danger ? context.p.dnd : context.p.foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
  if (selected != null) actions[selected].onTap();
}

class PositionedTap extends StatefulWidget {
  const PositionedTap({super.key, this.onTap, required this.child});

  final void Function(Offset globalPosition)? onTap;
  final Widget child;

  @override
  State<PositionedTap> createState() => _PositionedTapState();
}

class _PositionedTapState extends State<PositionedTap> {
  Offset? _tapPos;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:
          widget.onTap == null ? null : (d) => _tapPos = d.globalPosition,
      onTap: widget.onTap == null
          ? null
          : () => widget.onTap!(_tapPos ?? Offset.zero),
      child: widget.child,
    );
  }
}

class ContextRegion extends StatefulWidget {
  const ContextRegion({
    super.key,
    this.actions,
    required this.child,
    this.onTap,
    this.openMenu,
  });

  final List<MenuAction> Function()? actions;
  final Widget child;
  final void Function(Offset globalPosition)? onTap;
  final Future<void> Function(BuildContext context, Offset globalPosition)?
      openMenu;

  @override
  State<ContextRegion> createState() => _ContextRegionState();
}

class _ContextRegionState extends State<ContextRegion> {
  Offset? _tapPos;

  Future<void> _open(BuildContext context, Offset globalPosition) {
    if (widget.openMenu != null) {
      return widget.openMenu!(context, globalPosition);
    }
    return showAppContextMenu(
      context,
      globalPosition,
      widget.actions?.call() ?? const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null
          ? null
          : (d) => _tapPos = d.globalPosition,
      onTap: widget.onTap == null
          ? null
          : () => widget.onTap!(_tapPos ?? Offset.zero),
      onSecondaryTapUp: (d) {
        _open(context, d.globalPosition);
      },
      onLongPressStart: (d) {
        HapticFeedback.mediumImpact();
        _open(context, d.globalPosition);
      },
      child: widget.child,
    );
  }
}

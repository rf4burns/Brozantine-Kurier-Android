import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';

const _menuWidth = 260.0;
const _menuInset = 8.0;

class MenuAction {
  const MenuAction({
    required this.label,
    required this.onTap,
    this.icon,
    this.danger = false,
    this.enabled = true,
    this.dividerBefore = false,
    this.submenu = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool danger;
  final bool enabled;
  final bool dividerBefore;
  final bool submenu;
}

typedef ContextMenuHeaderBuilder = Widget Function(
  BuildContext context,
  VoidCallback close,
);

Future<void> showAppContextMenu(
  BuildContext context,
  Offset globalPosition,
  List<MenuAction> actions, {
  ContextMenuHeaderBuilder? header,
}) async {
  final visible = actions.where((a) => a.enabled).toList();
  if (visible.isEmpty && header == null) return;

  await Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black26,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (ctx, _, _) => _ContextMenuPage(
        anchor: globalPosition,
        actions: visible,
        header: header,
      ),
    ),
  );
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
    this.header,
    required this.child,
    this.onTap,
    this.openMenu,
  });

  final List<MenuAction> Function()? actions;
  final ContextMenuHeaderBuilder? header;
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
      header: widget.header,
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

class _ContextMenuPage extends StatelessWidget {
  const _ContextMenuPage({
    required this.anchor,
    required this.actions,
    this.header,
  });

  final Offset anchor;
  final List<MenuAction> actions;
  final ContextMenuHeaderBuilder? header;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final availW = size.width - pad.left - pad.right - _menuInset * 2;
    final width = math.min(_menuWidth, availW);

    var left = anchor.dx;
    if (left + width > size.width - pad.right - _menuInset) {
      left = size.width - width - pad.right - _menuInset;
    }
    if (left < pad.left + _menuInset) left = pad.left + _menuInset;

    final maxH = size.height - pad.top - pad.bottom - _menuInset * 2;
    var top = anchor.dy;
    final minTop = pad.top + _menuInset;
    final spaceBelow = size.height - pad.bottom - top - _menuInset;
    if (spaceBelow < 160) {
      top = (anchor.dy - 200).clamp(minTop, size.height);
    }
    if (top < minTop) top = minTop;
    final heightCap =
        (size.height - pad.bottom - top - _menuInset).clamp(80.0, maxH);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: width,
                maxWidth: width,
                maxHeight: heightCap,
              ),
              child: _KurierMenuCard(
                actions: actions,
                header: header,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KurierMenuCard extends StatelessWidget {
  const _KurierMenuCard({
    required this.actions,
    this.header,
  });

  final List<MenuAction> actions;
  final ContextMenuHeaderBuilder? header;

  void _close(BuildContext context) {
    Navigator.of(context).pop();
  }

  void _run(BuildContext context, MenuAction action) {
    _close(context);
    action.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Material(
      color: p.sidebar,
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header != null) header!(context, () => _close(context)),
            for (var i = 0; i < actions.length; i++) ...[
              if (actions[i].dividerBefore &&
                  (header != null || i > 0))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Divider(color: p.divider, height: 1),
                ),
              _MenuRow(
                action: actions[i],
                onTap: () => _run(context, actions[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.action,
    required this.onTap,
  });

  final MenuAction action;
  final VoidCallback onTap;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final danger = widget.action.danger;
    final color = danger ? p.dnd : p.foreground;
    final iconColor = danger ? p.dnd : p.muted;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover ? p.card.withValues(alpha: 0.7) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  if (widget.action.icon != null) ...[
                    Icon(widget.action.icon, size: 18, color: iconColor),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      widget.action.label,
                      style: TextStyle(color: color, fontSize: 14),
                    ),
                  ),
                  if (widget.action.submenu)
                    Icon(Icons.chevron_right, size: 18, color: p.faint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/breakpoints.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import 'shared.dart';

const kSettingsNavWidth = 232.0;
const kSettingsContentMax = 1152.0;

class SettingsNavItem {
  const SettingsNavItem({
    required this.id,
    required this.label,
    this.icon,
    this.disabled = false,
  });

  final String id;
  final String label;
  final IconData? icon;
  final bool disabled;
}

class SettingsNavGroup {
  const SettingsNavGroup({this.label, required this.items});

  final String? label;
  final List<SettingsNavItem> items;
}

bool settingsIsCompact(BuildContext context) =>
    breakpointOf(MediaQuery.sizeOf(context).width) != Breakpoint.desktop;

class SettingsScreenLayout extends StatefulWidget {
  const SettingsScreenLayout({
    super.key,
    required this.title,
    required this.groups,
    required this.current,
    required this.onSelect,
    required this.onClose,
    required this.body,
    this.header,
    this.onHeaderTap,
    this.footer,
    this.startOnDetail = false,
    this.scrollBody = true,
    this.constrainWidth = true,
  });

  final String title;
  final List<SettingsNavGroup> groups;
  final String current;
  final ValueChanged<String> onSelect;
  final VoidCallback onClose;
  final WidgetBuilder body;
  final Widget? header;
  final VoidCallback? onHeaderTap;
  final Widget? footer;
  final bool startOnDetail;
  final bool scrollBody;
  final bool constrainWidth;

  @override
  State<SettingsScreenLayout> createState() => _SettingsScreenLayoutState();
}

class _SettingsScreenLayoutState extends State<SettingsScreenLayout>
    with SingleTickerProviderStateMixin {
  late bool _pushed;
  late final AnimationController _sheet;

  @override
  void initState() {
    super.initState();
    _pushed = widget.startOnDetail;
    _sheet = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..forward();
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  String get _currentLabel {
    for (final group in widget.groups) {
      for (final item in group.items) {
        if (item.id == widget.current) return item.label;
      }
    }
    return widget.title;
  }

  void _open(String id) {
    widget.onSelect(id);
    setState(() => _pushed = true);
  }

  void _openHeader() {
    widget.onHeaderTap?.call();
    setState(() => _pushed = true);
  }

  @override
  Widget build(BuildContext context) {
    final compact =
        breakpointOf(MediaQuery.sizeOf(context).width) != Breakpoint.desktop;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Focus(
        autofocus: true,
        child: compact ? _buildCompact(context) : _buildDesktop(context),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    final p = context.p;
    return ColoredBox(
      color: p.sidebar,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: kSettingsNavWidth,
            child: ColoredBox(
              color: p.sidebar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 12, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Text(
                      widget.title.toUpperCase(),
                      style: TextStyle(
                        color: p.faint,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  for (final group in widget.groups) ...[
                    if (group.label != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                        child: Text(
                          group.label!.toUpperCase(),
                          style: TextStyle(
                            color: p.faint,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    for (final item in group.items)
                      _NavButton(
                        item: item,
                        selected: widget.current == item.id,
                        onSelect: widget.onSelect,
                      ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: p.background,
              child: Column(
                children: [
                  SizedBox(
                    height: 56,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: _CloseEsc(
                          onClose: widget.onClose,
                          tooltip: L10n.of(context)('closeEsc'),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(40, 0, 40, 24),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = widget.constrainWidth &&
                                  constraints.maxWidth > kSettingsContentMax
                              ? kSettingsContentMax
                              : constraints.maxWidth;
                          return Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: width,
                              height: constraints.maxHeight,
                              child: widget.scrollBody
                                  ? SingleChildScrollView(
                                      padding: const EdgeInsets.only(
                                        bottom: 40,
                                      ),
                                      child: widget.body(context),
                                    )
                                  : widget.body(context),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _sheet, curve: Curves.easeOutCubic));
    return SlideTransition(
      position: slide,
      child: PopScope(
        canPop: !_pushed,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          setState(() => _pushed = false);
        },
        child: Material(
          color: context.p.rail,
          child: SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) => Stack(
                fit: StackFit.expand,
                children: [
                  ...previous,
                  if (current != null) current,
                ],
              ),
              transitionBuilder: (child, anim) {
                final isDetail = child.key == const ValueKey('detail');
                final offset = Tween<Offset>(
                  begin: Offset(isDetail ? 0.18 : -0.08, 0),
                  end: Offset.zero,
                ).animate(anim);
                return SlideTransition(
                  position: offset,
                  child: FadeTransition(opacity: anim, child: child),
                );
              },
              child: _pushed
                  ? KeyedSubtree(
                      key: const ValueKey('detail'),
                      child: _compactDetail(context),
                    )
                  : KeyedSubtree(
                      key: const ValueKey('list'),
                      child: _compactList(context),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactBar({
    required BuildContext context,
    required IconData leading,
    required VoidCallback onLeading,
    required String title,
  }) {
    final p = context.p;
    return SizedBox(
      height: kHeaderHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: Icon(leading, color: p.foreground),
              onPressed: onLeading,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.foreground,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactList(BuildContext context) {
    final p = context.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _compactBar(
          context: context,
          leading: Icons.close,
          onLeading: widget.onClose,
          title: widget.title,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (widget.header != null) ...[
                GestureDetector(
                  onTap: widget.onHeaderTap == null ? null : _openHeader,
                  behavior: HitTestBehavior.opaque,
                  child: widget.header,
                ),
                const SizedBox(height: 8),
              ],
              for (final group in widget.groups) ...[
                if (group.label != null &&
                    group.label!.toLowerCase() != widget.title.toLowerCase())
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                    child: Text(
                      group.label!.toUpperCase(),
                      style: TextStyle(
                        color: p.faint,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 8),
                _CompactGroupCard(
                  items: group.items,
                  onSelect: _open,
                ),
              ],
              if (widget.footer != null) ...[
                const SizedBox(height: 24),
                widget.footer!,
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _compactDetail(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _compactBar(
          context: context,
          leading: Icons.arrow_back,
          onLeading: () => setState(() => _pushed = false),
          title: _currentLabel,
        ),
        Expanded(
          child: ColoredBox(
            color: context.p.background,
            child: widget.scrollBody
                ? SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    child: widget.body(context),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: widget.body(context),
                  ),
          ),
        ),
      ],
    );
  }
}

class _CompactGroupCard extends StatelessWidget {
  const _CompactGroupCard({required this.items, required this.onSelect});

  final List<SettingsNavItem> items;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      decoration: BoxDecoration(
        color: p.sidebar,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: p.divider,
                indent: items[i].icon != null ? 48 : 16,
                endIndent: 16,
              ),
            _CompactRow(item: items[i], onSelect: onSelect),
          ],
        ],
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({required this.item, required this.onSelect});

  final SettingsNavItem item;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final muted = item.disabled;
    return InkWell(
      onTap: muted ? null : () => onSelect(item.id),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minTap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              if (item.icon != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    item.icon,
                    size: 16,
                    color: muted
                        ? p.faint.withValues(alpha: 0.4)
                        : p.foreground,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: muted
                        ? p.faint.withValues(alpha: 0.4)
                        : p.foreground,
                    fontSize: 16,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: muted ? p.faint.withValues(alpha: 0.4) : p.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onSelect,
  });

  final SettingsNavItem item;
  final bool selected;
  final ValueChanged<String> onSelect;

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final active = widget.selected || _hover;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.item.disabled
              ? null
              : () => widget.onSelect(widget.item.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: active && !widget.item.disabled
                  ? p.card
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.item.label,
              style: TextStyle(
                color: widget.item.disabled
                    ? p.faint.withValues(alpha: 0.4)
                    : active
                        ? p.foreground
                        : p.muted,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseEsc extends StatelessWidget {
  const _CloseEsc({required this.onClose, required this.tooltip});
  final VoidCallback onClose;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onClose,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: p.divider),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.close, size: 16, color: p.muted),
          ),
        ),
      ),
    );
  }
}

class SettingsPageHeader extends StatelessWidget {
  const SettingsPageHeader({
    super.key,
    required this.title,
    this.description,
  });

  final String title;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final compact = settingsIsCompact(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compact) ...[
          Text(
            title,
            style: TextStyle(
              color: p.foreground,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          if (description != null) const SizedBox(height: 4),
        ],
        if (description != null)
          Text(
            description!,
            style: TextStyle(color: p.muted, fontSize: 14, height: 1.4),
          ),
      ],
    );
  }
}

class SettingsSelect<T> extends StatelessWidget {
  const SettingsSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.minWidth = 0,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: 36),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.divider),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              borderRadius: BorderRadius.circular(6),
              dropdownColor: p.card,
              icon: Icon(Icons.expand_more, size: 18, color: p.foreground),
              style: TextStyle(color: p.foreground, fontSize: 14),
              isExpanded: minWidth > 0,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    this.title,
    this.description,
    required this.children,
    this.padding,
    this.expand = false,
  });

  final String? title;
  final String? description;
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final compact = settingsIsCompact(context);
    final showTitle = title != null && !compact;
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitle)
          Text(
            title!,
            style: TextStyle(
              color: p.foreground,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        if (description != null) ...[
          if (showTitle) const SizedBox(height: 6),
          Text(
            description!,
            style: TextStyle(color: p.muted, fontSize: 14, height: 1.4),
          ),
        ],
        if (showTitle || description != null) const SizedBox(height: 20),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          children[i],
        ],
      ],
    );
    return Container(
      width: double.infinity,
      height: expand ? double.infinity : null,
      padding: padding ??
          (compact
              ? const EdgeInsets.fromLTRB(16, 16, 16, 16)
              : const EdgeInsets.fromLTRB(24, 24, 24, 24)),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.divider),
      ),
      child: expand ? SingleChildScrollView(child: column) : column,
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    required this.label,
    this.description,
    required this.child,
  });

  final String label;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            color: p.foreground,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 2),
          Text(
            description!,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.35),
          ),
        ],
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class KurierSwitch extends StatelessWidget {
  const KurierSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final on = value;
    final bg = on ? context.k.accent : context.p.rail;
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: 32,
          height: 18,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsActions extends StatelessWidget {
  const SettingsActions({
    super.key,
    required this.cancelLabel,
    required this.saveLabel,
    required this.onCancel,
    required this.onSave,
    this.saveEnabled = true,
  });

  final String cancelLabel;
  final String saveLabel;
  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final bool saveEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: onCancel,
            child: Text(
              cancelLabel,
              style: TextStyle(color: context.p.muted, fontSize: 14),
            ),
          ),
          KurierButton(
            label: saveLabel,
            onPressed: saveEnabled ? onSave : null,
          ),
        ],
      ),
    );
  }
}

class SettingsSearchField extends StatelessWidget {
  const SettingsSearchField({
    super.key,
    required this.hint,
    required this.controller,
    this.onChanged,
  });

  final String hint;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return KurierField(
      controller: controller,
      hint: hint,
      dense: true,
      onChanged: onChanged,
      prefix: Icon(Icons.search, size: 18, color: context.p.faint),
    );
  }
}

class SettingsSplitPane extends StatelessWidget {
  const SettingsSplitPane({
    super.key,
    required this.left,
    required this.right,
    this.leftWidth = 320,
  });

  final Widget left;
  final Widget right;
  final double leftWidth;

  @override
  Widget build(BuildContext context) {
    if (settingsIsCompact(context)) return left;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: leftWidth, child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SizedBox.expand(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SettingsSegmented extends StatelessWidget {
  const SettingsSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.rail,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++)
              Padding(
                padding: const EdgeInsets.all(4),
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: i == index ? p.card : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: i == index ? p.foreground : p.muted,
                        fontSize: 14,
                        fontWeight:
                            i == index ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SettingsToggleRow extends StatelessWidget {
  const SettingsToggleRow({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
    this.leadingSwitch = false,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool leadingSwitch;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final enabled = onChanged != null;
    final text = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: enabled ? p.foreground : p.muted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 2),
            Text(
              description!,
              style: TextStyle(color: p.muted, fontSize: 13, height: 1.35),
            ),
          ],
        ],
      ),
    );
    final toggle = KurierSwitch(value: value, onChanged: onChanged);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: leadingSwitch
          ? [toggle, const SizedBox(width: 12), text]
          : [text, const SizedBox(width: 12), toggle],
    );
  }
}

class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: context.p.faint,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );
  }
}

class SettingsDropdown<T> extends StatelessWidget {
  const SettingsDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.rail,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            hint: hint == null
                ? null
                : Text(hint!, style: TextStyle(color: p.faint, fontSize: 14)),
            borderRadius: BorderRadius.circular(8),
            dropdownColor: p.card,
            icon: Icon(Icons.expand_more, size: 20, color: p.muted),
            style: TextStyle(color: p.foreground, fontSize: 14),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class SettingsChoiceCards extends StatelessWidget {
  const SettingsChoiceCards({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _ChoiceCard(
              label: options[i].$2,
              selected: value == options[i].$1,
              onTap: () => onChanged(options[i].$1),
              accent: context.k.accent,
              palette: p,
            ),
          ),
        ],
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accent,
    required this.palette,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: palette.rail,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? accent : palette.divider,
            width: selected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: palette.foreground,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class SettingsThemeTile extends StatelessWidget {
  const SettingsThemeTile({
    super.key,
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = palettes[preset]!;
    final name = preset.name[0].toUpperCase() + preset.name.substring(1);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected ? context.k.accent : pal.divider,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ColoredBox(
                      color: pal.rail,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: pal.sidebar,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: ColoredBox(
                      color: pal.background,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? context.p.foreground : context.p.muted,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsAccentSwatch extends StatelessWidget {
  const SettingsAccentSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: context.k.accent.withValues(alpha: 0.6),
                    blurRadius: 0,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}

class SettingsColorPicker extends StatelessWidget {
  const SettingsColorPicker({
    super.key,
    required this.value,
    required this.swatches,
    required this.onChanged,
  });

  final String value;
  final List<Color> swatches;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = colorFromHex(value);
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: selected,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.p.divider),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in swatches)
                GestureDetector(
                  onTap: () => onChanged(colorToHex(c)),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: colorToHex(c).toUpperCase() ==
                                value.toUpperCase()
                            ? Colors.white
                            : context.p.divider,
                        width: colorToHex(c).toUpperCase() ==
                                value.toUpperCase()
                            ? 2
                            : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: context.k.accent,
        inactiveTrackColor: context.p.rail,
        thumbColor: Colors.white,
        overlayColor: context.k.accent.withValues(alpha: 0.16),
        trackHeight: 4,
      ),
      child: Slider(
        min: min,
        max: max,
        value: value.clamp(min, max),
        onChanged: onChanged,
      ),
    );
  }
}

class SettingsDangerRow extends StatelessWidget {
  const SettingsDangerRow({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.p.sidebar,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.logout, size: 18, color: context.p.dnd),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: context.p.dnd,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String colorToHex(Color c) {
  final hex = c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
  return '#${hex.toUpperCase()}';
}

class SettingsStickyFooter extends StatelessWidget {
  const SettingsStickyFooter({
    super.key,
    required this.cancelLabel,
    required this.saveLabel,
    required this.onCancel,
    required this.onSave,
    this.saveEnabled = true,
  });

  final String cancelLabel;
  final String saveLabel;
  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final bool saveEnabled;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: p.sidebar,
        border: Border(top: BorderSide(color: p.divider)),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: onCancel,
            child: Text(cancelLabel, style: TextStyle(color: p.muted)),
          ),
          KurierButton(
            label: saveLabel,
            onPressed: saveEnabled ? onSave : null,
          ),
        ],
      ),
    );
  }
}

class RoleColorDot extends StatelessWidget {
  const RoleColorDot({super.key, required this.color, this.size = 12});

  final String color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorFromHex(color),
        shape: BoxShape.circle,
      ),
    );
  }
}

Color colorFromHex(String hex) {
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 3) {
    s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
  }
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return const Color(0xFF80848E);
  return Color(int.parse(s, radix: 16));
}

class SettingsEmptyHint extends StatelessWidget {
  const SettingsEmptyHint({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: context.p.muted, fontSize: 14),
        ),
      ),
    );
  }
}

InputDecoration settingsInputDecoration(BuildContext context, {String? hint}) {
  final p = context.p;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: p.faint, fontSize: 15),
    filled: true,
    fillColor: p.rail,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: p.divider),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: p.divider),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: context.k.accent),
    ),
  );
}

class OverlayDialogShell extends StatelessWidget {
  const OverlayDialogShell({
    super.key,
    required this.onClose,
    required this.child,
    this.maxWidth = 512,
  });

  final VoidCallback onClose;
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): onClose,
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          onTap: onClose,
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.5),
            child: Center(
              child: GestureDetector(
                onTap: () {},
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Material(
                    color: p.background,
                    elevation: 8,
                    shadowColor: Colors.black54,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: p.divider),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

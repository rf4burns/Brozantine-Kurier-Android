import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/config.dart';
import '../protocol/mentions.dart';
import '../protocol/permissions.dart';
import '../session/session_controller.dart';
import 'shared.dart';

void replaceMentionQuery(
  TextEditingController controller,
  String insert, {
  int maxLength = AppConfig.maxMessageLength,
}) {
  if (insert.isEmpty) return;
  final text = controller.text;
  final sel = controller.selection;
  final cursor = sel.isValid ? sel.extentOffset : text.length;
  final q = mentionQueryAt(text, cursor);
  if (q == null) return;
  var replacement = '@$insert ';
  final available = maxLength - (text.length - (cursor - q.atIndex));
  if (available <= 0) return;
  if (replacement.length > available) {
    replacement = replacement.substring(0, available);
  }
  controller.value = TextEditingValue(
    text: text.replaceRange(q.atIndex, cursor, replacement),
    selection: TextSelection.collapsed(offset: q.atIndex + replacement.length),
  );
}

class MentionMenuController extends ChangeNotifier {
  MentionMenuController({required this.controller, required this.session}) {
    controller.addListener(_rebuild);
    session.addListener(_rebuild);
    _rebuild();
  }

  final TextEditingController controller;
  final SessionController session;

  String _queryKey = '';
  bool dismissed = false;
  int highlighted = 0;
  List<MentionCandidate> items = const [];
  MentionQuery? query;

  bool get isOpen => query != null && !dismissed && items.isNotEmpty;

  void _rebuild() {
    final text = controller.text;
    final sel = controller.selection;
    final cursor = sel.isValid ? sel.extentOffset : text.length;
    final next = mentionQueryAt(text, cursor);
    final key = next == null ? '' : '${next.atIndex}:${next.query}';
    query = next;
    if (key != _queryKey) {
      _queryKey = key;
      dismissed = false;
      highlighted = 0;
    }
    items = next == null
        ? const []
        : mentionCandidates(
            users: session.users.values,
            query: next.query,
            canMentionEveryone: session.can(Permission.mentionEveryone),
          );
    if (items.isEmpty) {
      highlighted = 0;
    } else if (highlighted >= items.length) {
      highlighted = items.length - 1;
    }
    notifyListeners();
  }

  void select(MentionCandidate candidate) {
    replaceMentionQuery(controller, candidate.insert);
    dismissed = true;
    notifyListeners();
  }

  bool applyHighlighted() {
    if (!isOpen) return false;
    select(items[highlighted]);
    return true;
  }

  void dismiss() {
    if (!isOpen) return;
    dismissed = true;
    notifyListeners();
  }

  void highlightAt(int index) {
    if (index < 0 || index >= items.length) return;
    highlighted = index;
    notifyListeners();
  }

  void highlightNext() {
    if (items.isEmpty) return;
    highlighted = (highlighted + 1) % items.length;
    notifyListeners();
  }

  void highlightPrevious() {
    if (items.isEmpty) return;
    highlighted = (highlighted - 1 + items.length) % items.length;
    notifyListeners();
  }

  @override
  void dispose() {
    controller.removeListener(_rebuild);
    session.removeListener(_rebuild);
    super.dispose();
  }
}

class MentionNextIntent extends Intent {
  const MentionNextIntent();
}

class MentionPrevIntent extends Intent {
  const MentionPrevIntent();
}

class MentionDismissIntent extends Intent {
  const MentionDismissIntent();
}

class MentionApplyIntent extends Intent {
  const MentionApplyIntent();
}

Map<ShortcutActivator, Intent> mentionShortcutMap({
  required bool includeApply,
}) {
  return {
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const MentionNextIntent(),
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const MentionPrevIntent(),
    const SingleActivator(LogicalKeyboardKey.escape):
        const MentionDismissIntent(),
    if (includeApply)
      const SingleActivator(LogicalKeyboardKey.tab): const MentionApplyIntent(),
  };
}

Map<Type, Action<Intent>> mentionShortcutActions(
  MentionMenuController menu, {
  VoidCallback? onApplyOrSend,
}) {
  return {
    MentionNextIntent: _OpenMenuAction<MentionNextIntent>(
      menu: menu,
      onInvoke: (_) {
        menu.highlightNext();
        return null;
      },
    ),
    MentionPrevIntent: _OpenMenuAction<MentionPrevIntent>(
      menu: menu,
      onInvoke: (_) {
        menu.highlightPrevious();
        return null;
      },
    ),
    MentionDismissIntent: _OpenMenuAction<MentionDismissIntent>(
      menu: menu,
      onInvoke: (_) {
        menu.dismiss();
        return null;
      },
    ),
    MentionApplyIntent: _OpenMenuAction<MentionApplyIntent>(
      menu: menu,
      onInvoke: (_) {
        if (menu.applyHighlighted()) return null;
        onApplyOrSend?.call();
        return null;
      },
    ),
  };
}

class _OpenMenuAction<T extends Intent> extends CallbackAction<T> {
  _OpenMenuAction({required this.menu, required super.onInvoke});

  final MentionMenuController menu;

  @override
  bool isEnabled(T intent) => menu.isOpen;
}

class MentionSuggestionMenu extends StatelessWidget {
  const MentionSuggestionMenu({
    super.key,
    required this.session,
    required this.items,
    required this.highlighted,
    required this.onHighlight,
    required this.onSelect,
  });

  final SessionController session;
  final List<MentionCandidate> items;
  final int highlighted;
  final ValueChanged<int> onHighlight;
  final ValueChanged<MentionCandidate> onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.p.rail,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: context.p.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: Scrollbar(
          thickness: 6,
          radius: const Radius.circular(8),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              final selected = i == highlighted;
              return MouseRegion(
                onEnter: (_) => onHighlight(i),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(item),
                  child: ColoredBox(
                    key: ValueKey('mention-${item.key}'),
                    color: selected
                        ? context.p.card.withValues(alpha: 0.95)
                        : Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          _leading(context, item),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.p.foreground,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                if (item.subtitle != null)
                                  Text(
                                    item.subtitle!,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.p.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _leading(BuildContext context, MentionCandidate item) {
    if (item.kind == MentionKind.user) {
      return UserAvatar(user: item.user, session: session, size: 28);
    }
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.p.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.alternate_email, size: 16, color: context.k.accent),
    );
  }
}

class MentionSuggestionColumn extends StatelessWidget {
  const MentionSuggestionColumn({
    super.key,
    required this.menu,
    required this.child,
  });

  final MentionMenuController menu;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: menu,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (menu.isOpen) ...[
              MentionSuggestionMenu(
                session: menu.session,
                items: menu.items,
                highlighted: menu.highlighted,
                onHighlight: menu.highlightAt,
                onSelect: menu.select,
              ),
              const SizedBox(height: 6),
            ],
            child,
          ],
        );
      },
    );
  }
}

Future<String?> showMentionEditDialog({
  required BuildContext context,
  required SessionController session,
  required String initialText,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) =>
        _MentionEditDialog(session: session, initialText: initialText),
  );
}

class _MentionEditDialog extends StatefulWidget {
  const _MentionEditDialog({required this.session, required this.initialText});

  final SessionController session;
  final String initialText;

  @override
  State<_MentionEditDialog> createState() => _MentionEditDialogState();
}

class _MentionEditDialogState extends State<_MentionEditDialog> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;
  late final MentionMenuController _menu;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialText);
    _focus = FocusNode();
    _menu = MentionMenuController(controller: _ctrl, session: widget.session);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _menu.dispose();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return AlertDialog(
      title: Text(l('editMessage')),
      content: Shortcuts(
        shortcuts: mentionShortcutMap(includeApply: true),
        child: Actions(
          actions: mentionShortcutActions(_menu),
          child: MentionSuggestionColumn(
            menu: _menu,
            child: KurierField(
              controller: _ctrl,
              focusNode: _focus,
              maxLines: 4,
              maxLength: AppConfig.maxMessageLength,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(l('save')),
        ),
      ],
    );
  }
}

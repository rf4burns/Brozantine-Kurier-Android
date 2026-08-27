import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/mentions.dart';
import '../protocol/models.dart';
import '../protocol/search_query.dart';
import '../session/session_controller.dart';
import 'shared.dart';

const _operatorDescKeys = {
  'from': 'searchOpFrom',
  'mentions': 'searchOpMentions',
  'in': 'searchOpIn',
  'has': 'searchOpHas',
  'before': 'searchOpBefore',
  'after': 'searchOpAfter',
  'during': 'searchOpDuring',
  'pinned': 'searchOpPinned',
};

const _dateOperators = {'before', 'after', 'during'};

class SearchDialog extends StatefulWidget {
  const SearchDialog({super.key, required this.session});
  final SessionController session;

  @override
  State<SearchDialog> createState() => _SearchDialogState();
}

class _SearchSuggestion {
  const _SearchSuggestion({
    required this.label,
    required this.insert,
    required this.keyName,
    this.description,
    this.trailingSpace = false,
    this.pickDate = false,
  });

  final String label;
  final String insert;
  final String keyName;
  final String? description;
  final bool trailingSpace;
  final bool pickDate;
}

class _SearchDialogState extends State<SearchDialog> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  int _highlighted = 0;
  bool _menuDismissed = false;
  bool _ran = false;
  String _lastText = '';

  SessionController get s => widget.session;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onText);
    _focus.addListener(_onFocus);
    _focus.onKeyEvent = _onKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onText() {
    if (_ctrl.text != _lastText) {
      _lastText = _ctrl.text;
      _menuDismissed = false;
      _highlighted = 0;
    }
    setState(() {});
  }

  void _onFocus() {
    if (_focus.hasFocus) _menuDismissed = false;
    setState(() {});
  }

  String get _prefix {
    final text = _ctrl.text;
    final offset = _ctrl.selection.baseOffset;
    if (offset < 0 || offset > text.length) return text;
    return text.substring(0, offset);
  }

  List<_SearchSuggestion> _suggestions(L10n l) {
    final prefix = _prefix;
    final active = activeSearchToken(prefix);
    if (active.key != null && searchOperatorKeys.contains(active.key)) {
      return _valueSuggestions(l, active.key!, active.value ?? '');
    }
    return [
      for (final key in matchingSearchOperators(prefix))
        _SearchSuggestion(
          label: '$key:',
          insert: '$key:',
          keyName: key,
          description: l(_operatorDescKeys[key] ?? key),
          pickDate: _dateOperators.contains(key),
        ),
    ];
  }

  List<_SearchSuggestion> _valueSuggestions(L10n l, String key, String value) {
    final q = value.toLowerCase();
    bool matches(String name) => q.isEmpty || name.toLowerCase().contains(q);

    switch (key) {
      case 'from':
      case 'mentions':
        final users = s.users.values
            .where((u) => !u.deleted && !u.banned)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        return [
          for (final u in users)
            if (matches(u.displayName) || matches(u.name))
              _SearchSuggestion(
                label: u.name.isNotEmpty ? u.name : u.displayName,
                insert: formatSearchOperatorToken(key, u.name),
                keyName: '${key}-${u.id}',
                trailingSpace: true,
              ),
        ].take(50).toList();
      case 'in':
        final channels = s.channels.values
            .where((c) => c.isText && !c.isDm)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        return [
          for (final c in channels)
            if (matches(c.name) || matches('#${c.name}'))
              _SearchSuggestion(
                label: '#${c.name}',
                insert: formatSearchOperatorToken(key, c.name),
                keyName: 'in-${c.id}',
                trailingSpace: true,
              ),
        ];
      case 'has':
        return [
          for (final item in searchHasValues)
            if (matches(item))
              _SearchSuggestion(
                label: item,
                insert: formatSearchOperatorToken(key, item),
                keyName: 'has-$item',
                trailingSpace: true,
              ),
        ];
      case 'pinned':
        return [
          for (final item in const ['true', 'false'])
            if (matches(item))
              _SearchSuggestion(
                label: item,
                insert: formatSearchOperatorToken(key, item),
                keyName: 'pinned-$item',
                trailingSpace: true,
              ),
        ];
      case 'before':
      case 'after':
      case 'during':
        if (value.isNotEmpty) return const [];
        return [
          _SearchSuggestion(
            label: l('searchPickDate'),
            insert: '$key:',
            keyName: 'date-$key',
            pickDate: true,
          ),
        ];
      default:
        return const [];
    }
  }

  void _replaceActive(String token, {bool trailingSpace = false}) {
    final prefix = _prefix;
    final active = activeSearchToken(prefix);
    final after = _ctrl.text.substring(
      _ctrl.selection.baseOffset.clamp(0, _ctrl.text.length),
    );
    final next =
        '${replaceActiveSearchToken(prefix, token, trailingSpace: trailingSpace)}$after';
    final caret = active.start + token.length + (trailingSpace ? 1 : 0);
    _ctrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret),
    );
  }

  Future<void> _apply(_SearchSuggestion suggestion) async {
    _replaceActive(
      suggestion.insert,
      trailingSpace: suggestion.trailingSpace && !suggestion.pickDate,
    );
    _focus.requestFocus();
    if (suggestion.pickDate) {
      await _pickDate(suggestion.insert.split(':').first);
    }
  }

  Future<void> _pickDate(String key) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2000),
      lastDate: now.add(const Duration(days: 1)),
    );
    if (!mounted || picked == null) {
      _focus.requestFocus();
      return;
    }
    _replaceActive(
      formatSearchOperatorToken(key, formatSearchDate(picked)),
      trailingSpace: true,
    );
    _focus.requestFocus();
  }

  void _runSearch() {
    _menuDismissed = true;
    _ran = true;
    s.search(_ctrl.text);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final l = L10n.of(context);
    final items = _suggestions(l);
    final showMenu = _focus.hasFocus && !_menuDismissed && items.isNotEmpty;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (showMenu) {
        setState(() => _menuDismissed = true);
        return KeyEventResult.handled;
      }
      Navigator.maybePop(context);
      return KeyEventResult.handled;
    }

    if (!showMenu) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _highlighted = (_highlighted + 1) % items.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _highlighted = (_highlighted - 1 + items.length) % items.length,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_highlighted >= 0 && _highlighted < items.length) {
        _apply(items[_highlighted]);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Dialog(
      child: SizedBox(
        width: 560,
        height: 520,
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            final items = _suggestions(l);
            final showMenu = !_menuDismissed && items.isNotEmpty;
            final highlighted =
                items.isEmpty ? 0 : _highlighted.clamp(0, items.length - 1);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l('search'),
                          style: TextStyle(
                            color: context.p.foreground,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      CompactIconButton(
                        tooltip: l('close'),
                        icon: Icons.close,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l('searchDesc'),
                    style: TextStyle(color: context.p.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  KurierField(
                    controller: _ctrl,
                    focusNode: _focus,
                    dense: true,
                    hint: l('searchPlaceholder'),
                    onSubmitted: (_) {
                      if (showMenu && items.isNotEmpty) {
                        _apply(items[highlighted]);
                      } else {
                        _runSearch();
                      }
                    },
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Stack(
                      children: [
                        _results(l, showMenu),
                        if (showMenu)
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _SuggestionMenu(
                              items: items,
                              highlighted: highlighted,
                              onHighlight: (i) =>
                                  setState(() => _highlighted = i),
                              onSelect: _apply,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _channelLabel(KurierMessage m) {
    final channel = s.channels[m.channelId];
    if (channel == null) return '';
    if (channel.isDm) return channel.name;
    return '#${channel.name}';
  }

  Widget _results(L10n l, bool menuOpen) {
    if (s.searching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_ran && s.searchMessages.isEmpty && s.searchFiles.isEmpty) {
      if (menuOpen) return const SizedBox.shrink();
      return EmptyHint(l('searchHint'));
    }
    if (s.searchMessages.isEmpty && s.searchFiles.isEmpty) {
      return EmptyHint(l('noResults'));
    }
    return ListView(
      children: [
        for (final m in s.searchMessages)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SearchResultCard(
              session: s,
              message: m,
              channelLabel: _channelLabel(m),
              onTap: () {
                Navigator.pop(context);
                s.jumpToMessage(m.channelId, m.id);
              },
            ),
          ),
        for (final f in s.searchFiles)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: context.p.card,
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                dense: true,
                leading: Icon(
                  Icons.attach_file,
                  color: context.p.muted,
                  size: 18,
                ),
                title: Text(
                  f.originalName,
                  style: TextStyle(color: context.p.foreground, fontSize: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.session,
    required this.message,
    required this.channelLabel,
    required this.onTap,
  });

  final SessionController session;
  final KurierMessage message;
  final String channelLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final author = resolveMessageAuthor(
      session,
      l,
      userId: message.userId,
      pluginId: message.pluginId,
    );
    final user = author.user;
    final nameColor = user != null
        ? (userRoleColor(user, session.roles) ?? context.p.foreground)
        : context.p.foreground;
    final snippet = htmlToPlainText(message.content ?? '');

    return Material(
      color: context.p.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(
                user: user,
                session: session,
                size: 28,
                showStatus: user != null,
                imageUrl: author.imageUrl,
                fallbackName: author.name,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Text(
                          author.name,
                          style: TextStyle(
                            color: nameColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          '· ${relativeTime(message.createdAt)}',
                          style: TextStyle(
                            color: context.p.faint,
                            fontSize: 12,
                          ),
                        ),
                        if (channelLabel.isNotEmpty)
                          Text(
                            '· $channelLabel',
                            style: TextStyle(
                              color: context.p.muted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    if (snippet.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        snippet,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.p.foreground,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: context.p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionMenu extends StatelessWidget {
  const _SuggestionMenu({
    required this.items,
    required this.highlighted,
    required this.onHighlight,
    required this.onSelect,
  });

  final List<_SearchSuggestion> items;
  final int highlighted;
  final ValueChanged<int> onHighlight;
  final ValueChanged<_SearchSuggestion> onSelect;

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
                    key: ValueKey('search-op-${item.keyName}'),
                    color: selected
                        ? context.p.card.withValues(alpha: 0.95)
                        : Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          Text(
                            item.label,
                            style: TextStyle(
                              color: context.p.foreground,
                              fontWeight: item.description != null
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          if (item.description != null) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item.description!,
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.p.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
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
}

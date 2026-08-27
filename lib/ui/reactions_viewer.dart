import 'package:flutter/material.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../core/emoji_codec.dart';
import '../protocol/models.dart';
import '../session/session_controller.dart';
import 'context_menu.dart';
import 'emoji_glyph.dart';
import 'shared.dart';

class ReactionGroup {
  ReactionGroup({
    required this.emoji,
    required this.count,
    required this.mine,
    required this.userIds,
  });

  final String emoji;
  final int count;
  final bool mine;
  final List<int> userIds;
}

class _MutableReactionGroup {
  _MutableReactionGroup(this.emoji);
  final String emoji;
  int count = 0;
  bool mine = false;
  final List<int> userIds = [];
}

Map<String, ReactionGroup> groupMessageReactions(
  Iterable<MessageReaction> reactions, {
  int? ownUserId,
}) {
  final groups = <String, _MutableReactionGroup>{};
  for (final r in reactions) {
    final key = EmojiCodec.reactionEmojiKey(r.emoji);
    if (key.isEmpty) continue;
    final g = groups.putIfAbsent(key, () => _MutableReactionGroup(key));
    if (r.count > 1 || r.userIds.isNotEmpty) {
      g.count += r.count > 0 ? r.count : 1;
      for (final uid in r.userIds) {
        if (!g.userIds.contains(uid)) g.userIds.add(uid);
      }
      if (r.userId > 0 && !g.userIds.contains(r.userId)) {
        g.userIds.add(r.userId);
      }
      if (r.me) g.mine = true;
    } else {
      g.count += 1;
      if (r.userId > 0 && !g.userIds.contains(r.userId)) {
        g.userIds.add(r.userId);
      }
      if (r.me || (ownUserId != null && r.userId == ownUserId)) {
        g.mine = true;
      }
    }
  }
  return {
    for (final e in groups.entries)
      e.key: ReactionGroup(
        emoji: e.value.emoji,
        count: e.value.count,
        mine: e.value.mine,
        userIds: e.value.userIds,
      ),
  };
}

KurierMessage? findSessionMessage(
  SessionController session, {
  required int channelId,
  required int messageId,
}) {
  Iterable<KurierMessage> lists() sync* {
    final channel = session.messages[channelId];
    if (channel != null) yield* channel;
    yield* session.threadMessages;
    yield* session.pinned;
    yield* session.searchMessages;
  }

  for (final m in lists()) {
    if (m.id == messageId) return m;
  }
  return null;
}

String reactionChipTooltip(
  ReactionGroup group,
  SessionController session,
  L10n l,
) {
  final names = [
    for (final id in group.userIds)
      session.users[id]?.displayName ?? l('unknownUser'),
  ];
  final label = EmojiCodec.displayLabel(group.emoji);
  if (names.isEmpty) return label;
  final shown = names.length <= 3
      ? names.join(', ')
      : '${names.take(3).join(', ')} +${names.length - 3}';
  return '$shown\n$label';
}

Future<void> showReactionsViewer(
  BuildContext context, {
  required SessionController session,
  required int channelId,
  required int messageId,
  String? initialEmojiKey,
}) {
  final message = findSessionMessage(
    session,
    channelId: channelId,
    messageId: messageId,
  );
  if (message == null || message.reactions.isEmpty) {
    return Future.value();
  }

  final phone = MediaQuery.sizeOf(context).width < 768;
  Widget viewer() => ReactionsViewer(
        session: session,
        channelId: channelId,
        messageId: messageId,
        initialEmojiKey: initialEmojiKey,
      );

  if (phone) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(ctx).bottom),
        child: Material(
          color: ctx.p.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.62,
            child: viewer(),
          ),
        ),
      ),
    );
  }

  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: ctx.p.background,
      child: SizedBox(
        width: 500,
        height: 440,
        child: viewer(),
      ),
    ),
  );
}

class ReactionsViewer extends StatefulWidget {
  const ReactionsViewer({
    super.key,
    required this.session,
    required this.channelId,
    required this.messageId,
    this.initialEmojiKey,
  });

  final SessionController session;
  final int channelId;
  final int messageId;
  final String? initialEmojiKey;

  @override
  State<ReactionsViewer> createState() => _ReactionsViewerState();
}

class _ReactionsViewerState extends State<ReactionsViewer> {
  late String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialEmojiKey;
    widget.session.addListener(_onSession);
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final message = findSessionMessage(
      widget.session,
      channelId: widget.channelId,
      messageId: widget.messageId,
    );
    final groups = groupMessageReactions(
      message?.reactions ?? const [],
      ownUserId: widget.session.ownUserId,
    );

    if (groups.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }

    final selected = (_selected != null && groups.containsKey(_selected))
        ? _selected!
        : groups.keys.first;

    return Material(
      key: const ValueKey('reactions-viewer'),
      color: p.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 420;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 48,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l('reactions'),
                          style: TextStyle(
                            color: p.foreground,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l('close'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, color: p.muted, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(color: p.divider, height: 1),
              Expanded(
                child: stacked
                    ? Column(
                        children: [
                          SizedBox(
                            height: 52,
                            child: _EmojiRail(
                              session: widget.session,
                              groups: groups,
                              selected: selected,
                              axis: Axis.horizontal,
                              onSelect: (key) =>
                                  setState(() => _selected = key),
                            ),
                          ),
                          Divider(color: p.divider, height: 1),
                          Expanded(
                            child: _UserList(
                              session: widget.session,
                              userIds: groups[selected]!.userIds,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 88,
                            child: ColoredBox(
                              color: p.sidebar,
                              child: _EmojiRail(
                                session: widget.session,
                                groups: groups,
                                selected: selected,
                                axis: Axis.vertical,
                                onSelect: (key) =>
                                    setState(() => _selected = key),
                              ),
                            ),
                          ),
                          VerticalDivider(color: p.divider, width: 1),
                          Expanded(
                            child: _UserList(
                              session: widget.session,
                              userIds: groups[selected]!.userIds,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmojiRail extends StatelessWidget {
  const _EmojiRail({
    required this.session,
    required this.groups,
    required this.selected,
    required this.axis,
    required this.onSelect,
  });

  final SessionController session;
  final Map<String, ReactionGroup> groups;
  final String selected;
  final Axis axis;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final custom = session.customEmojis;
    final p = context.p;
    final horizontal = axis == Axis.horizontal;
    return ListView.builder(
      scrollDirection: axis,
      padding: horizontal
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8)
          : const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: groups.length,
      itemBuilder: (context, i) {
        final key = groups.keys.elementAt(i);
        final count = groups[key]!.count;
        final active = key == selected;
        return Padding(
          padding: EdgeInsets.only(
            bottom: horizontal ? 0 : 2,
            right: horizontal ? 4 : 0,
          ),
          child: Material(
            color: active ? p.card : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              key: ValueKey('reactions-tab-$key'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelect(key),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontal ? 10 : 8,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EmojiGlyph(
                      emojiKey: key,
                      customEmojis: custom,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: TextStyle(
                        color: active ? p.foreground : p.muted,
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UserList extends StatelessWidget {
  const _UserList({required this.session, required this.userIds});

  final SessionController session;
  final List<int> userIds;

  @override
  Widget build(BuildContext context) {
    if (userIds.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          L10n.of(context)('reactorDetailsUnavailable'),
          style: TextStyle(color: context.p.muted, fontSize: 13),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: userIds.length,
      itemBuilder: (context, i) {
        final id = userIds[i];
        final user = session.users[id];
        return _ReactorRow(
          session: session,
          user: user,
          userId: id,
        );
      },
    );
  }
}

class _ReactorRow extends StatefulWidget {
  const _ReactorRow({
    required this.session,
    required this.user,
    required this.userId,
  });

  final SessionController session;
  final KurierUser? user;
  final int userId;

  @override
  State<_ReactorRow> createState() => _ReactorRowState();
}

class _ReactorRowState extends State<_ReactorRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final user = widget.user;
    final display = user?.displayName ?? l('unknownUser');
    final handle = user?.name ?? '';
    final nameColor = user != null
        ? (userRoleColor(user, widget.session.roles) ?? p.foreground)
        : p.foreground;
    final canOpen = user != null && !user.deleted;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: canOpen ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: PositionedTap(
        onTap: canOpen
            ? (pos) {
                Navigator.of(context).pop();
                widget.session.showProfile(user, anchor: pos);
              }
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _hover ? p.card.withValues(alpha: 0.85) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              UserAvatar(
                user: user,
                session: widget.session,
                size: 36,
                showStatus: user != null,
                fallbackName: display,
                statusBorderColor: p.background,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      display,
                      key: ValueKey('reactions-user-${widget.userId}'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: nameColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    if (handle.isNotEmpty)
                      Text(
                        handle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.muted,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

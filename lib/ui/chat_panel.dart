import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/breakpoints.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../core/emoji_codec.dart';
import '../core/quick_reactions.dart';
import '../protocol/config.dart';
import '../protocol/mentions.dart';
import '../protocol/models.dart';
import '../protocol/permissions.dart';
import '../protocol/platform.dart';
import '../session/session_controller.dart';
import 'context_menu.dart';
import 'emoji_glyph.dart';
import 'emoji_picker.dart';
import 'gif_picker.dart';
import 'member_list.dart';
import 'message_embeds.dart';
import 'message_html.dart';
import 'mentions_dialog.dart';
import 'pins_popover.dart';
import 'reactions_viewer.dart';
import 'search_dialog.dart';
import 'shared.dart';
import 'voice_stage.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.session,
    required this.channel,
    this.onBack,
    this.onToggleMembers,
    this.membersOpen = false,
  });

  final SessionController session;
  final KurierChannel channel;
  final VoidCallback? onBack;
  final VoidCallback? onToggleMembers;
  final bool membersOpen;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _scroll = ScrollController();
  final _compose = TextEditingController();
  final _composeFocus = FocusNode();
  final _jumpKey = GlobalKey();
  bool _atBottom = true;
  int? _highlightMessageId;
  Timer? _highlightTimer;
  bool _wasFetching = false;

  SessionController get s => widget.session;
  KurierChannel get channel => widget.channel;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _wasFetching =
        s.fetchingMessages[channel.id] == true ||
        s.loadingMessages[channel.id] == true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeJump();
      _onScroll();
    });
  }

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != channel.id) {
      _atBottom = true;
      _highlightMessageId = null;
      _wasFetching = false;
    }
    final fetching =
        s.fetchingMessages[channel.id] == true ||
        s.loadingMessages[channel.id] == true;
    if (_wasFetching && !fetching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
      });
    }
    _wasFetching = fetching;
    _maybeJump();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.offset < 80;
    if (atBottom != _atBottom) {
      setState(() => _atBottom = atBottom);
    }
    if (s.fetchingMessages[channel.id] == true) return;
    if (s.nextCursor[channel.id] == null) return;
    if (_scroll.position.maxScrollExtent - _scroll.offset <= 80) {
      s.loadOlderMessages(channel.id);
    }
  }

  void _maybeJump() {
    if (s.jumpTargetChannelId != channel.id) return;
    final id = s.jumpTargetMessageId;
    if (id == null) return;
    s.clearJumpTarget();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _jumpToMessage(id);
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scroll.dispose();
    _compose.dispose();
    _composeFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final list = s.messages[channel.id] ?? const <KurierMessage>[];
    final typingNames = (s.typing[channel.id] ?? [])
        .map((t) => s.users[t.userId]?.displayName ?? '')
        .where((n) => n.isNotEmpty)
        .join(', ');
    return Material(
      color: context.p.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, l),
          if (s.threadParentId != null) _threadBar(context, l),
          Expanded(
            child: Stack(
              children: [
                _messageList(context, l, list),
                if (s.fetchingMessages[channel.id] == true)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      semanticsLabel: l('fetchingOlderMessages'),
                    ),
                  ),
                if (!_atBottom || s.isChannelDetached(channel.id))
                  Positioned(
                    right: 16,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      tooltip: l('jumpToPresent'),
                      onPressed: () => _jumpToPresent(),
                      child: const Icon(Icons.arrow_downward),
                    ),
                  ),
              ],
            ),
          ),
          if (s.isChannelDetached(channel.id)) _olderMessagesBanner(context, l),
          if (typingNames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '$typingNames…',
                  style: TextStyle(color: context.p.faint, fontSize: 12),
                ),
              ),
            ),
          if (s.replyTo != null) _replyBar(context, l),
          if (s.connectedVoiceChannelId != null &&
              s.selectedChannelId != s.connectedVoiceChannelId)
            CompactVoiceBar(session: s),
          ComposeBar(
            controller: _compose,
            focus: _composeFocus,
            session: s,
            channel: channel,
            onSend: () async {
              final text = _compose.text;
              _compose.clear();
              await s.sendMessage(text);
              if (_atBottom && _scroll.hasClients) {
                _scroll.animateTo(
                  0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, L10n l) {
    final topic = channel.topic;
    final phone =
        breakpointOf(MediaQuery.sizeOf(context).width) == Breakpoint.phone;
    return SizedBox(
      height: kHeaderHeight,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: context.p.divider)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (widget.onBack != null)
                      CompactIconButton(
                        icon: Icons.menu,
                        onPressed: widget.onBack,
                      ),
                    Icon(
                      channel.isDm ? Icons.forum : Icons.tag,
                      color: context.p.muted,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        channel.isDm
                            ? (s.dms
                                      .where((d) => d.channelId == channel.id)
                                      .map(
                                        (d) => s.users[d.userId]?.displayName,
                                      )
                                      .firstOrNull ??
                                  channel.name)
                            : channel.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.p.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (topic != null && topic.isNotEmpty) ...[
                      Container(
                        width: 1,
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: context.p.divider,
                      ),
                      Flexible(
                        child: Text(
                          topic,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.p.faint,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Builder(
                builder: (btnCtx) => CompactIconButton(
                  tooltip: l('pins'),
                  icon: Icons.push_pin_outlined,
                  onPressed: () => _openPins(btnCtx),
                ),
              ),
              ListenableBuilder(
                listenable: s,
                builder: (context, _) {
                  final btn = CompactIconButton(
                    tooltip: l('mentions'),
                    icon: Icons.alternate_email,
                    onPressed: () => _openMentions(context),
                  );
                  if (s.unreadMentionCount <= 0) {
                    return KeyedSubtree(
                      key: const ValueKey('mentions-button'),
                      child: btn,
                    );
                  }
                  return Tooltip(
                    message: l('mentions'),
                    child: GestureDetector(
                      key: const ValueKey('mentions-button'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openMentions(context),
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          IgnorePointer(child: btn),
                          Positioned(
                            right: -2,
                            top: -2,
                            child: UnreadBadge(
                              key: const ValueKey('mentions-unread-badge'),
                              count: s.unreadMentionCount,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (!phone) _searchChip(context, l),
              if (phone)
                CompactIconButton(
                  tooltip: l('search'),
                  icon: Icons.search,
                  onPressed: () => _openSearch(context),
                ),
              if (widget.onToggleMembers != null)
                CompactIconButton(
                  tooltip: l('members', {'count': '${s.users.length}'}),
                  icon: widget.membersOpen
                      ? Icons.people
                      : Icons.people_outline,
                  onPressed: widget.onToggleMembers,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchChip(BuildContext context, L10n l) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4),
      child: Material(
        color: context.p.rail,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: () => _openSearch(context),
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            width: 168,
            height: 28,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Icon(Icons.search, size: 14, color: context.p.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l('searchContent'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.p.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _replyBar(BuildContext context, L10n l) {
    final r = s.replyTo!;
    return Container(
      color: context.p.card,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l('replyingTo', {
                'name': resolveMessageAuthor(
                  s,
                  l,
                  userId: r.userId,
                  pluginId: r.pluginId,
                ).name,
              }),
              style: TextStyle(color: context.p.muted, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () {
              s.replyTo = null;
              s.refresh();
            },
          ),
        ],
      ),
    );
  }

  Widget _threadBar(BuildContext context, L10n l) {
    return Container(
      color: context.p.card,
      child: ListTile(
        dense: true,
        title: Text(l('thread'), style: TextStyle(color: context.p.foreground)),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: s.closeThread,
        ),
      ),
    );
  }

  Future<void> _openMentions(BuildContext context) async {
    final nav = Navigator.of(context, rootNavigator: true);
    await s.loadMentions();
    if (!nav.mounted) return;
    await showDialog<void>(
      context: nav.context,
      builder: (_) => MentionsDialog(session: s),
    );
  }

  Widget _messageList(BuildContext context, L10n l, List<KurierMessage> list) {
    if (list.isEmpty) {
      if (s.loadingMessages[channel.id] == true) {
        return const Center(child: CircularProgressIndicator());
      }
      return EmptyHint(l('selectChannel'));
    }
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.only(bottom: kMsgScrollerSpacer),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final msg = list[list.length - 1 - i];
        final prev = (list.length - 1 - i) > 0
            ? list[list.length - 2 - i]
            : null;
        final grouped = prev != null && messagesFormGroup(prev, msg);
        return MessageTile(
          key: msg.id == _highlightMessageId
              ? _jumpKey
              : ValueKey('msg-${msg.id}'),
          session: s,
          message: msg,
          grouped: grouped,
          highlighted: msg.id == _highlightMessageId,
        );
      },
    );
  }

  Widget _olderMessagesBanner(BuildContext context, L10n l) {
    return Material(
      color: context.p.card,
      child: InkWell(
        onTap: _jumpToPresent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.history, size: 16, color: context.p.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l('viewingOlderMessages'),
                  style: TextStyle(color: context.p.foreground, fontSize: 13),
                ),
              ),
              Text(
                l('jumpToPresent'),
                style: TextStyle(
                  color: context.k.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _jumpToPresent() async {
    if (s.isChannelDetached(channel.id)) {
      await s.returnToPresent(channel.id);
      if (!mounted) return;
    }
    if (_scroll.hasClients) {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _openSearch(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => SearchDialog(session: s),
    );
  }

  Future<void> _openPins(BuildContext context) {
    return showPinsPopover(
      context: context,
      session: s,
      channelId: channel.id,
      onJumpToMessage: _jumpToMessage,
      messageBuilder: (m) => MessageTile(
        session: s,
        message: m,
        grouped: false,
        readOnly: true,
        showFiles: false,
        showReactions: false,
      ),
    );
  }

  Future<void> _jumpToMessage(int id) async {
    final list = s.messages[channel.id] ?? const <KurierMessage>[];
    if (!list.any((m) => m.id == id)) {
      await s.loadMessages(channel.id, target: id);
    }
    if (!mounted) return;
    setState(() => _highlightMessageId = id);
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _highlightMessageId = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealMessage(id));
  }

  void _revealMessage(int id) {
    final ctx = _jumpKey.currentContext;
    if (ctx != null && ctx.mounted) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
      return;
    }
    final list = s.messages[channel.id] ?? const <KurierMessage>[];
    final idx = list.indexWhere((m) => m.id == id);
    if (idx < 0 || !_scroll.hasClients) return;
    final reverseIndex = list.length - 1 - idx;
    final targetOffset = (reverseIndex * 88.0).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.jumpTo(targetOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final again = _jumpKey.currentContext;
      if (again != null && again.mounted) {
        Scrollable.ensureVisible(again, alignment: 0.35);
      }
    });
  }
}

class MessageTile extends StatelessWidget {
  const MessageTile({
    super.key,
    required this.session,
    required this.message,
    required this.grouped,
    this.readOnly = false,
    this.showFiles = true,
    this.showReactions = true,
    this.highlighted = false,
  });

  final SessionController session;
  final KurierMessage message;
  final bool grouped;
  final bool readOnly;
  final bool showFiles;
  final bool showReactions;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final l = L10n.of(context);
    final author = resolveMessageAuthor(
      s,
      l,
      userId: message.userId,
      pluginId: message.pluginId,
    );
    final user = author.user;
    final mentioned = hasMention(message.content, s.ownUserId);
    final displayHtml = hideGifUrlsInHtml(message.content ?? '');
    final showBody = messageHtmlHasVisibleText(displayHtml);
    final surface = _MessageSurface(
      mentioned: mentioned,
      highlighted: highlighted,
      padding: EdgeInsets.fromLTRB(
        kMsgPadH,
        grouped ? kMsgFollowUpTop : kMsgGroupTop,
        kMsgPadH,
        0,
      ),
      hoverBar: readOnly ? null : _hoverReactBar(context, s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: kMsgAvatar,
            child: grouped
                ? const SizedBox()
                : PositionedTap(
                    onTap: (pos) {
                      if (user != null) {
                        s.showProfile(user, anchor: pos);
                      }
                    },
                    child: UserAvatar(
                      user: user,
                      session: s,
                      size: kMsgAvatar,
                      statusBorderColor: context.p.background,
                      imageUrl: author.imageUrl,
                      fallbackName: author.name,
                      showStatus: user != null,
                    ),
                  ),
          ),
          const SizedBox(width: kMsgGutter),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!grouped)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: PositionedTap(
                          onTap: (pos) {
                            if (user != null) {
                              s.showProfile(user, anchor: pos);
                            }
                          },
                          child: Text(
                            author.name,
                            key: ValueKey('msg-author-${message.id}'),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: user != null && user.deleted
                                  ? context.p.muted
                                  : user != null
                                  ? (_roleColor(user) ?? context.p.foreground)
                                  : context.k.accent.withValues(alpha: 0.8),
                              fontWeight: message.userId == s.ownUserId
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 16,
                              height: 1.5,
                              decoration: user != null && user.deleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      if (author.isPlugin) ...[
                        const SizedBox(width: 8),
                        Text(
                          l('botBadge'),
                          style: TextStyle(
                            color: context.k.accent.withValues(alpha: 0.6),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.6,
                            height: 1.5,
                            backgroundColor: context.k.accent.withValues(
                              alpha: 0.1,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        relativeTime(message.createdAt),
                        style: TextStyle(
                          color: context.p.faint,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      if (message.editedAt != null)
                        Text(
                          ' ${l('edited')}',
                          style: TextStyle(
                            color: context.p.faint,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                    ],
                  ),
                if (message.replyTo != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      htmlToPlainText(message.replyTo!.content ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.p.faint, fontSize: 12),
                    ),
                  ),
                if (showBody)
                  MessageBody(
                    html: displayHtml,
                    color: context.p.foreground,
                    linkColor: context.k.accent,
                    ownUserId: s.ownUserId,
                    customEmojis: s.customEmojis,
                    onLink: (url) => launchUrl(Uri.parse(url)),
                  ),
                if (showFiles)
                  for (final f in message.files) _file(context, s, f),
                MessageEmbeds(message: message, session: s),
                if (showReactions && message.reactions.isNotEmpty)
                  _reactions(context, s),
                if (!readOnly && message.replyCount > 0)
                  GestureDetector(
                    onTap: () => s.openThread(message),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: Text(
                        '${message.replyCount}',
                        style: TextStyle(
                          color: context.k.accent,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (readOnly) return surface;
    return ContextRegion(actions: () => _actions(context, l), child: surface);
  }

  List<MenuAction> _actions(BuildContext context, L10n l) {
    final s = session;
    return [
      MenuAction(
        label: l('reply'),
        onTap: () {
          s.replyTo = message;
          s.refresh();
        },
      ),
      MenuAction(label: l('replyInThread'), onTap: () => s.openThread(message)),
      for (final e in QuickReactions.top(count: 4))
        MenuAction(
          label: EmojiCodec.displayLabel(e),
          onTap: () => s.toggleReaction(message.id, e),
        ),
      MenuAction(label: l('addReaction'), onTap: () => _pickEmoji(context)),
      if (message.reactions.isNotEmpty)
        MenuAction(
          label: l('viewReactions'),
          onTap: () => showReactionsViewer(
            context,
            session: s,
            channelId: message.channelId,
            messageId: message.id,
          ),
        ),
      MenuAction(
        label: message.pinned ? l('unpin') : l('pin'),
        enabled: s.can(Permission.pinMessages),
        onTap: () => s.togglePin(message.id),
      ),
      MenuAction(
        label: l('copyText'),
        onTap: () =>
            PlatformBridge.copyText(htmlToPlainText(message.content ?? '')),
      ),
      MenuAction(
        label: l('edit'),
        enabled: message.userId == s.ownUserId && message.editable,
        onTap: () => _edit(context),
      ),
      MenuAction(
        label: l('deleteMessage'),
        danger: true,
        enabled:
            message.userId == s.ownUserId || s.can(Permission.manageMessages),
        onTap: () => s.deleteMessage(message.id),
      ),
    ];
  }

  Widget? _hoverReactBar(BuildContext context, SessionController s) {
    if (breakpointOf(MediaQuery.sizeOf(context).width) == Breakpoint.phone) {
      return null;
    }
    final custom = s.customEmojis;
    return Material(
      color: context.p.sidebar,
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in QuickReactions.top(count: 3))
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => s.toggleReaction(message.id, e),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: EmojiGlyph(
                    key: ValueKey('hover-$e'),
                    emojiKey: e,
                    customEmojis: custom,
                    size: 18,
                  ),
                ),
              ),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _pickEmoji(context),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.add_reaction_outlined,
                  size: 18,
                  color: context.p.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color? _roleColor(KurierUser? user) {
    if (user == null) return null;
    return userRoleColor(user, session.roles);
  }

  Widget _file(BuildContext context, SessionController s, KurierFile f) {
    final url = s.fileUrl(f);
    if (f.isImage) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: GestureDetector(
          onTap: () {
            showDialog<void>(
              context: context,
              builder: (_) => Dialog(child: Image.network(url)),
            );
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      );
    }
    if (f.isVideo) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: TextButton(
          onPressed: () => launchUrl(Uri.parse(url)),
          child: Text(f.originalName),
        ),
      );
    }
    return ListTile(
      dense: true,
      leading: const Icon(Icons.attach_file),
      title: Text(
        f.originalName,
        style: TextStyle(color: context.p.foreground),
      ),
      onTap: () => launchUrl(Uri.parse(url)),
    );
  }

  Widget _reactions(BuildContext context, SessionController s) {
    final groups = groupMessageReactions(
      message.reactions,
      ownUserId: s.ownUserId,
    );
    final custom = s.customEmojis;
    final l = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final e in groups.entries)
            Tooltip(
              message: reactionChipTooltip(e.value, s, l),
              child: Material(
                color: e.value.mine
                    ? context.k.accent.withValues(alpha: 0.18)
                    : context.p.card,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  key: ValueKey('reaction-${message.id}-${e.key}'),
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => s.toggleReaction(message.id, e.key),
                  onSecondaryTap: () => showReactionsViewer(
                    context,
                    session: s,
                    channelId: message.channelId,
                    messageId: message.id,
                    initialEmojiKey: e.key,
                  ),
                  onLongPress: () {
                    HapticFeedback.lightImpact();
                    showReactionsViewer(
                      context,
                      session: s,
                      channelId: message.channelId,
                      messageId: message.id,
                      initialEmojiKey: e.key,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EmojiGlyph(
                          emojiKey: e.key,
                          customEmojis: custom,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${e.value.count}',
                          style: TextStyle(
                            color: context.p.foreground,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickEmoji(BuildContext context) async {
    final pick = await showKurierEmojiPicker(context, session: session);
    if (pick == null) return;
    await session.toggleReaction(message.id, pick.value);
  }

  Future<void> _edit(BuildContext context) async {
    final ctrl = TextEditingController(
      text: htmlToPlainText(message.content ?? ''),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.of(ctx)('editMessage')),
        content: KurierField(
          controller: ctrl,
          maxLines: 4,
          maxLength: AppConfig.maxMessageLength,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(L10n.of(ctx)('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(L10n.of(ctx)('save')),
          ),
        ],
      ),
    );
    if (ok == true) await session.editMessage(message.id, ctrl.text);
  }
}

class _MessageSurface extends StatefulWidget {
  const _MessageSurface({
    required this.mentioned,
    required this.padding,
    required this.child,
    this.hoverBar,
    this.highlighted = false,
  });

  final bool mentioned;
  final bool highlighted;
  final EdgeInsets padding;
  final Widget child;
  final Widget? hoverBar;

  @override
  State<_MessageSurface> createState() => _MessageSurfaceState();
}

class _MessageSurfaceState extends State<_MessageSurface> {
  bool _hover = false;

  static const _mention = Color(0xFFF0B232);

  @override
  Widget build(BuildContext context) {
    final Color bg;
    if (widget.highlighted) {
      bg = _mention.withValues(alpha: 0.18);
    } else if (widget.mentioned) {
      bg = _mention.withValues(alpha: 0.10);
    } else if (_hover) {
      bg = Colors.white.withValues(alpha: 0.03);
    } else {
      bg = Colors.transparent;
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          border: widget.mentioned
              ? const Border(left: BorderSide(color: _mention, width: 2))
              : null,
        ),
        child: Stack(
          children: [
            Padding(
              padding: widget.mentioned
                  ? widget.padding.copyWith(left: widget.padding.left + 2)
                  : widget.padding,
              child: widget.child,
            ),
            if (_hover && widget.hoverBar != null)
              Positioned(right: 8, top: 0, child: widget.hoverBar!),
          ],
        ),
      ),
    );
  }
}

class ComposeBar extends StatelessWidget {
  const ComposeBar({
    super.key,
    required this.controller,
    required this.focus,
    required this.session,
    required this.channel,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final SessionController session;
  final KurierChannel channel;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = session;
    final hint = channel.isDm
        ? l('dmPlaceholder', {'name': channel.name})
        : l('messagePlaceholder', {'name': channel.name});
    final bottom = 16.0 + MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
      child: Material(
        color: context.p.card,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Shortcuts(
                    shortcuts: const {
                      SingleActivator(
                        LogicalKeyboardKey.enter,
                        includeRepeats: false,
                      ): _SendIntent(),
                      SingleActivator(
                        LogicalKeyboardKey.numpadEnter,
                        includeRepeats: false,
                      ): _SendIntent(),
                      SingleActivator(LogicalKeyboardKey.enter, shift: true):
                          _NewlineIntent(),
                      SingleActivator(
                        LogicalKeyboardKey.numpadEnter,
                        shift: true,
                      ): _NewlineIntent(),
                    },
                    child: Actions(
                      actions: {
                        _SendIntent: CallbackAction<_SendIntent>(
                          onInvoke: (_) {
                            if (controller.value.isComposingRangeValid) {
                              return null;
                            }
                            onSend();
                            return null;
                          },
                        ),
                        _NewlineIntent: CallbackAction<_NewlineIntent>(
                          onInvoke: (_) {
                            if (controller.value.isComposingRangeValid) {
                              return null;
                            }
                            _insertAtCursor('\n');
                            return null;
                          },
                        ),
                      },
                      child: TextField(
                        controller: controller,
                        focusNode: focus,
                        minLines: 1,
                        maxLines: 8,
                        maxLength: AppConfig.maxMessageLength,
                        maxLengthEnforcement: MaxLengthEnforcement.enforced,
                        keyboardType: TextInputType.multiline,
                        style: TextStyle(
                          color: context.p.foreground,
                          fontSize: 16,
                        ),
                        cursorColor: context.k.accent,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        onChanged: (_) => s.signalTyping(),
                        decoration: InputDecoration(
                          hintText: hint,
                          hintStyle: TextStyle(
                            color: context.p.faint,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          filled: false,
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 11,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final remaining =
                        AppConfig.maxMessageLength - controller.text.length;
                    if (remaining > 200) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 4, bottom: 12),
                      child: Text(
                        '$remaining',
                        style: TextStyle(
                          color: remaining <= 50
                              ? context.p.dnd
                              : context.p.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
                CompactIconButton(
                  icon: Icons.gif_box_outlined,
                  iconSize: 20,
                  tooltip: l('gifs'),
                  onPressed: () => _gifs(context),
                ),
                CompactIconButton(
                  icon: Icons.emoji_emotions_outlined,
                  iconSize: 20,
                  tooltip: l('emoji'),
                  onPressed: () => _insertEmoji(context, s),
                ),
                if (s.can(Permission.uploadFiles))
                  CompactIconButton(
                    icon: Icons.attach_file,
                    iconSize: 20,
                    tooltip: l('upload'),
                    onPressed: () => _attach(s),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _attach(SessionController s) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    final files = result.files
        .where((f) => f.bytes != null)
        .map((f) => (name: f.name, bytes: f.bytes!))
        .toList();
    await s.sendFiles(files);
  }

  void _insertAtCursor(String insert) {
    if (insert.isEmpty) return;
    final sel = controller.selection;
    final base = controller.text;
    final start = sel.isValid ? sel.start : base.length;
    final end = sel.isValid ? sel.end : base.length;
    final available =
        AppConfig.maxMessageLength - (base.length - (end - start));
    if (available <= 0) return;
    final clipped = insert.length <= available
        ? insert
        : insert.substring(0, available);
    controller.value = TextEditingValue(
      text: base.replaceRange(start, end, clipped),
      selection: TextSelection.collapsed(offset: start + clipped.length),
    );
  }

  Future<void> _insertEmoji(BuildContext context, SessionController s) async {
    final pick = await showKurierEmojiPicker(context, session: s);
    if (pick == null) return;
    _insertAtCursor(pick.isCustom ? ':${pick.value}:' : pick.value);
  }

  Future<void> _gifs(BuildContext context) async {
    final url = await showKurierGifPicker(context, session: session);
    if (url == null || url.isEmpty) return;
    await session.sendMessage(url);
  }
}

class _SendIntent extends Intent {
  const _SendIntent();
}

class _NewlineIntent extends Intent {
  const _NewlineIntent();
}

class MemberSheet extends StatelessWidget {
  const MemberSheet({super.key, required this.session});
  final SessionController session;
  @override
  Widget build(BuildContext context) => MemberListBody(session: session);
}

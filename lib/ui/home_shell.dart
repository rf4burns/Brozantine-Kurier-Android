import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/breakpoints.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/models.dart';
import '../protocol/permissions.dart';
import '../session/session_controller.dart';
import 'chat_panel.dart';
import 'context_menu.dart';
import 'member_context_menu.dart';
import 'member_list.dart';
import 'panel_resize_handle.dart';
import 'profile_card.dart';
import 'settings_screens.dart';
import 'shared.dart';
import 'voice_stage.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _channelsOpen = false;
  bool _membersSheet = false;
  int _shownErrorEpoch = -1;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final bp = breakpointOf(width);
    final s = ref.watch(sessionProvider);
    final channel = s.selectedChannelId != null
        ? s.channels[s.selectedChannelId!]
        : null;
    final err = s.error;
    if (err != null && err.isNotEmpty && s.errorEpoch != _shownErrorEpoch) {
      _shownErrorEpoch = s.errorEpoch;
      final message = err == missingPermissionKey
          ? L10n.of(context)('missingPermission')
          : err;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) return;
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text(message)));
        s.clearError();
      });
    }

    Widget body;
    switch (bp) {
      case Breakpoint.desktop:
        body = _Desktop(s: s, channel: channel);
      case Breakpoint.tablet:
        body = _Tablet(
          s: s,
          channel: channel,
          membersOpen: _membersSheet,
          onOpenMembers: () => setState(() => _membersSheet = true),
          onCloseMembers: () => setState(() => _membersSheet = false),
        );
      case Breakpoint.phone:
        body = _Phone(
          s: s,
          channel: channel,
          channelsOpen: _channelsOpen || channel == null,
          membersOpen: _membersSheet,
          onOpenChannels: () => setState(() => _channelsOpen = true),
          onCloseChannels: () => setState(() => _channelsOpen = false),
          onOpenMembers: () => setState(() => _membersSheet = true),
          onCloseMembers: () => setState(() => _membersSheet = false),
        );
    }

    return Scaffold(
      backgroundColor: context.p.rail,
      body: Stack(
        children: [
          Positioned.fill(
            child: bp == Breakpoint.phone ? SafeArea(child: body) : body,
          ),
          if (s.overlay != null) SettingsHost(session: s),
          if (s.profileUser != null)
            ProfileCard(session: s, user: s.profileUser!),
        ],
      ),
    );
  }
}

class _Desktop extends StatelessWidget {
  const _Desktop({required this.s, required this.channel});
  final SessionController s;
  final KurierChannel? channel;

  @override
  Widget build(BuildContext context) {
    final showMembers = channel != null && !channel!.isDm && s.membersOpen;
    final fitted = fitPanelWidths(
      windowWidth: MediaQuery.sizeOf(context).width,
      sidebarWidth: s.sidebarWidth,
      membersWidth: s.membersWidth,
      showMembers: showMembers,
    );
    return Row(
      children: [
        ServerRail(session: s),
        ChannelSidebar(session: s, width: fitted.sidebar),
        PanelResizeHandle(
          key: PanelResizeHandle.channelsKey,
          onDrag: (dx) {
            final live = fitPanelWidths(
              windowWidth: MediaQuery.sizeOf(context).width,
              sidebarWidth: s.sidebarWidth,
              membersWidth: s.membersWidth,
              showMembers: showMembers,
            );
            s.setSidebarWidth(live.sidebar + dx);
          },
        ),
        Expanded(child: _main(context)),
        if (showMembers) ...[
          PanelResizeHandle(
            key: PanelResizeHandle.membersKey,
            onDrag: (dx) {
              final live = fitPanelWidths(
                windowWidth: MediaQuery.sizeOf(context).width,
                sidebarWidth: s.sidebarWidth,
                membersWidth: s.membersWidth,
                showMembers: true,
              );
              s.setMembersWidth(live.members - dx);
            },
          ),
          SizedBox(
            width: fitted.members,
            child: MemberList(session: s),
          ),
        ],
      ],
    );
  }

  Widget _main(BuildContext context) {
    if (channel == null) {
      return ColoredBox(
        color: context.p.background,
        child: EmptyHint(L10n.of(context)('selectChannel')),
      );
    }
    if (channel!.isVoice) {
      return VoiceStage(
        session: s,
        channel: channel!,
        onToggleMembers: s.toggleMembers,
        membersOpen: s.membersOpen,
      );
    }
    return ChatPanel(
      key: ValueKey('chat-${channel!.id}'),
      session: s,
      channel: channel!,
      onToggleMembers: s.toggleMembers,
      membersOpen: s.membersOpen,
    );
  }
}

class _Tablet extends StatelessWidget {
  const _Tablet({
    required this.s,
    required this.channel,
    required this.membersOpen,
    required this.onOpenMembers,
    required this.onCloseMembers,
  });

  final SessionController s;
  final KurierChannel? channel;
  final bool membersOpen;
  final VoidCallback onOpenMembers;
  final VoidCallback onCloseMembers;

  @override
  Widget build(BuildContext context) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    final fitted = fitPanelWidths(
      windowWidth: windowWidth,
      sidebarWidth: s.sidebarWidth,
      membersWidth: s.membersWidth,
      showMembers: false,
    );
    final membersW = s.membersWidth
        .clamp(kSidebarMinWidth, kSidebarMaxWidth)
        .toDouble();
    return Stack(
      children: [
        Row(
          children: [
            ServerRail(session: s),
            ChannelSidebar(session: s, width: fitted.sidebar),
            PanelResizeHandle(
              key: PanelResizeHandle.channelsKey,
              onDrag: (dx) {
                final live = fitPanelWidths(
                  windowWidth: MediaQuery.sizeOf(context).width,
                  sidebarWidth: s.sidebarWidth,
                  membersWidth: s.membersWidth,
                  showMembers: false,
                );
                s.setSidebarWidth(live.sidebar + dx);
              },
            ),
            Expanded(child: _main(context)),
          ],
        ),
        if (membersOpen) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: onCloseMembers,
              child: Container(color: Colors.black54),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: membersW + kResizeHandleWidth,
            child: Row(
              children: [
                PanelResizeHandle(
                  key: PanelResizeHandle.membersKey,
                  onDrag: (dx) => s.setMembersWidth(s.membersWidth - dx),
                ),
                SizedBox(
                  width: membersW,
                  child: MemberList(session: s),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _main(BuildContext context) {
    if (channel == null) {
      return ColoredBox(
        color: context.p.background,
        child: EmptyHint(L10n.of(context)('selectChannel')),
      );
    }
    if (channel!.isVoice) {
      return VoiceStage(
        session: s,
        channel: channel!,
        onToggleMembers: onOpenMembers,
        membersOpen: membersOpen,
      );
    }
    return ChatPanel(
      key: ValueKey('chat-${channel!.id}'),
      session: s,
      channel: channel!,
      onToggleMembers: onOpenMembers,
      membersOpen: membersOpen,
    );
  }
}

class _Phone extends StatelessWidget {
  const _Phone({
    required this.s,
    required this.channel,
    required this.channelsOpen,
    required this.membersOpen,
    required this.onOpenChannels,
    required this.onCloseChannels,
    required this.onOpenMembers,
    required this.onCloseMembers,
  });

  final SessionController s;
  final KurierChannel? channel;
  final bool channelsOpen;
  final bool membersOpen;
  final VoidCallback onOpenChannels;
  final VoidCallback onCloseChannels;
  final VoidCallback onOpenMembers;
  final VoidCallback onCloseMembers;

  @override
  Widget build(BuildContext context) {
    final overlayAsHome = channel == null;
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (membersOpen) {
          if (v > 240) onCloseMembers();
          return;
        }
        if (overlayAsHome && s.showingDms) {
          if (v > 240) s.returnToLastTextChannel();
          return;
        }
        if (channelsOpen && !overlayAsHome) {
          if (v < -240) onCloseChannels();
          return;
        }
        if (v > 240) onOpenChannels();
        if (v < -240 && channel != null && !channel!.isDm) onOpenMembers();
      },
      child: Stack(
        children: [
          Positioned.fill(child: _main(context)),
          if (channelsOpen) ...[
            if (!overlayAsHome)
              Positioned.fill(
                child: GestureDetector(
                  onTap: onCloseChannels,
                  child: Container(color: Colors.black54),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              bottom: 0,
              right: overlayAsHome ? 0 : null,
              width: overlayAsHome ? null : (kRailWidth + kSidebarWidth),
              child: Row(
                children: [
                  ServerRail(session: s),
                  Expanded(
                    child: ChannelSidebar(
                      session: s,
                      fill: true,
                      onChannelPicked: overlayAsHome ? null : onCloseChannels,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (membersOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: onCloseMembers,
                child: Container(color: Colors.black54),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: (MediaQuery.sizeOf(context).width * 0.86).clamp(
                240.0,
                320.0,
              ),
              child: MemberList(session: s),
            ),
          ],
        ],
      ),
    );
  }

  Widget _main(BuildContext context) {
    if (channel == null) {
      return ColoredBox(color: context.p.background);
    }
    if (channel!.isVoice) {
      return VoiceStage(
        session: s,
        channel: channel!,
        onBack: onOpenChannels,
        onToggleMembers: channel!.isDm ? null : onOpenMembers,
        membersOpen: membersOpen,
      );
    }
    return ChatPanel(
      key: ValueKey('chat-${channel!.id}'),
      session: s,
      channel: channel!,
      onBack: onOpenChannels,
      onToggleMembers: channel!.isDm ? null : onOpenMembers,
      membersOpen: membersOpen,
    );
  }
}

class ServerRail extends StatelessWidget {
  const ServerRail({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = session;
    final dmsOn = s.publicSettings['directMessagesEnabled'] != false;
    return Container(
      width: kRailWidth,
      color: context.p.rail,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          if (dmsOn) ...[
            _railBtn(
              context,
              active: s.showingDms,
              tooltip: l('directMessages'),
              onTap: () {
                s.showingDms = true;
                s.selectedChannelId = null;
                s.refresh();
                s.loadDms();
              },
              child: Icon(Icons.forum, color: context.p.foreground, size: 22),
            ),
            Container(
              width: 32,
              height: 2,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: context.p.divider,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
          for (final h in s.hosts)
            ContextRegion(
              onTap: (_) {
                s.showingDms = false;
                s.switchHost(h.host);
              },
              actions: () => [
                MenuAction(
                  icon: Icons.remove_circle_outline,
                  label: l('removeServer'),
                  danger: true,
                  onTap: () => s.removeHost(h.host),
                ),
              ],
              child: _railBtn(
                context,
                active: !s.showingDms && h.host == s.activeHost,
                tooltip: h.name ?? h.host,
                child: _hostGlyph(context, h),
              ),
            ),
          _railBtn(
            context,
            active: false,
            tooltip: l('addServer'),
            onTap: () => _addHost(context, s, l),
            child: Icon(Icons.add, color: context.p.online, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _hostGlyph(BuildContext context, SavedHost h) {
    final s = session;
    final logo = h.host == s.activeHost ? s.info?.logo : null;
    final url = logo != null ? s.fileUrl(logo) : null;
    final letter = (h.name ?? h.host).isNotEmpty
        ? (h.name ?? h.host)[0].toUpperCase()
        : 'K';
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.network(
          url,
          width: kRailIcon,
          height: kRailIcon,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Center(
            child: Text(letter, style: const TextStyle(color: Colors.white)),
          ),
        ),
      );
    }
    return Center(
      child: Text(
        letter,
        style: const TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  Widget _railBtn(
    BuildContext context, {
    required bool active,
    required String tooltip,
    required Widget child,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: active ? context.k.accent : context.p.card,
          borderRadius: BorderRadius.circular(active ? 16 : 24),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(active ? 16 : 24),
            child: SizedBox(width: kRailIcon, height: kRailIcon, child: child),
          ),
        ),
      ),
    );
  }

  Future<void> _addHost(
    BuildContext context,
    SessionController s,
    L10n l,
  ) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l('addServer')),
        content: KurierField(controller: ctrl, hint: l('addServerHint')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l('confirm')),
          ),
        ],
      ),
    );
    if (ok == true) await s.addHost(ctrl.text);
  }
}

class ChannelSidebar extends StatelessWidget {
  const ChannelSidebar({
    super.key,
    required this.session,
    this.fill = false,
    this.width,
    this.onChannelPicked,
  });

  final SessionController session;
  final bool fill;
  final double? width;
  final VoidCallback? onChannelPicked;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = session;
    return SizedBox(
      width: fill ? null : (width ?? kSidebarWidth),
      child: Material(
        color: context.p.sidebar,
        child: Column(
          children: [
            SizedBox(
              height: kHeaderHeight,
              child: Material(
                color: context.p.sidebar,
                child: InkWell(
                  onTap: () => _serverMenu(context, s, l),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.showingDms ? l('directMessages') : s.serverName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.p.foreground,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Icon(Icons.menu, size: 16, color: context.p.muted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Divider(color: context.p.divider, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(kChannelListPad),
                children: [
                  if (s.showingDms) ..._dmList(context, s, l),
                  if (!s.showingDms) ...[
                    ...s.visibleCategories().map((cat) {
                      final collapsed = s.collapsedCategories.contains(cat.id);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _categoryHeader(context, s, cat, l),
                          if (!collapsed)
                            ...s
                                .visibleChannelsIn(cat.id)
                                .map(
                                  (c) => c.isVoice
                                      ? _voiceTile(context, s, c, l)
                                      : _textTile(context, s, c, l),
                                ),
                        ],
                      );
                    }),
                    ...s
                        .visibleChannelsIn(null)
                        .map(
                          (c) => c.isVoice
                              ? _voiceTile(context, s, c, l)
                              : _textTile(context, s, c, l),
                        ),
                  ],
                ],
              ),
            ),
            VoiceControlBar(session: s),
            AccountBar(session: s),
          ],
        ),
      ),
    );
  }

  void _pick(SessionController s, int id) {
    s.selectChannel(id);
    onChannelPicked?.call();
  }

  Future<void> _serverMenu(
    BuildContext context,
    SessionController s,
    L10n l,
  ) async {
    await showAppContextMenu(context, const Offset(120, 48), [
      if (s.can(Permission.manageSettings) ||
          s.can(Permission.manageRoles) ||
          s.can(Permission.viewAuditLog))
          MenuAction(
            icon: Icons.settings_outlined,
            label: l('serverSettings'),
            onTap: () => s.openOverlay('serverSettings'),
          ),
        if (s.can(Permission.manageChannels))
          MenuAction(
            icon: Icons.tag,
            label: l('createChannel'),
            onTap: () => _createChannel(context, s),
          ),
        if (s.can(Permission.manageCategories))
          MenuAction(
            icon: Icons.create_new_folder_outlined,
            label: l('createCategory'),
            onTap: () => _createCategory(context, s),
          ),
        MenuAction(
          icon: Icons.logout,
          label: l('disconnect'),
          danger: true,
          dividerBefore: true,
          onTap: () => s.disconnect(),
        ),
    ]);
  }

  List<Widget> _dmList(BuildContext context, SessionController s, L10n l) {
    if (s.dms.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            l('noDms'),
            style: TextStyle(color: context.p.faint, fontSize: 13),
          ),
        ),
      ];
    }
    return [
      for (final dm in s.dms)
        _row(
          context,
          selected: s.selectedChannelId == dm.channelId,
          onTap: () => _pick(s, dm.channelId),
          leading: UserAvatar(user: s.users[dm.userId], session: s, size: 24),
          label: s.users[dm.userId]?.displayName ?? l('unknownUser'),
          unread: dm.unreadCount,
        ),
    ];
  }

  Widget _categoryHeader(
    BuildContext context,
    SessionController s,
    KurierCategory cat,
    L10n l,
  ) {
    final collapsed = s.collapsedCategories.contains(cat.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, kCategoryHeaderTop, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: ContextRegion(
              onTap: (_) => s.toggleCategory(cat.id),
              actions: () => [
                if (s.can(Permission.manageChannels))
                  MenuAction(
                    icon: Icons.tag,
                    label: l('createChannel'),
                    onTap: () => _createChannel(context, s, categoryId: cat.id),
                  ),
                if (s.can(Permission.manageCategories))
                  MenuAction(
                    icon: Icons.delete_outline,
                    label: l('delete'),
                    danger: true,
                    dividerBefore: s.can(Permission.manageChannels),
                    onTap: () => s.deleteCategory(cat.id),
                  ),
              ],
              child: Row(
                children: [
                  Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                    size: 12,
                    color: context.p.faint,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      cat.name.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.p.faint,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (s.can(Permission.manageChannels))
            CompactIconButton(
              tooltip: l('createChannel'),
              icon: Icons.add,
              size: 18,
              iconSize: 16,
              onPressed: () => _createChannel(context, s, categoryId: cat.id),
            ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required bool selected,
    required VoidCallback onTap,
    required Widget leading,
    required String label,
    int unread = 0,
    bool unreadBold = true,
    Widget? trailing,
    Color? accent,
    String? subtitle,
  }) {
    final color =
        accent ??
        (selected || (unread > 0 && unreadBold)
            ? context.p.foreground
            : context.p.muted);
    final status = subtitle?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: kChannelRowGap),
      child: Material(
        color: selected ? context.p.card : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kChannelRowPadH,
              vertical: kChannelRowPadV,
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontWeight: unread > 0
                              ? FontWeight.w600
                              : FontWeight.w500,
                          fontSize: 15,
                          height: 1.2,
                        ),
                      ),
                      if (status != null && status.isNotEmpty)
                        VoiceStatusText(status),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
                UnreadBadge(count: unread),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _textTile(
    BuildContext context,
    SessionController s,
    KurierChannel c,
    L10n l,
  ) {
    final unread = s.readStates[c.id] ?? 0;
    return ContextRegion(
      onTap: (_) => _pick(s, c.id),
      actions: () => [
        if (s.can(Permission.manageChannels))
          MenuAction(
            icon: Icons.settings_outlined,
            label: l('channelSettings'),
            onTap: () => s.openOverlay('channelSettings', channelId: c.id),
          ),
        MenuAction(
          icon: Icons.notifications_outlined,
          label: l('notifyAll'),
          dividerBefore: s.can(Permission.manageChannels),
          onTap: () => s.setNotificationOverride(c.id, 'all'),
        ),
        MenuAction(
          icon: Icons.alternate_email,
          label: l('notifyMentions'),
          onTap: () => s.setNotificationOverride(c.id, 'mentions'),
        ),
        MenuAction(
          icon: Icons.notifications_off_outlined,
          label: l('notifyMute'),
          onTap: () => s.setNotificationOverride(c.id, 'nothing'),
        ),
        if (s.can(Permission.manageChannels))
          MenuAction(
            icon: Icons.delete_outline,
            label: l('delete'),
            danger: true,
            dividerBefore: true,
            onTap: () => s.deleteChannel(c.id),
          ),
      ],
      child: _row(
        context,
        selected: s.selectedChannelId == c.id,
        onTap: () => _pick(s, c.id),
        leading: Icon(Icons.tag, size: kChannelIcon, color: context.p.muted),
        label: c.name,
        unread: unread,
      ),
    );
  }

  Widget _voiceTile(
    BuildContext context,
    SessionController s,
    KurierChannel c,
    L10n l,
  ) {
    final occupants = s.voiceMap[c.id] ?? {};
    final streams = s.externalStreams[c.id] ?? const <ExternalStream>[];
    final connected = s.connectedVoiceChannelId == c.id;
    final selected = s.selectedChannelId == c.id;
    final occupied = occupants.isNotEmpty || streams.isNotEmpty;
    final sharing = occupants.values.any((st) => st.sharingScreen);
    final since = s.occupiedSince[c.id];
    final liveColor = sharing
        ? const Color(0xFF3B82F6)
        : connected || (selected && occupied)
        ? kVoiceLive
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContextRegion(
          onTap: (_) => _pick(s, c.id),
          actions: () => [
            if (s.can(Permission.setVoiceChannelStatus))
              MenuAction(
                icon: Icons.edit_outlined,
                label: l('voiceStatus'),
                onTap: () async {
                  final ctrl = TextEditingController(
                    text: c.displayedVoiceStatus ?? '',
                  );
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l('voiceStatus')),
                      content: KurierField(controller: ctrl),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(l('cancel')),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(l('save')),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await s.setVoiceStatus(c.id, ctrl.text);
                },
              ),
            if (s.can(Permission.manageChannels))
              MenuAction(
                icon: Icons.delete_outline,
                label: l('delete'),
                danger: true,
                dividerBefore: s.can(Permission.setVoiceChannelStatus),
                onTap: () => s.deleteChannel(c.id),
              ),
          ],
          child: _row(
            context,
            selected: selected,
            onTap: () => _pick(s, c.id),
            accent: liveColor,
            leading: occupied
                ? VoiceWaveform(
                    size: kChannelIcon,
                    color: liveColor ?? context.p.muted,
                    screenSharing: sharing && (connected || selected),
                  )
                : Icon(
                    Icons.volume_up,
                    size: kChannelIcon,
                    color: liveColor ?? context.p.muted,
                  ),
            label: c.name,
            subtitle: c.displayedVoiceStatus,
            trailing: since != null && since > 0
                ? ElapsedTime(
                    startedAt: since,
                    style: const TextStyle(color: kVoiceLive, fontSize: 10),
                  )
                : null,
          ),
        ),
        if (occupied)
          Padding(
            padding: const EdgeInsets.only(left: kVoiceOccupantIndent, top: 2),
            child: Column(
              children: [
                for (final e in occupants.entries)
                  _voiceOccupant(context, s, e.key, e.value),
                for (final stream in streams) _externalStream(context, stream),
              ],
            ),
          ),
      ],
    );
  }

  Widget _voiceOccupant(
    BuildContext context,
    SessionController s,
    int userId,
    VoiceUserState st,
  ) {
    final user = s.users[userId];
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      child: Row(
        children: [
          UserAvatar(
            user: user,
            session: s,
            size: kVoiceOccupantAvatar,
            showStatus: false,
            speakingIntensity: s.speakingOf(userId, micMuted: st.micMuted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              user?.displayName ?? '',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.p.muted,
                fontSize: 13,
                height: 1.2,
              ),
            ),
          ),
          ElapsedTime(
            startedAt: st.joinedAt,
            style: TextStyle(color: context.p.muted, fontSize: 10),
          ),
          if (st.micMuted ||
              st.soundMuted ||
              st.webcamEnabled ||
              st.sharingScreen) ...[
            const SizedBox(width: 4),
            if (st.micMuted)
              Icon(Icons.mic_off, size: 12, color: context.p.dnd),
            if (st.soundMuted)
              Icon(Icons.headset_off, size: 12, color: context.p.dnd),
            if (st.webcamEnabled)
              Icon(Icons.videocam, size: 12, color: const Color(0xFF3B82F6)),
            if (st.sharingScreen)
              Icon(
                Icons.screen_share,
                size: 12,
                color: const Color(0xFFA855F7),
              ),
          ],
        ],
      ),
    );
    if (user == null) return row;
    return ContextRegion(
      onTap: (pos) => s.showProfile(user, anchor: pos),
      openMenu: (ctx, pos) => openMemberPointerMenu(ctx, pos, s, user),
      child: row,
    );
  }

  Widget _externalStream(BuildContext context, ExternalStream stream) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      child: Row(
        children: [
          if (stream.avatarUrl != null && stream.avatarUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                stream.avatarUrl!,
                width: kVoiceOccupantAvatar,
                height: kVoiceOccupantAvatar,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.router,
                  size: kVoiceOccupantAvatar,
                  color: context.p.muted.withValues(alpha: 0.6),
                ),
              ),
            )
          else
            Icon(
              Icons.router,
              size: kVoiceOccupantAvatar,
              color: context.p.muted.withValues(alpha: 0.6),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              stream.title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.p.muted,
                fontSize: 13,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createChannel(
    BuildContext context,
    SessionController s, {
    int? categoryId,
  }) async {
    final l = L10n.of(context);
    final name = TextEditingController();
    var type = 'TEXT';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(l('createChannel')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              KurierField(controller: name, label: l('channelName')),
              RadioListTile(
                title: Text(l('textChannel')),
                value: 'TEXT',
                groupValue: type,
                onChanged: (v) => setSt(() => type = v!),
              ),
              RadioListTile(
                title: Text(l('voiceChannel')),
                value: 'VOICE',
                groupValue: type,
                onChanged: (v) => setSt(() => type = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l('confirm')),
            ),
          ],
        ),
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await s.createChannel(
        name: name.text.trim(),
        type: type,
        categoryId: categoryId,
      );
    }
  }

  Future<void> _createCategory(
    BuildContext context,
    SessionController s,
  ) async {
    final l = L10n.of(context);
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l('createCategory')),
        content: KurierField(controller: name, label: l('categoryName')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l('confirm')),
          ),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await s.createCategory(name.text.trim());
    }
  }
}

class AccountBar extends StatelessWidget {
  const AccountBar({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final l = L10n.of(context);
    final me = s.me;
    final voiceId = s.connectedVoiceChannelId;
    final canSpeak =
        voiceId == null || s.canChannel(voiceId, ChannelPermission.speak);
    final muteEnabled = canSpeak && !s.soundMuted;
    return Container(
      height: kAccountBarHeight,
      decoration: BoxDecoration(
        color: context.p.rail,
        border: Border(top: BorderSide(color: context.p.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => s.openOverlay('userSettings'),
            child: UserAvatar(user: me, session: s, size: 32),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => s.openOverlay('userSettings'),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    me?.displayName ?? '',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.p.foreground,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      height: 1.15,
                    ),
                  ),
                  Text(
                    me?.statusMessage?.trim().isNotEmpty == true
                        ? me!.statusMessage!
                        : (me?.status ?? ''),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.p.faint,
                      fontSize: 11,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
          CompactIconButton(
            tooltip: s.micMuted ? l('unmute') : l('mute'),
            icon: s.micMuted ? Icons.mic_off : Icons.mic,
            color: s.micMuted ? context.p.dnd : context.p.muted,
            background: s.micMuted
                ? context.p.dnd.withValues(alpha: 0.12)
                : null,
            onPressed: muteEnabled ? () => s.setMicMuted(!s.micMuted) : null,
          ),
          CompactIconButton(
            tooltip: s.soundMuted ? l('undeafen') : l('deafen'),
            icon: s.soundMuted ? Icons.headset_off : Icons.headset,
            color: s.soundMuted ? context.p.dnd : context.p.muted,
            background: s.soundMuted
                ? context.p.dnd.withValues(alpha: 0.12)
                : null,
            onPressed: () => s.setSoundMuted(!s.soundMuted),
          ),
          CompactIconButton(
            tooltip: l('userSettings'),
            icon: Icons.settings,
            onPressed: () => s.openOverlay('userSettings'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/breakpoints.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/models.dart';
import '../protocol/presence.dart';
import '../session/session_controller.dart';
import 'member_context_menu.dart';
import 'shared.dart';
import 'user_admin_info.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.session, required this.user});
  final SessionController session;
  final KurierUser user;

  @override
  Widget build(BuildContext context) {
    final phone =
        breakpointOf(MediaQuery.sizeOf(context).width) == Breakpoint.phone;
    if (phone) {
      return _MobileProfileSheet(session: session, user: user);
    }
    return _DesktopProfileCard(session: session, user: user);
  }
}

String formatMemberSince(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String profileHandle(KurierUser user) => '@${user.name}';

Widget profilePresenceLine(BuildContext context, KurierUser user) {
  if (user.deleted) return const SizedBox.shrink();
  final l = L10n.of(context);
  final p = context.p;
  final color = switch (user.status) {
    'idle' => p.idle,
    'online' || 'dnd' => p.online,
    _ => p.muted,
  };
  return Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      l(presenceLabelKey(user.status)),
      style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );
}

Offset desktopPopoutOffset({
  required Size view,
  required EdgeInsets pad,
  required Offset? anchor,
  required double width,
  double estimatedHeight = 480,
}) {
  const gap = 12.0;
  const margin = 8.0;
  double left;
  double top;
  if (anchor == null) {
    left = ((view.width - width) / 2).clamp(margin, view.width);
    top = ((view.height - estimatedHeight) / 2).clamp(
      pad.top + margin,
      view.height,
    );
  } else {
    left = anchor.dx + gap;
    if (left + width > view.width - margin) {
      left = anchor.dx - width - gap;
    }
    if (left < margin) left = margin;
    if (left + width > view.width - margin) {
      left = (view.width - width - margin).clamp(margin, view.width);
    }
    top = anchor.dy;
    if (top + 160 > view.height - pad.bottom - margin) {
      top = view.height - pad.bottom - margin - 160;
    }
    if (top < pad.top + margin) top = pad.top + margin;
  }
  return Offset(left, top);
}

class ProfileAvatarBadge extends StatelessWidget {
  const ProfileAvatarBadge({
    super.key,
    required this.session,
    required this.user,
    this.size = 72,
    this.ringWidth = 4,
  });

  final SessionController session;
  final KurierUser user;
  final double size;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ringWidth),
      decoration: BoxDecoration(
        color: context.p.sidebar,
        shape: BoxShape.circle,
      ),
      child: UserAvatar(
        user: user,
        session: session,
        size: size,
        statusBorderColor: context.p.sidebar,
      ),
    );
  }
}

Widget profileSectionLabel(BuildContext context, String text) {
  return Text(
    text,
    style: TextStyle(
      color: context.p.faint,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
    ),
  );
}

class _DesktopProfileCard extends StatelessWidget {
  const _DesktopProfileCard({required this.session, required this.user});
  final SessionController session;
  final KurierUser user;

  static const _width = 300.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final pos = desktopPopoutOffset(
      view: size,
      pad: pad,
      anchor: session.profileAnchor,
      width: _width,
    );
    final maxH = (size.height - pos.dy - pad.bottom - 8).clamp(
      160.0,
      size.height,
    );

    return Positioned.fill(
      child: _ProfileDismissScope(
        session: session,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: session.closeOverlay,
          child: Stack(
            children: [
              Positioned(
                left: pos.dx,
                top: pos.dy,
                child: GestureDetector(
                  onTap: () {},
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _width,
                      maxHeight: maxH,
                    ),
                    child: Material(
                      key: const ValueKey('profile-popout'),
                      color: context.p.sidebar,
                      elevation: 16,
                      shadowColor: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: ListenableBuilder(
                        listenable: session,
                        builder: (context, _) => _DesktopPopoutBody(
                          session: session,
                          user: session.users[user.id] ?? user,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopPopoutBody extends StatelessWidget {
  const _DesktopPopoutBody({required this.session, required this.user});
  final SessionController session;
  final KurierUser user;

  static const _bannerH = 90.0;
  static const _avatar = 72.0;
  static const _ring = 4.0;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final l = L10n.of(context);
    final p = context.p;
    final live = user;
    final a = MemberActionPlan(s, live);
    final roles =
        live.roleIds.map((id) => s.roles[id]).whereType<KurierRole>().toList()
          ..sort((x, y) => y.position.compareTo(x.position));
    final voiceId = s.voiceChannelIdOf(live.id);
    final voiceCh = voiceId != null ? s.channels[voiceId] : null;
    final occupants = voiceId != null
        ? (s.voiceMap[voiceId] ?? const <int, VoiceUserState>{})
        : const <int, VoiceUserState>{};
    final badge = _avatar + _ring * 2;
    final bannerUrl = live.banner != null ? s.fileUrl(live.banner!) : '';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _bannerH + badge / 2,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: _bannerH,
                  child: ColoredBox(
                    color: profileBannerColor(live.profileColor),
                    child: bannerUrl.isNotEmpty
                        ? Image.network(
                            bannerUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            gaplessPlayback: true,
                            errorBuilder: (_, _, _) => const SizedBox.expand(),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  top: _bannerH - badge / 2,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ProfileAvatarBadge(
                      session: s,
                      user: live,
                      size: _avatar,
                      ringWidth: _ring,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  live.displayName,
                  style: TextStyle(
                    color: live.deleted ? p.muted : p.foreground,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    decoration: live.deleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  profileHandle(live),
                  style: TextStyle(color: p.muted, fontSize: 14),
                ),
                profilePresenceLine(context, live),
                if (live.deleted)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l('accountDeleted'),
                      style: TextStyle(color: p.muted),
                    ),
                  ),
                if ((live.pronouns ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      live.pronouns!.trim(),
                      style: TextStyle(color: p.muted, fontSize: 13),
                    ),
                  ),
                if ((live.statusMessage ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      live.statusMessage!.trim(),
                      style: TextStyle(color: p.foreground, fontSize: 13),
                    ),
                  ),
                if ((live.bio ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  profileSectionLabel(context, l('aboutMe')),
                  const SizedBox(height: 4),
                  Text(
                    live.bio!.trim(),
                    style: TextStyle(color: p.foreground, fontSize: 14),
                  ),
                ],
                if (roles.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  profileSectionLabel(context, l('roles').toUpperCase()),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final r in roles) RoleChip(role: r)],
                  ),
                ],
                if (voiceCh != null) ...[
                  const SizedBox(height: 14),
                  profileSectionLabel(context, l('inVoice')),
                  const SizedBox(height: 8),
                  _VoiceCard(
                    session: s,
                    channel: voiceCh,
                    occupants: occupants,
                    onJoin: () {
                      s.closeOverlay();
                      s.selectChannel(voiceCh.id);
                      s.joinVoice(voiceCh.id);
                    },
                  ),
                ],
                if (a.showVolume) ...[
                  const SizedBox(height: 14),
                  profileSectionLabel(context, l('volumeSection')),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                    decoration: BoxDecoration(
                      color: p.rail,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: UserVolumeSlider(session: s, userId: live.id),
                  ),
                ],
                const SizedBox(height: 14),
              ],
            ),
          ),
          Divider(color: p.divider, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: live.createdAt > 0
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l('memberSince'),
                              style: TextStyle(
                                color: p.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatMemberSince(live.createdAt),
                              style: TextStyle(
                                color: p.foreground,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                if (a.dmOk)
                  IconButton(
                    key: const ValueKey('profile-message'),
                    tooltip: l('messageUser'),
                    onPressed: () {
                      s.closeOverlay();
                      s.openDm(live.id);
                    },
                    icon: Icon(
                      Icons.chat_bubble_outline,
                      size: 20,
                      color: p.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDismissScope extends StatelessWidget {
  const _ProfileDismissScope({required this.session, required this.child});
  final SessionController session;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) session.closeOverlay();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape):
              session.closeOverlay,
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

class _MobileProfileSheet extends StatelessWidget {
  const _MobileProfileSheet({required this.session, required this.user});
  final SessionController session;
  final KurierUser user;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final reservedTop = pad.top + 48;
    final heightFactor = ((size.height - reservedTop) / size.height).clamp(
      0.5,
      0.92,
    );
    return Positioned.fill(
      child: _ProfileDismissScope(
        session: session,
        child: GestureDetector(
          key: const ValueKey('profile-barrier'),
          behavior: HitTestBehavior.opaque,
          onTap: session.closeOverlay,
          child: ColoredBox(
            color: Colors.black54,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onTap: () {},
                child: FractionallySizedBox(
                  heightFactor: heightFactor,
                  widthFactor: 1,
                  child: Material(
                    color: context.p.sidebar,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SafeArea(
                      top: false,
                      child: _MobileProfileBody(session: session, user: user),
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

class _MobileProfileBody extends StatelessWidget {
  const _MobileProfileBody({required this.session, required this.user});
  final SessionController session;
  final KurierUser user;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final s = session;
        final l = L10n.of(context);
        final p = context.p;
        final live = s.users[user.id] ?? user;
        final a = MemberActionPlan(s, live);
        final roles =
            live.roleIds
                .map((id) => s.roles[id])
                .whereType<KurierRole>()
                .toList()
              ..sort((x, y) => y.position.compareTo(x.position));
        final voiceId = s.voiceChannelIdOf(live.id);
        final voiceCh = voiceId != null ? s.channels[voiceId] : null;
        final occupants = voiceId != null
            ? (s.voiceMap[voiceId] ?? const <int, VoiceUserState>{})
            : const <int, VoiceUserState>{};

        return Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _Header(
                      session: s,
                      user: live,
                      showOverflow: a.hasOverflowActions,
                      onClose: s.closeOverlay,
                      onOverflow: () =>
                          showMemberOverflowSheet(context, s, live),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverList.list(
                      children: [
                        Text(
                          live.displayName,
                          style: TextStyle(
                            color: live.deleted ? p.muted : p.foreground,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            decoration: live.deleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          profileHandle(live),
                          style: TextStyle(color: p.muted, fontSize: 14),
                        ),
                        profilePresenceLine(context, live),
                        if ((live.pronouns ?? '').trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              live.pronouns!.trim(),
                              style: TextStyle(color: p.muted, fontSize: 14),
                            ),
                          ),
                        if (live.deleted)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              l('accountDeleted'),
                              style: TextStyle(color: p.muted),
                            ),
                          ),
                        if (a.dmOk) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: FilledButton.icon(
                              onPressed: () {
                                s.closeOverlay();
                                s.openDm(live.id);
                              },
                              icon: const Icon(Icons.chat_bubble, size: 18),
                              label: Text(l('messageUser')),
                              style: FilledButton.styleFrom(
                                backgroundColor: context.k.accent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (a.showAdminInfo) ...[
                          SizedBox(height: a.dmOk ? 8 : 16),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton.icon(
                              key: const ValueKey('profile-details'),
                              onPressed: () =>
                                  showUserAdminInfoSheet(context, s, live),
                              icon: const Icon(
                                Icons.assignment_outlined,
                                size: 18,
                              ),
                              label: Text(l('detailsTitle')),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: p.foreground,
                                side: BorderSide(color: p.divider),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (voiceCh != null) ...[
                          const SizedBox(height: 20),
                          profileSectionLabel(context, l('inVoice')),
                          const SizedBox(height: 8),
                          _VoiceCard(
                            session: s,
                            channel: voiceCh,
                            occupants: occupants,
                            onJoin: () {
                              s.closeOverlay();
                              s.selectChannel(voiceCh.id);
                              s.joinVoice(voiceCh.id);
                            },
                          ),
                        ],
                        if (a.showVolume) ...[
                          const SizedBox(height: 16),
                          profileSectionLabel(context, l('volumeSection')),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                            decoration: BoxDecoration(
                              color: p.rail,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: UserVolumeSlider(
                              session: s,
                              userId: live.id,
                            ),
                          ),
                        ],
                        if ((live.bio ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 20),
                          profileSectionLabel(context, l('bio')),
                          const SizedBox(height: 6),
                          Text(
                            live.bio!.trim(),
                            style: TextStyle(color: p.foreground, fontSize: 15),
                          ),
                        ],
                        if (live.createdAt > 0) ...[
                          const SizedBox(height: 20),
                          profileSectionLabel(context, l('memberSince')),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: p.muted,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formatMemberSince(live.createdAt),
                                style: TextStyle(
                                  color: p.foreground,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (roles.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          profileSectionLabel(
                            context,
                            l('roles').toUpperCase(),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final r in roles) RoleChip(role: r),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.user,
    required this.showOverflow,
    required this.onClose,
    required this.onOverflow,
  });

  final SessionController session;
  final KurierUser user;
  final bool showOverflow;
  final VoidCallback onClose;
  final VoidCallback onOverflow;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final p = context.p;
    const bannerH = 140.0;
    const avatar = 80.0;
    const overlap = 28.0;
    final bannerUrl = user.banner != null ? s.fileUrl(user.banner!) : '';
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 280) onClose();
      },
      child: SizedBox(
        height: bannerH + avatar - overlap + 12,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: bannerH,
              child: ColoredBox(
                color: profileBannerColor(user.profileColor),
                child: bannerUrl.isNotEmpty
                    ? Image.network(
                        bannerUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) => const SizedBox.expand(),
                      )
                    : null,
              ),
            ),
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: IconButton(
                  key: const ValueKey('profile-close'),
                  tooltip: L10n.of(context)('close'),
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),
            if (showOverflow)
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  child: IconButton(
                    key: const ValueKey('profile-overflow'),
                    tooltip: L10n.of(context)('others'),
                    onPressed: onOverflow,
                    icon: const Icon(Icons.more_horiz, color: Colors.white),
                  ),
                ),
              ),
            Positioned(
              left: 16,
              top: bannerH - overlap,
              child: ProfileAvatarBadge(session: s, user: user, size: avatar),
            ),
            if ((user.statusMessage ?? '').trim().isNotEmpty)
              Positioned(
                left: 16 + avatar + 12,
                top: bannerH - overlap + 8,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: p.rail,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    user.statusMessage!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: p.foreground, fontSize: 13),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
    required this.session,
    required this.channel,
    required this.occupants,
    required this.onJoin,
  });

  final SessionController session;
  final KurierChannel channel;
  final Map<int, VoiceUserState> occupants;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final l = L10n.of(context);
    final p = context.p;
    final ids = occupants.keys.take(5).toList();
    final alreadyIn = s.connectedVoiceChannelId == channel.id;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.rail,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 28.0 + (ids.length > 1 ? (ids.length - 1) * 16.0 : 0),
                height: 28,
                child: Stack(
                  children: [
                    for (var i = 0; i < ids.length; i++)
                      Positioned(
                        left: i * 16.0,
                        child: UserAvatar(
                          user: s.users[ids[i]],
                          session: s,
                          size: 28,
                          showStatus: false,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.volume_up, size: 16, color: p.foreground),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            channel.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.foreground,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (channel.displayedVoiceStatus != null)
                      VoiceStatusText(channel.displayedVoiceStatus!),
                    Text(
                      l('inServer', {'name': s.serverName}),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton(
              onPressed: alreadyIn ? null : onJoin,
              style: FilledButton.styleFrom(
                backgroundColor: p.online,
                disabledBackgroundColor: p.card,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(alreadyIn ? l('voiceConnected') : l('joinVoice')),
            ),
          ),
        ],
      ),
    );
  }
}

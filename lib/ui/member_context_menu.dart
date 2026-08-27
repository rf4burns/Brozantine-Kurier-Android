import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/breakpoints.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/config.dart';
import '../protocol/models.dart';
import '../protocol/permissions.dart';
import '../session/session_controller.dart';
import 'shared.dart';

const _menuWidth = 280.0;

class MemberActionPlan {
  MemberActionPlan(SessionController s, KurierUser u)
      : own = u.id == s.ownUserId,
        deleted = u.deleted,
        canMod = s.canModerate(u),
        dmOk = u.id != s.ownUserId &&
            !u.deleted &&
            s.publicSettings['directMessagesEnabled'] != false,
        showVolume = u.id != s.ownUserId && !u.deleted,
        showNick = !u.deleted &&
            (u.id == s.ownUserId
                ? s.can(Permission.changeNickname)
                : s.can(Permission.manageNicknames) && s.canModerate(u)),
        showMove = u.id != s.ownUserId &&
            !u.deleted &&
            s.canModerate(u) &&
            s.can(Permission.moveMembers) &&
            s.channels.values.any((c) => c.isVoice && !c.isDm),
        showRoles = u.id != s.ownUserId &&
            !u.deleted &&
            s.canModerate(u) &&
            s.can(Permission.manageRoles),
        showReset = u.id != s.ownUserId && !u.deleted && s.isOwner,
        showServerMute = u.id != s.ownUserId &&
            !u.deleted &&
            s.canModerate(u) &&
            s.can(Permission.muteMembers),
        showServerDeafen = u.id != s.ownUserId &&
            !u.deleted &&
            s.canModerate(u) &&
            s.can(Permission.deafenMembers),
        showKick = u.id != s.ownUserId &&
            !u.deleted &&
            s.canModerate(u) &&
            s.can(Permission.kickMembers),
        showBan = u.id != s.ownUserId &&
            !u.deleted &&
            s.canModerate(u) &&
            s.can(Permission.banMembers),
        showDelete = u.id != s.ownUserId &&
            !u.deleted &&
            s.canModerate(u) &&
            s.can(Permission.deleteUsers) &&
            !u.roleIds.contains(AppConfig.ownerRoleId),
        showCopy = s.can(Permission.manageUsers);

  final bool own;
  final bool deleted;
  final bool canMod;
  final bool dmOk;
  final bool showVolume;
  final bool showNick;
  final bool showMove;
  final bool showRoles;
  final bool showReset;
  final bool showServerMute;
  final bool showServerDeafen;
  final bool showKick;
  final bool showBan;
  final bool showDelete;
  final bool showCopy;

  bool get showManage => showNick || showMove || showRoles || showReset;
  bool get showModeration =>
      showServerMute || showServerDeafen || showKick || showBan || showDelete;
  bool get hasOverflowActions =>
      dmOk || showVolume || showManage || showModeration || showCopy;
}

Future<void> openMemberPointerMenu(
  BuildContext context,
  Offset globalPosition,
  SessionController session,
  KurierUser user,
) {
  if (breakpointOf(MediaQuery.sizeOf(context).width) == Breakpoint.phone) {
    session.showProfile(user, anchor: globalPosition);
    return Future.value();
  }
  return showMemberContextMenu(context, globalPosition, session, user);
}

Future<void> copyMemberText(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(L10n.of(context)('copied'))),
  );
}

Future<void> editMemberNickname(
  BuildContext context,
  SessionController s,
  KurierUser u,
) async {
  final l = L10n.of(context);
  final ctrl = TextEditingController(text: u.nickname ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l('setNickname')),
      content: KurierField(controller: ctrl, label: l('nickname')),
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
  if (ok == true) await s.updateNickname(u.id, ctrl.text);
}

Future<void> moveMemberToVoice(
  BuildContext context,
  SessionController s,
  KurierUser u,
) async {
  final l = L10n.of(context);
  final channels = s.channels.values
      .where((c) => c.isVoice && !c.isDm)
      .toList()
    ..sort((a, b) => a.position.compareTo(b.position));
  final current = s.voiceChannelIdOf(u.id);
  final picked = await showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(l('moveToVoice')),
      children: [
        for (final c in channels)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, c.id),
            child: Text(
              current == c.id ? '${c.name} ✓' : c.name,
              style: TextStyle(color: ctx.p.foreground),
            ),
          ),
      ],
    ),
  );
  if (picked != null && picked != current) {
    await s.moveUser(u.id, picked);
  }
}

Future<void> manageMemberRoles(
  BuildContext context,
  SessionController s,
  KurierUser u,
) async {
  final l = L10n.of(context);
  final actorPos = s.highestRolePosition(s.me?.roleIds ?? const []);
  final assignable = s.roles.values
      .where((r) {
        if (r.id == AppConfig.ownerRoleId) return false;
        if (r.isDefault) return false;
        if (s.isOwner) return true;
        return r.position < actorPos;
      })
      .toList()
    ..sort((a, b) => b.position.compareTo(a.position));
  final selected = {...u.roleIds};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(l('manageRoles')),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final r in assignable)
                    CheckboxListTile(
                      dense: true,
                      value: selected.contains(r.id),
                      title: Text(r.name),
                      onChanged: (v) {
                        setSt(() {
                          if (v == true) {
                            selected.add(r.id);
                          } else {
                            selected.remove(r.id);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
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
    },
  );
  if (ok != true) return;
  final current = u.roleIds.toSet();
  for (final id in selected.difference(current)) {
    await s.addUserRole(u.id, id);
  }
  for (final id in current.difference(selected)) {
    if (s.roles[id]?.isDefault == true) continue;
    if (id == AppConfig.ownerRoleId) continue;
    await s.removeUserRole(u.id, id);
  }
}

Future<void> resetMemberPassword(
  BuildContext context,
  SessionController s,
  KurierUser u,
) async {
  final l = L10n.of(context);
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l('resetPassword')),
      content: KurierField(
        controller: ctrl,
        label: l('newPassword'),
        obscure: true,
      ),
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
  if (ok == true && ctrl.text.isNotEmpty) {
    await s.resetUserPassword(u.id, ctrl.text);
  }
}

Future<void> kickMember(
  BuildContext context,
  SessionController s,
  KurierUser u,
) async {
  final l = L10n.of(context);
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l('kickFromServer')),
      content: KurierField(controller: ctrl, label: l('reason'), hint: l('reason')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l('kick')),
        ),
      ],
    ),
  );
  if (ok == true) await s.kick(u.id, ctrl.text);
}

Future<void> banMember(
  BuildContext context,
  SessionController s,
  KurierUser u,
) async {
  final l = L10n.of(context);
  if (u.banned) {
    await s.unban(u.id);
    return;
  }
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l('banFromServer')),
      content: KurierField(controller: ctrl, label: l('reason'), hint: l('reason')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l('ban')),
        ),
      ],
    ),
  );
  if (ok == true) await s.ban(u.id, ctrl.text);
}

Future<void> deleteMember(
  BuildContext context,
  SessionController s,
  KurierUser u,
) async {
  final l = L10n.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l('deleteAccount')),
      content: Text(l('deleteAccountConfirm')),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l('delete')),
        ),
      ],
    ),
  );
  if (ok == true) await s.deleteUser(u.id);
}

Future<void> showMemberOverflowSheet(
  BuildContext context,
  SessionController session,
  KurierUser user,
) {
  final l = L10n.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return ListenableBuilder(
        listenable: session,
        builder: (ctx, _) {
          final live = session.users[user.id] ?? user;
          final a = MemberActionPlan(session, live);
          final p = ctx.p;
          Widget item({
            required String label,
            required VoidCallback onTap,
            bool danger = false,
          }) {
            return InkWell(
              onTap: onTap,
              child: SizedBox(
                height: 52,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: danger ? p.dnd : p.foreground,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          Widget sep() => Divider(height: 1, color: p.divider);

          Future<void> run(Future<void> Function(BuildContext c) action) async {
            Navigator.pop(ctx);
            if (context.mounted) await action(context);
          }

          final actions = <Widget>[
            if (a.dmOk)
              item(
                label: l('messageUser'),
                onTap: () => run((_) => session.openDm(live.id)),
              ),
            if (a.showVolume)
              item(
                label: session.isLocallyMuted(live.id)
                    ? l('unmuteLocally')
                    : l('muteLocally'),
                onTap: () => session.toggleLocalMute(live.id),
              ),
            if (a.showCopy) ...[
              item(
                label: l('copyUsername'),
                onTap: () => run((c) => copyMemberText(c, live.name)),
              ),
              item(
                label: l('copyUserId'),
                onTap: () => run((c) => copyMemberText(c, '${live.id}')),
              ),
            ],
            if (a.showNick)
              item(
                label: l('setNickname'),
                onTap: () => run((c) => editMemberNickname(c, session, live)),
              ),
            if (a.showMove)
              item(
                label: l('moveToVoice'),
                onTap: () => run((c) => moveMemberToVoice(c, session, live)),
              ),
            if (a.showRoles)
              item(
                label: l('manageRoles'),
                onTap: () => run((c) => manageMemberRoles(c, session, live)),
              ),
            if (a.showReset)
              item(
                label: l('resetPassword'),
                onTap: () => run((c) => resetMemberPassword(c, session, live)),
              ),
            if (a.showServerMute)
              item(
                label: live.serverMuted ? l('unmute') : l('serverMute'),
                onTap: () => run(
                  (_) => session.muteUser(live.id, !live.serverMuted),
                ),
              ),
            if (a.showServerDeafen)
              item(
                label: live.serverDeafened ? l('undeafen') : l('serverDeafen'),
                onTap: () => run(
                  (_) => session.deafenUser(live.id, !live.serverDeafened),
                ),
              ),
            if (a.showKick)
              item(
                label: l('kickFromServer'),
                danger: true,
                onTap: () => run((c) => kickMember(c, session, live)),
              ),
            if (a.showBan)
              item(
                label: live.banned ? l('unban') : l('banFromServer'),
                danger: true,
                onTap: () => run((c) => banMember(c, session, live)),
              ),
            if (a.showDelete)
              item(
                label: l('deleteAccount'),
                danger: true,
                onTap: () => run((c) => deleteMember(c, session, live)),
              ),
          ];
          final tiles = <Widget>[
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) sep(),
              actions[i],
            ],
          ];

          final listCap = MediaQuery.sizeOf(ctx).height * 0.55;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: listCap),
                    child: Material(
                      color: p.sidebar,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: ListView(
                        shrinkWrap: true,
                        children: tiles,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Material(
                    color: p.sidebar,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx),
                      child: SizedBox(
                        height: 52,
                        width: double.infinity,
                        child: Center(
                          child: Text(
                            l('close'),
                            style: TextStyle(
                              color: p.foreground,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> showMemberContextMenu(
  BuildContext context,
  Offset globalPosition,
  SessionController session,
  KurierUser user,
) {
  final host = context;
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black38,
      pageBuilder: (ctx, _, _) => _MemberMenuPage(
        anchor: globalPosition,
        session: session,
        userId: user.id,
        hostContext: host,
      ),
    ),
  );
}

class _MemberMenuPage extends StatelessWidget {
  const _MemberMenuPage({
    required this.anchor,
    required this.session,
    required this.userId,
    required this.hostContext,
  });

  final Offset anchor;
  final SessionController session;
  final int userId;
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    const maxH = 0.86;
    final menuH = size.height * maxH;
    var left = anchor.dx;
    var top = anchor.dy;
    if (left + _menuWidth > size.width - 8) {
      left = size.width - _menuWidth - 8;
    }
    if (left < 8) left = 8;
    if (top + 120 > size.height - pad.bottom) {
      top = (size.height - menuH - pad.bottom).clamp(8.0, size.height);
    }
    if (top < pad.top + 8) top = pad.top + 8;

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
                maxWidth: _menuWidth,
                maxHeight: size.height - top - pad.bottom - 8,
              ),
              child: _MemberMenu(
                session: session,
                userId: userId,
                hostContext: hostContext,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberMenu extends StatefulWidget {
  const _MemberMenu({
    required this.session,
    required this.userId,
    required this.hostContext,
  });
  final SessionController session;
  final int userId;
  final BuildContext hostContext;

  @override
  State<_MemberMenu> createState() => _MemberMenuState();
}

class _MemberMenuState extends State<_MemberMenu> {
  UserAdminInfo? _info;
  var _loadingInfo = false;

  SessionController get s => widget.session;

  KurierUser? get user => s.users[widget.userId];

  bool get _canFetchInfo => s.canAny(const [
        Permission.manageUsers,
        Permission.viewUserSensitiveData,
        Permission.viewAuditLog,
        Permission.manageStorage,
      ]);

  @override
  void initState() {
    super.initState();
    if (_canFetchInfo) _loadInfo();
  }

  Future<void> _loadInfo() async {
    setState(() => _loadingInfo = true);
    final info = await s.getUserInfo(widget.userId);
    if (!mounted) return;
    setState(() {
      _info = info;
      _loadingInfo = false;
    });
    final fetched = info?.user;
    if (fetched != null && s.users.containsKey(fetched.id)) {
      final existing = s.users[fetched.id]!;
      if ((existing.identity == null || existing.identity!.isEmpty) &&
          fetched.identity != null) {
        existing.identity = fetched.identity;
      }
      if (existing.lastLoginAt == 0 && fetched.lastLoginAt != 0) {
        existing.lastLoginAt = fetched.lastLoginAt;
      }
    }
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _run(Future<void> Function(BuildContext ctx) action) async {
    final host = widget.hostContext;
    _close();
    if (host.mounted) await action(host);
  }

  @override
  Widget build(BuildContext context) {
    final u = user;
    if (u == null) return const SizedBox.shrink();
    final l = L10n.of(context);
    final p = context.p;
    final a = MemberActionPlan(s, u);
    final roles = u.roleIds
        .map((id) => s.roles[id])
        .whereType<KurierRole>()
        .toList()
      ..sort((b, c) => c.position.compareTo(b.position));

    final showCards = _info != null;
    final showSensitive = s.can(Permission.viewUserSensitiveData);
    final showJoined = u.createdAt > 0 && !showCards;
    final showLastActive =
        (u.lastLoginAt > 0 || (_info?.user.lastLoginAt ?? 0) > 0) && !showCards;

    final dmOk = a.dmOk;
    final showVolume = a.showVolume;
    final showNick = a.showNick;
    final showMove = a.showMove;
    final showRoles = a.showRoles;
    final showReset = a.showReset;
    final showServerMute = a.showServerMute;
    final showServerDeafen = a.showServerDeafen;
    final showKick = a.showKick;
    final showBan = a.showBan;
    final showDelete = a.showDelete;
    final showManage = a.showManage;
    final showModeration = a.showModeration;

    return Material(
      color: p.sidebar,
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: ListenableBuilder(
        listenable: s,
        builder: (context, _) {
          final live = s.users[widget.userId] ?? u;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
                  child: Text(
                    live.displayName,
                    style: TextStyle(
                      color: p.foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (roles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final r in roles) RoleChip(role: r),
                      ],
                    ),
                  ),
                if (_loadingInfo && _info == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: p.muted,
                        ),
                      ),
                    ),
                  ),
                if (showCards) ...[
                  _InfoCard(
                    icon: Icons.show_chart,
                    title: l('serverActivity'),
                    rows: [
                      _InfoRow(
                        icon: Icons.chat_bubble_outline,
                        label: l('serverActivityMessages'),
                        value: '${_info!.messages.length}',
                      ),
                      _InfoRow(
                        icon: Icons.link,
                        label: l('serverActivityLinks'),
                        value: '${_info!.linkCount}',
                      ),
                      _InfoRow(
                        icon: Icons.insert_drive_file_outlined,
                        label: l('serverActivityFiles'),
                        value: '${_info!.files.length}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _InfoCard(
                    icon: Icons.storage,
                    title: l('storage'),
                    rows: [
                      _InfoRow(
                        label: l('usedStorage'),
                        value: formatBytes(_info!.storage.usedStorage),
                      ),
                      _InfoRow(
                        label: l('quota'),
                        value: _info!.storage.quota > 0
                            ? formatBytes(_info!.storage.quota)
                            : l('unlimited'),
                      ),
                      _InfoRow(
                        label: l('serverActivityFiles'),
                        value: '${_info!.storage.fileCount}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _DetailsCard(
                    user: _info!.user.lastLoginAt > 0 ? _info!.user : live,
                    login: _info!.logins.isEmpty ? null : _info!.logins.first,
                    showSensitive: showSensitive,
                  ),
                  const SizedBox(height: 8),
                ] else if (showJoined || showLastActive) ...[
                  if (showJoined)
                    _MetaRow(
                      icon: Icons.calendar_today_outlined,
                      label: l('joinedServer'),
                      value: compactRelativeTime(live.createdAt),
                    ),
                  if (showLastActive)
                    _MetaRow(
                      icon: Icons.schedule,
                      label: l('lastActive'),
                      value: compactRelativeTime(
                        live.lastLoginAt > 0
                            ? live.lastLoginAt
                            : _info?.user.lastLoginAt ?? 0,
                      ),
                    ),
                  const SizedBox(height: 4),
                ],
                _Item(
                  icon: Icons.person_outline,
                  label: l('viewProfile'),
                  onTap: () => _run((_) async => s.showProfile(live)),
                ),
                if (dmOk)
                  _Item(
                    icon: Icons.chat_bubble_outline,
                    label: l('messageUser'),
                    onTap: () => _run((_) => s.openDm(live.id)),
                  ),
                if (showVolume) ...[
                  _Divider(),
                  _SectionLabel(l('volumeSection')),
                  _Item(
                    icon: s.isLocallyMuted(live.id)
                        ? Icons.volume_off_outlined
                        : Icons.volume_up_outlined,
                    label: s.isLocallyMuted(live.id)
                        ? l('unmuteLocally')
                        : l('muteLocally'),
                    onTap: () => s.toggleLocalMute(live.id),
                  ),
                  UserVolumeSlider(session: s, userId: live.id),
                ],
                if (showManage) ...[
                  _Divider(),
                  _SectionLabel(l('manageSection')),
                  if (showNick)
                    _Item(
                      icon: Icons.badge_outlined,
                      label: l('setNickname'),
                      onTap: () => _run((ctx) => editMemberNickname(ctx, s, live)),
                    ),
                  if (showMove)
                    _Item(
                      icon: Icons.swap_horiz,
                      label: l('moveToVoice'),
                      onTap: () => _run((ctx) => moveMemberToVoice(ctx, s, live)),
                    ),
                  if (showRoles)
                    _Item(
                      icon: Icons.shield_outlined,
                      label: l('manageRoles'),
                      onTap: () => _run((ctx) => manageMemberRoles(ctx, s, live)),
                    ),
                  if (showReset)
                    _Item(
                      icon: Icons.lock_reset,
                      label: l('resetPassword'),
                      onTap: () => _run((ctx) => resetMemberPassword(ctx, s, live)),
                    ),
                ],
                if (showModeration) ...[
                  _Divider(),
                  _SectionLabel(l('moderationSection')),
                  if (showServerMute)
                    _Item(
                      icon: Icons.mic_off_outlined,
                      label: live.serverMuted ? l('unmute') : l('serverMute'),
                      onTap: () => _run(
                        (_) => s.muteUser(live.id, !live.serverMuted),
                      ),
                    ),
                  if (showServerDeafen)
                    _Item(
                      icon: Icons.headset_off,
                      label:
                          live.serverDeafened ? l('undeafen') : l('serverDeafen'),
                      onTap: () => _run(
                        (_) => s.deafenUser(live.id, !live.serverDeafened),
                      ),
                    ),
                  if (showKick)
                    _Item(
                      icon: Icons.logout,
                      label: l('kickFromServer'),
                      danger: true,
                      onTap: () => _run((ctx) => kickMember(ctx, s, live)),
                    ),
                  if (showBan)
                    _Item(
                      icon: Icons.gavel,
                      label: live.banned ? l('unban') : l('banFromServer'),
                      danger: true,
                      onTap: () => _run((ctx) => banMember(ctx, s, live)),
                    ),
                  if (showDelete)
                    _Item(
                      icon: Icons.delete_outline,
                      label: l('deleteAccount'),
                      danger: true,
                      onTap: () => _run((ctx) => deleteMember(ctx, s, live)),
                    ),
                ],
                _Divider(),
                _Item(
                  icon: Icons.alternate_email,
                  label: l('copyUsername'),
                  onTap: () => _copy(live.name),
                ),
                _Item(
                  icon: Icons.tag,
                  label: l('copyUserId'),
                  onTap: () => _copy('${live.id}'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    final host = widget.hostContext;
    final l = L10n.of(host.mounted ? host : context);
    _close();
    if (!host.mounted) return;
    ScaffoldMessenger.maybeOf(host)?.showSnackBar(
      SnackBar(content: Text(l('copied'))),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.rows,
  });

  final IconData icon;
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        color: p.rail,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: p.muted),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: p.foreground,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in rows) row,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({this.icon, required this.label, required this.value});
  final IconData? icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: p.muted),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
          ),
          Text(value, style: TextStyle(color: p.foreground, fontSize: 13)),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatefulWidget {
  const _DetailsCard({
    required this.user,
    required this.login,
    required this.showSensitive,
  });

  final KurierUser user;
  final UserLoginInfo? login;
  final bool showSensitive;

  @override
  State<_DetailsCard> createState() => _DetailsCardState();
}

class _DetailsCardState extends State<_DetailsCard> {
  final _revealed = <String>{};

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final u = widget.user;
    final login = widget.login;
    final location = [
      if ((login?.country ?? '').isNotEmpty) login!.country,
      if ((login?.city ?? '').isNotEmpty) login!.city,
    ].join(' - ');
    return _InfoCard(
      icon: Icons.assignment_outlined,
      title: l('detailsTitle'),
      rows: [
        _InfoRow(label: l('userIdLabel'), value: '${u.id}'),
        if (widget.showSensitive) ...[
          _SecretRow(
            label: l('identity'),
            value: u.identity?.trim().isNotEmpty == true
                ? u.identity!
                : l('unknownValue'),
            revealed: _revealed.contains('identity'),
            onToggle: () => setState(() {
              if (!_revealed.add('identity')) _revealed.remove('identity');
            }),
          ),
          _SecretRow(
            label: l('ipAddressLabel'),
            value: (login?.ip ?? '').isNotEmpty
                ? login!.ip!
                : l('unknownValue'),
            revealed: _revealed.contains('ip'),
            onToggle: () => setState(() {
              if (!_revealed.add('ip')) _revealed.remove('ip');
            }),
          ),
          _SecretRow(
            label: l('locationLabel'),
            value: location.isEmpty ? l('naValue') : location,
            revealed: _revealed.contains('loc'),
            onToggle: () => setState(() {
              if (!_revealed.add('loc')) _revealed.remove('loc');
            }),
          ),
        ],
        if (u.createdAt > 0)
          _InfoRow(
            icon: Icons.calendar_today_outlined,
            label: l('joinedServer'),
            value: compactRelativeTime(u.createdAt),
          ),
        if (u.lastLoginAt > 0)
          _InfoRow(
            icon: Icons.schedule,
            label: l('lastActive'),
            value: compactRelativeTime(u.lastLoginAt),
          ),
      ],
    );
  }
}

class _SecretRow extends StatelessWidget {
  const _SecretRow({
    required this.label,
    required this.value,
    required this.revealed,
    required this.onToggle,
  });

  final String label;
  final String value;
  final bool revealed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
          ),
          Text(
            revealed ? value : '***',
            style: TextStyle(color: p.foreground, fontSize: 13),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onToggle,
            child: Icon(
              revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 16,
              color: p.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: p.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
          ),
          Text(value, style: TextStyle(color: p.foreground, fontSize: 13)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: context.p.faint,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Divider(color: context.p.divider, height: 1),
    );
  }
}

class _Item extends StatefulWidget {
  const _Item({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final color = widget.danger ? p.dnd : p.foreground;
    final iconColor = widget.danger ? p.dnd : p.muted;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: _hover ? p.card.withValues(alpha: 0.7) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(color: color, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class UserVolumeSlider extends StatelessWidget {
  const UserVolumeSlider({
    super.key,
    required this.session,
    required this.userId,
  });
  final SessionController session;
  final int userId;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final vol = session.localUserVolume(userId);
    final pct = (vol * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.graphic_eq, size: 18, color: p.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l('userVolume'),
                  style: TextStyle(color: p.foreground, fontSize: 14),
                ),
              ),
              Text('$pct%', style: TextStyle(color: p.muted, fontSize: 12)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: context.k.accent,
              inactiveTrackColor: p.divider,
              thumbColor: context.k.accent,
            ),
            child: Slider(
              value: vol,
              onChanged: (v) => session.setLocalUserVolume(userId, v),
            ),
          ),
        ],
      ),
    );
  }
}

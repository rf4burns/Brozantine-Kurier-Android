import 'package:flutter/material.dart';

import '../app/breakpoints.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/models.dart';
import '../session/session_controller.dart';
import 'context_menu.dart';
import 'member_context_menu.dart';
import 'shared.dart';

Future<void> showMemberPane(BuildContext context, SessionController session) {
  final width = MediaQuery.sizeOf(context).width;
  final paneWidth = width < 700 ? (width * 0.86).clamp(240.0, 320.0) : 280.0;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: L10n.of(context)('members', {'count': '${session.users.length}'}),
    barrierColor: Colors.black54,
    pageBuilder: (ctx, _, _) {
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: ctx.p.sidebar,
          child: SizedBox(
            width: paneWidth,
            height: MediaQuery.sizeOf(ctx).height,
            child: SafeArea(child: MemberList(session: session)),
          ),
        ),
      );
    },
  );
}

class MemberList extends StatelessWidget {
  const MemberList({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final count = session.users.values.where((u) => !u.deleted).length;
        return Material(
          color: context.p.sidebar,
          child: Column(
            children: [
              SizedBox(
                height: kHeaderHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      L10n.of(context)('members', {'count': '$count'}),
                      style: TextStyle(
                        color: context.p.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
              ),
              Divider(color: context.p.divider, height: 1),
              Expanded(child: MemberListBody(session: session)),
            ],
          ),
        );
      },
    );
  }
}

class MemberListBody extends StatelessWidget {
  const MemberListBody({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final l = L10n.of(context);
    final members = s.users.values.where((u) => !u.deleted).toList();
    // Discord-style: online members sit under their highest rank. Owner and
    // the default role never become headers; leftover online users go under
    // Online, and everyone offline is one Offline group.
    final ranked = s.roles.values.where(isMemberListRole).toList()
      ..sort((a, b) {
        final byPos = b.position.compareTo(a.position);
        return byPos != 0 ? byPos : a.id.compareTo(b.id);
      });

    int byName(KurierUser a, KurierUser b) =>
        a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());

    final byRole = <int, List<KurierUser>>{};
    final online = <KurierUser>[];
    final offline = <KurierUser>[];
    final banned = <KurierUser>[];

    for (final u in members) {
      if (u.banned) {
        banned.add(u);
        continue;
      }
      if (!u.isOnline) {
        offline.add(u);
        continue;
      }
      final role = displayRole(u, s.roles);
      if (role != null) {
        byRole.putIfAbsent(role.id, () => []).add(u);
      } else {
        online.add(u);
      }
    }

    final groups = <_Group>[];
    for (final role in ranked) {
      final list = byRole[role.id];
      if (list == null || list.isEmpty) continue;
      list.sort(byName);
      groups.add(
        _Group(
          '${role.name} — ${list.length}',
          list,
          color: parseHexColor(role.color),
        ),
      );
    }
    online.sort(byName);
    offline.sort(byName);
    banned.sort(byName);
    if (online.isNotEmpty) {
      groups.add(_Group(l('online', {'count': '${online.length}'}), online));
    }
    if (offline.isNotEmpty) {
      groups.add(_Group(l('offline', {'count': '${offline.length}'}), offline));
    }
    if (banned.isNotEmpty) {
      groups.add(_Group(l('bannedGroup', {'count': '${banned.length}'}), banned));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      children: [
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
            child: Text(
              g.title.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: g.color ?? context.p.faint,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.24,
              ),
            ),
          ),
          for (final u in g.users) _member(context, s, u),
        ],
      ],
    );
  }

  Widget _member(
    BuildContext context,
    SessionController s,
    KurierUser u,
  ) {
    final nameColor = userRoleColor(u, s.roles) ?? context.p.foreground;
    return ContextRegion(
      key: ValueKey(u.id),
      onTap: (pos) => s.showProfile(u, anchor: pos),
      openMenu: (ctx, pos) => openMemberPointerMenu(ctx, pos, s, u),
      child: _MemberRow(
        dimmed: !u.isOnline || u.banned,
        child: Row(
          children: [
            UserAvatar(user: u, session: s, size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                u.displayName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: nameColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  decoration: u.banned ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatefulWidget {
  const _MemberRow({required this.child, this.dimmed = false});
  final Widget child;
  final bool dimmed;

  @override
  State<_MemberRow> createState() => _MemberRowState();
}

class _MemberRowState extends State<_MemberRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: _hover ? context.p.card.withValues(alpha: 0.7) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Opacity(
          opacity: widget.dimmed ? 0.4 : 1,
          child: widget.child,
        ),
      ),
    );
  }
}

class _Group {
  _Group(this.title, this.users, {this.color});
  final String title;
  final List<KurierUser> users;
  final Color? color;
}

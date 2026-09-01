import 'package:flutter/material.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/models.dart';
import '../protocol/permissions.dart';
import '../session/session_controller.dart';
import 'shared.dart';

bool canFetchUserAdminInfo(SessionController s) =>
    s.isOwner ||
    s.canAny(const [
      Permission.manageUsers,
      Permission.viewUserSensitiveData,
      Permission.viewAuditLog,
      Permission.manageStorage,
    ]);

void applyFetchedUserAdminInfo(SessionController s, UserAdminInfo? info) {
  final fetched = info?.user;
  if (fetched == null || !s.users.containsKey(fetched.id)) return;
  final existing = s.users[fetched.id]!;
  if ((existing.identity == null || existing.identity!.isEmpty) &&
      fetched.identity != null) {
    existing.identity = fetched.identity;
  }
  if (existing.lastLoginAt == 0 && fetched.lastLoginAt != 0) {
    existing.lastLoginAt = fetched.lastLoginAt;
  }
}

Future<bool> banMemberBrowser(
  BuildContext context,
  SessionController s,
  String token,
) async {
  final l = L10n.of(context);
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l('banBrowserTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l('banBrowserMsg')),
          const SizedBox(height: 12),
          KurierField(controller: ctrl, label: l('reason'), hint: l('reason')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l('cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l('banBrowserConfirm')),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) {
    ctrl.dispose();
    return false;
  }
  final reason = ctrl.text.trim();
  ctrl.dispose();
  try {
    await s.addAccessBan({
      'kind': 'device',
      'value': token,
      if (reason.isNotEmpty) 'reason': reason,
    });
    if (!context.mounted) return true;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(l('banBrowserSuccess'))));
    return true;
  } catch (_) {
    if (!context.mounted) return false;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(l('failedBanBrowser'))));
    return false;
  }
}

Future<void> showUserAdminInfoSheet(
  BuildContext context,
  SessionController session,
  KurierUser user,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _UserAdminInfoSheet(session: session, user: user),
  );
}

class UserAdminInfoPanel extends StatelessWidget {
  const UserAdminInfoPanel({
    super.key,
    required this.session,
    required this.user,
    required this.info,
    required this.loading,
  });

  final SessionController session;
  final KurierUser user;
  final UserAdminInfo? info;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final showCards = info != null;
    final showSensitive = session.can(Permission.viewUserSensitiveData);
    final showBrowserToken = session.isOwner;
    final showJoined = user.createdAt > 0 && !showCards;
    final showLastActive =
        (user.lastLoginAt > 0 || (info?.user.lastLoginAt ?? 0) > 0) &&
        !showCards;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading && info == null)
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
                value: '${info!.messages.length}',
              ),
              _InfoRow(
                icon: Icons.link,
                label: l('serverActivityLinks'),
                value: '${info!.linkCount}',
              ),
              _InfoRow(
                icon: Icons.insert_drive_file_outlined,
                label: l('serverActivityFiles'),
                value: '${info!.files.length}',
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
                value: formatBytes(info!.storage.usedStorage),
              ),
              _InfoRow(
                label: l('quota'),
                value: info!.storage.quota > 0
                    ? formatBytes(info!.storage.quota)
                    : l('unlimited'),
              ),
              _InfoRow(
                label: l('serverActivityFiles'),
                value: '${info!.storage.fileCount}',
              ),
            ],
          ),
          const SizedBox(height: 8),
          _DetailsCard(
            session: session,
            user: info!.user.lastLoginAt > 0 ? info!.user : user,
            login: info!.logins.isEmpty ? null : info!.logins.first,
            showSensitive: showSensitive,
            showBrowserToken: showBrowserToken,
          ),
          const SizedBox(height: 8),
        ] else if (showJoined || showLastActive) ...[
          if (showJoined)
            _MetaRow(
              icon: Icons.calendar_today_outlined,
              label: l('joinedServer'),
              value: compactRelativeTime(user.createdAt),
            ),
          if (showLastActive)
            _MetaRow(
              icon: Icons.schedule,
              label: l('lastActive'),
              value: compactRelativeTime(
                user.lastLoginAt > 0
                    ? user.lastLoginAt
                    : info?.user.lastLoginAt ?? 0,
              ),
            ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

class _UserAdminInfoSheet extends StatefulWidget {
  const _UserAdminInfoSheet({required this.session, required this.user});
  final SessionController session;
  final KurierUser user;

  @override
  State<_UserAdminInfoSheet> createState() => _UserAdminInfoSheetState();
}

class _UserAdminInfoSheetState extends State<_UserAdminInfoSheet> {
  UserAdminInfo? _info;
  var _loading = false;

  SessionController get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final info = await s.getUserInfo(widget.user.id);
    if (!mounted) return;
    applyFetchedUserAdminInfo(s, info);
    setState(() {
      _info = info;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final live = s.users[widget.user.id] ?? widget.user;
    final listCap = MediaQuery.sizeOf(context).height * 0.7;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          key: const ValueKey('user-admin-info-sheet'),
          color: p.sidebar,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: listCap),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l('detailsTitle'),
                          style: TextStyle(
                            color: p.foreground,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l('close'),
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close, color: p.muted),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListenableBuilder(
                    listenable: s,
                    builder: (context, _) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        child: UserAdminInfoPanel(
                          session: s,
                          user: s.users[live.id] ?? live,
                          info: _info,
                          loading: _loading,
                        ),
                      );
                    },
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
    required this.session,
    required this.user,
    required this.login,
    required this.showSensitive,
    required this.showBrowserToken,
  });

  final SessionController session;
  final KurierUser user;
  final UserLoginInfo? login;
  final bool showSensitive;
  final bool showBrowserToken;

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
    final token = widget.showBrowserToken
        ? (login?.deviceToken?.trim() ?? '')
        : '';
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
        ],
        if (widget.showBrowserToken)
          _SecretRow(
            icon: Icons.fingerprint,
            label: l('browserTokenLabel'),
            value: token.isNotEmpty ? token : l('unknownValue'),
            revealed: _revealed.contains('device'),
            onToggle: () => setState(() {
              if (!_revealed.add('device')) _revealed.remove('device');
            }),
            action: token.isNotEmpty
                ? _BanBrowserButton(
                    onPressed: () =>
                        banMemberBrowser(context, widget.session, token),
                  )
                : null,
          ),
        if (widget.showSensitive)
          _SecretRow(
            label: l('locationLabel'),
            value: location.isEmpty ? l('naValue') : location,
            revealed: _revealed.contains('loc'),
            onToggle: () => setState(() {
              if (!_revealed.add('loc')) _revealed.remove('loc');
            }),
          ),
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

class _BanBrowserButton extends StatelessWidget {
  const _BanBrowserButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: p.foreground,
        side: BorderSide(color: p.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(
        L10n.of(context)('banBrowserBtn'),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _SecretRow extends StatelessWidget {
  const _SecretRow({
    this.icon,
    required this.label,
    required this.value,
    required this.revealed,
    required this.onToggle,
    this.action,
  });

  final IconData? icon;
  final String label;
  final String value;
  final bool revealed;
  final VoidCallback onToggle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: p.muted),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.muted, fontSize: 13),
            ),
          ),
          Flexible(
            child: Text(
              revealed ? value : '***',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(color: p.foreground, fontSize: 13),
            ),
          ),
          if (action != null) ...[const SizedBox(width: 6), action!],
          const SizedBox(width: 4),
          InkWell(
            onTap: onToggle,
            child: Icon(
              revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
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

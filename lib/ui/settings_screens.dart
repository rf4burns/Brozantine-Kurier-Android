import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/activity_log.dart';
import '../protocol/config.dart';
import '../protocol/models.dart';
import '../protocol/permissions.dart';
import '../session/session_controller.dart';
import 'settings_chrome.dart';
import 'server_settings.dart';
import 'settings_user.dart';
import 'shared.dart';

class SettingsHost extends ConsumerWidget {
  const SettingsHost({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = session;
    return Positioned.fill(
      child: switch (s.overlay) {
        'userSettings' => UserSettings(session: s),
        'serverSettings' => ServerSettings(session: s),
        'channelSettings' => ChannelSettings(session: s),
        'welcome' => WelcomeSheet(session: s),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

const _userTabIcons = <String, IconData>{
  'profile': Icons.person_outline,
  'devices': Icons.headset_mic_outlined,
  'appearance': Icons.palette_outlined,
  'sounds': Icons.volume_up_outlined,
  'notifications': Icons.notifications_outlined,
  'password': Icons.lock_outline,
  'security': Icons.shield_outlined,
  'others': Icons.tune,
  'about': Icons.info_outline,
};

List<SettingsNavItem> _userItems(List<(String, String)> tabs) => [
      for (final t in tabs)
        SettingsNavItem(id: t.$1, label: t.$2, icon: _userTabIcons[t.$1]),
    ];

const _serverTabIcons = <String, IconData>{
  'general': Icons.info_outline,
  'roles': Icons.badge_outlined,
  'emojis': Icons.emoji_emotions_outlined,
  'users': Icons.people_outline,
  'resetPasswords': Icons.lock_reset,
  'invites': Icons.link,
  'audit': Icons.assignment_outlined,
  'security': Icons.security,
  'accessBans': Icons.gavel,
  'storage': Icons.storage,
  'plugins': Icons.extension,
  'updates': Icons.system_update,
};

List<SettingsNavItem> _serverItems(List<(String, String)> tabs) => [
      for (final t in tabs)
        SettingsNavItem(id: t.$1, label: t.$2, icon: _serverTabIcons[t.$1]),
    ];

class UserSettings extends StatefulWidget {
  const UserSettings({super.key, required this.session});
  final SessionController session;
  @override
  State<UserSettings> createState() => _UserSettingsState();
}

class _UserSettingsState extends State<UserSettings> {
  late String tab;

  @override
  void initState() {
    super.initState();
    tab = widget.session.settingsTab;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final l = L10n.of(context);
    final tabs = [
      ('profile', l('profile')),
      ('devices', l('devices')),
      ('appearance', l('appearance')),
      ('sounds', l('sounds')),
      ('notifications', l('notifications')),
      ('password', l('password')),
      ('security', l('security')),
      ('others', l('others')),
      ('about', l('about')),
    ];
    return SettingsScreenLayout(
      title: l('userSettings'),
      groups: [
        SettingsNavGroup(
          items: _userItems(tabs),
        ),
      ],
      current: tab,
      onSelect: (id) => setState(() => tab = id),
      onClose: s.closeOverlay,
      header: UserIdentityCard(session: s),
      onHeaderTap: () => setState(() => tab = 'profile'),
      footer: SettingsDangerRow(
        label: l('disconnect'),
        onTap: () {
          s.closeOverlay();
          s.disconnect();
        },
      ),
      body: (_) => switch (tab) {
        'profile' => ProfileSettingsTab(s: s),
        'devices' => DevicesSettingsTab(s: s),
        'appearance' => AppearanceSettingsTab(s: s),
        'sounds' => SoundsSettingsTab(s: s),
        'notifications' => NotificationsSettingsTab(s: s),
        'password' => PasswordSettingsTab(s: s),
        'security' => SecuritySettingsTab(s: s),
        'others' => OthersSettingsTab(s: s),
        _ => AboutSettingsTab(s: s),
      },
    );
  }
}

class ServerSettings extends StatefulWidget {
  const ServerSettings({super.key, required this.session});
  final SessionController session;
  @override
  State<ServerSettings> createState() => _ServerSettingsState();
}

class _ServerSettingsState extends State<ServerSettings> {
  late String tab;
  late final bool startOnDetail;

  @override
  void initState() {
    super.initState();
    startOnDetail = widget.session.settingsTab != 'profile';
    tab = widget.session.settingsTab == 'profile'
        ? 'general'
        : widget.session.settingsTab;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final l = L10n.of(context);
    final tabs = <(String, String)>[
      if (s.can(Permission.manageSettings)) ('general', l('general')),
      if (s.can(Permission.manageRoles)) ('roles', l('roles')),
      if (s.can(Permission.manageEmojis)) ('emojis', l('emojis')),
      if (s.can(Permission.manageUsers) ||
          s.can(Permission.kickMembers) ||
          s.can(Permission.banMembers))
        ('users', l('users')),
      if (s.me?.roleIds.contains(AppConfig.ownerRoleId) == true)
        ('resetPasswords', l('resetPasswords')),
      if (s.can(Permission.manageInvites)) ('invites', l('invites')),
      if (s.can(Permission.viewAuditLog)) ('audit', l('auditLog')),
      if (s.me?.roleIds.contains(AppConfig.ownerRoleId) == true) ...[
        ('security', l('securityLog')),
        ('accessBans', l('accessBans')),
      ],
      if (s.can(Permission.manageStorage)) ('storage', l('storage')),
      if (s.can(Permission.managePlugins)) ('plugins', l('plugins')),
      if (s.can(Permission.manageUpdates)) ('updates', l('updates')),
    ];
    if (tabs.isEmpty) {
      return Center(child: Text(l('failed')));
    }
    if (tabs.every((t) => t.$1 != tab)) tab = tabs.first.$1;
    final canEdit = s.can(Permission.manageSettings);
    return SettingsScreenLayout(
      title: l('serverSettings'),
      groups: [SettingsNavGroup(items: _serverItems(tabs))],
      current: tab,
      onSelect: (id) => setState(() => tab = id),
      onClose: s.closeOverlay,
      header: _ServerIdentity(session: s, showEdit: canEdit),
      onHeaderTap: canEdit ? () => setState(() => tab = 'general') : null,
      startOnDetail: startOnDetail,
      scrollBody: serverSettingsScrollBody(tab),
      constrainWidth: serverSettingsConstrainWidth(tab),
      body: (_) => switch (tab) {
        'audit' => _ActivityLogPanel(s: s, security: false),
        'security' => _SecurityLogPanel(s: s),
        'accessBans' => _AccessBans(s: s),
        _ => serverSettingsBody(tab, s),
      },
    );
  }
}

class _ServerIdentity extends StatelessWidget {
  const _ServerIdentity({required this.session, required this.showEdit});
  final SessionController session;
  final bool showEdit;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final p = context.p;
    final logo = s.info?.logo;
    final url = logo != null ? s.fileUrl(logo) : null;
    final name = s.serverName;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : 'K';
    final fallback = Text(
      letter,
      style: TextStyle(
        color: p.foreground,
        fontSize: 32,
        fontWeight: FontWeight.w800,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 80,
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.sidebar,
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: url != null && url.isNotEmpty
                    ? Image.network(
                        url,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => fallback,
                      )
                    : fallback,
              ),
              if (showEdit)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: p.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.rail, width: 2),
                    ),
                    child: Icon(Icons.edit, size: 12, color: p.foreground),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityLogPanel extends StatefulWidget {
  const _SecurityLogPanel({required this.s});
  final SessionController s;
  @override
  State<_SecurityLogPanel> createState() => _SecurityLogPanelState();
}

class _SecurityLogPanelState extends State<_SecurityLogPanel> {
  List<Map<String, dynamic>> locked = [];
  int? unlockingId;

  @override
  void initState() {
    super.initState();
    _loadLocked();
  }

  Future<void> _loadLocked() async {
    final items = await widget.s.getLockedUsers();
    if (!mounted) return;
    setState(() => locked = items);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsPageHeader(title: l('securityLockedAccounts')),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.divider),
          ),
          child: locked.isEmpty
              ? Text(
                  l('securityNoLockedAccounts'),
                  style: TextStyle(color: p.muted, fontSize: 14),
                )
              : Column(
                  children: [
                    for (var i = 0; i < locked.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _LockedUserRow(
                        s: widget.s,
                        user: locked[i],
                        unlocking: unlockingId == asInt(locked[i]['id']),
                        onUnlock: (id) async {
                          setState(() => unlockingId = id);
                          await widget.s.unlockUser(id);
                          await _loadLocked();
                          if (mounted) setState(() => unlockingId = null);
                        },
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 28),
        _ActivityLogPanel(s: widget.s, security: true),
      ],
    );
  }
}

class _LockedUserRow extends StatelessWidget {
  const _LockedUserRow({
    required this.s,
    required this.user,
    required this.unlocking,
    required this.onUnlock,
  });

  final SessionController s;
  final Map<String, dynamic> user;
  final bool unlocking;
  final ValueChanged<int> onUnlock;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final id = asInt(user['id']) ?? 0;
    final live = s.users[id];
    final name = live?.displayName ?? '${user['name'] ?? l('unknownUser')}';
    final identity = '${user['identity'] ?? live?.identity ?? ''}';
    final lockedAt = parseTimestamp(user['lockedAt']);
    return Row(
      children: [
        UserAvatar(
          user: live,
          session: s,
          size: 32,
          statusBorderColor: p.card,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: p.foreground,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                [
                  if (identity.isNotEmpty) identity,
                  if (lockedAt > 0) formatAbsoluteTime(lockedAt),
                ].join(' · '),
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        KurierButton(
          label: l('securityUnlock'),
          outline: true,
          onPressed: unlocking || id == 0 ? null : () => onUnlock(id),
        ),
      ],
    );
  }
}

class _ActivityLogPanel extends StatefulWidget {
  const _ActivityLogPanel({required this.s, required this.security});
  final SessionController s;
  final bool security;
  @override
  State<_ActivityLogPanel> createState() => _ActivityLogPanelState();
}

class _ActivityLogPanelState extends State<_ActivityLogPanel> {
  List<ActivityLogItem> items = [];
  int? nextCursor;
  bool loading = true;
  String typeFilter = '';
  int userFilter = 0;

  List<String> get _typeOptions =>
      widget.security ? kSecurityActivityLogTypeList : kAuditActivityLogTypes;

  @override
  void initState() {
    super.initState();
    _load(replace: true);
  }

  Future<void> _load({required bool replace, int? cursor}) async {
    setState(() => loading = true);
    final page = await widget.s.activityLog(
      security: widget.security,
      cursor: cursor,
      type: typeFilter.isEmpty ? null : typeFilter,
      userId: userFilter == 0 ? null : userFilter,
    );
    if (!mounted) return;
    setState(() {
      final parsed = [
        for (final raw in page.items) ActivityLogItem.fromJson(raw),
      ];
      items = replace ? parsed : [...items, ...parsed];
      nextCursor = page.nextCursor;
      loading = false;
    });
  }

  Map<int, String> get _userNames => {
        for (final u in widget.s.users.values) u.id: u.displayName,
      };

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final users = widget.s.users.values.toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsPageHeader(
          title: widget.security ? l('securityLogTitle') : l('auditLogTitle'),
          description:
              widget.security ? l('securityLogDesc') : l('auditLogDesc'),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            SettingsSelect<String>(
              value: typeFilter,
              onChanged: (v) {
                setState(() => typeFilter = v ?? '');
                _load(replace: true);
              },
              items: [
                DropdownMenuItem(value: '', child: Text(l('auditAllActions'))),
                for (final type in _typeOptions)
                  DropdownMenuItem(
                    value: type,
                    child: Text(formatTypeLabel(type)),
                  ),
              ],
            ),
            SettingsSelect<int>(
              value: userFilter,
              minWidth: 160,
              onChanged: (v) {
                setState(() => userFilter = v ?? 0);
                _load(replace: true);
              },
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text(l('auditAllUsers')),
                ),
                for (final u in users)
                  if (u.id != 0)
                    DropdownMenuItem(
                      value: u.id,
                      child: Text(u.displayName),
                    ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (items.isEmpty && !loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              widget.security ? l('securityLogEmpty') : l('auditEmpty'),
              style: TextStyle(color: p.muted, fontSize: 14),
            ),
          ),
        for (final item in items)
          _ActivityLogRow(
            s: widget.s,
            item: item,
            actorName: (item.userId != null
                    ? _userNames[item.userId!]
                    : null) ??
                l('auditSystem'),
            userNames: _userNames,
          ),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (nextCursor != null && !loading)
          Align(
            alignment: Alignment.centerLeft,
            child: KurierButton(
              label: l('auditLoadMore'),
              outline: true,
              onPressed: () => _load(replace: false, cursor: nextCursor),
            ),
          ),
      ],
    );
  }
}

class _ActivityLogRow extends StatelessWidget {
  const _ActivityLogRow({
    required this.s,
    required this.item,
    required this.actorName,
    required this.userNames,
  });

  final SessionController s;
  final ActivityLogItem item;
  final String actorName;
  final Map<int, String> userNames;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final text = formatActivityLogEntry(
      t: l.call,
      actorName: actorName,
      type: item.type,
      userId: item.userId,
      details: item.details,
      userNameById: userNames,
    );
    final user = item.userId != null ? s.users[item.userId!] : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user != null)
            UserAvatar(
              user: user,
              session: s,
              size: 32,
              statusBorderColor: p.background,
            )
          else
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: p.card,
                shape: BoxShape.circle,
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ActivityLogText(text: text, actorName: actorName, color: p.foreground),
                const SizedBox(height: 2),
                Text(
                  [
                    if (item.createdAt > 0) activityLogTimestamp(item.createdAt),
                    if (item.ip != null) item.ip!,
                  ].join(' · '),
                  style: TextStyle(color: p.faint, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityLogText extends StatelessWidget {
  const _ActivityLogText({
    required this.text,
    required this.actorName,
    required this.color,
  });

  final String text;
  final String actorName;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final idx = text.indexOf(actorName);
    if (idx < 0) {
      return Text(text, style: TextStyle(color: color, fontSize: 14));
    }
    return Text.rich(
      TextSpan(
        style: TextStyle(color: color, fontSize: 14),
        children: [
          if (idx > 0) TextSpan(text: text.substring(0, idx)),
          TextSpan(
            text: actorName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(text: text.substring(idx + actorName.length)),
        ],
      ),
    );
  }
}

class _AccessBans extends StatefulWidget {
  const _AccessBans({required this.s});
  final SessionController s;
  @override
  State<_AccessBans> createState() => _AccessBansState();
}

class _AccessBansState extends State<_AccessBans> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final next = await widget.s.getAccessBans();
    if (!mounted) return;
    setState(() {
      items = next;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BanSection(
          s: widget.s,
          kind: 'ip',
          items: items.where((e) => e['kind'] == 'ip').toList(),
          onChanged: _load,
        ),
        const SizedBox(height: 24),
        _BanSection(
          s: widget.s,
          kind: 'mac',
          items: items.where((e) => e['kind'] == 'mac').toList(),
          onChanged: _load,
        ),
        const SizedBox(height: 24),
        _BanSection(
          s: widget.s,
          kind: 'device',
          items: items.where((e) => e['kind'] == 'device').toList(),
          onChanged: _load,
        ),
      ],
    );
  }
}

class _BanSection extends StatefulWidget {
  const _BanSection({
    required this.s,
    required this.kind,
    required this.items,
    required this.onChanged,
  });

  final SessionController s;
  final String kind;
  final List<Map<String, dynamic>> items;
  final Future<void> Function() onChanged;

  @override
  State<_BanSection> createState() => _BanSectionState();
}

class _BanSectionState extends State<_BanSection> {
  final value = TextEditingController();
  final reason = TextEditingController();
  bool saving = false;

  @override
  void dispose() {
    value.dispose();
    reason.dispose();
    super.dispose();
  }

  String get _titleKey => switch (widget.kind) {
        'mac' => 'accessBansMacTitle',
        'device' => 'accessBansDeviceTitle',
        _ => 'accessBansIpTitle',
      };

  String get _descKey => switch (widget.kind) {
        'mac' => 'accessBansMacDesc',
        'device' => 'accessBansDeviceDesc',
        _ => 'accessBansIpDesc',
      };

  String get _placeholderKey => switch (widget.kind) {
        'mac' => 'accessBansMacPlaceholder',
        'device' => 'accessBansDevicePlaceholder',
        _ => 'accessBansIpPlaceholder',
      };

  String get _emptyKey => switch (widget.kind) {
        'mac' => 'accessBansEmptyMac',
        'device' => 'accessBansEmptyDevice',
        _ => 'accessBansEmptyIp',
      };

  Future<void> _add() async {
    if (value.text.trim().isEmpty || saving) return;
    setState(() => saving = true);
    try {
      await widget.s.addAccessBan({
        'kind': widget.kind,
        'value': value.text.trim(),
        if (reason.text.trim().isNotEmpty) 'reason': reason.text.trim(),
      });
      value.clear();
      reason.clear();
      await widget.onChanged();
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    return SettingsCard(
      title: l(_titleKey),
      description: l(_descKey),
      children: [
        if (widget.kind == 'device') _CurrentBrowserToken(s: widget.s),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 560;
            final address = SettingsGroup(
              label: l('accessBansValueLabel'),
              child: KurierField(
                controller: value,
                hint: l(_placeholderKey),
              ),
            );
            final reasonField = SettingsGroup(
              label: l('accessBansReasonLabel'),
              child: KurierField(
                controller: reason,
                hint: l('accessBansReasonLabel'),
              ),
            );
            if (stacked) {
              return Column(
                children: [
                  address,
                  const SizedBox(height: 12),
                  reasonField,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: address),
                const SizedBox(width: 12),
                Expanded(child: reasonField),
              ],
            );
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: KurierButton(
            label: l('addBan'),
            onPressed: saving ? null : _add,
          ),
        ),
        if (widget.items.isEmpty)
          Text(l(_emptyKey), style: TextStyle(color: p.muted, fontSize: 14))
        else
          for (final item in widget.items)
            _BanRow(
              s: widget.s,
              item: item,
              onRemove: () async {
                final id = asInt(item['id']);
                if (id == null) return;
                await widget.s.removeAccessBan(id);
                await widget.onChanged();
              },
            ),
      ],
    );
  }
}

class _BanRow extends StatelessWidget {
  const _BanRow({
    required this.s,
    required this.item,
    required this.onRemove,
  });

  final SessionController s;
  final Map<String, dynamic> item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final createdBy = asInt(item['createdBy']);
    final name = '${item['createdByName'] ?? ''}'.trim().isNotEmpty
        ? '${item['createdByName']}'
        : (createdBy != null
            ? (s.users[createdBy]?.displayName ?? l('accessBansUnknownUser'))
            : l('accessBansUnknownUser'));
    final createdAt = parseTimestamp(item['createdAt']);
    final reasonText = '${item['reason'] ?? ''}'.trim();
    final meta = [
      if (reasonText.isNotEmpty) reasonText,
      name,
      if (createdAt > 0) formatAbsoluteTime(createdAt),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['value'] ?? ''}',
                  style: TextStyle(
                    color: p.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(meta, style: TextStyle(color: p.muted, fontSize: 12)),
              ],
            ),
          ),
          KurierButton(
            label: l('remove'),
            outline: true,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _CurrentBrowserToken extends StatelessWidget {
  const _CurrentBrowserToken({required this.s});
  final SessionController s;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final token = s.store.deviceToken();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l('accessBansDeviceCurrentLabel'),
          style: TextStyle(
            color: p.foreground,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                token,
                style: TextStyle(
                  color: p.muted,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 8),
            KurierButton(
              label: l('accessBansDeviceCopy'),
              outline: true,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l('accessBansDeviceCopied'))),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

class ChannelSettings extends StatefulWidget {
  const ChannelSettings({super.key, required this.session});
  final SessionController session;
  @override
  State<ChannelSettings> createState() => _ChannelSettingsState();
}

class _ChannelSettingsState extends State<ChannelSettings> {
  String tab = 'general';
  late final TextEditingController name;
  late final TextEditingController topic;

  @override
  void initState() {
    super.initState();
    final ch = widget.session.channels[widget.session.settingsChannelId];
    name = TextEditingController(text: ch?.name ?? '');
    topic = TextEditingController(text: ch?.topic ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final l = L10n.of(context);
    final ch = s.channels[s.settingsChannelId];
    return SettingsScreenLayout(
      title: l('channelSettings'),
      groups: [
        SettingsNavGroup(
          items: [
            SettingsNavItem(id: 'general', label: l('general')),
            SettingsNavItem(id: 'permissions', label: l('permissions')),
          ],
        ),
      ],
      current: tab,
      onSelect: (id) => setState(() => tab = id),
      onClose: s.closeOverlay,
      body: (context) => tab == 'permissions'
          ? SettingsCard(
              title: l('permissionsTitle'),
              description: l('permissionsDesc'),
              children: [
                Text(
                  l('permissionsComingSoon'),
                  style: TextStyle(color: context.p.muted),
                ),
              ],
            )
          : SettingsCard(
              title: l('channelInfoTitle'),
              description: l('channelInfoDesc'),
              children: [
                SettingsGroup(
                  label: l('channelName'),
                  child: KurierField(controller: name),
                ),
                SettingsGroup(
                  label: l('topic'),
                  child: KurierField(controller: topic),
                ),
                SettingsActions(
                  cancelLabel: l('cancel'),
                  saveLabel: l('save'),
                  onCancel: s.closeOverlay,
                  onSave: ch == null
                      ? null
                      : () => s.updateChannel({
                            'channelId': ch.id,
                            'name': name.text,
                            'topic': topic.text,
                          }),
                ),
              ],
            ),
    );
  }
}

class WelcomeSheet extends StatefulWidget {
  const WelcomeSheet({super.key, required this.session});
  final SessionController session;
  @override
  State<WelcomeSheet> createState() => _WelcomeSheetState();
}

class _WelcomeSheetState extends State<WelcomeSheet> {
  late final name = TextEditingController(text: widget.session.me?.name ?? '');
  late final bio = TextEditingController(text: widget.session.me?.bio ?? '');

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = widget.session;
    final p = context.p;
    return OverlayDialogShell(
      onClose: s.closeOverlay,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l('welcomeTitle', {'name': s.serverName}),
            style: TextStyle(
              color: p.foreground,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l('welcomeProfileSetupDesc'),
            style: TextStyle(color: p.muted, fontSize: 14),
          ),
          const SizedBox(height: 16),
          KurierField(
            controller: name,
            hint: l('welcomeUsernamePlaceholder'),
          ),
          const SizedBox(height: 12),
          KurierField(
            controller: bio,
            hint: l('welcomeBioPlaceholder'),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              KurierButton(
                label: l('welcomeSkipBtn'),
                outline: true,
                onPressed: s.closeOverlay,
              ),
              const SizedBox(width: 8),
              KurierButton(
                label: l('welcomeSaveBtn'),
                onPressed: () async {
                  await s.updateMe({
                    'name': name.text.trim(),
                    'bio': bio.text.trim(),
                    'profileColor': s.me?.profileColor ?? '#262626',
                  });
                  s.closeOverlay();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

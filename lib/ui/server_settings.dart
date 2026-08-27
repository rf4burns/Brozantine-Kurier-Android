import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../core/custom_emoji.dart';
import '../protocol/models.dart';
import '../protocol/permissions.dart';
import '../session/session_controller.dart';
import 'emoji_glyph.dart';
import 'member_context_menu.dart';
import 'settings_chrome.dart';
import 'shared.dart';

Map<String, dynamic>? latestMarketplaceVersion(dynamic versions) {
  if (versions is! List || versions.isEmpty) return null;
  Map<String, dynamic>? best;
  var bestTs = -1;
  for (final v in versions) {
    if (v is! Map) continue;
    final map = Map<String, dynamic>.from(v);
    final ts = (map['timestamp'] as num?)?.toInt() ?? -1;
    if (best == null || ts > bestTs) {
      best = map;
      bestTs = ts;
    }
  }
  if (best != null) return best;
  final first = versions.first;
  if (first is Map) return Map<String, dynamic>.from(first);
  return null;
}

bool _serverTabFills(String tab) => switch (tab) {
      'general' ||
      'roles' ||
      'emojis' ||
      'users' ||
      'resetPasswords' ||
      'invites' ||
      'storage' ||
      'plugins' ||
      'updates' =>
        true,
      _ => false,
    };

Widget serverSettingsBody(String tab, SessionController s) {
  return switch (tab) {
    'general' => ServerGeneralTab(s: s),
    'roles' => ServerRolesTab(s: s),
    'emojis' => ServerEmojisTab(s: s),
    'users' => ServerUsersTab(s: s),
    'resetPasswords' => ServerResetPasswordsTab(s: s),
    'invites' => ServerInvitesTab(s: s),
    'storage' => ServerStorageTab(s: s),
    'plugins' => ServerPluginsTab(s: s),
    'updates' => ServerUpdatesTab(s: s),
    _ => const SizedBox.shrink(),
  };
}

bool serverSettingsScrollBody(String tab) => !_serverTabFills(tab);

bool serverSettingsConstrainWidth(String tab) => tab != 'users';

class ServerGeneralTab extends StatefulWidget {
  const ServerGeneralTab({super.key, required this.s});
  final SessionController s;
  @override
  State<ServerGeneralTab> createState() => _ServerGeneralTabState();
}

class _ServerGeneralTabState extends State<ServerGeneralTab> {
  Map<String, dynamic>? data;
  final name = TextEditingController();
  final desc = TextEditingController();
  final password = TextEditingController();
  KurierFile? logo;
  int welcomeChannelId = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    name.dispose();
    desc.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.s.getFullSettings();
      if (!mounted) return;
      data = d;
      name.text = '${d['name'] ?? ''}';
      desc.text = '${d['description'] ?? ''}';
      password.text = '${d['password'] ?? ''}';
      welcomeChannelId = asInt(d['welcomeChannelId']) ?? -1;
      if (d['logo'] is Map) {
        logo = KurierFile.fromJson(Map<String, dynamic>.from(d['logo'] as Map));
      } else {
        logo = null;
      }
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => data = {});
    }
  }

  bool _flag(String key, [bool fallback = false]) =>
      asBool(data?[key], fallback);

  void _setFlag(String key, bool value) {
    setState(() => data![key] = value);
  }

  Future<void> _save() async {
    await widget.s.updateServerSettings({
      'name': name.text,
      'description': desc.text,
      if (password.text.isNotEmpty) 'password': password.text,
      'onlyAskForPasswordOnFirstJoin': _flag('onlyAskForPasswordOnFirstJoin'),
      'allowNewUsers': _flag('allowNewUsers'),
      'directMessagesEnabled': _flag('directMessagesEnabled', true),
      'enablePlugins': _flag('enablePlugins'),
      'webRtcSimulcastEnabled': _flag('webRtcSimulcastEnabled'),
      'enableSearch': _flag('enableSearch', true),
      'showWelcomeDialog': _flag('showWelcomeDialog', true),
      'welcomeChannelId': welcomeChannelId < 0 ? null : welcomeChannelId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    if (data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final s = widget.s;
    final textChannels = s.channels.values
        .where((c) => c.isText && !c.isDm)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final channelIds = {-1, ...textChannels.map((c) => c.id)};
    final selectedWelcome =
        channelIds.contains(welcomeChannelId) ? welcomeChannelId : -1;
    final logoUrl = logo != null ? s.fileUrl(logo!) : null;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: SettingsCard(
              title: l('serverInfoTitle'),
              description: l('serverInfoDesc'),
              children: [
                SettingsGroup(
                  label: l('nameLabel'),
                  child: KurierField(
                    controller: name,
                    hint: l('namePlaceholder'),
                  ),
                ),
                SettingsGroup(
                  label: l('descriptionLabel'),
                  child: KurierField(
                    controller: desc,
                    hint: l('descriptionPlaceholder'),
                    maxLines: 4,
                  ),
                ),
                SettingsGroup(
                  label: l('serverPasswordLabel'),
                  child: KurierField(
                    controller: password,
                    hint: l('serverPasswordPlaceholder'),
                  ),
                ),
                SettingsToggleRow(
                  label: l('onlyAskForPasswordOnFirstJoinLabel'),
                  description: l('onlyAskForPasswordOnFirstJoinDesc'),
                  value: _flag('onlyAskForPasswordOnFirstJoin'),
                  onChanged: (v) =>
                      _setFlag('onlyAskForPasswordOnFirstJoin', v),
                ),
                SettingsGroup(
                  label: l('logoLabel'),
                  description: l('logoDesc'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: _pickLogo,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: context.p.rail,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.p.divider),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: logoUrl != null && logoUrl.isNotEmpty
                              ? Image.network(logoUrl, fit: BoxFit.contain)
                              : Icon(
                                  Icons.add_photo_alternate,
                                  color: context.p.faint,
                                ),
                        ),
                      ),
                      if (logo != null)
                        TextButton(
                          onPressed: _removeLogo,
                          child: Text(
                            l('removeImage'),
                            style: TextStyle(
                              color: context.p.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SettingsToggleRow(
                  label: l('allowNewUsersLabel'),
                  description: l('allowNewUsersDesc'),
                  value: _flag('allowNewUsers'),
                  onChanged: (v) => _setFlag('allowNewUsers', v),
                ),
                SettingsToggleRow(
                  label: l('pluginsLabel'),
                  description: l('pluginsDesc'),
                  value: _flag('enablePlugins'),
                  onChanged: (v) => _setFlag('enablePlugins', v),
                ),
                SettingsToggleRow(
                  label: l('simulcastLabel'),
                  description: l('simulcastDesc'),
                  value: _flag('webRtcSimulcastEnabled'),
                  onChanged: (v) => _setFlag('webRtcSimulcastEnabled', v),
                ),
                SettingsToggleRow(
                  label: l('directMessagesEnabledLabel'),
                  description: l('directMessagesEnabledDesc'),
                  value: _flag('directMessagesEnabled', true),
                  onChanged: (v) => _setFlag('directMessagesEnabled', v),
                ),
                SettingsToggleRow(
                  label: l('searchEnabledLabel'),
                  description: l('searchEnabledDesc'),
                  value: _flag('enableSearch', true),
                  onChanged: (v) => _setFlag('enableSearch', v),
                ),
                SettingsToggleRow(
                  label: l('showWelcomeDialogLabel'),
                  description: l('showWelcomeDialogDesc'),
                  value: _flag('showWelcomeDialog', true),
                  onChanged: (v) => _setFlag('showWelcomeDialog', v),
                ),
                SettingsGroup(
                  label: l('welcomeChannelLabel'),
                  description: l('welcomeChannelDesc'),
                  child: DropdownButtonFormField<int>(
                    value: selectedWelcome,
                    decoration: settingsInputDecoration(context),
                    items: [
                      DropdownMenuItem(
                        value: -1,
                        child: Text(l('welcomeChannelNone')),
                      ),
                      for (final c in textChannels)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text('#${c.name}'),
                        ),
                    ],
                    onChanged: (v) =>
                        setState(() => welcomeChannelId = v ?? -1),
                  ),
                ),
              ],
            ),
          ),
        ),
        SettingsStickyFooter(
          cancelLabel: l('cancel'),
          saveLabel: l('save'),
          onCancel: s.closeOverlay,
          onSave: _save,
        ),
      ],
    );
  }

  Future<void> _pickLogo() async {
    final r = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.image,
    );
    if (r == null || r.files.single.bytes == null) return;
    final id = await widget.s.uploadBytes(
      r.files.single.name,
      r.files.single.bytes!,
    );
    if (id == null) return;
    await widget.s.changeLogo(id);
    await _load();
  }

  Future<void> _removeLogo() async {
    await widget.s.changeLogo(null);
    await _load();
  }
}

class ServerRolesTab extends StatefulWidget {
  const ServerRolesTab({super.key, required this.s});
  final SessionController s;
  @override
  State<ServerRolesTab> createState() => _ServerRolesTabState();
}

class _ServerRolesTabState extends State<ServerRolesTab> {
  int? selectedId;

  List<KurierRole> get _roles {
    final roles = widget.s.roles.values.toList()
      ..sort((a, b) => b.position.compareTo(a.position));
    return roles;
  }

  KurierRole? get _selected {
    final id = selectedId;
    if (id == null) return null;
    return widget.s.roles[id];
  }

  Future<void> _addRole() async {
    final l = L10n.of(context);
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l('addRole')),
        content: KurierField(controller: ctrl, hint: l('nameLabel')),
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
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || name.isEmpty) return;
    await widget.s.addRole(name);
    if (!mounted) return;
    final created = widget.s.roles.values.where((r) => r.name == name);
    if (created.isNotEmpty) {
      setState(() => selectedId = created.last.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final compact = settingsIsCompact(context);
    final selected = _selected;
    if (compact && selected != null) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: Icon(Icons.arrow_back, color: context.p.foreground),
              onPressed: () => setState(() => selectedId = null),
            ),
          ),
          Expanded(child: _RoleEditor(s: widget.s, role: selected)),
        ],
      );
    }
    return SettingsSplitPane(
      left: _RoleList(
        roles: _roles,
        selectedId: selectedId,
        onSelect: (id) => setState(() => selectedId = id),
        onAdd: _addRole,
        onReorder: (ids) => widget.s.reorderRoles(ids),
      ),
      right: selected == null
          ? SettingsPanel(
              child: SettingsEmptyHint(text: l('selectRoleHint')),
            )
          : _RoleEditor(s: widget.s, role: selected),
    );
  }
}

class _RoleList extends StatelessWidget {
  const _RoleList({
    required this.roles,
    required this.selectedId,
    required this.onSelect,
    required this.onAdd,
    required this.onReorder,
  });

  final List<KurierRole> roles;
  final int? selectedId;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;
  final ValueChanged<List<int>> onReorder;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    return SettingsPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l('rolesTitle'),
                    style: TextStyle(
                      color: p.foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l('addRole'),
                  onPressed: onAdd,
                  icon: Icon(Icons.add, color: p.foreground, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: roles.length,
              onReorder: (oldIndex, newIndex) {
                final next = [...roles];
                if (newIndex > oldIndex) newIndex--;
                final item = next.removeAt(oldIndex);
                next.insert(newIndex, item);
                onReorder([for (final r in next) r.id]);
              },
              itemBuilder: (context, i) {
                final r = roles[i];
                final selected = r.id == selectedId;
                return ReorderableDragStartListener(
                  key: ValueKey(r.id),
                  index: i,
                  child: InkWell(
                    onTap: () => onSelect(r.id),
                    child: ColoredBox(
                      color: selected ? p.sidebar : Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.drag_indicator,
                              size: 16,
                              color: p.faint,
                            ),
                            const SizedBox(width: 8),
                            RoleColorDot(color: r.color),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.foreground,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
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
        ],
      ),
    );
  }
}

class _RoleEditor extends StatefulWidget {
  const _RoleEditor({required this.s, required this.role});
  final SessionController s;
  final KurierRole role;
  @override
  State<_RoleEditor> createState() => _RoleEditorState();
}

class _RoleEditorState extends State<_RoleEditor> {
  late final TextEditingController name;
  late String color;
  late bool hoist;
  late Set<String> selected;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.role.name);
    color = widget.role.color;
    hoist = widget.role.hoist;
    selected = Set<String>.from(widget.role.permissions);
  }

  @override
  void didUpdateWidget(covariant _RoleEditor old) {
    super.didUpdateWidget(old);
    if (old.role.id != widget.role.id) {
      name.text = widget.role.name;
      color = widget.role.color;
      hoist = widget.role.hoist;
      selected = Set<String>.from(widget.role.permissions);
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.s.updateRole({
      'roleId': widget.role.id,
      'name': name.text.trim().isEmpty ? widget.role.name : name.text.trim(),
      'color': color,
      'hoist': hoist,
      'permissions': selected.toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    return SettingsPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsGroup(
            label: l('nameLabel'),
            child: KurierField(controller: name, hint: l('nameLabel')),
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            label: l('color'),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in accentSwatches)
                  GestureDetector(
                    onTap: () => setState(
                      () => color = colorToHex(c),
                    ),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorFromHex(color) == c
                              ? p.foreground
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SettingsToggleRow(
            label: l('hoist'),
            value: hoist,
            onChanged: (v) => setState(() => hoist = v),
          ),
          const SizedBox(height: 16),
          Text(
            l('permissions'),
            style: TextStyle(
              color: p.foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                for (final perm in Permission.all)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      perm
                          .toLowerCase()
                          .split('_')
                          .map(
                            (w) => w.isEmpty
                                ? w
                                : '${w[0].toUpperCase()}${w.substring(1)}',
                          )
                          .join(' '),
                      style: TextStyle(color: p.foreground, fontSize: 13),
                    ),
                    value: selected.contains(perm),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        selected.add(perm);
                      } else {
                        selected.remove(perm);
                      }
                    }),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (!widget.role.isPersistent)
                KurierButton(
                  label: l('delete'),
                  danger: true,
                  onPressed: () => widget.s.deleteRole(widget.role.id),
                ),
              const Spacer(),
              KurierButton(label: l('save'), onPressed: _save),
            ],
          ),
        ],
      ),
    );
  }
}

class ServerEmojisTab extends StatefulWidget {
  const ServerEmojisTab({super.key, required this.s});
  final SessionController s;
  @override
  State<ServerEmojisTab> createState() => _ServerEmojisTabState();
}

class _ServerEmojisTabState extends State<ServerEmojisTab> {
  final search = TextEditingController();
  int? selectedId;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<KurierEmoji> get _filtered {
    final q = search.text.trim().toLowerCase();
    final all = widget.s.emojis.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (q.isEmpty) return all;
    return [for (final e in all) if (e.name.toLowerCase().contains(q)) e];
  }

  Future<void> _upload() async {
    final r = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.image,
    );
    if (r == null || r.files.single.bytes == null) return;
    final id = await widget.s.uploadBytes(
      r.files.single.name,
      r.files.single.bytes as Uint8List,
    );
    if (id == null) return;
    final name = r.files.single.name.split('.').first;
    await widget.s.addEmoji(name, id);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final compact = settingsIsCompact(context);
    final emojis = _filtered;
    final selected = selectedId == null ? null : widget.s.emojis[selectedId!];

    final list = SettingsPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l('emojiTitle'),
                    style: TextStyle(
                      color: p.foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l('addEmoji'),
                  onPressed: _upload,
                  icon: Icon(Icons.add, color: p.foreground, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SettingsSearchField(
              controller: search,
              hint: l('searchEmojis'),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 72,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: emojis.length,
              itemBuilder: (context, i) {
                final e = emojis[i];
                final on = e.id == selectedId;
                return InkWell(
                  onTap: () => setState(() => selectedId = e.id),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: on ? p.sidebar : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: CustomEmojiGlyph(
                        emoji: CustomEmoji(
                          name: e.name,
                          url: widget.s.fileUrl(e.file),
                        ),
                        size: 36,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    final empty = SettingsPanel(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('😊', style: TextStyle(fontSize: compact ? 48 : 64)),
              const SizedBox(height: 16),
              Text(
                l('uploadCustomEmojis'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.foreground,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l('uploadCustomEmojisDesc'),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.muted, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 20),
              KurierButton(label: l('uploadEmoji'), onPressed: _upload),
            ],
          ),
        ),
      ),
    );

    final detail = selected == null
        ? empty
        : SettingsPanel(
            child: Column(
              children: [
                const Spacer(),
                CustomEmojiGlyph(
                  emoji: CustomEmoji(
                    name: selected.name,
                    url: widget.s.fileUrl(selected.file),
                  ),
                  size: 72,
                ),
                const SizedBox(height: 12),
                Text(
                  ':${selected.name}:',
                  style: TextStyle(
                    color: p.foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                KurierButton(
                  label: l('delete'),
                  danger: true,
                  onPressed: () {
                    widget.s.deleteEmoji(selected.id);
                    setState(() => selectedId = null);
                  },
                ),
              ],
            ),
          );

    if (compact) {
      return Column(
        children: [
          Expanded(child: list),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SizedBox(
              width: double.infinity,
              child: KurierButton(
                label: l('uploadEmoji'),
                onPressed: _upload,
              ),
            ),
          ),
        ],
      );
    }
    return SettingsSplitPane(left: list, right: detail);
  }
}

class ServerUsersTab extends StatefulWidget {
  const ServerUsersTab({super.key, required this.s});
  final SessionController s;
  @override
  State<ServerUsersTab> createState() => _ServerUsersTabState();
}

class _ServerUsersTabState extends State<ServerUsersTab> {
  final search = TextEditingController();
  int page = 0;
  static const pageSize = 8;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  List<KurierUser> get _filtered {
    final q = search.text.trim().toLowerCase();
    final users = widget.s.users.values
        .where((u) => u.id != 0 && !u.deleted)
        .toList()
      ..sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );
    if (q.isEmpty) return users;
    return [
      for (final u in users)
        if (u.displayName.toLowerCase().contains(q) ||
            u.name.toLowerCase().contains(q) ||
            (u.identity ?? '').toLowerCase().contains(q))
          u,
    ];
  }

  Future<void> _openActions(
    BuildContext context,
    KurierUser user,
    Offset global,
  ) async {
    if (settingsIsCompact(context)) {
      await showMemberOverflowSheet(context, widget.s, user);
    } else {
      await showMemberContextMenu(context, global, widget.s, user);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final compact = settingsIsCompact(context);
    final all = _filtered;
    final pages = (all.length / pageSize).ceil().clamp(1, 100000);
    if (page >= pages) page = pages - 1;
    final start = page * pageSize;
    final slice = all.skip(start).take(pageSize).toList();
    final from = all.isEmpty ? 0 : start + 1;
    final to = start + slice.length;

    Widget roleChips(KurierUser u) {
      final roles = [
        for (final id in u.roleIds)
          if (widget.s.roles[id] != null) widget.s.roles[id]!,
      ];
      if (roles.isEmpty) {
        return Text('—', style: TextStyle(color: p.faint, fontSize: 12));
      }
      return Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final r in roles.take(3))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: p.rail,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RoleColorDot(color: r.color, size: 8),
                  const SizedBox(width: 4),
                  Text(
                    r.name,
                    style: TextStyle(color: p.foreground, fontSize: 11),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    Widget statusOf(KurierUser u) {
      if (u.banned) {
        return Text(l('statusBanned'), style: TextStyle(color: p.dnd, fontSize: 13));
      }
      final on = u.isOnline;
      return Text(
        on ? l('statusOnline') : l('statusOffline'),
        style: TextStyle(
          color: on ? p.online : p.muted,
          fontSize: 13,
          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
        ),
      );
    }

    Widget actions(KurierUser u) {
      return Builder(
        builder: (ctx) {
          return IconButton(
            icon: Icon(Icons.more_vert, color: p.muted, size: 18),
            onPressed: () {
              final box = ctx.findRenderObject() as RenderBox;
              final pos = box.localToGlobal(Offset.zero);
              _openActions(ctx, u, pos);
            },
          );
        },
      );
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsPageHeader(
          title: l('usersTitle'),
          description: l('usersDesc'),
        ),
        const SizedBox(height: 16),
        SettingsSearchField(
          controller: search,
          hint: l('searchUsers'),
          onChanged: (_) => setState(() => page = 0),
        ),
      ],
    );

    final pager = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l('showingItems', {
                'from': '$from',
                'to': '$to',
                'total': '${all.length}',
              }),
              style: TextStyle(color: p.muted, fontSize: 12),
            ),
          ),
          IconButton(
            onPressed: page > 0 ? () => setState(() => page--) : null,
            icon: Icon(Icons.chevron_left, color: p.foreground),
          ),
          for (var i = 0; i < pages && i < 7; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: GestureDetector(
                onTap: () => setState(() => page = i),
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor:
                      i == page ? context.k.accent : Colors.transparent,
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      color: i == page ? Colors.white : p.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            onPressed:
                page < pages - 1 ? () => setState(() => page++) : null,
            icon: Icon(Icons.chevron_right, color: p.foreground),
          ),
        ],
      ),
    );

    if (compact) {
      return Column(
        children: [
          header,
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              itemCount: slice.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: p.divider),
              itemBuilder: (context, i) {
                final u = slice[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: UserAvatar(user: u, session: widget.s, size: 36),
                  title: Text(
                    u.displayName,
                    style: TextStyle(color: p.foreground),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if ((u.statusMessage ?? '').isNotEmpty)
                        Text(
                          u.statusMessage!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                      roleChips(u),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      statusOf(u),
                      actions(u),
                    ],
                  ),
                );
              },
            ),
          ),
          pager,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 16),
        Expanded(
          child: SettingsPanel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 280,
                        child: Text(
                          l('userCol'),
                          style: TextStyle(color: p.faint, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          l('rolesCol'),
                          style: TextStyle(color: p.faint, fontSize: 12),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          l('joinedAtCol'),
                          style: TextStyle(color: p.faint, fontSize: 12),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: Text(
                          l('lastJoinCol'),
                          style: TextStyle(color: p.faint, fontSize: 12),
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          l('statusCol'),
                          style: TextStyle(color: p.faint, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 36),
                    ],
                  ),
                ),
                Divider(height: 1, color: p.divider),
                Expanded(
                  child: ListView.builder(
                    itemCount: slice.length,
                    itemBuilder: (context, i) {
                      final u = slice[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 280,
                              child: Row(
                                children: [
                                  UserAvatar(
                                    user: u,
                                    session: widget.s,
                                    size: 32,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          u.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: p.foreground,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if ((u.statusMessage ?? '')
                                            .isNotEmpty)
                                          Text(
                                            u.statusMessage!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: p.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(child: roleChips(u)),
                            SizedBox(
                              width: 110,
                              child: Text(
                                u.createdAt > 0
                                    ? compactRelativeTime(u.createdAt)
                                    : '—',
                                style: TextStyle(color: p.muted, fontSize: 12),
                              ),
                            ),
                            SizedBox(
                              width: 110,
                              child: Text(
                                u.lastLoginAt > 0
                                    ? compactRelativeTime(u.lastLoginAt)
                                    : '—',
                                style: TextStyle(color: p.muted, fontSize: 12),
                              ),
                            ),
                            SizedBox(width: 80, child: statusOf(u)),
                            SizedBox(width: 36, child: actions(u)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        pager,
      ],
    );
  }
}

class ServerResetPasswordsTab extends StatefulWidget {
  const ServerResetPasswordsTab({super.key, required this.s});
  final SessionController s;
  @override
  State<ServerResetPasswordsTab> createState() =>
      _ServerResetPasswordsTabState();
}

class _ServerResetPasswordsTabState extends State<ServerResetPasswordsTab> {
  int? uid;
  final pass = TextEditingController();
  final confirm = TextEditingController();

  @override
  void dispose() {
    pass.dispose();
    confirm.dispose();
    super.dispose();
  }

  bool get _match =>
      pass.text.isNotEmpty && pass.text == confirm.text && uid != null;

  Future<void> _save() async {
    if (!_match) return;
    await widget.s.resetUserPassword(uid!, pass.text);
    pass.clear();
    confirm.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final users = widget.s.users.values.where((u) => u.id != 0).toList()
      ..sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: SettingsCard(
              title: l('resetPasswordsTitle'),
              description: l('resetPasswordsDesc'),
              children: [
                SettingsGroup(
                  label: l('userCol'),
                  child: DropdownButtonFormField<int>(
                    value: uid,
                    decoration: settingsInputDecoration(
                      context,
                      hint: l('selectUser'),
                    ),
                    items: [
                      for (final u in users)
                        DropdownMenuItem(
                          value: u.id,
                          child: Text(u.displayName),
                        ),
                    ],
                    onChanged: (v) => setState(() => uid = v),
                  ),
                ),
                SettingsGroup(
                  label: l('newPassword'),
                  child: KurierField(
                    controller: pass,
                    obscure: true,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SettingsGroup(
                  label: l('confirmNewPassword'),
                  child: KurierField(
                    controller: confirm,
                    obscure: true,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (pass.text.isNotEmpty &&
                    confirm.text.isNotEmpty &&
                    pass.text != confirm.text)
                  Text(
                    l('passwordsDoNotMatch'),
                    style: TextStyle(color: context.p.dnd, fontSize: 13),
                  ),
              ],
            ),
          ),
        ),
        SettingsStickyFooter(
          cancelLabel: l('cancel'),
          saveLabel: l('save'),
          saveEnabled: _match,
          onCancel: widget.s.closeOverlay,
          onSave: _save,
        ),
      ],
    );
  }
}

class ServerInvitesTab extends StatefulWidget {
  const ServerInvitesTab({super.key, required this.s});
  final SessionController s;
  @override
  State<ServerInvitesTab> createState() => _ServerInvitesTabState();
}

class _ServerInvitesTabState extends State<ServerInvitesTab> {
  List<dynamic> items = [];
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.s.getInvites().then((v) {
      if (mounted) setState(() => items = v);
    }).catchError((_) {
      if (mounted) setState(() => items = []);
    });
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Map<String, dynamic> _map(dynamic i) =>
      i is Map ? Map<String, dynamic>.from(i) : {'code': '$i'};

  List<Map<String, dynamic>> get _filtered {
    final q = search.text.trim().toLowerCase();
    final mapped = [for (final i in items) _map(i)];
    if (q.isEmpty) return mapped;
    return [
      for (final i in mapped)
        if ('${i['code']}'.toLowerCase().contains(q) ||
            '${i['createdByName'] ?? i['creator'] ?? ''}'
                .toLowerCase()
                .contains(q))
          i,
    ];
  }

  String _creator(Map<String, dynamic> i) {
    final named = '${i['createdByName'] ?? i['creatorName'] ?? ''}'.trim();
    if (named.isNotEmpty) return named;
    final id = asInt(i['createdBy'] ?? i['creatorId'] ?? i['userId']);
    if (id != null) return widget.s.users[id]?.displayName ?? '$id';
    return '—';
  }

  String _role(Map<String, dynamic> i) {
    final id = asInt(i['roleId']);
    if (id != null) return widget.s.roles[id]?.name ?? '—';
    final name = '${i['role'] ?? ''}'.trim();
    return name.isEmpty ? '—' : name;
  }

  String _uses(Map<String, dynamic> i) {
    final used = asInt(i['uses'] ?? i['used'] ?? i['currentUses']) ?? 0;
    final max = asInt(i['maxUses']);
    if (max == null || max <= 0) return '$used';
    return '$used / $max';
  }

  String _expires(Map<String, dynamic> i, L10n l) {
    final raw = i['expiresAt'] ?? i['expires'];
    final ms = asInt(raw) ?? 0;
    if (ms <= 0) return l('neverExpires');
    return compactRelativeTime(ms);
  }

  String _created(Map<String, dynamic> i) {
    final ms = asInt(i['createdAt'] ?? i['created']) ?? 0;
    if (ms <= 0) return '—';
    return compactRelativeTime(ms);
  }

  bool _expired(Map<String, dynamic> i) {
    final ms = asInt(i['expiresAt'] ?? i['expires']) ?? 0;
    if (ms <= 0) return false;
    return DateTime.fromMillisecondsSinceEpoch(ms).isBefore(DateTime.now());
  }

  Future<void> _reload() async {
    try {
      items = await widget.s.getInvites();
    } catch (_) {
      items = [];
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final compact = settingsIsCompact(context);
    final rows = _filtered;

    final header = Row(
      children: [
        Expanded(
          child: SettingsPageHeader(
            title: l('invitesTitle'),
            description: l('invitesDesc'),
          ),
        ),
        KurierButton(
          label: l('createInvite'),
          onPressed: () async {
            await widget.s.addInvite();
            await _reload();
          },
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsPageHeader(
            title: l('invitesTitle'),
            description: l('invitesDesc'),
          ),
          const SizedBox(height: 12),
          KurierButton(
            label: l('createInvite'),
            onPressed: () async {
              await widget.s.addInvite();
              await _reload();
            },
          ),
          const SizedBox(height: 12),
          SettingsSearchField(
            controller: search,
            hint: l('searchInvites'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: rows.isEmpty
                ? SettingsEmptyHint(text: l('noInvitesFound'))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: p.divider),
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${row['code'] ?? ''}',
                          style: TextStyle(
                            color: p.foreground,
                            fontFamily: 'monospace',
                          ),
                        ),
                        subtitle: Text(
                          '${_role(row)} · ${_creator(row)} · ${_uses(row)}',
                          style: TextStyle(color: p.muted, fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: p.muted),
                          onPressed: () async {
                            final id = asInt(row['id']);
                            if (id != null) {
                              await widget.s.deleteInvite(id);
                            }
                            await _reload();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 16),
        SettingsSearchField(
          controller: search,
          hint: l('searchInvites'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: SettingsPanel(
            padding: EdgeInsets.zero,
            child: rows.isEmpty
                ? Column(
                    children: [
                      const Spacer(),
                      Text(
                        l('noInvitesFound'),
                        style: TextStyle(color: p.muted),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          l('noItemFound'),
                          style: TextStyle(color: p.faint, fontSize: 12),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                        child: Row(
                          children: [
                            _col(l('inviteCodeCol'), 120, p),
                            _col(l('inviteRoleCol'), 120, p),
                            _col(l('inviteCreatorCol'), 140, p),
                            _col(l('inviteUsesCol'), 80, p),
                            _col(l('inviteExpiresCol'), 100, p),
                            _col(l('inviteCreatedCol'), 100, p),
                            _col(l('inviteStatusCol'), 80, p),
                            const Spacer(),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: p.divider),
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 120,
                                child: Text(
                                  '${row['code'] ?? ''}',
                                  style: TextStyle(
                                    color: p.foreground,
                                    fontFamily: 'monospace',
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: Text(
                                  _role(row),
                                  style: TextStyle(color: p.muted, fontSize: 13),
                                ),
                              ),
                              SizedBox(
                                width: 140,
                                child: Text(
                                  _creator(row),
                                  style: TextStyle(color: p.muted, fontSize: 13),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  _uses(row),
                                  style: TextStyle(color: p.muted, fontSize: 13),
                                ),
                              ),
                              SizedBox(
                                width: 100,
                                child: Text(
                                  _expires(row, l),
                                  style: TextStyle(color: p.muted, fontSize: 13),
                                ),
                              ),
                              SizedBox(
                                width: 100,
                                child: Text(
                                  _created(row),
                                  style: TextStyle(color: p.muted, fontSize: 13),
                                ),
                              ),
                              SizedBox(
                                width: 80,
                                child: Text(
                                  _expired(row)
                                      ? l('inviteExpired')
                                      : l('inviteActive'),
                                  style: TextStyle(
                                    color: _expired(row) ? p.muted : p.online,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: p.muted,
                                  size: 18,
                                ),
                                onPressed: () async {
                                  final id = asInt(row['id']);
                                  if (id != null) {
                                    await widget.s.deleteInvite(id);
                                  }
                                  await _reload();
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _col(String label, double width, Palette p) {
    return SizedBox(
      width: width,
      child: Text(label, style: TextStyle(color: p.faint, fontSize: 12)),
    );
  }
}

const _kMb = 1024 * 1024;
const _kGb = 1024 * _kMb;

const _storageMinQuota = 1 * _kGb;
const _storageMaxQuota = 1024 * _kGb;
const _storageDefaultQuota = 100 * _kGb;
const _storageMinFileSize = 1 * _kMb;
const _storageMaxFileSize = 2 * _kGb;
const _storageMinAvatarSize = 50 * 1024;
const _storageMaxAvatarSize = 50 * _kMb;
const _storageDefaultAvatarSize = 3 * _kMb;
const _storageMinBannerSize = 100 * 1024;
const _storageMaxBannerSize = 100 * _kMb;
const _storageDefaultBannerSize = 3 * _kMb;
const _storageMinQuotaPerUser = 0;
const _storageMaxQuotaPerUser = 100 * _kGb;
const _storageMinFilesPerMessage = 0;
const _storageMaxFilesPerMessage = 20;
const _storageDefaultFilesPerMessage = 10;
const _storageMinSignedTtl = 30 * 60;
const _storageMaxSignedTtl = 7 * 24 * 60 * 60;
const _storageDefaultSignedTtl = 60 * 60;
const _storageMinImageQuality = 1;
const _storageMaxImageQuality = 100;
const _storageDefaultImageQuality = 80;

class _StorageSizePreset {
  const _StorageSizePreset(this.label, this.value);
  final String label;
  final int value;
}

const _quotaPresets = [
  _StorageSizePreset('25 GB', 25 * _kGb),
  _StorageSizePreset('100 GB', 100 * _kGb),
  _StorageSizePreset('250 GB', 250 * _kGb),
];

const _maxFileSizePresets = [
  _StorageSizePreset('25 MB', 25 * _kMb),
  _StorageSizePreset('100 MB', 100 * _kMb),
  _StorageSizePreset('500 MB', 500 * _kMb),
  _StorageSizePreset('1 GB', 1 * _kGb),
];

const _maxAvatarSizePresets = [
  _StorageSizePreset('1 MB', 1 * _kMb),
  _StorageSizePreset('3 MB', 3 * _kMb),
  _StorageSizePreset('10 MB', 10 * _kMb),
];

const _maxBannerSizePresets = [
  _StorageSizePreset('1 MB', 1 * _kMb),
  _StorageSizePreset('3 MB', 3 * _kMb),
  _StorageSizePreset('10 MB', 10 * _kMb),
];

const _quotaPerUserPresets = [
  _StorageSizePreset('Unlimited', 0),
  _StorageSizePreset('1 GB', 1 * _kGb),
  _StorageSizePreset('20 GB', 20 * _kGb),
  _StorageSizePreset('100 GB', 100 * _kGb),
];

const _filesPerMessagePresets = [0, 5, 10, 20];

const _signedTtlPresets = [
  _StorageSizePreset('1 hr', 60 * 60),
  _StorageSizePreset('6 hr', 6 * 60 * 60),
  _StorageSizePreset('12 hr', 12 * 60 * 60),
  _StorageSizePreset('24 hr', 24 * 60 * 60),
];

class ServerStorageTab extends StatefulWidget {
  const ServerStorageTab({super.key, required this.s});
  final SessionController s;
  @override
  State<ServerStorageTab> createState() => _ServerStorageTabState();
}

class _ServerStorageTabState extends State<ServerStorageTab> {
  bool loaded = false;
  bool downloading = false;
  int? totalSpace;
  int? freeSpace;
  int? systemUsed;
  int? serverUsed;

  bool uploadEnabled = true;
  bool dmFileSharing = true;
  int quota = _storageDefaultQuota;
  int maxFileSize = _storageMaxFileSize;
  int maxAvatarSize = _storageDefaultAvatarSize;
  int maxBannerSize = _storageDefaultBannerSize;
  int quotaPerUser = _storageMinQuotaPerUser;
  int maxFilesPerMessage = _storageDefaultFilesPerMessage;
  String overflowAction = 'prevent';
  bool imageOptimization = false;
  int imageQuality = _storageDefaultImageQuality;
  bool signedUrls = false;
  int signedTtlSeconds = _storageDefaultSignedTtl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  int _clampInt(int value, int min, int max) =>
      value < min ? min : (value > max ? max : value);

  int _bytes(Map<String, dynamic> map, List<String> keys, int fallback) {
    for (final key in keys) {
      final v = asInt(map[key]);
      if (v != null) return v;
    }
    return fallback;
  }

  Future<void> _load() async {
    try {
      final raw = await widget.s.getStorageSettings();
      final settings = raw['storageSettings'] is Map
          ? Map<String, dynamic>.from(raw['storageSettings'] as Map)
          : raw;
      final metrics = raw['diskMetrics'] is Map
          ? Map<String, dynamic>.from(raw['diskMetrics'] as Map)
          : raw;
      uploadEnabled = asBool(
        settings['storageUploadEnabled'] ?? settings['allowUploads'],
        true,
      );
      dmFileSharing = asBool(
        settings['storageFileSharingInDirectMessages'] ??
            settings['allowFileSharingInDirectMessages'],
        true,
      );
      quota = _clampInt(
        _bytes(settings, ['storageQuota', 'space', 'maxTotalUpload'], quota),
        _storageMinQuota,
        _storageMaxQuota,
      );
      maxFileSize = _clampInt(
        _bytes(
          settings,
          ['storageUploadMaxFileSize', 'maxFileSize', 'maxUploadSize'],
          maxFileSize,
        ),
        _storageMinFileSize,
        _storageMaxFileSize,
      );
      maxAvatarSize = _clampInt(
        _bytes(settings, ['storageMaxAvatarSize', 'maxAvatarSize'], maxAvatarSize),
        _storageMinAvatarSize,
        _storageMaxAvatarSize,
      );
      maxBannerSize = _clampInt(
        _bytes(settings, ['storageMaxBannerSize', 'maxBannerSize'], maxBannerSize),
        _storageMinBannerSize,
        _storageMaxBannerSize,
      );
      quotaPerUser = _clampInt(
        _bytes(
          settings,
          ['storageSpaceQuotaByUser', 'quotaPerUser', 'userQuota'],
          quotaPerUser,
        ),
        _storageMinQuotaPerUser,
        _storageMaxQuotaPerUser,
      );
      maxFilesPerMessage = _clampInt(
        _bytes(
          settings,
          ['storageMaxFilesPerMessage', 'maxFilesPerMessage'],
          maxFilesPerMessage,
        ),
        _storageMinFilesPerMessage,
        _storageMaxFilesPerMessage,
      );
      final overflow =
          '${settings['storageOverflowAction'] ?? overflowAction}';
      overflowAction = overflow == 'delete' ? 'delete' : 'prevent';
      imageOptimization = asBool(
        settings['storageImageOptimizationEnabled'],
        imageOptimization,
      );
      imageQuality = _clampInt(
        _bytes(
          settings,
          ['storageImageOptimizationQuality'],
          imageQuality,
        ),
        _storageMinImageQuality,
        _storageMaxImageQuality,
      );
      signedUrls = asBool(settings['storageSignedUrlsEnabled'], signedUrls);
      signedTtlSeconds = _clampInt(
        _bytes(
          settings,
          ['storageSignedUrlsTtlSeconds'],
          signedTtlSeconds,
        ),
        _storageMinSignedTtl,
        _storageMaxSignedTtl,
      );
      totalSpace = asInt(metrics['totalSpace'] ?? metrics['totalDiskSpace']);
      freeSpace = asInt(metrics['freeSpace'] ?? metrics['availableSpace']);
      systemUsed = asInt(metrics['usedSpace'] ?? metrics['systemUsed']);
      serverUsed = asInt(
        metrics['sharkordUsedSpace'] ??
            metrics['usedStorage'] ??
            metrics['kurierUsed'],
      );
    } catch (_) {}
    if (mounted) setState(() => loaded = true);
  }

  Future<void> _save() async {
    try {
      await widget.s.updateServerSettings({
        'storageUploadEnabled': uploadEnabled,
        'storageFileSharingInDirectMessages': dmFileSharing,
        'storageQuota': quota,
        'storageUploadMaxFileSize': maxFileSize,
        'storageMaxAvatarSize': maxAvatarSize,
        'storageMaxBannerSize': maxBannerSize,
        'storageMaxFilesPerMessage': maxFilesPerMessage,
        'storageSpaceQuotaByUser': quotaPerUser,
        'storageOverflowAction': overflowAction,
        'storageSignedUrlsEnabled': signedUrls,
        'storageSignedUrlsTtlSeconds': signedTtlSeconds,
        'storageImageOptimizationEnabled': imageOptimization,
        'storageImageOptimizationQuality': imageQuality,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _downloadBackup() async {
    setState(() => downloading = true);
    try {
      await widget.s.downloadServerBackup();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
    if (mounted) setState(() => downloading = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    if (!loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    Widget stat(String label, int? value) {
      if (value == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
            ),
            Text(
              formatBytes(value),
              style: TextStyle(
                color: p.foreground,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final usage = (totalSpace != null && totalSpace! > 0 && systemUsed != null)
        ? (systemUsed! / totalSpace!).clamp(0, 1).toDouble()
        : (totalSpace != null && freeSpace != null && totalSpace! > 0)
            ? ((totalSpace! - freeSpace!) / totalSpace!).clamp(0, 1).toDouble()
            : null;
    final usagePercent = usage == null ? null : (usage * 100).toStringAsFixed(1);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: SettingsCard(
              title: l('storageTitle'),
              description: l('storageDesc'),
              children: [
                if (totalSpace != null) stat(l('totalDiskSpace'), totalSpace),
                if (freeSpace != null) stat(l('availableSpace'), freeSpace),
                if (systemUsed != null) stat(l('systemUsed'), systemUsed),
                if (serverUsed != null) stat(l('serverUsed'), serverUsed),
                if (usage != null) ...[
                  Text(
                    l('diskUsage'),
                    style: TextStyle(
                      color: p.foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: usage,
                      minHeight: 8,
                      backgroundColor: p.rail,
                      color: context.k.accent,
                    ),
                  ),
                  if (usagePercent != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      l('diskUsedPercent', {'percent': usagePercent}),
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                  ],
                ],
                SettingsGroup(
                  label: l('downloadBackupLabel'),
                  description: l('downloadBackupDesc'),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: KurierButton(
                      label: l('downloadBackupButton'),
                      outline: true,
                      onPressed: downloading ? null : _downloadBackup,
                    ),
                  ),
                ),
                SettingsToggleRow(
                  label: l('allowUploads'),
                  description: l('allowUploadsDesc'),
                  value: uploadEnabled,
                  onChanged: (v) => setState(() => uploadEnabled = v),
                ),
                SettingsToggleRow(
                  label: l('allowFileSharingDm'),
                  description: l('allowFileSharingDmDesc'),
                  value: dmFileSharing,
                  onChanged: uploadEnabled
                      ? (v) => setState(() => dmFileSharing = v)
                      : null,
                ),
                _StorageSizeControl(
                  label: l('quota'),
                  description: l('quotaDesc'),
                  help: l('quotaHelp'),
                  value: quota,
                  min: _storageMinQuota,
                  max: _storageMaxQuota,
                  disabled: !uploadEnabled,
                  presets: _quotaPresets,
                  onChanged: (v) => setState(() => quota = v),
                ),
                _StorageSizeControl(
                  label: l('maxFileSize'),
                  description: l('maxFileSizeDesc'),
                  value: maxFileSize,
                  min: _storageMinFileSize,
                  max: _storageMaxFileSize,
                  disabled: !uploadEnabled,
                  presets: _maxFileSizePresets,
                  onChanged: (v) => setState(() => maxFileSize = v),
                ),
                _StorageSizeControl(
                  label: l('maxAvatarSize'),
                  description: l('maxAvatarSizeDesc'),
                  value: maxAvatarSize,
                  min: _storageMinAvatarSize,
                  max: _storageMaxAvatarSize,
                  disabled: !uploadEnabled,
                  presets: _maxAvatarSizePresets,
                  onChanged: (v) => setState(() => maxAvatarSize = v),
                ),
                _StorageSizeControl(
                  label: l('maxBannerSize'),
                  description: l('maxBannerSizeDesc'),
                  value: maxBannerSize,
                  min: _storageMinBannerSize,
                  max: _storageMaxBannerSize,
                  disabled: !uploadEnabled,
                  presets: _maxBannerSizePresets,
                  onChanged: (v) => setState(() => maxBannerSize = v),
                ),
                _StorageSizeControl(
                  label: l('quotaPerUser'),
                  description: l('quotaPerUserDesc'),
                  value: quotaPerUser,
                  min: _storageMinQuotaPerUser,
                  max: _storageMaxQuotaPerUser,
                  disabled: !uploadEnabled,
                  unlimitedZero: true,
                  presets: _quotaPerUserPresets,
                  onChanged: (v) => setState(() => quotaPerUser = v),
                ),
                SettingsGroup(
                  label: l('maxFilesPerMessage'),
                  description: l('maxFilesPerMessageDesc'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 88,
                            child: _StorageNumberField(
                              value: maxFilesPerMessage,
                              enabled: uploadEnabled,
                              onChanged: (v) => setState(
                                () => maxFilesPerMessage = _clampInt(
                                  v,
                                  _storageMinFilesPerMessage,
                                  _storageMaxFilesPerMessage,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l('filesUnit'),
                            style: TextStyle(color: p.muted, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final n in _filesPerMessagePresets)
                            _StoragePresetButton(
                              label: '$n',
                              selected: maxFilesPerMessage == n,
                              enabled: uploadEnabled,
                              onPressed: () =>
                                  setState(() => maxFilesPerMessage = n),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                SettingsGroup(
                  label: l('overflowAction'),
                  description: l('overflowActionDesc'),
                  child: SettingsDropdown<String>(
                    value: overflowAction,
                    onChanged: uploadEnabled
                        ? (v) => setState(
                              () => overflowAction =
                                  v == 'delete' ? 'delete' : 'prevent',
                            )
                        : null,
                    items: [
                      DropdownMenuItem(
                        value: 'delete',
                        child: Text(l('overflowDeleteOldFiles')),
                      ),
                      DropdownMenuItem(
                        value: 'prevent',
                        child: Text(l('overflowPreventUploads')),
                      ),
                    ],
                  ),
                ),
                SettingsToggleRow(
                  label: l('imageOptimization'),
                  description: l('imageOptimizationDesc'),
                  value: imageOptimization,
                  onChanged: uploadEnabled
                      ? (v) => setState(() => imageOptimization = v)
                      : null,
                ),
                SettingsGroup(
                  label: l('imageQuality'),
                  description: l('imageQualityDesc'),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SettingsSlider(
                              value: imageQuality.toDouble(),
                              min: _storageMinImageQuality.toDouble(),
                              max: _storageMaxImageQuality.toDouble(),
                              onChanged: uploadEnabled
                                  ? (v) => setState(
                                        () => imageQuality = v.round().clamp(
                                              _storageMinImageQuality,
                                              _storageMaxImageQuality,
                                            ).toInt(),
                                      )
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$imageQuality%',
                            style: TextStyle(
                              color: p.foreground,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SettingsToggleRow(
                  label: l('signedUrls'),
                  description: l('signedUrlsDesc'),
                  value: signedUrls,
                  onChanged: (v) => setState(() => signedUrls = v),
                ),
                SettingsGroup(
                  label: l('signedUrlsTtl'),
                  description: l('signedUrlsTtlDesc'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 88,
                            child: _StorageNumberField(
                              value: (signedTtlSeconds / 60).round(),
                              enabled: true,
                              onChanged: (minutes) => setState(() {
                                signedTtlSeconds = _clampInt(
                                  minutes * 60,
                                  _storageMinSignedTtl,
                                  _storageMaxSignedTtl,
                                );
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l('signedUrlsTtlUnit'),
                            style: TextStyle(color: p.muted, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final preset in _signedTtlPresets)
                            _StoragePresetButton(
                              label: preset.label,
                              selected: signedTtlSeconds == preset.value,
                              onPressed: () => setState(
                                () => signedTtlSeconds = preset.value,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SettingsStickyFooter(
          cancelLabel: l('cancel'),
          saveLabel: l('save'),
          onCancel: widget.s.closeOverlay,
          onSave: _save,
        ),
      ],
    );
  }
}

class _StorageSizeControl extends StatelessWidget {
  const _StorageSizeControl({
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.presets,
    required this.onChanged,
    this.help,
    this.disabled = false,
    this.unlimitedZero = false,
  });

  final String label;
  final String description;
  final String? help;
  final int value;
  final int min;
  final int max;
  final List<_StorageSizePreset> presets;
  final ValueChanged<int> onChanged;
  final bool disabled;
  final bool unlimitedZero;

  int get _safeMax => max <= min ? min + 1 : max;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final preview = unlimitedZero && value <= 0
        ? l('unlimited')
        : formatBytes(value);
    final mb = (value / _kMb).round();
    return SettingsGroup(
      label: label,
      description: description,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SettingsSlider(
                  value: value.toDouble().clamp(min.toDouble(), _safeMax.toDouble()),
                  min: min.toDouble(),
                  max: _safeMax.toDouble(),
                  onChanged: disabled
                      ? null
                      : (v) => onChanged(v.round().clamp(min, max).toInt()),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                preview,
                style: TextStyle(
                  color: p.foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 88,
                child: _StorageNumberField(
                  value: mb,
                  enabled: !disabled,
                  onChanged: (nextMb) {
                    final bytes = nextMb * _kMb;
                    onChanged(bytes.clamp(min, max).toInt());
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l('mbUnit'),
                style: TextStyle(color: p.muted, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in presets)
                _StoragePresetButton(
                  label: unlimitedZero && preset.value <= 0
                      ? l('unlimited')
                      : preset.label,
                  selected: value == preset.value,
                  enabled: !disabled,
                  onPressed: () => onChanged(preset.value.clamp(min, max).toInt()),
                ),
            ],
          ),
          if (help != null) ...[
            const SizedBox(height: 8),
            Text(
              help!,
              style: TextStyle(color: p.faint, fontSize: 12, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _StorageNumberField extends StatefulWidget {
  const _StorageNumberField({
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  State<_StorageNumberField> createState() => _StorageNumberFieldState();
}

class _StorageNumberFieldState extends State<_StorageNumberField> {
  late final TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(covariant _StorageNumberField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && controller.text != '${widget.value}') {
      controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: TextStyle(color: context.p.foreground, fontSize: 13),
      decoration: settingsInputDecoration(context),
      onChanged: (raw) {
        final parsed = int.tryParse(raw);
        if (parsed == null) return;
        widget.onChanged(parsed);
      },
    );
  }
}

class _StoragePresetButton extends StatelessWidget {
  const _StoragePresetButton({
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? context.k.accent : p.foreground,
        side: BorderSide(
          color: selected ? context.k.accent : p.divider,
        ),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class ServerPluginsTab extends StatefulWidget {
  const ServerPluginsTab({super.key, required this.s});
  final SessionController s;
  @override
  State<ServerPluginsTab> createState() => _ServerPluginsTabState();
}

class _ServerPluginsTabState extends State<ServerPluginsTab> {
  List<dynamic> installed = [];
  List<dynamic> market = [];
  int segment = 0;

  @override
  void initState() {
    super.initState();
    widget.s.getPlugins().then((v) {
      if (mounted) setState(() => installed = v);
    }).catchError((_) {});
    widget.s.fetchMarketplace().then((v) {
      if (mounted) setState(() => market = v);
    }).catchError((_) {});
  }

  Map<String, dynamic> _asMap(dynamic p) {
    if (p is Map) return Map<String, dynamic>.from(p);
    return {'id': '$p', 'name': '$p'};
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final list = segment == 0 ? installed : market;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsPageHeader(
          title: l('pluginsTitle'),
          description: l('pluginsManageDesc'),
        ),
        const SizedBox(height: 16),
        SettingsSegmented(
          labels: [l('installed'), l('marketplace')],
          index: segment,
          onChanged: (i) => setState(() => segment = i),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: list.isEmpty
              ? SettingsEmptyHint(text: l('noItemFound'))
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: p.divider),
                  itemBuilder: (context, i) {
                    final raw = _asMap(list[i]);
                    final plugin = raw['plugin'] is Map
                        ? Map<String, dynamic>.from(raw['plugin'] as Map)
                        : raw;
                    final id = '${plugin['id'] ?? raw['id'] ?? ''}';
                    final name =
                        '${plugin['name'] ?? plugin['id'] ?? raw['name'] ?? id}';
                    final desc =
                        '${plugin['description'] ?? raw['description'] ?? ''}';
                    final latest = latestMarketplaceVersion(raw['versions']);
                    final version =
                        '${plugin['version'] ?? raw['version'] ?? latest?['version'] ?? ''}';
                    final author =
                        '${plugin['author'] ?? raw['author'] ?? ''}';
                    final enabled = plugin['enabled'] == true ||
                        raw['enabled'] == true;
                    final icon =
                        '${plugin['icon'] ?? raw['icon'] ?? plugin['logo'] ?? raw['logo'] ?? ''}';
                    final meta = [
                      if (version.isNotEmpty) 'v$version',
                      if (author.isNotEmpty) author,
                    ].join(' · ');
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          _PluginIcon(name: name, icon: icon),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    color: p.foreground,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (desc.isNotEmpty)
                                  Text(
                                    desc,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: p.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                if (meta.isNotEmpty)
                                  Text(
                                    meta,
                                    style: TextStyle(
                                      color: p.faint,
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (segment == 0) ...[
                            IconButton(
                              tooltip: l('pluginSettings'),
                              icon: Icon(Icons.settings_outlined, color: p.muted),
                              onPressed: () => _openSettings(id),
                            ),
                            IconButton(
                              tooltip: l('delete'),
                              icon: Icon(Icons.delete_outline, color: p.muted),
                              onPressed: () async {
                                await widget.s.removePlugin(id);
                                installed = await widget.s.getPlugins();
                                if (mounted) setState(() {});
                              },
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l('pluginEnabled'),
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            KurierSwitch(
                              value: enabled,
                              onChanged: (v) async {
                                await widget.s.togglePlugin(id, v);
                                installed = await widget.s.getPlugins();
                                if (mounted) setState(() {});
                              },
                            ),
                          ] else
                            KurierButton(
                              label: l('install'),
                              onPressed: () async {
                                final ver = '${latest?['version'] ?? version}';
                                if (ver.isEmpty) return;
                                await widget.s.installPlugin(id, ver);
                                installed = await widget.s.getPlugins();
                                if (mounted) setState(() {});
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _openSettings(String id) async {
    final settings = await widget.s.getPluginSettings(id);
    if (!mounted || settings.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.of(ctx)('pluginSettings')),
        content: SizedBox(
          width: 360,
          child: Text(
            settings.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
            style: TextStyle(color: ctx.p.foreground, fontSize: 13),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(ctx)('close')),
          ),
        ],
      ),
    );
  }
}

class _PluginIcon extends StatelessWidget {
  const _PluginIcon({required this.name, required this.icon});
  final String name;
  final String icon;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : 'P';
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: p.rail,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: icon.startsWith('http')
          ? Image.network(
              icon,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Text(
                letter,
                style: TextStyle(
                  color: p.foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : Text(
              letter,
              style: TextStyle(
                color: p.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class ServerUpdatesTab extends StatefulWidget {
  const ServerUpdatesTab({super.key, required this.s});
  final SessionController s;
  @override
  State<ServerUpdatesTab> createState() => _ServerUpdatesTabState();
}

class _ServerUpdatesTabState extends State<ServerUpdatesTab> {
  String current = '';
  String latest = '';
  bool hasUpdate = false;
  bool loaded = false;

  @override
  void initState() {
    super.initState();
    current = widget.s.info?.version ?? '';
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await widget.s.getUpdate();
      if (!mounted) return;
      String nextCurrent = current;
      String nextLatest = current;
      var update = false;
      if (raw is Map) {
        final map = Map<String, dynamic>.from(raw);
        nextCurrent =
            '${map['currentVersion'] ?? map['current'] ?? map['installed'] ?? nextCurrent}';
        nextLatest =
            '${map['latestVersion'] ?? map['latest'] ?? map['version'] ?? nextLatest}';
        update = asBool(
          map['hasUpdate'] ?? map['updateAvailable'] ?? map['available'],
        );
        if (!update &&
            nextLatest.isNotEmpty &&
            nextCurrent.isNotEmpty &&
            nextLatest != nextCurrent) {
          update = true;
        }
      } else if (raw != null) {
        nextLatest = '$raw';
        update = nextLatest.isNotEmpty && nextLatest != nextCurrent;
      }
      setState(() {
        current = nextCurrent;
        latest = nextLatest.isEmpty ? nextCurrent : nextLatest;
        hasUpdate = update;
        loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: SettingsCard(
              title: l('updatesTitle'),
              description: l('updatesDesc'),
              children: [
                _VersionRow(
                  label: l('updatesCurrentVersion'),
                  value: current.isEmpty ? '—' : current,
                ),
                _VersionRow(
                  label: l('updatesLatestVersion'),
                  value: latest.isEmpty ? '—' : latest,
                ),
                if (loaded)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasUpdate
                          ? context.k.accent.withValues(alpha: 0.12)
                          : const Color(0xFF242C52),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasUpdate
                              ? Icons.system_update
                              : Icons.check_circle_outline,
                          color: hasUpdate ? context.k.accent : const Color(0xFF8EA1E1),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hasUpdate
                                ? l('updatesAvailableBanner')
                                : l('updatesUpToDateBanner'),
                            style: TextStyle(color: p.foreground, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        SettingsStickyFooter(
          cancelLabel: l('close'),
          saveLabel: hasUpdate ? l('applyUpdate') : l('noUpdatesAvailable'),
          saveEnabled: hasUpdate,
          onCancel: widget.s.closeOverlay,
          onSave: hasUpdate ? widget.s.applyUpdate : null,
        ),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: p.faint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(color: p.muted, fontSize: 14)),
          ),
          Text(
            value,
            style: TextStyle(
              color: p.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

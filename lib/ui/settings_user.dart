import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../app/app_version.dart';
import '../app/l10n.dart';
import '../app/release_notes.dart';
import '../app/theme.dart';
import '../app/app_platform.dart';
import '../native/android_runtime.dart';
import '../protocol/audio_output.dart';
import '../protocol/config.dart';
import '../protocol/device_token.dart';
import '../protocol/permissions.dart';
import '../protocol/platform.dart';
import '../protocol/sounds.dart';
import '../session/session_controller.dart';
import 'media_stream_view_stub.dart'
    if (dart.library.js_interop) 'media_stream_view_web.dart'
    if (dart.library.io) 'media_stream_view_io.dart';
import 'member_context_menu.dart';
import 'profile_card.dart';
import 'settings_chrome.dart';
import 'shared.dart';

const _profileColorSwatches = [
  Color(0xFFED4245),
  Color(0xFFC44E2A),
  Color(0xFF8B5A3C),
  Color(0xFF5C4A3A),
  Color(0xFF3A3A3C),
  Color(0xFF232428),
  Color(0xFF5865F2),
  Color(0xFF3BA55D),
  Color(0xFFEB459E),
  Color(0xFFFAA61A),
];

class UserIdentityCard extends StatelessWidget {
  const UserIdentityCard({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final me = s.me;
    final p = context.p;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: p.sidebar,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          UserAvatar(user: me, session: s, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  me?.displayName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (me != null)
                  Text(
                    profileHandle(me),
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileSettingsTab extends StatefulWidget {
  const ProfileSettingsTab({super.key, required this.s});
  final SessionController s;
  @override
  State<ProfileSettingsTab> createState() => _ProfileSettingsTabState();
}

class _ProfileSettingsTabState extends State<ProfileSettingsTab> {
  late final name = TextEditingController(text: widget.s.me?.name ?? '');
  late final nick = TextEditingController(text: widget.s.me?.nickname ?? '');
  late final pronouns = TextEditingController(
    text: widget.s.me?.pronouns ?? '',
  );
  late final status = TextEditingController(
    text: widget.s.me?.statusMessage ?? '',
  );
  late final bio = TextEditingController(text: widget.s.me?.bio ?? '');
  late String color = widget.s.me?.profileColor ?? '#262626';

  @override
  void initState() {
    super.initState();
    for (final c in [name, nick, pronouns, status, bio]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    name.dispose();
    nick.dispose();
    pronouns.dispose();
    status.dispose();
    bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = widget.s;
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AvatarBannerRow(s: s, onPick: _pick, onRemoveAvatar: _removeAvatar),
        const SizedBox(height: 16),
        SettingsGroup(
          label: l('profileColor'),
          child: SettingsColorPicker(
            value: color,
            swatches: _profileColorSwatches,
            onChanged: (hex) => setState(() => color = hex),
          ),
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          label: l('username'),
          child: KurierField(controller: name, hint: l('username')),
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          label: l('nickname'),
          child: KurierField(controller: nick, hint: l('nicknameHint')),
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          label: l('pronouns'),
          child: KurierField(controller: pronouns, hint: l('pronouns')),
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          label: l('status'),
          child: KurierField(controller: status, hint: l('statusHint')),
        ),
        const SizedBox(height: 16),
        SettingsGroup(
          label: l('bio'),
          child: KurierField(controller: bio, hint: l('bioHint'), maxLines: 4),
        ),
        SettingsActions(
          cancelLabel: l('cancel'),
          saveLabel: l('save'),
          onCancel: s.closeOverlay,
          onSave: () => s.updateMe({
            'name': name.text,
            'nickname': nick.text,
            'pronouns': pronouns.text,
            'statusMessage': status.text,
            'bio': bio.text,
            'profileColor': color,
          }),
        ),
      ],
    );
    return SettingsCard(
      title: l('profileTitle'),
      description: l('profileDesc'),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 640;
            if (stack) {
              return Column(
                children: [
                  form,
                  const SizedBox(height: 20),
                  _ProfilePreview(
                    s: s,
                    name: name.text,
                    nick: nick.text,
                    color: color,
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: form),
                const SizedBox(width: 24),
                SizedBox(
                  width: 260,
                  child: _ProfilePreview(
                    s: s,
                    name: name.text,
                    nick: nick.text,
                    color: color,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _pick(SessionController s, {required bool avatar}) async {
    final r = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.image,
    );
    if (r == null || r.files.single.bytes == null) return;
    final id = await s.uploadBytes(r.files.single.name, r.files.single.bytes!);
    if (id == null) return;
    if (avatar) {
      await s.changeAvatar(id);
    } else {
      await s.changeBanner(id);
    }
    if (mounted) setState(() {});
  }

  Future<void> _removeAvatar() async {
    await widget.s.changeAvatar(null);
    if (mounted) setState(() {});
  }
}

class _AvatarBannerRow extends StatelessWidget {
  const _AvatarBannerRow({
    required this.s,
    required this.onPick,
    required this.onRemoveAvatar,
  });

  final SessionController s;
  final Future<void> Function(SessionController s, {required bool avatar})
  onPick;
  final Future<void> Function() onRemoveAvatar;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final me = s.me;
    final bannerUrl = me?.banner != null ? s.fileUrl(me!.banner!) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => onPick(s, avatar: true),
              child: UserAvatar(
                user: me,
                session: s,
                size: 80,
                showStatus: false,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => onPick(s, avatar: false),
                child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                    color: profileBannerColor(me?.profileColor ?? '#262626'),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: bannerUrl != null && bannerUrl.isNotEmpty
                      ? Image.network(
                          bannerUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, _, _) => const SizedBox.expand(),
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
        if (me?.avatar != null)
          TextButton(
            onPressed: onRemoveAvatar,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.only(top: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              l('removeAvatar'),
              style: TextStyle(color: context.p.muted, fontSize: 13),
            ),
          ),
      ],
    );
  }
}

class _ProfilePreview extends StatelessWidget {
  const _ProfilePreview({
    required this.s,
    required this.name,
    required this.nick,
    required this.color,
  });

  final SessionController s;
  final String name;
  final String nick;
  final String color;

  @override
  Widget build(BuildContext context) {
    final me = s.me;
    final display = nick.trim().isNotEmpty ? nick.trim() : name.trim();
    final handle = name.trim().isEmpty ? '' : '@${name.trim()}';
    return Container(
      decoration: BoxDecoration(
        color: context.p.sidebar,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.p.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 72,
            width: double.infinity,
            child: ColoredBox(color: profileBannerColor(color)),
          ),
          Transform.translate(
            offset: const Offset(0, -28),
            child: Column(
              children: [
                UserAvatar(user: me, session: s, size: 64, showStatus: false),
                const SizedBox(height: 8),
                Text(
                  display.isEmpty ? (me?.displayName ?? '') : display,
                  style: TextStyle(
                    color: context.p.foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (handle.isNotEmpty)
                  Text(
                    handle,
                    style: TextStyle(color: context.p.muted, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DevicesSettingsTab extends StatefulWidget {
  const DevicesSettingsTab({super.key, required this.s});
  final SessionController s;
  @override
  State<DevicesSettingsTab> createState() => _DevicesSettingsTabState();
}

class _DevicesSettingsTabState extends State<DevicesSettingsTab> {
  List<MediaDeviceInfo> _devices = const [];
  AudioOutputPlan _outputPlan = const AudioOutputPlan();
  var _testing = false;
  var _previewing = false;
  double _level = 0;
  Timer? _meter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _meter?.cancel();
    PlatformBridge.stopMicTest();
    PlatformBridge.stopVideoPreview();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await PlatformBridge.enumerate();
    if (!mounted) return;
    setState(() {
      _devices = list;
      _outputPlan = resolveAudioOutput(
        devices: list,
        canSetOutputDevice: PlatformBridge.canSetOutputDevice,
        outputFollowsMic: PlatformBridge.isIos || PlatformBridge.isAndroid,
      );
    });
  }

  List<MediaDeviceInfo> _of(String kind) =>
      _devices.where((d) => d.kind == kind).toList();

  String? _validId(String? stored, List<MediaDeviceInfo> devices) {
    if (stored == null || stored.isEmpty) return '';
    if (devices.any((d) => d.deviceId == stored)) return stored;
    return '';
  }

  Future<void> _persist(Future<void> Function() fn) async {
    await fn();
    widget.s.refresh();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = widget.s;
    final store = s.store;
    final inputs = _of('audioinput');
    final cameras = _of('videoinput');
    final outputChoices = _outputPlan.usesMicRoute
        ? _outputPlan.classified.realDevices
        : _of('audiooutput').where((d) => !isVirtualAudioOutput(d)).toList();
    final mic = _validId(store.micDevice, inputs);
    final speaker = _validId(
      _outputPlan.usesMicRoute ? store.micDevice : s.speakerOutputId,
      outputChoices,
    );
    final camera = _validId(store.cameraDevice, cameras);
    final defaultLabel = l('defaultDevice');

    DropdownMenuItem<String> item(String id, String label) => DropdownMenuItem(
      value: id,
      child: Text(label.isEmpty ? id : label, overflow: TextOverflow.ellipsis),
    );

    String outputLabel(MediaDeviceInfo d) {
      if (d.label.isNotEmpty) return d.label;
      if (isDefaultAudioOutputId(d.deviceId)) return l('bluetoothAudio');
      return d.deviceId;
    }

    return SettingsCard(
      title: l('devicesTitle'),
      description: l('devicesDesc'),
      children: [
        SettingsGroup(
          label: l('outputDevice'),
          child: SettingsDropdown<String>(
            value: speaker,
            items: [
              item('', defaultLabel),
              for (final d in outputChoices) item(d.deviceId, outputLabel(d)),
            ],
            onChanged: (v) async {
              final id = v == null || v.isEmpty ? null : v;
              if (_outputPlan.usesMicRoute) {
                await s.applyMicForOutput(id);
              } else {
                await s.applySpeakerDevice(id);
              }
              if (mounted) setState(() {});
            },
          ),
        ),
        SettingsGroup(
          label: l('inputDevice'),
          child: SettingsDropdown<String>(
            value: mic,
            items: [
              item('', defaultLabel),
              for (final d in inputs)
                item(d.deviceId, d.label.isEmpty ? d.deviceId : d.label),
            ],
            onChanged: (v) => _persist(
              () => store.setMicDevice(v == null || v.isEmpty ? null : v),
            ),
          ),
        ),
        SettingsGroup(
          label: l('inputMode'),
          child: SettingsChoiceCards(
            value: store.ptt ? 'ptt' : 'vad',
            options: [('vad', l('voiceActivity')), ('ptt', l('pushToTalk'))],
            onChanged: (v) => _persist(() => store.setPtt(v == 'ptt')),
          ),
        ),
        SettingsGroup(
          label: l('noiseSuppression'),
          child: SettingsDropdown<String>(
            value: store.noiseSuppression == 'standard' ? 'standard' : 'none',
            items: [
              DropdownMenuItem(value: 'none', child: Text(l('noiseNone'))),
              DropdownMenuItem(
                value: 'standard',
                child: Text(l('noiseStandard')),
              ),
            ],
            onChanged: (v) =>
                _persist(() => store.setNoiseSuppression(v ?? 'none')),
          ),
        ),
        SettingsToggleRow(
          label: l('echoCancellation'),
          value: store.echoCancellation,
          onChanged: (v) => _persist(() => store.setEchoCancellation(v)),
        ),
        SettingsToggleRow(
          label: l('autoGainControl'),
          value: store.autoGainControl,
          onChanged: (v) => _persist(() => store.setAutoGainControl(v)),
        ),
        SettingsToggleRow(
          label: l('voiceActivitySensitivity'),
          value: store.vadSensitivity,
          onChanged: (v) => _persist(() => store.setVadSensitivity(v)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: KurierButton(
            label: _testing ? l('stopTest') : l('startTest'),
            outline: true,
            onPressed: _toggleMicTest,
          ),
        ),
        _MicLevelBar(level: _level),
        SettingsToggleRow(
          label: l('attenuation'),
          description: l('attenuationDesc'),
          value: store.attenuateOthers,
          onChanged: (v) => _persist(() => store.setAttenuateOthers(v)),
        ),
        SettingsGroup(
          label:
              '${l('attenuationAmount')} (${store.attenuationAmount.round()}%)',
          child: SettingsSlider(
            value: store.attenuationAmount,
            onChanged: (v) async {
              await store.setAttenuationAmount(v);
              s.refresh();
              if (mounted) setState(() {});
            },
          ),
        ),
        SettingsToggleRow(
          label: l('skipDeviceCheck'),
          description: l('skipDeviceCheckDesc'),
          value: store.skipDeviceCheck,
          onChanged: (v) => _persist(() => store.setSkipDeviceCheck(v)),
        ),
        SettingsToggleRow(
          label: l('keepScreenOnVoice'),
          description: l('keepScreenOnVoiceDesc'),
          value: store.keepScreenOnVoice,
          onChanged: (v) async {
            if (v) {
              if (!await confirmKeepScreenOnVoice(context)) return;
            }
            await widget.s.setKeepScreenOnVoice(v);
            if (mounted) setState(() {});
          },
        ),
        SettingsGroup(
          label: l('webcam'),
          child: SettingsDropdown<String>(
            value: camera,
            items: [
              item('', defaultLabel),
              for (final d in cameras)
                item(d.deviceId, d.label.isEmpty ? d.deviceId : d.label),
            ],
            onChanged: (v) async {
              await store.setCameraDevice(v == null || v.isEmpty ? null : v);
              PlatformBridge.setCameraDevice(store.cameraDevice);
              s.refresh();
              if (mounted) setState(() {});
            },
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: KurierButton(
            label: _previewing ? l('stopVideoPreview') : l('startVideoPreview'),
            outline: true,
            onPressed: _togglePreview,
          ),
        ),
        if (_previewing)
          SizedBox(
            height: 180,
            width: double.infinity,
            child: mediaStreamView(mediaKey: 'preview:video'),
          ),
      ],
    );
  }

  Future<void> _toggleMicTest() async {
    if (_testing) {
      _meter?.cancel();
      PlatformBridge.stopMicTest();
      setState(() {
        _testing = false;
        _level = 0;
      });
      return;
    }
    await PlatformBridge.startMicTest(
      deviceId: widget.s.store.micDevice,
      audioConstraints: widget.s.store.audioConstraints(),
    );
    _meter?.cancel();
    _meter = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      setState(() => _level = PlatformBridge.micTestLevel());
    });
    setState(() => _testing = true);
  }

  Future<void> _togglePreview() async {
    if (_previewing) {
      PlatformBridge.stopVideoPreview();
      setState(() => _previewing = false);
      return;
    }
    await PlatformBridge.startVideoPreview(
      deviceId: widget.s.store.cameraDevice,
    );
    if (!mounted) return;
    setState(() => _previewing = true);
  }
}

class _MicLevelBar extends StatelessWidget {
  const _MicLevelBar({required this.level});
  final double level;

  @override
  Widget build(BuildContext context) {
    final t = (level / 100).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            ColoredBox(color: context.p.rail, child: const SizedBox.expand()),
            FractionallySizedBox(
              widthFactor: t,
              child: ColoredBox(color: context.k.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class AppearanceSettingsTab extends StatelessWidget {
  const AppearanceSettingsTab({super.key, required this.s});
  final SessionController s;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final currentAccent = colorFromHex(s.accent);
    return SettingsCard(
      title: l('appearanceTitle'),
      description: l('appearanceDesc'),
      children: [
        SettingsSectionLabel(text: l('themePresetLabel')),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 560 ? 4 : 2;
            return GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 8,
              childAspectRatio: 1.28,
              children: [
                for (final preset in ThemePreset.values)
                  SettingsThemeTile(
                    preset: preset,
                    selected: s.themePreset == preset.name,
                    onTap: () async {
                      s.themePreset = preset.name;
                      await s.store.setPreset(preset.name);
                      s.refresh();
                    },
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        SettingsSectionLabel(text: l('accentColorLabel')),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in accentSwatches)
              SettingsAccentSwatch(
                color: c,
                selected: c.toARGB32() == currentAccent.toARGB32(),
                onTap: () async {
                  s.accent = colorToHex(c);
                  await s.store.setAccent(s.accent);
                  s.refresh();
                },
              ),
          ],
        ),
      ],
    );
  }
}

class SoundsSettingsTab extends StatelessWidget {
  const SoundsSettingsTab({super.key, required this.s});
  final SessionController s;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return SettingsCard(
      title: l('sounds'),
      description: l('soundsDesc'),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: KurierButton(
            label: l('openSoundLibrary'),
            onPressed: () => _openLibrary(context),
          ),
        ),
      ],
    );
  }

  void _openLibrary(BuildContext context) {
    final l = L10n.of(context);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: l('close'),
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, _) {
        return OverlayDialogShell(
          onClose: () => Navigator.pop(ctx),
          child: _SoundLibraryBody(s: s, title: l('soundLibraryTitle')),
        );
      },
    );
  }
}

class _SoundLibraryBody extends StatelessWidget {
  const _SoundLibraryBody({required this.s, required this.title});
  final SessionController s;
  final String title;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.7;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.p.foreground,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                SettingsToggleRow(
                  label: l('mentionSound'),
                  value: s.store.soundMention,
                  onChanged: (v) async {
                    await s.store.setSoundMention(v);
                    s.refresh();
                  },
                ),
                const SizedBox(height: 8),
                SettingsToggleRow(
                  label: l('messageSound'),
                  value: s.store.soundMessage,
                  onChanged: (v) async {
                    await s.store.setSoundMessage(v);
                    s.refresh();
                  },
                ),
                const SizedBox(height: 16),
                for (final type in KurierSoundType.all) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l(KurierSoundType.l10nKeys[type] ?? type),
                          style: TextStyle(
                            color: context.p.foreground,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      KurierButton(
                        label: l('playSound'),
                        outline: true,
                        onPressed: () => PlatformBridge.playSound(type),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class NotificationsSettingsTab extends StatelessWidget {
  const NotificationsSettingsTab({super.key, required this.s});
  final SessionController s;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final perm = PlatformBridge.notificationPermission();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsCard(
          title: l('notificationsTitle'),
          description: isNativeMobile
              ? l('notificationsPushDesc')
              : l('notificationsDesc'),
          children: [
            if (perm != 'granted') ...[
              Text(
                perm,
                style: TextStyle(color: context.p.muted, fontSize: 13),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: KurierButton(
                  label: l('enableNotifications'),
                  outline: true,
                  onPressed: () async {
                    await PlatformBridge.requestNotifications();
                    s.refresh();
                  },
                ),
              ),
            ],
            SettingsToggleRow(
              leadingSwitch: true,
              label: l('allMessages'),
              description: l('allMessagesDesc'),
              value: s.store.notifyAll,
              onChanged: (v) async {
                await s.store.setNotifyAll(v);
                await androidSyncPrefs(
                  trpc: s.trpc,
                  notifyAll: v,
                  mentions: s.store.notifyMentions,
                  dm: s.store.notifyDm,
                  replies: s.store.notifyReplies,
                );
                s.refresh();
              },
            ),
            SettingsToggleRow(
              leadingSwitch: true,
              label: l('mentionsOnly'),
              description: l('mentionsOnlyDesc'),
              value: s.store.notifyMentions,
              onChanged: (v) async {
                await s.store.setNotifyMentions(v);
                await androidSyncPrefs(
                  trpc: s.trpc,
                  notifyAll: s.store.notifyAll,
                  mentions: v,
                  dm: s.store.notifyDm,
                  replies: s.store.notifyReplies,
                );
                s.refresh();
              },
            ),
            SettingsToggleRow(
              leadingSwitch: true,
              label: l('dmNotifications'),
              description: l('dmNotificationsDesc'),
              value: s.store.notifyDm,
              onChanged: (v) async {
                await s.store.setNotifyDm(v);
                await androidSyncPrefs(
                  trpc: s.trpc,
                  notifyAll: s.store.notifyAll,
                  mentions: s.store.notifyMentions,
                  dm: v,
                  replies: s.store.notifyReplies,
                );
                s.refresh();
              },
            ),
            SettingsToggleRow(
              leadingSwitch: true,
              label: l('repliesToMe'),
              description: l('repliesToMeDesc'),
              value: s.store.notifyReplies,
              onChanged: (v) async {
                await s.store.setNotifyReplies(v);
                await androidSyncPrefs(
                  trpc: s.trpc,
                  notifyAll: s.store.notifyAll,
                  mentions: s.store.notifyMentions,
                  dm: s.store.notifyDm,
                  replies: v,
                );
                s.refresh();
              },
            ),
            if (androidNotificationSettingsAvailable) ...[
              Text(
                l('systemNotificationSettingsDesc'),
                style: TextStyle(
                  color: context.p.muted,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: KurierButton(
                  label: l('systemNotificationSettings'),
                  outline: true,
                  onPressed: androidOpenNotificationSettings,
                ),
              ),
            ],
          ],
        ),
        if (isNativeMobile) ...[
          const SizedBox(height: 16),
          SettingsCard(
            title: l('appLock'),
            description: l('appLockDesc'),
            children: [
              SettingsToggleRow(
                leadingSwitch: true,
                label: l('appLock'),
                value: androidAppLockEnabled,
                onChanged: (v) async {
                  await setAndroidAppLockEnabled(v);
                  s.refresh();
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class PasswordSettingsTab extends StatefulWidget {
  const PasswordSettingsTab({super.key, required this.s});
  final SessionController s;
  @override
  State<PasswordSettingsTab> createState() => _PasswordSettingsTabState();
}

class _PasswordSettingsTabState extends State<PasswordSettingsTab> {
  final cur = TextEditingController();
  final next = TextEditingController();
  final confirm = TextEditingController();
  String? error;

  @override
  void dispose() {
    cur.dispose();
    next.dispose();
    confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return SettingsCard(
      title: l('passwordTitle'),
      description: l('passwordDesc'),
      children: [
        SettingsGroup(
          label: l('currentPassword'),
          child: KurierField(controller: cur, obscure: true),
        ),
        SettingsGroup(
          label: l('newPassword'),
          child: KurierField(controller: next, obscure: true),
        ),
        SettingsGroup(
          label: l('confirmPassword'),
          child: KurierField(controller: confirm, obscure: true),
        ),
        if (error != null)
          Text(error!, style: TextStyle(color: context.p.dnd, fontSize: 13)),
        SettingsActions(
          cancelLabel: l('cancel'),
          saveLabel: l('save'),
          onCancel: widget.s.closeOverlay,
          onSave: () async {
            if (next.text != confirm.text) {
              setState(() => error = l('passwordsDoNotMatch'));
              return;
            }
            setState(() => error = null);
            await widget.s.updatePassword(current: cur.text, next: next.text);
          },
        ),
      ],
    );
  }
}

class SecuritySettingsTab extends StatefulWidget {
  const SecuritySettingsTab({super.key, required this.s});
  final SessionController s;
  @override
  State<SecuritySettingsTab> createState() => _SecuritySettingsTabState();
}

class _SecuritySettingsTabState extends State<SecuritySettingsTab> {
  String qid = securityQuestionIds.first;
  final answer = TextEditingController();
  final current = TextEditingController();

  @override
  void dispose() {
    answer.dispose();
    current.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return SettingsCard(
      title: l('securityTitle'),
      description: l('securityDesc'),
      children: [
        SettingsGroup(
          label: l('securityQuestion'),
          child: SettingsDropdown<String>(
            value: qid,
            items: [
              for (final id in securityQuestionIds)
                DropdownMenuItem(value: id, child: Text(l('q_$id'))),
            ],
            onChanged: (v) {
              if (v != null) setState(() => qid = v);
            },
          ),
        ),
        SettingsGroup(
          label: l('securityAnswer'),
          child: KurierField(controller: answer),
        ),
        SettingsGroup(
          label: l('currentPassword'),
          child: KurierField(controller: current, obscure: true),
        ),
        SettingsActions(
          cancelLabel: l('cancel'),
          saveLabel: l('save'),
          onCancel: widget.s.closeOverlay,
          onSave: () => widget.s.updateSecurity(
            questionId: qid,
            answer: answer.text,
            currentPassword: current.text,
          ),
        ),
      ],
    );
  }
}

class OthersSettingsTab extends StatefulWidget {
  const OthersSettingsTab({super.key, required this.s});
  final SessionController s;
  @override
  State<OthersSettingsTab> createState() => _OthersSettingsTabState();
}

class _OthersSettingsTabState extends State<OthersSettingsTab> {
  final token = TextEditingController();
  final klipy = TextEditingController();

  @override
  void initState() {
    super.initState();
    klipy.text = widget.s.store.klipy ?? '';
  }

  @override
  void dispose() {
    token.dispose();
    klipy.dispose();
    super.dispose();
  }

  String _langLabel(BuildContext context, String code) {
    final l = L10n.of(context);
    return l('lang_$code');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final l = L10n.of(context);
    return SettingsCard(
      title: l('othersTitle'),
      description: l('othersDesc'),
      children: [
        SettingsToggleRow(
          label: l('autoJoin'),
          description: l('autoJoinDesc'),
          value: s.store.autoJoin,
          onChanged: (v) async {
            await s.store.setAutoJoin(v);
            s.refresh();
          },
        ),
        SettingsToggleRow(
          label: l('compact'),
          description: l('compactDesc'),
          value: s.store.compact,
          onChanged: (v) async {
            await s.store.setCompact(v);
            s.refresh();
          },
        ),
        SettingsGroup(
          label: l('language'),
          description: l('languageDesc'),
          child: SettingsDropdown<String>(
            value: s.locale,
            items: [
              for (final loc in supportedLocales)
                DropdownMenuItem(
                  value: loc.languageCode,
                  child: Text(_langLabel(context, loc.languageCode)),
                ),
            ],
            onChanged: (v) async {
              if (v == null) return;
              s.locale = v;
              await s.store.setLocale(v);
              s.refresh();
            },
          ),
        ),
        SettingsGroup(
          label: l('gifKey'),
          description: l('gifKeyDesc'),
          child: KurierField(controller: klipy, hint: l('gifKeyHint')),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: KurierButton(
            label: l('save'),
            onPressed: () => s.store.setKlipy(klipy.text),
          ),
        ),
        SettingsGroup(
          label: l('ownerToken'),
          child: KurierField(controller: token),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: KurierButton(
            label: l('useToken'),
            onPressed: () => s.claimOwner(token.text),
          ),
        ),
        if (s.isOwner)
          CurrentBrowserToken(
            s: s,
            title: l('clientDataTitle'),
            description: l('clientDataDesc'),
          ),
      ],
    );
  }
}

class CurrentBrowserToken extends StatefulWidget {
  const CurrentBrowserToken({
    super.key,
    required this.s,
    this.title,
    this.description,
    this.onBanned,
    this.bannedValues = const [],
  });

  final SessionController s;
  final String? title;
  final String? description;
  final Future<void> Function()? onBanned;
  final List<Map<String, dynamic>> bannedValues;

  @override
  State<CurrentBrowserToken> createState() => _CurrentBrowserTokenState();
}

class _CurrentBrowserTokenState extends State<CurrentBrowserToken> {
  var _bannedLocally = false;

  bool _matchesToken(String token, String? raw) {
    final want = normalizeDeviceToken(token);
    final got = normalizeDeviceToken(raw);
    return want != null && got != null && want == got;
  }

  bool _isBanned(String token) {
    if (_bannedLocally) return true;
    return widget.bannedValues.any(
      (item) => _matchesToken(token, '${item['value'] ?? ''}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final token = widget.s.store.deviceToken();
    final banned = _isBanned(token);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title != null)
          Text(
            widget.title!,
            style: TextStyle(
              color: p.foreground,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (widget.description != null) ...[
          const SizedBox(height: 2),
          Text(
            widget.description!,
            style: TextStyle(color: p.muted, fontSize: 13, height: 1.35),
          ),
        ],
        const SizedBox(height: 8),
        SelectableText(
          token,
          style: TextStyle(
            color: p.muted,
            fontSize: 13,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
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
            if (banned)
              Text(
                l('accessBansDeviceBanned'),
                style: TextStyle(color: p.muted, fontSize: 13),
              )
            else
              KurierButton(
                label: l('accessBansDeviceBan'),
                danger: true,
                onPressed: () async {
                  final ok = await banMemberBrowser(context, widget.s, token);
                  if (!ok || !mounted) return;
                  setState(() => _bannedLocally = true);
                  await widget.onBanned?.call();
                },
              ),
          ],
        ),
      ],
    );
  }
}

class AboutSettingsTab extends StatefulWidget {
  const AboutSettingsTab({super.key, required this.s});
  final SessionController s;

  @override
  State<AboutSettingsTab> createState() => _AboutSettingsTabState();
}

class _AboutSettingsTabState extends State<AboutSettingsTab> {
  late final Future<String> _version = _loadVersion();

  Future<String> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return displayAppVersion(
        packageVersion: info.version,
        stamp: AppConfig.webStamp,
      );
    } catch (_) {
      return displayAppVersion(stamp: AppConfig.webStamp);
    }
  }

  void _openListDialog(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final l = L10n.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
            ),
            child: children.isEmpty
                ? Text(l('noChangelog'))
                : ListView(shrinkWrap: true, children: children),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l('close')),
          ),
        ],
      ),
    );
  }

  void _openChangelog(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    if (releaseNotes.isEmpty) {
      _openListDialog(
        context,
        title: l('changelog'),
        children: [Text(l('noChangelog'))],
      );
      return;
    }
    final children = <Widget>[];
    for (var i = 0; i < releaseNotes.length; i++) {
      final entry = releaseNotes[i];
      if (i > 0) children.add(const SizedBox(height: 16));
      children.add(
        Text(
          entry.version,
          style: TextStyle(
            color: p.foreground,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      if (entry.notes.isEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(l('noChangelog'), style: TextStyle(color: p.muted)),
          ),
        );
        continue;
      }
      for (final note in entry.notes) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '• $note',
              style: TextStyle(color: p.muted, height: 1.4),
            ),
          ),
        );
      }
    }
    _openListDialog(context, title: l('changelog'), children: children);
  }

  void _openThirdParty(BuildContext context) {
    final l = L10n.of(context);
    final p = context.p;
    final children = <Widget>[];
    for (var i = 0; i < thirdPartyPrograms.length; i++) {
      final item = thirdPartyPrograms[i];
      if (i > 0) children.add(const SizedBox(height: 14));
      children.add(
        Text(
          item.name,
          style: TextStyle(
            color: p.foreground,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            item.usage,
            style: TextStyle(color: p.muted, height: 1.4),
          ),
        ),
      );
    }
    _openListDialog(context, title: l('thirdPartyUsage'), children: children);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return SettingsCard(
      title: l('about'),
      description: l('pluginWidgetsNote'),
      children: [
        FutureBuilder<String>(
          future: _version,
          builder: (context, snap) {
            final version =
                snap.data ?? displayAppVersion(stamp: AppConfig.webStamp);
            return Text(
              '${l('version')}: $version',
              style: TextStyle(color: context.p.foreground),
            );
          },
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            KurierButton(
              label: l('changelog'),
              outline: true,
              onPressed: () => _openChangelog(context),
            ),
            KurierButton(
              label: l('thirdPartyUsage'),
              outline: true,
              onPressed: () => _openThirdParty(context),
            ),
          ],
        ),
        Text(l('logs'), style: TextStyle(color: context.p.faint)),
        for (final line in widget.s.logs.reversed.take(30))
          Text(line, style: TextStyle(color: context.p.muted, fontSize: 11)),
      ],
    );
  }
}

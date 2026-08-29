import 'dart:async';

import 'package:flutter/material.dart';

import '../app/breakpoints.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/audio_output.dart';
import '../protocol/models.dart';
import '../protocol/permissions.dart';
import '../protocol/platform.dart';
import '../protocol/voice_protocol.dart';
import '../session/session_controller.dart';
import 'context_menu.dart';
import 'media_stream_view_stub.dart'
    if (dart.library.js_interop) 'media_stream_view_web.dart';
import 'member_context_menu.dart';
import 'shared.dart';
import 'transport_stats_popover.dart';

class VoiceStage extends StatefulWidget {
  const VoiceStage({
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
  State<VoiceStage> createState() => _VoiceStageState();
}

class _VoiceStageState extends State<VoiceStage> {
  String? _focusedWatchKey;

  SessionController get session => widget.session;
  KurierChannel get channel => widget.channel;

  @override
  void didUpdateWidget(VoiceStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.id != widget.channel.id) {
      _focusedWatchKey = null;
    }
  }

  void _toggleFocus(String watchKey) {
    setState(() {
      _focusedWatchKey = _focusedWatchKey == watchKey ? null : watchKey;
    });
  }

  void _clearFocusIf(String watchKey) {
    if (_focusedWatchKey != watchKey) return;
    setState(() => _focusedWatchKey = null);
  }

  bool _isWatchKeyActive(SessionController s, String watchKey) {
    final occupants = s.voiceMap[channel.id] ?? {};
    for (final e in occupants.entries) {
      if (!e.value.sharingScreen) continue;
      if (StreamKind.watchKey(e.key, external: false) != watchKey) continue;
      return e.key == s.ownUserId || s.isWatchingStream(e.key);
    }
    for (final stream
        in s.externalStreams[channel.id] ?? const <ExternalStream>[]) {
      if (StreamKind.watchKey(stream.streamId, external: true) != watchKey) {
        continue;
      }
      return s.isWatchingStream(stream.streamId, external: true);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final l = L10n.of(context);
    final connected = s.connectedVoiceChannelId == channel.id;
    final phone =
        breakpointOf(MediaQuery.sizeOf(context).width) == Breakpoint.phone;
    final focusedKey = _focusedWatchKey;
    final focusedCard = focusedKey != null && _isWatchKeyActive(s, focusedKey)
        ? _focusedCard(context, s, focusedKey)
        : null;
    final headerBtnSize = phone ? minTap : kCompactBtn;
    return Material(
      color: context.p.background,
      child: Column(
        children: [
          Container(
            height: kHeaderHeight,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: context.p.divider)),
            ),
            child: Row(
              children: [
                if (widget.onBack != null)
                  CompactIconButton(
                    icon: Icons.menu,
                    size: headerBtnSize,
                    onPressed: widget.onBack,
                  ),
                Icon(Icons.volume_up, color: context.p.muted, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          channel.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.p.foreground,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (channel.displayedVoiceStatus != null) ...[
                        Container(
                          width: 1,
                          height: 16,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          color: context.p.divider,
                        ),
                        Flexible(
                          child: VoiceStatusText(channel.displayedVoiceStatus!),
                        ),
                      ],
                    ],
                  ),
                ),
                if (s.hasMusicBot)
                  CompactIconButton(
                    tooltip: l('musicBot'),
                    icon: Icons.library_music,
                    size: headerBtnSize,
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: context.p.sidebar,
                      builder: (_) => MusicBotSheet(session: s),
                    ),
                  ),
                if (widget.onToggleMembers != null)
                  CompactIconButton(
                    tooltip: l('members', {'count': '${s.users.length}'}),
                    icon: widget.membersOpen
                        ? Icons.people
                        : Icons.people_outline,
                    size: headerBtnSize,
                    onPressed: widget.onToggleMembers,
                  ),
              ],
            ),
          ),
          Expanded(child: _occupantArea(context, s, phone, focusedCard)),
          if (connected && s.voiceAudioLocked)
            _TapToEnableAudioBanner(session: s),
          _controls(context, s, l, connected, phone: phone),
        ],
      ),
    );
  }

  Widget _occupantArea(
    BuildContext context,
    SessionController s,
    bool phone,
    Widget? focusedCard,
  ) {
    if (focusedCard != null) {
      return Padding(
        padding: EdgeInsets.all(phone ? 8 : 16),
        child: focusedCard,
      );
    }
    final tiles = _occupantTiles(context, s, phone: phone);
    if (phone && tiles.isNotEmpty && tiles.length <= 2) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Column(children: [for (final t in tiles) Expanded(child: t)]),
      );
    }
    return GridView.count(
      crossAxisCount: MediaQuery.sizeOf(context).width > 900 ? 3 : 2,
      padding: const EdgeInsets.all(16),
      children: tiles,
    );
  }

  List<Widget> _occupantTiles(
    BuildContext context,
    SessionController s, {
    required bool phone,
  }) {
    final occupants = s.voiceMap[channel.id] ?? {};
    var tileCount = occupants.length;
    for (final e in occupants.entries) {
      if (e.value.sharingScreen) tileCount++;
    }
    tileCount +=
        (s.externalStreams[channel.id] ?? const <ExternalStream>[]).length;
    final avatarSize = phone && tileCount > 0 && tileCount <= 2
        ? kVoiceTileAvatarPhone
        : 72.0;
    return [
      for (final e in occupants.entries)
        _tile(
          context,
          s,
          e.key,
          e.value,
          avatarSize: avatarSize,
          namePill: phone,
        ),
      for (final e in occupants.entries)
        if (e.value.sharingScreen) _screenCard(context, s, e.key, e.value),
      for (final stream
          in s.externalStreams[channel.id] ?? const <ExternalStream>[])
        _ext(context, stream),
    ];
  }

  Widget? _focusedCard(
    BuildContext context,
    SessionController s,
    String watchKey,
  ) {
    final occupants = s.voiceMap[channel.id] ?? {};
    for (final e in occupants.entries) {
      if (e.value.sharingScreen &&
          StreamKind.watchKey(e.key, external: false) == watchKey) {
        return _screenCard(context, s, e.key, e.value, focused: true);
      }
    }
    for (final stream
        in s.externalStreams[channel.id] ?? const <ExternalStream>[]) {
      if (StreamKind.watchKey(stream.streamId, external: true) == watchKey) {
        return _ext(context, stream, focused: true);
      }
    }
    return null;
  }

  Widget _tile(
    BuildContext context,
    SessionController s,
    int userId,
    VoiceUserState st, {
    double avatarSize = 72,
    bool namePill = false,
  }) {
    final user = s.users[userId];
    final showCam = s.showingWebcam(userId, st);
    Widget nameText = Text(
      user?.displayName ?? '',
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: context.p.foreground,
        shadows: showCam
            ? const [Shadow(blurRadius: 8, color: Colors.black)]
            : null,
      ),
    );
    Widget nameRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (namePill) Flexible(child: nameText) else nameText,
        if (st.micMuted) Icon(Icons.mic_off, size: 16, color: context.p.dnd),
        if (st.sharingScreen)
          Icon(Icons.screen_share, size: 16, color: context.k.accent),
      ],
    );
    if (namePill) {
      nameRow = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: showCam
              ? context.p.rail.withValues(alpha: 0.85)
              : context.p.rail,
          borderRadius: BorderRadius.circular(20),
        ),
        child: nameRow,
      );
    }
    final tile = Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.p.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showCam)
            mediaStreamView(
              mediaKey: s.mediaKeyFor(
                remoteId: userId,
                kind: StreamKind.video,
                local: userId == s.ownUserId,
              ),
            )
          else
            Center(
              child: UserAvatar(
                user: user,
                session: s,
                size: avatarSize,
                speakingIntensity: s.speakingOf(userId, micMuted: st.micMuted),
              ),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            right: namePill ? 8 : null,
            child: nameRow,
          ),
        ],
      ),
    );
    if (user == null) return tile;
    return ContextRegion(
      onTap: (pos) => s.showProfile(user, anchor: pos),
      openMenu: (ctx, pos) => openMemberPointerMenu(ctx, pos, s, user),
      child: tile,
    );
  }

  Widget _screenCard(
    BuildContext context,
    SessionController s,
    int userId,
    VoiceUserState _, {
    bool focused = false,
  }) {
    final user = s.users[userId];
    final own = userId == s.ownUserId;
    final watching = own || s.isWatchingStream(userId);
    final canWatch = !own && s.canWatchStream(userId);
    final l = L10n.of(context);
    final key = StreamKind.watchKey(userId, external: false);
    return _watchableCard(
      context,
      watching: watching,
      focused: focused,
      mediaKey: s.mediaKeyFor(
        remoteId: userId,
        kind: StreamKind.screen,
        local: own,
      ),
      fit: BoxFit.contain,
      placeholder: UserAvatar(user: user, session: s, size: 72),
      label: l('userScreen', {'name': user?.displayName ?? ''}),
      onWatch: own ? null : () => s.watchStream(userId),
      canWatch: canWatch,
      onStop: own
          ? null
          : () {
              _clearFocusIf(key);
              s.stopWatching(userId);
            },
      onToggleFullscreen: watching ? () => _toggleFocus(key) : null,
      muteKind: StreamKind.screenAudio,
      remoteId: userId,
      fullscreenPrefix: 'stream',
      watchKey: ValueKey('watch-stream-$userId'),
      stopKey: ValueKey('stop-watching-$userId'),
    );
  }

  Widget _ext(
    BuildContext context,
    ExternalStream stream, {
    bool focused = false,
  }) {
    final s = session;
    final watching = s.isWatchingStream(stream.streamId, external: true);
    final canWatch = s.canWatchStream(stream.streamId, external: true);
    final key = StreamKind.watchKey(stream.streamId, external: true);
    return _watchableCard(
      context,
      watching: watching,
      focused: focused,
      mediaKey: s.mediaKeyFor(
        remoteId: stream.streamId,
        kind: StreamKind.externalVideo,
      ),
      fit: BoxFit.contain,
      placeholder: stream.avatarUrl != null && stream.avatarUrl!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                stream.avatarUrl!,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.router, size: 48, color: context.p.muted),
              ),
            )
          : Icon(Icons.router, size: 48, color: context.p.muted),
      label: stream.title,
      onWatch: () => s.watchStream(stream.streamId, external: true),
      canWatch: canWatch,
      onStop: () {
        _clearFocusIf(key);
        s.stopWatching(stream.streamId, external: true);
      },
      onToggleFullscreen: watching ? () => _toggleFocus(key) : null,
      muteKind: StreamKind.externalAudio,
      remoteId: stream.streamId,
      fullscreenPrefix: 'stream-ext',
      watchKey: ValueKey('watch-stream-ext-${stream.streamId}'),
      stopKey: ValueKey('stop-watching-ext-${stream.streamId}'),
    );
  }

  Widget _watchableCard(
    BuildContext context, {
    required bool watching,
    required bool focused,
    required String mediaKey,
    required BoxFit fit,
    required Widget placeholder,
    required String label,
    required VoidCallback? onWatch,
    bool canWatch = false,
    required VoidCallback? onStop,
    required VoidCallback? onToggleFullscreen,
    required String muteKind,
    required int remoteId,
    required String fullscreenPrefix,
    required Key watchKey,
    required Key stopKey,
  }) {
    final s = session;
    final l = L10n.of(context);
    final phone =
        breakpointOf(MediaQuery.sizeOf(context).width) == Breakpoint.phone;
    final overlaySize = phone ? minTap : kCompactBtn;
    final mute = watching
        ? _streamMuteButton(context, s, remoteId, muteKind, overlaySize)
        : null;
    return Container(
      margin: focused ? EdgeInsets.zero : const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.p.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (watching)
            GestureDetector(
              onTap: phone && onToggleFullscreen != null
                  ? onToggleFullscreen
                  : null,
              behavior: HitTestBehavior.opaque,
              child: mediaStreamView(mediaKey: mediaKey, fit: fit),
            )
          else
            GestureDetector(
              onTap: onWatch,
              behavior: HitTestBehavior.opaque,
              child: Center(child: placeholder),
            ),
          Positioned(
            left: 8,
            top: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFED4245),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    l('live'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (watching) ...[
                  const SizedBox(height: 4),
                  _StreamStatsBadge(mediaKey: mediaKey, stacked: phone),
                ],
              ],
            ),
          ),
          if (!watching && onWatch != null)
            Center(
              child: Tooltip(
                message: canWatch ? l('watchStream') : l('missingPermission'),
                child: FilledButton(
                  key: watchKey,
                  onPressed: onWatch,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.k.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: context.p.card,
                    disabledForegroundColor: context.p.muted,
                  ),
                  child: Text(l('watchStream')),
                ),
              ),
            ),
          if (watching)
            Positioned(
              right: 8,
              top: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onToggleFullscreen != null)
                    CompactIconButton(
                      key: ValueKey(
                        focused
                            ? 'exit-fullscreen-$fullscreenPrefix-$remoteId'
                            : 'fullscreen-$fullscreenPrefix-$remoteId',
                      ),
                      tooltip: focused
                          ? l('exitFullscreen')
                          : l('fullscreenStream'),
                      icon: focused ? Icons.fullscreen_exit : Icons.fullscreen,
                      size: overlaySize,
                      onPressed: onToggleFullscreen,
                    ),
                  if (onStop != null)
                    CompactIconButton(
                      key: stopKey,
                      tooltip: l('stopWatching'),
                      icon: Icons.close,
                      size: overlaySize,
                      onPressed: onStop,
                    ),
                  if (mute != null) mute,
                ],
              ),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Text(
              label,
              style: TextStyle(
                color: context.p.foreground,
                shadows: watching
                    ? const [Shadow(blurRadius: 8, color: Colors.black)]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _streamMuteButton(
    BuildContext context,
    SessionController s,
    int remoteId,
    String kind,
    double size,
  ) {
    if (!s.hasStreamConsumer(remoteId, kind)) return null;
    final muted = s.isStreamMuted(remoteId, kind);
    final l = L10n.of(context);
    return CompactIconButton(
      tooltip: muted ? l('unmute') : l('mute'),
      icon: muted ? Icons.volume_off : Icons.volume_up,
      color: muted ? context.p.dnd : context.p.foreground,
      size: size,
      onPressed: () => s.toggleStreamMute(remoteId, kind),
    );
  }

  String _joinLabel(SessionController s, L10n l) {
    if (s.voiceState == 'connecting') return l('voiceConnecting');
    if (s.voiceState == 'failed') return l('voiceFailed');
    return l('joinVoice');
  }

  VoidCallback _screenSharePressed(
    BuildContext context,
    SessionController s,
    L10n l,
  ) {
    if (PlatformBridge.isIos) {
      return () {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l('screenShareIos'))));
      };
    }
    return () => s.toggleScreen();
  }

  Future<void> _showPhoneVoiceMore(
    BuildContext context,
    SessionController s,
    L10n l,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.p.sidebar,
      builder: (ctx) {
        Widget row({
          required Key key,
          required IconData icon,
          required String label,
          required VoidCallback onTap,
          Color? iconColor,
          bool active = false,
        }) {
          return ListTile(
            key: key,
            leading: Icon(icon, color: iconColor ?? ctx.p.foreground),
            title: Text(label, style: TextStyle(color: ctx.p.foreground)),
            trailing: active ? Icon(Icons.check, color: ctx.k.accent) : null,
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l('more'),
                    style: TextStyle(
                      color: ctx.p.foreground,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              row(
                key: const ValueKey('voice-ctrl-cam'),
                icon: s.webcam ? Icons.videocam : Icons.videocam_off,
                label: s.webcam ? l('cameraOff') : l('cameraOn'),
                active: s.webcam,
                onTap: s.toggleWebcam,
              ),
              row(
                key: const ValueKey('voice-ctrl-share'),
                icon: s.sharing ? Icons.stop_screen_share : Icons.screen_share,
                label: s.sharing ? l('stopShare') : l('shareScreen'),
                active: s.sharing,
                onTap: _screenSharePressed(context, s, l),
              ),
              row(
                key: const ValueKey('voice-ctrl-keep-awake'),
                icon: Icons.stay_current_portrait,
                iconColor: s.store.keepScreenOnVoice
                    ? ctx.k.accent
                    : ctx.p.foreground,
                label: l('keepScreenOnVoice'),
                active: s.store.keepScreenOnVoice,
                onTap: () => toggleKeepScreenOnVoice(context, s),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _controls(
    BuildContext context,
    SessionController s,
    L10n l,
    bool connected, {
    required bool phone,
  }) {
    if (phone) return _phoneControls(context, s, l, connected);
    return Container(
      color: context.p.rail,
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!connected)
            KurierButton(
              label: _joinLabel(s, l),
              onPressed: s.voiceState == 'connecting'
                  ? null
                  : () => s.joinVoice(channel.id),
            )
          else ...[
            if (s.store.ptt)
              GestureDetector(
                onLongPressStart: (_) => s.pttDown(),
                onLongPressEnd: (_) => s.pttUp(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: context.k.accent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    l('holdToTalk'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              )
            else
              IconButton(
                icon: Icon(
                  s.micMuted ? Icons.mic_off : Icons.mic,
                  color: s.micMuted ? context.p.dnd : context.p.foreground,
                ),
                onPressed: () => s.setMicMuted(!s.micMuted),
              ),
            IconButton(
              icon: Icon(
                s.soundMuted ? Icons.headset_off : Icons.headset,
                color: s.soundMuted ? context.p.dnd : context.p.foreground,
              ),
              onPressed: () => s.setSoundMuted(!s.soundMuted),
            ),
            IconButton(
              icon: Icon(
                s.webcam ? Icons.videocam : Icons.videocam_off,
                color: context.p.foreground,
              ),
              tooltip: s.canEnableWebcam() || s.webcam
                  ? null
                  : l('missingPermission'),
              onPressed: s.toggleWebcam,
            ),
            IconButton(
              icon: Icon(
                s.sharing ? Icons.stop_screen_share : Icons.screen_share,
                color: context.p.foreground,
              ),
              onPressed: _screenSharePressed(context, s, l),
            ),
            IconButton(
              key: const ValueKey('voice-ctrl-keep-awake'),
              icon: Icon(
                Icons.stay_current_portrait,
                color: s.store.keepScreenOnVoice
                    ? context.k.accent
                    : context.p.foreground,
              ),
              tooltip: l('keepScreenOnVoice'),
              onPressed: () => toggleKeepScreenOnVoice(context, s),
            ),
            CompactIconButton(
              icon: Icons.call_end,
              color: Colors.redAccent,
              onPressed: s.leaveVoice,
              tooltip: l('disconnectVoice'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _phoneControls(
    BuildContext context,
    SessionController s,
    L10n l,
    bool connected,
  ) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final child = !connected
        ? SizedBox(
            width: double.infinity,
            height: kVoiceJoinHeight,
            child: FilledButton(
              key: const ValueKey('join-voice'),
              onPressed: s.voiceState == 'connecting'
                  ? null
                  : () => s.joinVoice(channel.id),
              style: FilledButton.styleFrom(
                backgroundColor: context.p.online,
                disabledBackgroundColor: context.p.card,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, kVoiceJoinHeight),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                visualDensity: VisualDensity.standard,
                tapTargetSize: MaterialTapTargetSize.padded,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(_joinLabel(s, l)),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              if (s.store.ptt)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onLongPressStart: (_) => s.pttDown(),
                      onLongPressEnd: (_) => s.pttUp(),
                      child: Container(
                        height: kVoiceCtrlBtn,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.k.accent,
                          borderRadius: BorderRadius.circular(
                            kVoiceCtrlBtn / 2,
                          ),
                        ),
                        child: Text(
                          l('holdToTalk'),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                )
              else
                _VoiceRoundButton(
                  key: const ValueKey('voice-ctrl-mic'),
                  icon: s.micMuted ? Icons.mic_off : Icons.mic,
                  iconColor: s.micMuted ? context.p.dnd : context.p.foreground,
                  tooltip: s.micMuted ? l('unmute') : l('mute'),
                  onPressed: () => s.setMicMuted(!s.micMuted),
                ),
              _VoiceRoundButton(
                key: const ValueKey('voice-ctrl-deafen'),
                icon: s.soundMuted ? Icons.headset_off : Icons.headset,
                iconColor: s.soundMuted ? context.p.dnd : context.p.foreground,
                onPressed: () => s.setSoundMuted(!s.soundMuted),
              ),
              _VoiceOutputControl(session: s),
              _VoiceRoundButton(
                key: const ValueKey('voice-ctrl-more'),
                icon: Icons.more_horiz,
                iconColor: s.webcam || s.sharing || s.store.keepScreenOnVoice
                    ? context.k.accent
                    : context.p.foreground,
                tooltip: l('more'),
                onPressed: () => _showPhoneVoiceMore(context, s, l),
              ),
              _VoiceRoundButton(
                key: const ValueKey('voice-ctrl-leave'),
                icon: Icons.call_end,
                iconColor: Colors.white,
                background: context.p.dnd,
                tooltip: l('disconnectVoice'),
                onPressed: s.leaveVoice,
              ),
            ],
          );
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomInset),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.p.rail,
          borderRadius: BorderRadius.circular(kVoiceBarRadius),
        ),
        child: child,
      ),
    );
  }
}

class _VoiceOutputControl extends StatefulWidget {
  const _VoiceOutputControl({required this.session, this.compact = false});

  final SessionController session;
  final bool compact;

  @override
  State<_VoiceOutputControl> createState() => _VoiceOutputControlState();
}

class _VoiceOutputControlState extends State<_VoiceOutputControl> {
  ClassifiedAudioOutputs _classified = const ClassifiedAudioOutputs();
  int _deviceEpoch = 0;

  SessionController get session => widget.session;

  bool get _usesMicRoute =>
      PlatformBridge.isIos && !PlatformBridge.canSetOutputDevice;

  String? get _currentId =>
      _usesMicRoute ? session.store.micDevice : session.speakerOutputId;

  @override
  void initState() {
    super.initState();
    _deviceEpoch = session.audioDevicesEpoch;
    session.addListener(_onSession);
    _refreshDevices();
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    super.dispose();
  }

  @override
  void didUpdateWidget(_VoiceOutputControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_onSession);
      widget.session.addListener(_onSession);
    }
  }

  void _onSession() {
    if (session.audioDevicesEpoch == _deviceEpoch) return;
    _deviceEpoch = session.audioDevicesEpoch;
    _refreshDevices();
  }

  Future<ClassifiedAudioOutputs> _refreshDevices() async {
    final list = await PlatformBridge.enumerate();
    final classified = _usesMicRoute
        ? classifyAudioInputsForOutput(list)
        : classifyAudioOutputs(list);
    final current = _currentId;
    if (current != null &&
        classified.externals.any((d) => d.deviceId == current)) {
      session.lastExternalOutputId = current;
    }
    if (mounted) setState(() => _classified = classified);
    return classified;
  }

  AudioOutputRoute get _route => audioOutputRoute(_currentId, _classified);

  IconData get _icon => _iconForRoute(_route);

  void _snack(BuildContext context, String key) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(L10n.of(context)(key))));
  }

  Future<void> _apply(String? id, ClassifiedAudioOutputs classified) async {
    if (id != null &&
        !isDefaultAudioOutputId(id) &&
        classified.externals.any((d) => d.deviceId == id)) {
      session.lastExternalOutputId = id;
    }
    if (_usesMicRoute) {
      await session.applyMicForOutput(id);
      return;
    }
    await session.applySpeakerDevice(id);
  }

  Future<void> _onTap() async {
    if (!mounted) return;
    if (!PlatformBridge.canSetOutputDevice && !_usesMicRoute) {
      _snack(context, 'audioOutputIos');
      return;
    }
    var classified = _classified;
    if (classified.realDevices.isEmpty) {
      classified = await _refreshDevices();
      if (!mounted) return;
    }
    if (_usesMicRoute && classified.realDevices.isEmpty) {
      _snack(context, 'audioOutputIos');
      return;
    }
    final result = nextAudioOutput(
      currentId: _currentId,
      classified: classified,
      lastExternalId: session.lastExternalOutputId,
    );
    switch (result.kind) {
      case AudioOutputToggle.toDevice:
        try {
          await _apply(result.deviceId, classified);
        } catch (_) {
          if (mounted) _snack(context, 'audioOutputFailed');
        }
      case AudioOutputToggle.noOtherDevices:
        _snack(context, 'noOtherAudioDevices');
      case AudioOutputToggle.pickDevice:
        await _showPicker(classified);
    }
    unawaited(_refreshDevices());
  }

  Future<void> _onLongPress() async {
    if (!mounted) return;
    if (!PlatformBridge.canSetOutputDevice && !_usesMicRoute) {
      _snack(context, 'audioOutputIos');
      return;
    }
    final classified = await _refreshDevices();
    if (!mounted) return;
    if (_usesMicRoute && classified.realDevices.isEmpty) {
      _snack(context, 'audioOutputIos');
      return;
    }
    await _showPicker(classified);
  }

  bool _isCurrentDevice(String deviceId, String current) {
    if (isDefaultAudioOutputId(deviceId)) {
      return isDefaultAudioOutputId(current);
    }
    return deviceId == current;
  }

  String _deviceLabel(L10n l, MediaDeviceInfo d) {
    if (d.label.isNotEmpty) return d.label;
    if (isDefaultAudioOutputId(d.deviceId)) return l('bluetoothAudio');
    return d.deviceId;
  }

  Future<void> _showPicker(ClassifiedAudioOutputs classified) async {
    final devices = classified.realDevices;
    if (devices.isEmpty) {
      _snack(context, 'noOtherAudioDevices');
      return;
    }
    final l = L10n.of(context);
    final current = _currentId ?? '';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.p.sidebar,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l('switchAudioOutput'),
                  style: TextStyle(
                    color: ctx.p.foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final d in devices)
                ListTile(
                  leading: Icon(
                    _iconForRoute(audioOutputRoute(d.deviceId, classified)),
                    color: _isCurrentDevice(d.deviceId, current)
                        ? ctx.k.accent
                        : ctx.p.foreground,
                  ),
                  title: Text(
                    _deviceLabel(l, d),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ctx.p.foreground),
                  ),
                  trailing: _isCurrentDevice(d.deviceId, current)
                      ? Icon(Icons.check, color: ctx.k.accent)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await _apply(d.deviceId, classified);
                    } catch (_) {
                      if (mounted) _snack(context, 'audioOutputFailed');
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  String _tooltip(L10n l) {
    switch (_route) {
      case AudioOutputRoute.speaker:
        return l('speakerPhone');
      case AudioOutputRoute.bluetooth:
        return l('bluetoothAudio');
      case AudioOutputRoute.unknown:
        return l('switchAudioOutput');
    }
  }

  IconData _iconForRoute(AudioOutputRoute route) {
    switch (route) {
      case AudioOutputRoute.speaker:
        return Icons.volume_up;
      case AudioOutputRoute.bluetooth:
        return Icons.bluetooth_audio;
      case AudioOutputRoute.unknown:
        return Icons.volume_up;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    if (widget.compact) {
      return GestureDetector(
        onLongPress: _onLongPress,
        child: CompactIconButton(
          key: const ValueKey('compact-voice-output'),
          tooltip: _tooltip(l),
          icon: _icon,
          onPressed: _onTap,
        ),
      );
    }
    return _VoiceRoundButton(
      key: const ValueKey('voice-ctrl-output'),
      icon: _icon,
      tooltip: _tooltip(l),
      onPressed: _onTap,
      onLongPress: _onLongPress,
    );
  }
}

class _VoiceRoundButton extends StatelessWidget {
  const _VoiceRoundButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.onLongPress,
    this.tooltip,
    this.iconColor,
    this.background,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final String? tooltip;
  final Color? iconColor;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    Widget button = Material(
      color: background ?? context.p.background,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        onLongPress: onLongPress,
        child: SizedBox(
          width: kVoiceCtrlBtn,
          height: kVoiceCtrlBtn,
          child: Icon(
            icon,
            size: kVoiceCtrlIcon,
            color: iconColor ?? context.p.foreground,
          ),
        ),
      ),
    );
    if (onPressed == null) {
      button = Opacity(opacity: 0.4, child: button);
    }
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class _StreamStatsBadge extends StatefulWidget {
  const _StreamStatsBadge({required this.mediaKey, required this.stacked});

  final String mediaKey;
  final bool stacked;

  @override
  State<_StreamStatsBadge> createState() => _StreamStatsBadgeState();
}

class _StreamStatsBadgeState extends State<_StreamStatsBadge> {
  MediaStats _stats = const MediaStats();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  @override
  void didUpdateWidget(_StreamStatsBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaKey != widget.mediaKey) {
      _stats = const MediaStats();
      _tick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    final stats = await PlatformBridge.getMediaStats(widget.mediaKey);
    if (!mounted) return;
    setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    final fps = Text(
      '${_stats.fps.round()} FPS',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        shadows: [Shadow(blurRadius: 8, color: Colors.black)],
      ),
    );
    final bandwidth = Text(
      _formatBandwidth(_stats.bytesPerSec),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w600,
        shadows: [Shadow(blurRadius: 8, color: Colors.black)],
      ),
    );
    return Container(
      key: ValueKey('stream-stats-${widget.mediaKey}'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
      ),
      child: widget.stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [fps, bandwidth],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [fps, const SizedBox(width: 8), bandwidth],
            ),
    );
  }
}

String _formatBandwidth(double bytesPerSec) {
  final mb = bytesPerSec / 1e6;
  if (mb < 0.1) {
    return '${(bytesPerSec / 1e3).round()} KB/s';
  }
  return '${mb.toStringAsFixed(1)} MB/s';
}

class VoiceControlBar extends StatelessWidget {
  const VoiceControlBar({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final l = L10n.of(context);
    final id = s.connectedVoiceChannelId;
    if (id == null &&
        s.voiceState != 'connecting' &&
        s.voiceState != 'failed') {
      return const SizedBox.shrink();
    }
    Color statusColor;
    String statusText;
    IconData statusIcon;
    switch (s.voiceState) {
      case 'connecting':
        statusColor = const Color(0xFFF0B232);
        statusText = l('voiceConnecting');
        statusIcon = Icons.wifi_find;
      case 'failed':
        statusColor = context.p.dnd;
        statusText = l('voiceFailed');
        statusIcon = Icons.wifi_off;
      default:
        statusColor = const Color(0xFF23A55A);
        statusText = l('voiceConnected');
        statusIcon = Icons.wifi;
    }
    final rtt = s.voiceRttMs;
    final showShare = !PlatformBridge.isIos && PlatformBridge.canShareScreen;
    final voiceErrorText = s.voiceError == missingPermissionKey
        ? l('missingPermission')
        : s.voiceError == micUnavailableKey
        ? l('micUnavailable')
        : s.voiceError;
    return Container(
      decoration: BoxDecoration(
        color: context.p.card.withValues(alpha: 0.3),
        border: Border(top: BorderSide(color: context.p.divider)),
      ),
      child: Column(
        children: [
          GestureDetector(
            key: const ValueKey('voice-control-status'),
            onTap: () {
              if (id != null && s.selectedChannelId != id) {
                s.returnToVoiceChannel();
                return;
              }
              showTransportStatsPopover(context: context, session: s);
            },
            child: Container(
              color: context.p.card.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      statusText,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (s.voiceState == 'connected' && rtt != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      l('pingMs', {'ms': '$rtt'}),
                      style: TextStyle(
                        color: voicePingColor(rtt),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Flexible(
                  child: SizedBox(
                    height: 32,
                    child: OutlinedButton.icon(
                      onPressed: s.leaveVoice,
                      icon: const Icon(
                        Icons.call_end,
                        size: 14,
                        color: Colors.redAccent,
                      ),
                      label: Text(
                        l('disconnectVoice'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.redAccent,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        side: const BorderSide(color: Colors.redAccent),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _VoiceMediaButton(
                  tooltip: s.webcam
                      ? l('cameraOff')
                      : (s.canEnableWebcam()
                            ? l('cameraOn')
                            : l('missingPermission')),
                  icon: s.webcam ? Icons.videocam : Icons.videocam_off,
                  active: s.webcam,
                  activeColor: const Color(0xFF4ADE80),
                  onPressed: () => s.toggleWebcam(),
                ),
                if (showShare) ...[
                  const SizedBox(width: 4),
                  _VoiceMediaButton(
                    tooltip: s.sharing
                        ? l('stopShare')
                        : (s.canShareScreen()
                              ? l('shareScreen')
                              : l('missingPermission')),
                    icon: s.sharing
                        ? Icons.stop_screen_share
                        : Icons.screen_share,
                    active: s.sharing,
                    activeColor: const Color(0xFF60A5FA),
                    onPressed: () => s.toggleScreen(),
                  ),
                ],
              ],
            ),
          ),
          if (voiceErrorText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                voiceErrorText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.p.dnd, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoiceMediaButton extends StatelessWidget {
  const _VoiceMediaButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    required this.active,
    required this.activeColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool active;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? activeColor.withValues(alpha: 0.15) : context.p.card,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(
              icon,
              size: 16,
              color: onPressed == null
                  ? context.p.faint
                  : (active ? activeColor : context.p.muted),
            ),
          ),
        ),
      ),
    );
  }
}

class CompactVoiceBar extends StatelessWidget {
  const CompactVoiceBar({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final l = L10n.of(context);
    final ch = s.channels[s.connectedVoiceChannelId];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (s.voiceAudioLocked) _TapToEnableAudioBanner(session: s),
        Material(
          color: const Color(0xFF23A55A).withValues(alpha: 0.18),
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.volume_up,
                    color: Color(0xFF23A55A),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: l('returnToVoice'),
                      child: GestureDetector(
                        key: const ValueKey('return-to-voice'),
                        behavior: HitTestBehavior.opaque,
                        onTap: s.returnToVoiceChannel,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    l('voiceConnected'),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF23A55A),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (s.voiceRttMs != null) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    l('pingMs', {'ms': '${s.voiceRttMs}'}),
                                    style: TextStyle(
                                      color: voicePingColor(s.voiceRttMs!),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              ch?.name ?? '',
                              style: TextStyle(
                                color: context.p.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _VoiceOutputControl(session: s, compact: true),
                  CompactIconButton(
                    key: const ValueKey('compact-voice-keep-awake'),
                    tooltip: l('keepScreenOnVoice'),
                    icon: Icons.stay_current_portrait,
                    color: s.store.keepScreenOnVoice ? context.k.accent : null,
                    onPressed: () => toggleKeepScreenOnVoice(context, s),
                  ),
                  CompactIconButton(
                    key: const ValueKey('compact-voice-stats'),
                    tooltip: l('transportStats'),
                    icon: Icons.info_outline,
                    onPressed: () =>
                        showTransportStatsPopover(context: context, session: s),
                  ),
                  CompactIconButton(
                    tooltip: l('disconnectVoice'),
                    icon: Icons.call_end,
                    color: Colors.redAccent,
                    onPressed: s.leaveVoice,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TapToEnableAudioBanner extends StatelessWidget {
  const _TapToEnableAudioBanner({required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Material(
      color: const Color(0xFFF0B232),
      child: InkWell(
        onTap: session.enableVoiceAudio,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.volume_up, color: Color(0xFF1E1F22), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l('tapToEnableAudio'),
                  style: const TextStyle(
                    color: Color(0xFF1E1F22),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
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

class MusicBotSheet extends StatefulWidget {
  const MusicBotSheet({super.key, required this.session});
  final SessionController session;
  @override
  State<MusicBotSheet> createState() => _MusicBotSheetState();
}

class _MusicBotSheetState extends State<MusicBotSheet> {
  final q = TextEditingController();
  String current = '';
  List<String> queue = [];
  bool loading = false;

  Future<void> _refresh() async {
    setState(() => loading = true);
    try {
      final raw = await widget.session.musicAction('getPlayerState');
      if (raw is Map) {
        current = '${raw['currentSong'] ?? ''}';
        final qlist = raw['queue'];
        if (qlist is List) {
          queue = qlist.map((e) => '$e').toList();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final s = widget.session;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l('musicBot'),
            style: TextStyle(color: context.p.foreground, fontSize: 18),
          ),
          if (s.connectedVoiceChannelId == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                l('joinVoiceHint'),
                style: TextStyle(color: context.p.muted),
              ),
            )
          else ...[
            Text(
              current.isEmpty ? l('nothingPlaying') : current,
              style: TextStyle(color: context.p.foreground),
            ),
            KurierField(controller: q, hint: 'YouTube'),
            Row(
              children: [
                KurierButton(
                  label: l('play'),
                  onPressed: () async {
                    await s.musicAction('play', {'query': q.text});
                    await _refresh();
                  },
                ),
                const SizedBox(width: 8),
                KurierButton(
                  label: l('next'),
                  primary: false,
                  onPressed: () async {
                    await s.musicAction('skip');
                    await _refresh();
                  },
                ),
                const SizedBox(width: 8),
                KurierButton(
                  label: l('stop'),
                  danger: true,
                  onPressed: () async {
                    await s.musicAction('stop');
                    await _refresh();
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

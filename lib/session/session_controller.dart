import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Offset;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../app/breakpoints.dart';
import '../app/app_platform.dart';
import '../app/client_kind.dart';
import '../core/custom_emoji.dart';
import '../core/emoji_codec.dart';
import '../core/emoji_recent.dart';
import '../core/gif_search.dart';
import '../core/klipy_discover.dart';
import '../core/quick_reactions.dart';
import '../protocol/activity_log.dart';
import '../protocol/audio_output.dart';
import '../protocol/config.dart';
import '../protocol/http_api.dart';
import '../protocol/mentions.dart';
import '../protocol/models.dart';
import '../protocol/permissions.dart';
import '../protocol/platform.dart';
import '../protocol/presence.dart';
import '../protocol/search_query.dart';
import '../protocol/sounds.dart';
import '../protocol/trpc_client.dart';
import '../protocol/voice_protocol.dart';
import '../protocol/voice_stats.dart';
import '../native/android_runtime.dart';
import '../native/push_kind.dart';
import 'hosts_store.dart';
import 'message_history.dart';

enum SessionPhase { boot, login, connecting, ready, disconnected }

bool isFatalDisconnectCode(int code) =>
    code == 40000 || code == 40001 || code == 40002 || code == 40003;

class TypingUser {
  TypingUser(this.userId, this.until);
  final int userId;
  DateTime until;
}

class SessionController extends ChangeNotifier {
  final store = HostsStore();
  final logs = <String>[];

  /// Test seam for [getUserInfo] when no tRPC client is connected.
  UserAdminInfo? Function(int userId)? userInfoOverride;

  SessionPhase phase = SessionPhase.boot;
  List<SavedHost> hosts = [];
  String? activeHost;
  String? token;
  String? error;
  int? disconnectCode;
  String disconnectReason = '';
  bool needsServerPassword = false;
  bool showWelcome = false;
  ServerInfo? info;
  bool probing = false;
  String? pendingInvite;

  HttpApi? httpApi;
  TrpcClient? trpc;

  /// KLIPY key from this host's join payload or vanilla web client.
  String? serverKlipyKey;
  Future<void>? _klipyDiscover;

  JoinPayload? join;
  final users = <int, KurierUser>{};
  final channels = <int, KurierChannel>{};
  final categories = <int, KurierCategory>{};
  final roles = <int, KurierRole>{};
  final emojis = <int, KurierEmoji>{};
  Map<String, ChannelPerms> channelPerms = {};
  Map<int, int> readStates = {};
  Map<int, String> notificationOverrides = {};
  Map<String, dynamic> publicSettings = {};
  Map<int, Map<int, VoiceUserState>> voiceMap = {};
  Map<int, int?> occupiedSince = {};
  Map<int, List<ExternalStream>> externalStreams = {};
  List<dynamic> pluginsMetadata = [];
  List<dynamic> pluginCommands = [];
  int ownUserId = 0;
  String serverName = '';
  String serverId = '';

  int? selectedChannelId;
  int? lastTextChannelId;
  bool showingDms = false;
  bool membersOpen = true;
  double sidebarWidth = kSidebarWidth;
  double membersWidth = kSidebarWidth;
  Timer? _panelWidthSave;
  final collapsedCategories = <int>{};
  List<DmConversation> dms = [];
  final messages = <int, List<KurierMessage>>{};
  final nextCursor = <int, MessagesCursor?>{};
  final loadingMessages = <int, bool>{};
  final fetchingMessages = <int, bool>{};
  final detachedChannels = <int>{};
  int? jumpTargetChannelId;
  int? jumpTargetMessageId;
  KurierMessage? replyTo;
  int? threadParentId;
  List<KurierMessage> threadMessages = [];
  List<KurierMessage> pinned = [];
  bool loadingPinned = false;
  final typing = <int, List<TypingUser>>{};
  Timer? _typingSweep;
  DateTime? _lastTyped;
  bool _manualAway = false;
  bool _focused = true;
  Timer? _focusAwayTimer;

  /// Delay before unfocus reports Away. Tests may set this to [Duration.zero].
  @visibleForTesting
  Duration focusAwayDebounce = presenceFocusAwayDebounce;

  void refresh() => notifyListeners();

  int? connectedVoiceChannelId;
  bool micMuted = false;
  bool soundMuted = false;
  bool webcam = false;
  bool sharing = false;
  String voiceState = 'idle';
  String? voiceError;
  int? voiceRttMs;
  TransportStatsData transportStats = TransportStatsData.empty;
  Timer? _voiceStatsTimer;
  final _producerResyncs = <Timer>[];
  Completer<void>? _recvConnected;
  Map<String, dynamic>? rtpCapabilities;
  String? sendTransportId;
  final consumerKeys = <String, String>{};
  final volumes = <String, double>{};
  final localUserVolumes = <int, double>{};
  final speaking = <int, int>{};
  final watchingStreams = <String>{};
  String _sendConnState = '';
  String _recvConnState = '';
  Timer? _iceDisconnectedSend;
  Timer? _iceDisconnectedRecv;
  DateTime? _voiceConnectedAt;
  String? appliedSpeakerDevice;
  String? lastExternalOutputId;
  int audioDevicesEpoch = 0;
  DateTime? _playbackDeadSince;
  bool _didLightPlaybackRecovery = false;
  bool _silentRejoining = false;
  bool _checkingPlayback = false;
  bool voiceAudioLocked = false;
  bool _closingByUser = false;
  bool _recovering = false;
  int _recoverAttempts = 0;
  Timer? _recoverTimer;
  DateTime? _ignoreOwnVoiceLeaveUntil;
  final _autoRejoinAt = <DateTime>[];

  bool get simulcastEnabled => asBool(publicSettings['webRtcSimulcastEnabled']);

  bool searchOpen = false;
  String searchQuery = '';
  List<KurierMessage> searchMessages = [];
  List<KurierFile> searchFiles = [];
  bool searching = false;

  List<KurierMessage> mentionMessages = [];
  bool loadingMentions = false;
  bool mentionsLoaded = false;
  final unreadMentionIds = <int>{};
  int get unreadMentionCount => unreadMentionIds.length;

  String?
  overlay; // 'userSettings' | 'serverSettings' | 'channelSettings' | 'search' | 'welcome'
  String settingsTab = 'profile';
  int? settingsChannelId;
  KurierUser? profileUser;
  Offset? profileAnchor;

  String themePreset = 'dark';
  String accent = '#5865F2';
  String locale = 'en';

  final _subs = <StreamSubscription>[];
  bool _msBound = false;

  Future<void> boot() async {
    await store.load();
    EmojiRecent.store = store;
    QuickReactions.store = store;
    hosts = store.hosts();
    themePreset = store.preset;
    accent = store.accent;
    locale = store.locale;
    collapsedCategories
      ..clear()
      ..addAll(store.collapsedCats());
    sidebarWidth = store.sidebarWidth;
    membersWidth = store.membersWidth;
    pendingInvite = Uri.base.queryParameters['invite'];
    onVoiceNotificationAction = handleNotificationAction;
    onAndroidNotificationOpened = (link) {
      if (phase != SessionPhase.ready || link.channelId == null) return;
      takePendingDeepLink();
      unawaited(jumpToMessage(link.channelId!, link.messageId ?? 0));
    };
    onAndroidMarkRead = (channelId) async {
      readStates[channelId] = 0;
      final dm = dms.where((d) => d.channelId == channelId).firstOrNull;
      if (dm != null) dm.unreadCount = 0;
      notifyListeners();
      try {
        await trpc?.mutate('channels.markAsRead', {'channelId': channelId});
      } catch (_) {}
    };
    await _ensureDefaultHost();
    if (isNativeMobile && activeHost == null) {
      phase = SessionPhase.login;
      notifyListeners();
      return;
    }
    final saved = hosts.where((h) => h.host == activeHost).firstOrNull;
    final savedToken = saved?.token;
    if (savedToken != null && savedToken.isNotEmpty) {
      await probeActive();
      await connect(host: saved!.host, existingToken: savedToken);
      return;
    }
    phase = SessionPhase.login;
    notifyListeners();
    await probeActive();
  }

  bool _isLoopback(String host) {
    final h = host.split(':').first;
    return h.isEmpty || h == 'localhost' || h == '127.0.0.1';
  }

  Future<void> _ensureDefaultHost() async {
    if (isNativeMobile) {
      final saved = store.defaultHost;
      if (saved != null && hosts.any((h) => h.host == saved)) {
        activeHost = saved;
      } else {
        activeHost = null;
        if (saved != null) await store.setDefaultHost(null);
      }
      return;
    }
    final pageHost = Uri.base.host;
    final fromPage = !_isLoopback(pageHost);
    final target = fromPage ? pageHost : AppConfig.defaultHost;
    if (hosts.every((h) => h.host != target)) {
      hosts = [SavedHost(host: target, name: target), ...hosts];
      await store.saveHosts(hosts);
    }
    activeHost = store.activeHost ?? target;
    if (activeHost == null ||
        (_isLoopback(activeHost!) && !_isLoopback(target))) {
      activeHost = target;
      await store.setActiveHost(target);
    }
  }

  Future<void> probeActive() async {
    final host = activeHost;
    if (host == null) return;
    probing = true;
    notifyListeners();
    try {
      httpApi = HttpApi(originOf(host));
      info = await httpApi!.info();
      final idx = hosts.indexWhere((h) => h.host == host);
      if (idx >= 0 && info!.name.isNotEmpty) {
        hosts[idx].name = info!.name;
        await store.saveHosts(hosts);
      }
    } catch (e) {
      info = null;
      _log('info: $e');
    }
    probing = false;
    notifyListeners();
  }

  String originOf(String host) {
    final page = Uri.base;
    final normalized = host
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'/$'), '');
    if (normalized == page.host || normalized == page.authority) {
      return page.origin;
    }
    if (host.startsWith('http://') || host.startsWith('https://')) {
      return host.replaceAll(RegExp(r'/$'), '');
    }
    if (normalized.startsWith('localhost') ||
        normalized.startsWith('127.0.0.1')) {
      return 'http://$normalized';
    }
    return 'https://$normalized';
  }

  Future<void> addHost(String raw) async {
    var host = raw.trim();
    host = host.replaceFirst(RegExp(r'^https?://'), '');
    host = host.split('/').first;
    if (host.isEmpty) return;
    if (hosts.any((h) => h.host == host)) {
      activeHost = host;
      notifyListeners();
      return;
    }
    final first = hosts.isEmpty;
    hosts = [...hosts, SavedHost(host: host, name: host)];
    activeHost = host;
    await store.saveHosts(hosts);
    await store.setActiveHost(host);
    if (isNativeMobile && (first || store.defaultHost == null)) {
      await store.setDefaultHost(host);
    }
    notifyListeners();
    await probeActive();
  }

  Future<void> removeHost(String host) async {
    hosts = hosts.where((h) => h.host != host).toList();
    await store.saveHosts(hosts);
    if (activeHost == host) {
      if (isNativeMobile) {
        activeHost = null;
        await store.setActiveHost(null);
      } else {
        activeHost = hosts.isEmpty ? null : hosts.first.host;
        await store.setActiveHost(activeHost);
      }
    }
    if (store.defaultHost == host) {
      await store.setDefaultHost(null);
    }
    notifyListeners();
  }

  Future<void> setDefaultHost(String host) async {
    await store.setDefaultHost(host);
    notifyListeners();
  }

  Future<void> switchHost(String host) async {
    if (host == activeHost && phase == SessionPhase.ready) return;
    await disconnect(forgetToken: false);
    activeHost = host;
    await store.setActiveHost(host);
    await probeActive();
    final saved = hosts.where((h) => h.host == host).firstOrNull;
    final savedToken = saved?.token;
    if (savedToken != null && savedToken.isNotEmpty) {
      await connect(host: host, existingToken: savedToken);
      return;
    }
    phase = SessionPhase.login;
    notifyListeners();
  }

  Future<ServerInfo?> probe(String host) async {
    try {
      return await HttpApi(originOf(host)).info();
    } catch (_) {
      return null;
    }
  }

  Future<void> login({
    required String identity,
    required String password,
    String? invite,
    bool autoLogin = true,
    String? serverPassword,
  }) async {
    final host = activeHost;
    if (host == null) {
      error = 'No host';
      notifyListeners();
      return;
    }
    error = null;
    phase = SessionPhase.connecting;
    notifyListeners();
    try {
      httpApi = HttpApi(originOf(host));
      final t = await httpApi!.login(
        identity: identity,
        password: password,
        invite: invite ?? pendingInvite,
        deviceToken: store.deviceToken(),
      );
      await _persistToken(host, t, autoLogin);
      await connect(
        host: host,
        existingToken: t,
        serverPassword: serverPassword,
      );
    } catch (e) {
      error = '$e';
      phase = SessionPhase.login;
      notifyListeners();
    }
  }

  Future<void> connect({
    required String host,
    required String existingToken,
    String? serverPassword,
  }) async {
    error = null;
    phase = SessionPhase.connecting;
    overlay = null;
    profileUser = null;
    profileAnchor = null;
    token = existingToken;
    activeHost = host;
    httpApi = HttpApi(originOf(host));
    _klipyDiscover = null;
    serverKlipyKey = hosts.where((h) => h.host == host).firstOrNull?.klipy;
    _recoverTimer?.cancel();
    _recovering = false;
    _recoverAttempts = 0;
    notifyListeners();
    try {
      await trpc?.close(silent: true);
      trpc = TrpcClient(
        url: trpcWsUrl(originOf(host)),
        connectionParams: () => {
          'token': token ?? '',
          'deviceToken': store.deviceToken(),
          'client': kurierClientKind(),
        },
      );
      _attachTrpcClose(trpc!);
      await trpc!.connect();
      final handshake = await trpc!.query('others.handshake');
      final hs = handshake is Map ? Map<String, dynamic>.from(handshake) : {};
      needsServerPassword = asBool(hs['hasPassword']);
      if (needsServerPassword &&
          (serverPassword == null || serverPassword.isEmpty)) {
        phase = SessionPhase.login;
        notifyListeners();
        return;
      }
      final raw = await trpc!.query('others.joinServer', {
        'handshakeHash': hs['handshakeHash'],
        if (serverPassword != null) 'password': serverPassword,
      });
      final rawMap = Map<String, dynamic>.from(raw as Map);
      join = JoinPayload.fromJson(rawMap);
      _applyJoin(join!);
      await _adoptServerKlipy(rawMap);
      await _subscribeAll();
      try {
        dms = ((await trpc!.query('dms.get')) as List)
            .whereType<Map>()
            .map((e) => DmConversation.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {
        dms = [];
      }
      phase = SessionPhase.ready;
      final last = store.lastChannel(host);
      final lastChannel = last == null ? null : channels[last];
      if (store.autoJoin &&
          lastChannel != null &&
          canViewChannel(lastChannel)) {
        await selectChannel(lastChannel.id);
      } else {
        final firstText =
            channels.values
                .where((c) => c.isText && !c.isDm && canViewChannel(c))
                .toList()
              ..sort((a, b) => a.position.compareTo(b.position));
        if (firstText.isNotEmpty) await selectChannel(firstText.first.id);
      }
      if (showWelcome) overlay = 'welcome';
      _log('joined $serverName');
      final remotePrefs = await androidLoadPrefs(trpc: trpc);
      if (remotePrefs != null) {
        await store.applyNotifyPrefs(
          notifyAll: remotePrefs.notifyAll,
          mentions: remotePrefs.mentions,
          dm: remotePrefs.dm,
          replies: remotePrefs.replies,
        );
      }
      await androidOnLogin(
        trpc: trpc,
        origin: originOf(host),
        jwt: token ?? existingToken,
      );
      final link = takePendingDeepLink();
      if (link?.channelId != null) {
        await jumpToMessage(link!.channelId!, link.messageId ?? 0);
      }
      notifyListeners();
    } catch (e) {
      error = '$e';
      phase = SessionPhase.login;
      _log('connect: $e');
      unawaited(androidStopKeepAlive());
      notifyListeners();
    }
  }

  void _attachTrpcClose(TrpcClient client) {
    client.onClose = (code, reason) {
      if (_closingByUser || _recovering) return;
      if (phase != SessionPhase.ready) return;
      unawaited(_onSocketClosed(code, reason));
    };
  }

  Future<void> _onSocketClosed(int code, String reason) async {
    if (isFatalDisconnectCode(code)) {
      _goDisconnected(code, reason);
      return;
    }
    await _recoverConnection(code, reason);
  }

  void _goDisconnected(int code, String reason) {
    _recoverTimer?.cancel();
    _recovering = false;
    unawaited(androidStopKeepAlive());
    if (!_closingByUser) {
      PlatformBridge.playSound(KurierSoundType.serverDisconnected);
    }
    disconnectCode = code;
    disconnectReason = reason;
    overlay = null;
    profileUser = null;
    profileAnchor = null;
    phase = SessionPhase.disconnected;
    notifyListeners();
  }

  Future<void> _recoverConnection(int code, String reason) async {
    final host = activeHost;
    final existingToken = token;
    if (host == null || existingToken == null || existingToken.isEmpty) {
      _goDisconnected(code, reason);
      return;
    }
    if (_recovering) return;
    _recovering = true;
    _recoverAttempts++;
    _log('socket closed ($code), reconnecting attempt $_recoverAttempts');
    final voiceId = connectedVoiceChannelId;
    try {
      await trpc?.close(silent: true);
      trpc = TrpcClient(
        url: trpcWsUrl(originOf(host)),
        connectionParams: () => {
          'token': token ?? '',
          'deviceToken': store.deviceToken(),
          'client': kurierClientKind(),
        },
      );
      _attachTrpcClose(trpc!);
      await trpc!.connect().timeout(const Duration(seconds: 15));
      final handshake = await trpc!.query('others.handshake');
      final hs = handshake is Map ? Map<String, dynamic>.from(handshake) : {};
      final raw = await trpc!.query('others.joinServer', {
        'handshakeHash': hs['handshakeHash'],
      });
      final rawMap = Map<String, dynamic>.from(raw as Map);
      join = JoinPayload.fromJson(rawMap);
      _applyJoin(join!);
      await _subscribeAll();
      await androidOnLogin(
        trpc: trpc,
        origin: originOf(host),
        jwt: existingToken,
      );
      if (isNativeMobile && voiceId != null) {
        unawaited(
          androidSyncKeepAlive(
            serverName: serverName.isEmpty ? 'Kurier' : serverName,
            voiceChannelName: channels[voiceId]?.name,
          ),
        );
      }
      _recoverAttempts = 0;
      _recovering = false;
      if (voiceId != null) {
        connectedVoiceChannelId = voiceId;
        unawaited(_silentRejoinVoice());
      }
      notifyListeners();
    } catch (e) {
      _log('reconnect: $e');
      _recovering = false;
      if (_recoverAttempts >= 8) {
        _goDisconnected(code, reason);
        return;
      }
      final shift = (_recoverAttempts.clamp(1, 6)) - 1;
      _recoverTimer?.cancel();
      _recoverTimer = Timer(Duration(milliseconds: 500 * (1 << shift)), () {
        unawaited(_recoverConnection(code, reason));
      });
    }
  }

  void onAppFocusChanged(bool focused) {
    _focusAwayTimer?.cancel();
    if (focused) {
      if (_focused) return;
      _focused = true;
      unawaited(_pushPresence());
      return;
    }
    _focusAwayTimer = Timer(focusAwayDebounce, () {
      if (!_focused) return;
      _focused = false;
      unawaited(_pushPresence());
    });
  }

  void onAppResumed() {
    onAppFocusChanged(true);
    if (phase == SessionPhase.disconnected) {
      final host = activeHost;
      final existing =
          hosts.where((h) => h.host == host).firstOrNull?.token ?? token;
      if (host != null && existing != null && existing.isNotEmpty) {
        unawaited(connect(host: host, existingToken: existing));
      }
      return;
    }
    if (phase != SessionPhase.ready) return;
    if (trpc == null || !trpc!.isOpen) {
      if (!_recovering) {
        unawaited(_recoverConnection(1006, 'app resumed'));
      }
      return;
    }
    final link = takePendingDeepLink();
    if (link?.channelId != null) {
      unawaited(jumpToMessage(link!.channelId!, link.messageId ?? 0));
    } else if (selectedChannelId != null) {
      unawaited(androidClearChannelNotifications(selectedChannelId!));
    }
    if (connectedVoiceChannelId != null) {
      unawaited(() async {
        await _restartIceBoth();
        PlatformBridge.resumePlayback();
        await _resyncRemoteProducers();
        await ensureAudioProducer();
      }());
    }
    unawaited(_pushPresence());
  }

  @visibleForTesting
  Future<void> handleGatewayClosed(int code, String reason) {
    return _onSocketClosed(code, reason);
  }

  void _applyJoin(JoinPayload j) {
    ownUserId = j.ownUserId;
    serverName = j.serverName;
    serverId = j.serverId;
    publicSettings = j.publicSettings;
    channelPerms = j.channelPermissions;
    readStates = Map.of(j.readStates);
    notificationOverrides = Map.of(j.notificationOverrides);
    pluginsMetadata = j.pluginsMetadata;
    pluginCommands = j.commands;
    showWelcome = j.showWelcomeDialog;
    users
      ..clear()
      ..addEntries(j.users.map((u) => MapEntry(u.id, u)));
    channels
      ..clear()
      ..addEntries(j.channels.map((c) => MapEntry(c.id, c)));
    categories
      ..clear()
      ..addEntries(j.categories.map((c) => MapEntry(c.id, c)));
    roles
      ..clear()
      ..addEntries(j.roles.map((r) => MapEntry(r.id, r)));
    emojis
      ..clear()
      ..addEntries(j.emojis.map((e) => MapEntry(e.id, e)));
    _parseVoiceMap(j.voiceMap);
    _parseExternal(j.externalStreamsMap);
    unawaited(_pushPresence());
    final host = hosts.where((h) => h.host == activeHost).firstOrNull;
    if (host != null) {
      host.name = serverName;
      store.saveHosts(hosts);
    }
  }

  void _parseVoiceMap(Map<String, dynamic> raw) {
    voiceMap.clear();
    occupiedSince.clear();
    raw.forEach((cid, value) {
      final id = asInt(cid) ?? 0;
      if (value is! Map) return;
      occupiedSince[id] = asInt(value['occupiedSince']);
      final usersRaw = value['users'];
      final map = <int, VoiceUserState>{};
      if (usersRaw is Map) {
        usersRaw.forEach((uid, st) {
          if (st is Map) {
            map[asInt(uid) ?? 0] = VoiceUserState.fromJson(
              Map<String, dynamic>.from(st),
            );
          }
        });
      }
      voiceMap[id] = map;
    });
  }

  void _parseExternal(Map<String, dynamic> raw) {
    externalStreams.clear();
    raw.forEach((cid, value) {
      final id = asInt(cid) ?? 0;
      final list = <ExternalStream>[];
      if (value is Map) {
        value.forEach((sid, st) {
          if (st is Map) {
            final json = Map<String, dynamic>.from(st);
            json['streamId'] = asInt(json['streamId']) ?? asInt(sid) ?? 0;
            list.add(ExternalStream.fromJson(json));
          }
        });
      }
      externalStreams[id] = list;
    });
  }

  Future<void> _subscribeAll() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    void listen(String path, void Function(dynamic) fn) {
      _subs.add(trpc!.subscribe(path).listen(fn, onError: _log));
    }

    listen('messages.onNew', (d) => _onMessageEvent(d, isNew: true));
    listen('messages.onUpdate', (d) => _onMessageEvent(d, isNew: false));
    listen('messages.onDelete', _onMessageDelete);
    listen('messages.onTyping', _onTyping);
    listen('messages.onThreadReplyCountUpdate', _onThreadCount);
    listen('users.onJoin', (d) => _upsertUser(d, status: 'online'));
    listen('users.onLeave', _onUserLeave);
    listen('users.onUpdate', _upsertUser);
    listen('users.onCreate', _upsertUser);
    listen('users.onDelete', _onUserDelete);
    listen('channels.onCreate', _upsertChannel);
    listen('channels.onUpdate', _upsertChannel);
    listen('channels.onDelete', _onChannelDelete);
    listen('channels.onPermissionsUpdate', _onPerms);
    listen('channels.onReadStateUpdate', _onRead);
    listen('channels.onReadStateDelta', _onRead);
    listen('channels.onNotificationOverride', _onOverride);
    listen('categories.onCreate', _upsertCategory);
    listen('categories.onUpdate', _upsertCategory);
    listen('categories.onDelete', _onCategoryDelete);
    listen('roles.onCreate', _upsertRole);
    listen('roles.onUpdate', _upsertRole);
    listen('roles.onDelete', _onRoleDelete);
    listen('emojis.onCreate', _upsertEmoji);
    listen('emojis.onUpdate', _upsertEmoji);
    listen('emojis.onDelete', _onEmojiDelete);
    listen('voice.onJoin', _onVoiceJoin);
    listen('voice.onLeave', _onVoiceLeave);
    listen('voice.onUpdateState', _onVoiceState);
    listen('voice.onMoved', _onVoiceMoved);
    listen('voice.onNewProducer', _onNewProducer);
    listen('voice.onProducerClosed', _onProducerClosed);
    listen('voice.onAddExternalStream', _onAddExt);
    listen('voice.onUpdateExternalStream', _onUpdExt);
    listen('voice.onRemoveExternalStream', _onRemExt);
    listen('others.onServerSettingsUpdate', _onSettings);
    listen('plugins.onMetadataChange', (_) => _refreshPlugins());
    listen('plugins.onCommandsChange', (_) => _refreshCommands());
    listen('dms.onConversationOpen', _onDmOpen);
    _typingSweep = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      var changed = false;
      typing.forEach((cid, list) {
        list.removeWhere((t) => t.until.isBefore(now));
        if (list.isEmpty) changed = true;
      });
      final voiceLive =
          connectedVoiceChannelId != null ||
          occupiedSince.values.any((v) => v != null && v > 0) ||
          voiceMap.values.any((m) => m.isNotEmpty);
      if (changed || voiceLive) notifyListeners();
    });
  }

  Map<String, dynamic> _map(dynamic d) =>
      d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};

  KurierMessage _mergeMessage(KurierMessage prev, KurierMessage next) {
    if (next.channelId == 0) next.channelId = prev.channelId;
    next.content ??= prev.content;
    next.userId ??= prev.userId;
    next.pluginId ??= prev.pluginId;
    next.parentMessageId ??= prev.parentMessageId;
    next.replyToMessageId ??= prev.replyToMessageId;
    if (next.files.isEmpty && prev.files.isNotEmpty) next.files = prev.files;
    if (next.metadata.isEmpty && prev.metadata.isNotEmpty) {
      next.metadata = prev.metadata;
    }
    next.replyTo ??= prev.replyTo;
    next.pinnedAt ??= prev.pinnedAt;
    next.pinnedBy ??= prev.pinnedBy;
    if (next.createdAt == 0) next.createdAt = prev.createdAt;
    return next;
  }

  void _onMessageEvent(dynamic d, {required bool isNew}) {
    final raw = extractMessagePayload(d);
    if (raw == null) return;
    final incoming = KurierMessage.fromJson(raw);
    if (incoming.id == 0) return;

    var replaced = false;
    void replaceIn(List<KurierMessage> list) {
      final idx = list.indexWhere((m) => m.id == incoming.id);
      if (idx < 0) return;
      list[idx] = _mergeMessage(list[idx], incoming);
      replaced = true;
    }

    for (final list in messages.values) {
      replaceIn(list);
    }
    replaceIn(threadMessages);
    replaceIn(pinned);
    replaceIn(searchMessages);
    replaceIn(mentionMessages);

    if (!replaced && isNew) {
      final cid = incoming.channelId;
      if (cid == 0) return;
      if (incoming.parentMessageId == null) {
        final history = _historyOf(cid);
        final before = history.messages.length;
        addHistoryMessages(history, [incoming], isLive: true);
        _commitHistory(cid, history);
        if (history.messages.length > before) {
          if (selectedChannelId != cid) {
            readStates[cid] = (readStates[cid] ?? 0) + 1;
          }
          _trackIncomingMention(incoming);
          _notifyIncoming(incoming);
        }
      } else if (incoming.parentMessageId == threadParentId) {
        _notifyIncoming(incoming);
      }
    }
    if (threadParentId != null &&
        (incoming.parentMessageId == threadParentId ||
            incoming.id == threadParentId)) {
      if (incoming.parentMessageId == threadParentId) {
        final tIdx = threadMessages.indexWhere((m) => m.id == incoming.id);
        if (tIdx < 0) {
          threadMessages.add(incoming);
        }
      }
    }
    notifyListeners();
  }

  void _trackIncomingMention(KurierMessage incoming) {
    if (ownUserId == 0 || incoming.userId == ownUserId) return;
    if (!hasUserMention(incoming.content ?? '', ownUserId)) return;
    if (incoming.channelId != selectedChannelId) {
      unreadMentionIds.add(incoming.id);
    }
    if (mentionsLoaded) {
      mentionMessages.removeWhere((m) => m.id == incoming.id);
      mentionMessages.insert(0, incoming);
    }
  }

  void clearUnreadMentions() {
    if (unreadMentionIds.isEmpty) return;
    unreadMentionIds.clear();
    notifyListeners();
  }

  String? _notifyChannelLabel(int channelId, {required bool isDm}) {
    final channel = channels[channelId];
    if (isDm || (channel?.isDm ?? false)) {
      final fromChannel = channel?.name.trim();
      if (fromChannel != null && fromChannel.isNotEmpty) return fromChannel;
      return null;
    }
    final name = channel?.name.trim() ?? '';
    if (name.isEmpty) return null;
    return name.startsWith('#') ? name : '#$name';
  }

  void _notifyIncoming(KurierMessage msg) {
    final mentioned = hasMention(msg.content, ownUserId);
    final isDm = channels[msg.channelId]?.isDm ?? false;
    final level = notificationOverrides[msg.channelId];
    final replyToMe =
        msg.replyTo?.userId == ownUserId ||
        (msg.replyToMessageId != null &&
            messages[msg.channelId]?.any(
                  (m) => m.id == msg.replyToMessageId && m.userId == ownUserId,
                ) ==
                true);
    if (msg.userId != ownUserId &&
        level != 'nothing' &&
        (store.notifyAll ||
            (store.notifyMentions && mentioned) ||
            (store.notifyDm && isDm) ||
            (store.notifyReplies && replyToMe) ||
            level == 'all' ||
            (level == 'mentions' && mentioned))) {
      final user = users[msg.userId];
      final kind = PushKind.classify(
        isDm: isDm,
        mentioned: mentioned,
        replyToMe: replyToMe,
      );
      final title = user?.displayName ?? 'Kurier';
      final body = htmlToPlainText(msg.content ?? '');
      final channelName = _notifyChannelLabel(msg.channelId, isDm: isDm);
      if (isNativeMobile) {
        final viewingHere =
            androidIsAppForeground && selectedChannelId == msg.channelId;
        if (!viewingHere) {
          unawaited(
            androidShowIncomingNotification(
              title: title,
              body: body,
              kind: kind.wire,
              channelId: msg.channelId,
              messageId: msg.id,
              channelName: channelName,
            ),
          );
        }
      } else {
        PlatformBridge.notify(title, body, kind: kind.wire);
      }
    }
    if (shouldPlayIncomingMessageSound(
          isOwn: msg.userId == ownUserId,
          mentioned: mentioned,
          channelOverride: level,
          soundMention: store.soundMention,
          soundMessage: store.soundMessage,
        ) &&
        (!isNativeMobile || androidIsAppForeground)) {
      PlatformBridge.playSound(KurierSoundType.messageReceived);
    }
  }

  void _onMessageDelete(dynamic d) {
    final m = _map(d);
    final id = asInt(m['id']) ?? asInt(m['messageId']);
    final cid = asInt(m['channelId']);
    if (id == null) return;
    if (cid != null) {
      messages[cid]?.removeWhere((msg) => msg.id == id);
    } else {
      for (final list in messages.values) {
        list.removeWhere((msg) => msg.id == id);
      }
    }
    threadMessages.removeWhere((msg) => msg.id == id);
    pinned.removeWhere((msg) => msg.id == id);
    mentionMessages.removeWhere((msg) => msg.id == id);
    unreadMentionIds.remove(id);
    notifyListeners();
  }

  void _onTyping(dynamic d) {
    final m = _map(d);
    final cid = asInt(m['channelId']);
    final uid = asInt(m['userId']);
    if (cid == null || uid == null || uid == ownUserId) return;
    final list = typing.putIfAbsent(cid, () => []);
    list.removeWhere((t) => t.userId == uid);
    list.add(TypingUser(uid, DateTime.now().add(const Duration(seconds: 8))));
    notifyListeners();
  }

  void _onThreadCount(dynamic d) {
    final m = _map(d);
    final id = asInt(m['messageId']) ?? asInt(m['id']);
    final count = asInt(m['replyCount']) ?? 0;
    if (id == null) return;
    for (final list in messages.values) {
      final idx = list.indexWhere((msg) => msg.id == id);
      if (idx >= 0) list[idx].replyCount = count;
    }
    notifyListeners();
  }

  void _upsertUser(dynamic d, {String? status}) {
    final raw = extractUserPayload(d);
    if (raw == null) return;
    final id = asInt(raw['id']) ?? 0;
    final existing = id == 0 ? null : users[id];
    final u = KurierUser.fromJson(raw, existing: existing);
    if (u.id == 0) return;
    if (existing != null) {
      if (KurierUser.isPlaceholderName(u.name) &&
          !KurierUser.isPlaceholderName(existing.name)) {
        u.name = existing.name;
      }
      if (KurierUser.isPlaceholderName(u.nickname) &&
          !KurierUser.isPlaceholderName(existing.nickname)) {
        u.nickname = existing.nickname;
      }
    }
    if (status != null) {
      u.status = status;
    } else if (existing != null && !raw.containsKey('status')) {
      u.status = existing.status;
    }
    users[u.id] = u;
    notifyListeners();
  }

  void _onUserLeave(dynamic d) {
    final id = extractUserId(d);
    if (id == null) return;
    final u = users[id];
    if (u != null) {
      u.status = 'offline';
      u.mobile = false;
    }
    notifyListeners();
  }

  void _onUserDelete(dynamic d) {
    final id = extractUserId(d) ?? asInt(_map(d)['deletedUserId']);
    if (id == null) return;
    final u = users[id];
    if (u == null) return;
    u.deleted = true;
    u.status = 'offline';
    u.mobile = false;
    notifyListeners();
  }

  void _upsertChannel(dynamic d) {
    final c = KurierChannel.fromJson(_map(d));
    channels[c.id] = c;
    _syncSelectedChannelAccess();
    notifyListeners();
  }

  void _onChannelDelete(dynamic d) {
    final id = asInt(_map(d)['id']);
    if (id == null) return;
    channels.remove(id);
    if (selectedChannelId == id) selectedChannelId = null;
    notifyListeners();
  }

  void _upsertCategory(dynamic d) {
    final c = KurierCategory.fromJson(_map(d));
    categories[c.id] = c;
    notifyListeners();
  }

  void _onCategoryDelete(dynamic d) {
    final id = asInt(_map(d)['id']);
    if (id != null) categories.remove(id);
    notifyListeners();
  }

  void _upsertRole(dynamic d) {
    final r = KurierRole.fromJson(_map(d));
    roles[r.id] = r;
    notifyListeners();
  }

  void _onRoleDelete(dynamic d) {
    final id = asInt(_map(d)['id']);
    if (id != null) roles.remove(id);
    notifyListeners();
  }

  void _upsertEmoji(dynamic d) {
    final e = KurierEmoji.fromJson(_map(d));
    emojis[e.id] = e;
    notifyListeners();
  }

  void _onEmojiDelete(dynamic d) {
    final id = asInt(_map(d)['id']);
    if (id != null) emojis.remove(id);
    notifyListeners();
  }

  void _onPerms(dynamic d) {
    final m = _map(d);
    if (m['permissions'] is Map && m['channelId'] != null) {
      channelPerms['${m['channelId']}'] = ChannelPerms(
        Map<String, dynamic>.from(
          m['permissions'] as Map,
        ).map((k, v) => MapEntry(k, asBool(v))),
      );
    } else {
      final parsed = parseChannelPermissions(m);
      if (parsed.isNotEmpty) channelPerms = parsed;
    }
    _syncSelectedChannelAccess();
    notifyListeners();
  }

  void _syncSelectedChannelAccess() {
    final id = selectedChannelId;
    if (id == null) return;
    final ch = channels[id];
    if (ch == null || ch.isDm) return;
    if (canViewChannel(ch)) return;
    selectedChannelId = null;
    showingDms = false;
  }

  void _onRead(dynamic d) {
    final m = _map(d);
    final cid = asInt(m['channelId']);
    final count = asInt(m['count']);
    if (cid != null && count != null) readStates[cid] = count;
    notifyListeners();
  }

  void _onOverride(dynamic d) {
    final m = _map(d);
    final cid = asInt(m['channelId']);
    if (cid != null)
      notificationOverrides[cid] = '${m['level'] ?? m['override'] ?? ''}';
    notifyListeners();
  }

  void _onVoiceJoin(dynamic d) {
    final m = _map(d);
    final cid = asInt(m['channelId']);
    final uid = asInt(m['userId']);
    if (cid == null || uid == null) return;
    voiceMap.putIfAbsent(cid, () => {});
    voiceMap[cid]![uid] = VoiceUserState.fromJson(
      m['state'] is Map ? Map<String, dynamic>.from(m['state'] as Map) : m,
    );
    occupiedSince[cid] = asInt(m['occupiedSince']) ?? occupiedSince[cid];
    notifyListeners();
    if (uid != ownUserId && cid == connectedVoiceChannelId) {
      PlatformBridge.playSound(KurierSoundType.remoteUserJoinedVoiceChannel);
      _scheduleProducerResync();
    }
  }

  void _onVoiceLeave(dynamic d) {
    final m = _map(d);
    final cid = asInt(m['channelId']);
    final uid = asInt(m['userId']);
    if (uid == ownUserId &&
        (_silentRejoining ||
            (_ignoreOwnVoiceLeaveUntil != null &&
                DateTime.now().isBefore(_ignoreOwnVoiceLeaveUntil!)))) {
      return;
    }
    if (cid != null && uid != null) voiceMap[cid]?.remove(uid);
    if (uid == ownUserId &&
        connectedVoiceChannelId == cid &&
        voiceState != 'connecting') {
      _resetVoiceLocal();
      unawaited(_pushPresence());
    } else if (uid != ownUserId && cid == connectedVoiceChannelId) {
      PlatformBridge.playSound(KurierSoundType.remoteUserLeftVoiceChannel);
    }
    notifyListeners();
  }

  void _onVoiceState(dynamic d) {
    final m = _map(d);
    final cid = asInt(m['channelId']);
    final uid = asInt(m['userId']);
    if (cid == null || uid == null) return;
    final prevSharing = voiceMap[cid]?[uid]?.sharingScreen ?? false;
    final next = VoiceUserState.fromJson(
      m['state'] is Map ? Map<String, dynamic>.from(m['state'] as Map) : m,
    );
    voiceMap[cid]?[uid] = next;
    if (uid != ownUserId && cid == connectedVoiceChannelId) {
      if (next.sharingScreen && !prevSharing) {
        PlatformBridge.playSound(KurierSoundType.remoteUserStartedScreenshare);
      } else if (!next.sharingScreen && prevSharing) {
        PlatformBridge.playSound(KurierSoundType.remoteUserStoppedScreenshare);
      }
    }
    notifyListeners();
  }

  void _onVoiceMoved(dynamic d) {
    final m = _map(d);
    final uid = asInt(m['userId']);
    final from = asInt(m['fromChannelId']) ?? asInt(m['from']);
    final to =
        asInt(m['toChannelId']) ?? asInt(m['channelId']) ?? asInt(m['to']);
    if (uid == null) return;
    VoiceUserState? st;
    if (from != null) st = voiceMap[from]?.remove(uid);
    if (to != null) {
      voiceMap.putIfAbsent(to, () => {});
      voiceMap[to]![uid] = st ?? VoiceUserState();
    }
    if (uid == ownUserId) {
      if (to == null) {
        if (voiceState != 'connecting') _resetVoiceLocal();
      } else {
        connectedVoiceChannelId = to;
      }
    }
    notifyListeners();
  }

  Future<void> _onNewProducer(dynamic d) async {
    final m = _map(d);
    if (connectedVoiceChannelId == null) return;
    final kind = '${m['kind']}';
    final remoteId = voiceEventUserId(m) ?? 0;
    if (!_shouldConsumeProducer(kind, remoteId)) {
      notifyListeners();
      return;
    }
    try {
      await consumeProducer(kind: kind, remoteId: remoteId, replace: true);
    } catch (e) {
      _log('consume failed: $e');
    }
  }

  void _onProducerClosed(dynamic d) {
    final m = _map(d);
    final kind = '${m['kind']}';
    final remoteId = voiceEventUserId(m) ?? 0;
    final key = '$remoteId:$kind';
    final stored = consumerKeys.remove(key);
    volumes.remove(key);
    if (stored != null) PlatformBridge.closeConsumer(stored);
    if (kind == StreamKind.screen || kind == StreamKind.externalVideo) {
      watchingStreams.remove(
        StreamKind.watchKey(
          remoteId,
          external: kind == StreamKind.externalVideo,
        ),
      );
    }
    notifyListeners();
  }

  void _onAddExt(dynamic d) {
    final m = _map(d);
    final cid = asInt(m['channelId']);
    if (cid == null) return;
    final json = m['stream'] is Map
        ? Map<String, dynamic>.from(m['stream'] as Map)
        : Map<String, dynamic>.from(m);
    json['streamId'] = asInt(m['streamId']) ?? asInt(json['streamId']) ?? 0;
    final list = externalStreams.putIfAbsent(cid, () => []);
    list.removeWhere((s) => s.streamId == json['streamId']);
    list.add(ExternalStream.fromJson(json));
    notifyListeners();
  }

  void _onUpdExt(dynamic d) => notifyListeners();

  void _onRemExt(dynamic d) {
    final m = _map(d);
    final cid = asInt(m['channelId']);
    final sid = asInt(m['streamId']);
    final key = '${m['key'] ?? m['streamId']}';
    watchingStreams.remove(StreamKind.watchKey(sid ?? 0, external: true));
    externalStreams[cid]?.removeWhere(
      (s) => (sid != null && s.streamId == sid) || s.key == key,
    );
    notifyListeners();
  }

  void _onSettings(dynamic d) {
    final m = _map(d);
    publicSettings.addAll(m);
    if (m['name'] is String) serverName = m['name'] as String;
    final hinted = klipyKeyFromServerMap(m);
    if (hinted != null) unawaited(_setServerKlipy(hinted));
    notifyListeners();
  }

  Future<void> _refreshPlugins() async {
    try {
      pluginsMetadata = (await trpc!.query('plugins.get')).toString().isEmpty
          ? pluginsMetadata
          : List.from(
              ((await trpc!.query('plugins.get')) as Map)['plugins'] as List? ??
                  const [],
            );
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _refreshCommands() async {
    try {
      pluginCommands = List.from(
        await trpc!.query('plugins.getCommands') as List,
      );
    } catch (_) {}
    notifyListeners();
  }

  void _onDmOpen(dynamic d) {
    final cid = asInt(_map(d)['channelId']);
    if (cid != null) loadDms();
  }

  Future<void> loadDms() async {
    try {
      dms = ((await trpc!.query('dms.get')) as List)
          .whereType<Map>()
          .map((e) => DmConversation.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  KurierUser? get me => users[ownUserId];

  bool get manualAway => _manualAway;

  String get displayPresence => intendedPresenceStatus(
    manualAway: _manualAway,
    focused: _focused,
    inVoice: connectedVoiceChannelId != null,
  );

  void togglePresence() {
    final away = _manualAway || (!_focused && connectedVoiceChannelId == null);
    unawaited(setPresence(away ? presenceOnline : presenceIdle));
  }

  Future<void> setPresence(String status) async {
    if (status != presenceOnline && status != presenceIdle) return;
    _manualAway = status == presenceIdle;
    if (status == presenceOnline) _focused = true;
    await _pushPresence();
  }

  void _applyLocalPresence() {
    final self = me;
    if (self == null) return;
    final next = displayPresence;
    if (self.status == next) return;
    self.status = next;
    notifyListeners();
  }

  @visibleForTesting
  void applyLocalPresence() => _applyLocalPresence();

  Future<void> _pushPresence() async {
    _applyLocalPresence();
    if (trpc == null) return;
    try {
      await trpc!.mutate('users.setStatus', {'status': displayPresence});
    } catch (e) {
      _log('setStatus: $e');
    }
  }

  bool can(String permission) {
    final meRoles = me?.roleIds ?? [];
    if (meRoles.contains(AppConfig.ownerRoleId)) return true;
    for (final id in meRoles) {
      if (roles[id]?.permissions.contains(permission) ?? false) return true;
    }
    return false;
  }

  bool canAny(Iterable<String> permissions) => permissions.any(can);

  bool get isOwner => me?.roleIds.contains(AppConfig.ownerRoleId) == true;

  bool canJoinVoiceChannel(int channelId) =>
      can(Permission.joinVoiceChannels) &&
      canChannel(channelId, ChannelPermission.join);

  bool canSendInChannel(int? channelId) {
    if (channelId == null) return false;
    final ch = channels[channelId];
    if (ch == null) return false;
    if (ch.isDm) return true;
    if (!can(Permission.sendMessages)) return false;
    return canChannel(channelId, ChannelPermission.sendMessages);
  }

  bool canEnableWebcam() {
    if (!can(Permission.enableWebcam)) return false;
    final id = connectedVoiceChannelId;
    return id == null || canChannel(id, ChannelPermission.webcam);
  }

  bool canShareScreen() {
    if (!can(Permission.shareScreen)) return false;
    final id = connectedVoiceChannelId;
    return id == null || canChannel(id, ChannelPermission.shareScreen);
  }

  int errorEpoch = 0;

  void notifyError(Object err) {
    final text = err is String ? err : _voiceErrorText(err);
    error = isPermissionError(err) || isPermissionError(text)
        ? missingPermissionKey
        : text;
    errorEpoch++;
    notifyListeners();
  }

  void notifyMissingPermission() => notifyError(missingPermissionKey);

  void clearError() {
    error = null;
  }

  int highestRolePosition(List<int> roleIds) {
    if (roleIds.contains(AppConfig.ownerRoleId)) return 1 << 30;
    var max = -1;
    for (final id in roleIds) {
      final p = roles[id]?.position ?? -1;
      if (p > max) max = p;
    }
    return max;
  }

  bool canModerate(KurierUser target) {
    if (target.id == ownUserId) return false;
    if (isOwner) return true;
    return highestRolePosition(me?.roleIds ?? const []) >
        highestRolePosition(target.roleIds);
  }

  int? voiceChannelIdOf(int userId) {
    for (final e in voiceMap.entries) {
      if (e.value.containsKey(userId)) return e.key;
    }
    return null;
  }

  double localUserVolume(int userId) => localUserVolumes[userId] ?? 1;

  bool isLocallyMuted(int userId) => localUserVolume(userId) <= 0;

  void setLocalUserVolume(int userId, double volume) {
    final next = volume.clamp(0.0, 1.0);
    localUserVolumes[userId] = next;
    _applyLocalUserVolume(userId);
    notifyListeners();
  }

  void toggleLocalMute(int userId) {
    setLocalUserVolume(userId, isLocallyMuted(userId) ? 1 : 0);
  }

  void _applyLocalUserVolume(int userId) {
    final mapKey = '$userId:${StreamKind.audio}';
    final bridgeKey = consumerKeys[mapKey];
    if (bridgeKey == null) return;
    final vol = localUserVolume(userId);
    volumes[mapKey] = vol;
    if (!soundMuted) PlatformBridge.setVolume(bridgeKey, vol);
  }

  bool canChannel(int channelId, String perm) {
    final channel = channels[channelId];
    if (isOwner || channel == null || !channel.private) return true;
    if (perm != ChannelPermission.viewChannel &&
        !(channelPerms['$channelId']?.get(ChannelPermission.viewChannel) ??
            false)) {
      return false;
    }
    return channelPerms['$channelId']?.get(perm) ?? false;
  }

  /// Matches vanilla `canViewChannel`: public channels and the owner are
  /// always visible; private channels need VIEW_CHANNEL, unless this is the
  /// voice channel the user is currently connected to.
  bool canViewChannel(KurierChannel channel) {
    if (channel.isDm) return true;
    if (isOwner || !channel.private) return true;
    if (connectedVoiceChannelId == channel.id) return true;
    return channelPerms['${channel.id}']?.get(ChannelPermission.viewChannel) ??
        false;
  }

  /// Sidebar listing: managers still see private channels they cannot join.
  bool canSeeChannel(KurierChannel channel) {
    return canViewChannel(channel) || can(Permission.manageChannels);
  }

  /// Hide empty / fully-private categories unless the user can manage them.
  bool canSeeCategory(int categoryId) {
    if (can(Permission.manageChannels) || can(Permission.manageCategories)) {
      return true;
    }
    return channelsIn(categoryId).any(canViewChannel);
  }

  List<KurierChannel> textChannelsIn(int? categoryId) {
    return channels.values
        .where((c) => !c.isDm && c.isText && c.categoryId == categoryId)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  List<KurierChannel> voiceChannelsIn(int? categoryId) {
    return channels.values
        .where((c) => !c.isDm && c.isVoice && c.categoryId == categoryId)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  List<KurierChannel> channelsIn(int? categoryId) {
    return channels.values
        .where((c) => !c.isDm && c.categoryId == categoryId)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  List<KurierChannel> visibleChannelsIn(int? categoryId) {
    return channelsIn(categoryId).where(canSeeChannel).toList();
  }

  void toggleCategory(int id) {
    if (!collapsedCategories.remove(id)) collapsedCategories.add(id);
    store.setCollapsedCats(collapsedCategories);
    notifyListeners();
  }

  void toggleMembers() {
    membersOpen = !membersOpen;
    notifyListeners();
  }

  void setSidebarWidth(double width) {
    final next = width.clamp(kSidebarMinWidth, kSidebarMaxWidth).toDouble();
    if (next == sidebarWidth) return;
    sidebarWidth = next;
    notifyListeners();
    _schedulePanelWidthSave();
  }

  void setMembersWidth(double width) {
    final next = width.clamp(kSidebarMinWidth, kSidebarMaxWidth).toDouble();
    if (next == membersWidth) return;
    membersWidth = next;
    notifyListeners();
    _schedulePanelWidthSave();
  }

  void _schedulePanelWidthSave() {
    _panelWidthSave?.cancel();
    _panelWidthSave = Timer(const Duration(milliseconds: 300), () {
      store.setSidebarWidth(sidebarWidth);
      store.setMembersWidth(membersWidth);
    });
  }

  List<KurierCategory> sortedCategories() {
    return categories.values.toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  List<KurierCategory> visibleCategories() {
    return sortedCategories().where((c) => canSeeCategory(c.id)).toList();
  }

  bool isChannelDetached(int channelId) => detachedChannels.contains(channelId);

  ChannelHistoryState _historyOf(int channelId) {
    return ChannelHistoryState(
      messages: List<KurierMessage>.from(messages[channelId] ?? const []),
      nextCursor: nextCursor[channelId],
      detached: detachedChannels.contains(channelId),
    );
  }

  void _commitHistory(int channelId, ChannelHistoryState history) {
    messages[channelId] = history.messages;
    nextCursor[channelId] = history.nextCursor;
    if (history.detached) {
      detachedChannels.add(channelId);
    } else {
      detachedChannels.remove(channelId);
    }
  }

  void _trimChannel(int channelId) {
    final history = _historyOf(channelId);
    trimHistoryMessages(history);
    _commitHistory(channelId, history);
  }

  List<KurierMessage> _parseMessagePage(Map<String, dynamic> map) {
    return (map['messages'] as List?)
            ?.whereType<Map>()
            .map((e) => KurierMessage.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        [];
  }

  void _rememberTextChannel(KurierChannel? ch) {
    if (ch != null && ch.isText && !ch.isDm && canViewChannel(ch)) {
      lastTextChannelId = ch.id;
    }
  }

  Future<void> selectChannel(int id) async {
    if (selectedChannelId == id) {
      showingDms = channels[id]?.isDm ?? false;
      final ch = channels[id];
      _rememberTextChannel(ch);
      if (ch?.opensAsVoiceStage == true &&
          !(connectedVoiceChannelId == id && voiceState == 'connected')) {
        await joinVoice(id);
      }
      return;
    }
    final previous = selectedChannelId;
    showingDms = channels[id]?.isDm ?? false;
    selectedChannelId = id;
    threadParentId = null;
    replyTo = null;
    unawaited(androidClearChannelNotifications(id));
    if (previous != null) _trimChannel(previous);
    if (activeHost != null) await store.setLastChannel(activeHost!, id);
    final ch = channels[id];
    _rememberTextChannel(ch);
    notifyListeners();
    if (ch?.isText == true || ch?.isDm == true) {
      await loadMessages(id);
      try {
        await trpc?.mutate('channels.markAsRead', {'channelId': id});
        readStates[id] = 0;
      } catch (_) {}
    } else if (ch?.opensAsVoiceStage == true) {
      await joinVoice(id);
    }
    notifyListeners();
  }

  Future<void> returnToLastTextChannel() async {
    final id = lastTextChannelId;
    if (id == null) return;
    final ch = channels[id];
    if (ch == null || !ch.isText || ch.isDm || !canViewChannel(ch)) return;
    await selectChannel(id);
  }

  Future<void> returnToVoiceChannel() async {
    final id = connectedVoiceChannelId;
    if (id == null) return;
    await selectChannel(id);
  }

  Future<void> loadOlderMessages(int channelId) async {
    if (fetchingMessages[channelId] == true) return;
    final cursor = nextCursor[channelId];
    if (cursor == null) return;
    await loadMessages(channelId, cursor: cursor);
  }

  Future<void> returnToPresent([int? channelId]) async {
    final id = channelId ?? selectedChannelId;
    if (id == null) return;
    await loadMessages(id, returnToPresent: true);
  }

  Future<void> jumpToMessage(int channelId, int messageId) async {
    if (selectedChannelId != channelId) {
      await selectChannel(channelId);
    }
    final list = messages[channelId] ?? const <KurierMessage>[];
    if (!list.any((m) => m.id == messageId)) {
      await loadMessages(channelId, target: messageId);
    }
    jumpTargetChannelId = channelId;
    jumpTargetMessageId = messageId;
    notifyListeners();
  }

  void clearJumpTarget() {
    jumpTargetChannelId = null;
    jumpTargetMessageId = null;
  }

  Future<void> loadMessages(
    int channelId, {
    MessagesCursor? cursor,
    int? target,
    bool returnToPresent = false,
  }) async {
    if (trpc == null) return;
    if (cursor != null && fetchingMessages[channelId] == true) return;
    final existing = messages[channelId] ?? const <KurierMessage>[];
    final initial =
        existing.isEmpty &&
        cursor == null &&
        target == null &&
        !returnToPresent;
    if (initial) {
      loadingMessages[channelId] = true;
    } else {
      fetchingMessages[channelId] = true;
    }
    notifyListeners();
    try {
      final raw = await trpc!.query('messages.get', {
        'channelId': channelId,
        'limit': AppConfig.defaultMessagesLimit,
        if (cursor != null) 'cursor': cursor.toJson(),
        if (target != null) 'targetMessageId': target,
      });
      final map = _map(raw);
      final batch = _parseMessagePage(map);
      final pageCursor = MessagesCursor.parse(map['nextCursor']);
      final history = _historyOf(channelId);
      if (returnToPresent) {
        applyPresentPage(history, page: batch, nextCursor: pageCursor);
      } else if (target != null) {
        applyJumpWindow(
          history,
          page: batch,
          hasNewer: asBool(map['hasNewer']),
          nextCursor: pageCursor,
        );
      } else {
        applyFetchedPage(history, page: batch, nextCursor: pageCursor);
      }
      _commitHistory(channelId, history);
    } catch (e) {
      _log('messages.get: $e');
    }
    loadingMessages[channelId] = false;
    fetchingMessages[channelId] = false;
    notifyListeners();
  }

  String get gifApiKey {
    return AppConfig.klipyKeyFor(
      stored: store.klipy,
      host: activeHost,
      discovered: serverKlipyKey,
    );
  }

  Future<void> _adoptServerKlipy(Map<String, dynamic> raw) async {
    final hinted = klipyKeyFromServerMap(raw);
    if (hinted != null) await _setServerKlipy(hinted);
    final host = activeHost;
    if (host == null || httpApi == null) return;
    _klipyDiscover ??= _discoverServerKlipy(host);
  }

  Future<void> ensureServerKlipyKey() {
    if ((serverKlipyKey ?? '').trim().isNotEmpty) return Future.value();
    if (_klipyDiscover != null) return _klipyDiscover!;
    final host = activeHost;
    if (host == null || httpApi == null) return Future.value();
    _klipyDiscover = _discoverServerKlipy(host);
    return _klipyDiscover!;
  }

  Future<void> _discoverServerKlipy(String host) async {
    final key = await tryDiscoverKlipyKey(origin: originOf(host));
    if (key == null || key.isEmpty) return;
    await _setServerKlipy(key);
  }

  Future<void> _setServerKlipy(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return;
    serverKlipyKey = trimmed;
    final idx = hosts.indexWhere((h) => h.host == activeHost);
    if (idx >= 0 && hosts[idx].klipy != trimmed) {
      hosts[idx].klipy = trimmed;
      await store.saveHosts(hosts);
    }
    notifyListeners();
  }

  /// Search GIFs via vanilla `gifs.search`, then KLIPY trending/search.
  Future<List<String>> searchGifs(String query) async {
    final q = query.trim();
    if (trpc != null) {
      try {
        final raw = await trpc!.query('gifs.search', {
          'query': q,
          'page': 1,
          'perPage': 24,
        });
        final urls = gifUrlsFromJson(raw);
        if (urls.isNotEmpty) return urls;
      } catch (_) {}
    }
    final key = gifApiKey;
    if (key.isEmpty) return [];
    return fetchKlipyGifs(apiKey: key, query: q);
  }

  Future<void> toggleFavoriteGif(String url) async {
    final next = [...store.favoriteGifs()];
    if (next.contains(url)) {
      next.remove(url);
    } else {
      next.insert(0, url);
    }
    await store.setFavoriteGifs(next);
    notifyListeners();
  }

  Future<void> sendMessage(String text, {List<String> files = const []}) async {
    final cid = selectedChannelId;
    text = _clampMessageText(text);
    if (cid == null || (text.trim().isEmpty && files.isEmpty)) return;
    if (!canSendInChannel(cid)) {
      notifyMissingPermission();
      return;
    }
    final html = _messageHtml(text);
    final optimisticId = -DateTime.now().millisecondsSinceEpoch;
    final local = KurierMessage(
      id: optimisticId,
      channelId: cid,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      content: html,
      userId: ownUserId,
      replyToMessageId: replyTo?.id,
      parentMessageId: threadParentId,
      optimistic: true,
    );
    if (threadParentId != null) {
      threadMessages.add(local);
    } else {
      messages.putIfAbsent(cid, () => []).add(local);
    }
    final pendingReply = replyTo;
    replyTo = null;
    notifyListeners();
    try {
      await trpc!.mutate('messages.send', {
        'content': html,
        'channelId': cid,
        'files': files,
        if (pendingReply != null) 'replyToMessageId': pendingReply.id,
        if (threadParentId != null) 'parentMessageId': threadParentId,
      });
      messages[cid]?.removeWhere((m) => m.id == optimisticId);
      threadMessages.removeWhere((m) => m.id == optimisticId);
      PlatformBridge.playSound(KurierSoundType.messageSent);
    } catch (e) {
      messages[cid]?.removeWhere((m) => m.id == optimisticId);
      threadMessages.removeWhere((m) => m.id == optimisticId);
      notifyError(e);
    }
  }

  String _messageHtml(String text) {
    var html = textToMessageHtml(text);
    final canEveryone = can(Permission.mentionEveryone);
    html = injectMentions(
      html,
      text,
      users: users.values,
      everyone: canEveryone,
      here: canEveryone,
    );
    return EmojiCodec.expandCustomEmojisInEscapedHtml(html, customEmojis);
  }

  Future<void> signalTyping() async {
    final cid = selectedChannelId;
    if (cid == null) return;
    final now = DateTime.now();
    if (_lastTyped != null &&
        now.difference(_lastTyped!) < const Duration(milliseconds: 300)) {
      return;
    }
    _lastTyped = now;
    try {
      await trpc!.mutate('messages.signalTyping', {'channelId': cid});
    } catch (_) {}
  }

  Future<void> editMessage(int id, String text) async {
    await trpc!.mutate('messages.edit', {
      'messageId': id,
      'content': _messageHtml(_clampMessageText(text)),
    });
  }

  String _clampMessageText(String text) {
    if (text.length <= AppConfig.maxMessageLength) return text;
    return text.substring(0, AppConfig.maxMessageLength);
  }

  Future<void> deleteMessage(int id) async {
    await trpc!.mutate('messages.delete', {'messageId': id});
  }

  Future<void> togglePin(int id) async {
    await trpc!.mutate('messages.togglePin', {'messageId': id});
  }

  Future<void> toggleReaction(int id, String emoji) async {
    final key = EmojiCodec.encodeReactionKey(emoji, customEmojis);
    final targets = _messagesWithId(id);
    final previous = {
      for (final m in targets) m: List<MessageReaction>.from(m.reactions),
    };
    final patched = withToggledReaction(
      reactions: targets.isNotEmpty
          ? List<MessageReaction>.from(targets.first.reactions)
          : const [],
      key: key,
      ownUserId: ownUserId,
      messageId: id,
    );
    for (final m in targets) {
      m.reactions = patched;
    }
    if (targets.isNotEmpty) notifyListeners();

    try {
      await trpc!.mutate('messages.toggleReaction', {
        'messageId': id,
        'emoji': key,
      });
      await QuickReactions.record(key);
    } catch (err) {
      for (final entry in previous.entries) {
        entry.key.reactions = entry.value;
      }
      if (previous.isNotEmpty) notifyListeners();
      _log(err);
    }
  }

  Iterable<List<KurierMessage>> _allMessageLists() sync* {
    yield* messages.values;
    yield threadMessages;
    yield pinned;
    yield searchMessages;
    yield mentionMessages;
  }

  List<KurierMessage> _messagesWithId(int id) {
    final out = <KurierMessage>[];
    for (final list in _allMessageLists()) {
      for (final m in list) {
        if (m.id == id) out.add(m);
      }
    }
    return out;
  }

  Future<void> loadPinned(int channelId) async {
    loadingPinned = true;
    notifyListeners();
    try {
      final raw = await trpc!.query('messages.getPinned', {
        'channelId': channelId,
      });
      pinned = (raw as List)
          .whereType<Map>()
          .map((e) => KurierMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {}
    loadingPinned = false;
    notifyListeners();
  }

  Future<void> openThread(KurierMessage parent) async {
    threadParentId = parent.id;
    try {
      final raw = await trpc!.query('messages.getThread', {
        'messageId': parent.id,
      });
      threadMessages =
          (raw is List ? raw : (_map(raw)['messages'] as List? ?? const []))
              .whereType<Map>()
              .map((e) => KurierMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList();
    } catch (_) {
      threadMessages = [];
    }
    notifyListeners();
  }

  void closeThread() {
    threadParentId = null;
    threadMessages = [];
    notifyListeners();
  }

  Future<void> loadMentions() async {
    clearUnreadMentions();
    if (trpc == null) {
      notifyListeners();
      return;
    }
    final name = me?.name.trim() ?? '';
    if (name.isEmpty) {
      mentionMessages = [];
      mentionsLoaded = true;
      loadingMentions = false;
      notifyListeners();
      return;
    }
    loadingMentions = true;
    notifyListeners();
    try {
      final query = serializeSearchQuery(ParsedSearchQuery()..mentions = name);
      final raw = await trpc!.query('messages.search', {'query': query});
      final map = _map(raw);
      mentionMessages =
          (map['messages'] as List?)
              ?.whereType<Map>()
              .map((e) => KurierMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [];
      mentionMessages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      mentionsLoaded = true;
    } catch (e) {
      notifyError(e);
      mentionMessages = [];
    }
    loadingMentions = false;
    notifyListeners();
  }

  Future<void> search(String query) async {
    searchQuery = query;
    if (!isValidSearchQuery(parseSearchQuery(query))) {
      searchMessages = [];
      searchFiles = [];
      notifyListeners();
      return;
    }
    searching = true;
    notifyListeners();
    try {
      final raw = await trpc!.query('messages.search', {'query': query});
      final map = _map(raw);
      searchMessages =
          (map['messages'] as List?)
              ?.whereType<Map>()
              .map((e) => KurierMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [];
      searchFiles =
          (map['files'] as List?)
              ?.whereType<Map>()
              .map((e) => KurierFile.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [];
    } catch (e) {
      notifyError(e);
    }
    searching = false;
    notifyListeners();
  }

  Future<String?> uploadBytes(String name, Uint8List bytes) async {
    if (token == null || httpApi == null) return null;
    final temp = await httpApi!.upload(
      token: token!,
      originalName: name,
      bytes: bytes,
    );
    return temp['id'] as String?;
  }

  Future<void> sendFiles(List<({String name, Uint8List bytes})> files) async {
    final ids = <String>[];
    for (final f in files) {
      final id = await uploadBytes(f.name, f.bytes);
      if (id != null) ids.add(id);
    }
    if (ids.isNotEmpty) await sendMessage('', files: ids);
  }

  Future<void> openDm(int userId) async {
    final raw = await trpc!.mutate('dms.open', {'userId': userId});
    final cid = asInt(_map(raw)['channelId']);
    await loadDms();
    if (cid != null) await selectChannel(cid);
  }

  Future<void> kick(int userId, String reason) =>
      trpc!.mutate('users.kick', {'userId': userId, 'reason': reason});
  Future<void> ban(int userId, String reason) =>
      trpc!.mutate('users.ban', {'userId': userId, 'reason': reason});
  Future<void> unban(int userId) =>
      trpc!.mutate('users.unban', {'userId': userId});
  Future<void> muteUser(int userId, bool muted) =>
      trpc!.mutate('users.mute', {'userId': userId, 'muted': muted});
  Future<void> deafenUser(int userId, bool deafened) =>
      trpc!.mutate('users.deafen', {'userId': userId, 'deafened': deafened});
  Future<void> deleteUser(int userId) =>
      trpc!.mutate('users.delete', {'userId': userId});
  Future<void> updateNickname(int userId, String nickname) => trpc!.mutate(
    'users.updateNickname',
    {'userId': userId, 'nickname': nickname},
  );

  Future<void> updateMe(Map<String, dynamic> input) async {
    await trpc!.mutate('users.update', input);
  }

  Future<void> updatePassword({
    required String current,
    required String next,
  }) async {
    await trpc!.mutate('users.updatePassword', {
      'currentPassword': current,
      'newPassword': next,
    });
  }

  Future<void> updateSecurity({
    required String questionId,
    required String answer,
    String? currentPassword,
  }) async {
    await trpc!.mutate('users.updateSecurityQuestion', {
      'securityQuestionId': questionId,
      'answer': answer,
      if (currentPassword != null && currentPassword.isNotEmpty)
        'currentPassword': currentPassword,
    });
  }

  Future<void> claimOwner(String secret) async {
    await trpc!.mutate('others.useSecretToken', {'token': secret});
  }

  Future<void> createChannel({
    required String name,
    required String type,
    int? categoryId,
    String? topic,
  }) async {
    await trpc!.mutate('channels.add', {
      'name': name,
      'type': type,
      if (categoryId != null) 'categoryId': categoryId,
      if (topic != null) 'topic': topic,
    });
  }

  Future<void> createCategory(String name) =>
      trpc!.mutate('categories.add', {'name': name});

  Future<void> deleteChannel(int id) =>
      trpc!.mutate('channels.delete', {'channelId': id});
  Future<void> deleteCategory(int id) =>
      trpc!.mutate('categories.delete', {'categoryId': id});

  static const _notifyLevels = {'all', 'mentions', 'nothing'};

  String channelNotifyLevel(int channelId) {
    final level = notificationOverrides[channelId];
    if (level != null && _notifyLevels.contains(level)) return level;
    if (store.notifyAll) return 'all';
    if (store.notifyMentions) return 'mentions';
    return 'nothing';
  }

  Future<void> setNotificationOverride(int channelId, String level) async {
    notificationOverrides[channelId] = level;
    notifyListeners();
    await trpc!.mutate('channels.setNotificationOverride', {
      'channelId': channelId,
      'level': level,
    });
  }

  Future<void> setVoiceStatus(int channelId, String status) async {
    final text = asOptionalString(status);
    final ch = channels[channelId];
    if (ch != null) {
      ch.topic = text;
      ch.voiceStatus = text;
      notifyListeners();
    }
    await trpc!.mutate('channels.updateVoiceStatus', {
      'channelId': channelId,
      'topic': text,
      'status': text,
    });
  }

  Future<void> joinVoice(int channelId) async {
    if (connectedVoiceChannelId == channelId && voiceState == 'connected') {
      return;
    }
    if (voiceState == 'connecting') return;
    if (!canJoinVoiceChannel(channelId)) {
      notifyMissingPermission();
      return;
    }
    if (connectedVoiceChannelId != null &&
        connectedVoiceChannelId != channelId) {
      await leaveVoice();
    }
    voiceState = 'connecting';
    voiceError = null;
    notifyListeners();

    // Mic + audio unlock must happen in the original tap gesture. Any long
    // await before getUserMedia breaks iOS/Safari (and some Android WebViews).
    await PlatformBridge.unlockAudio();
    var haveMic = false;
    try {
      await PlatformBridge.getUserMedia(
        audio: true,
        deviceId: store.micDevice,
        audioConstraints: store.audioConstraints(),
      );
      haveMic = true;
    } catch (e) {
      _log('getUserMedia: $e');
    }
    try {
      await PlatformBridge.ensureReady();
    } catch (e) {
      await _failVoice(e);
      notifyListeners();
      return;
    }

    try {
      await _establishVoice(channelId, haveMic: haveMic);
    } catch (e) {
      if (isAlreadyInVoiceError(e)) {
        try {
          await trpc?.mutate('voice.leave');
        } catch (_) {}
        _resetVoiceLocal();
        voiceState = 'connecting';
        await Future<void>.delayed(const Duration(milliseconds: 400));
        try {
          await _establishVoice(channelId, haveMic: haveMic);
        } catch (e2) {
          await _failVoice(e2);
        }
      } else {
        await _failVoice(e);
      }
    }
    if (isNativeMobile && connectedVoiceChannelId != null) {
      final voiceName = channels[connectedVoiceChannelId!]?.name ?? 'voice';
      await androidSyncKeepAlive(
        serverName: serverName.isEmpty ? 'Kurier' : serverName,
        voiceChannelName: voiceName,
      );
      await androidSyncPip(webcam: webcam, sharing: sharing);
    }
    notifyListeners();
  }

  Future<void> _establishVoice(int channelId, {required bool haveMic}) async {
    final raw = await trpc!.mutate('voice.join', {
      'channelId': channelId,
      'state': {'micMuted': micMuted, 'soundMuted': soundMuted},
    });
    final caps = routerRtpCapabilitiesOf(raw);
    if (caps == null) {
      throw StateError('voice.join did not return router RTP capabilities');
    }
    connectedVoiceChannelId = channelId;
    unawaited(_pushPresence());
    rtpCapabilities = await PlatformBridge.loadDevice(caps);
    try {
      await PlatformBridge.setOutputDevice(speakerOutputId);
    } catch (e) {
      _log('setOutputDevice: $e');
    }
    PlatformBridge.setCameraDevice(store.cameraDevice);
    if (store.ptt) micMuted = true;
    if (!_msBound) {
      PlatformBridge.listen(_onMsEvent);
      _msBound = true;
    }
    final ice = AppConfig.iceServers();
    final send = asJsonMap(await trpc!.mutate('voice.createProducerTransport'));
    sendTransportId = await PlatformBridge.createSendTransport(send, ice);
    final recv = asJsonMap(await trpc!.mutate('voice.createConsumerTransport'));
    _recvConnected = Completer<void>();
    await PlatformBridge.createRecvTransport(recv, ice);
    var micFailed = !haveMic;
    if (haveMic) {
      try {
        await PlatformBridge.produce(StreamKind.audio);
        PlatformBridge.pauseMic(micMuted || soundMuted);
      } catch (e) {
        _log('produce audio: $e');
        micMuted = true;
        micFailed = true;
      }
    } else {
      micMuted = true;
    }
    await _waitForRecvConnected();
    if (connectedVoiceChannelId != channelId) return;
    try {
      final producers = asJsonMap(await trpc!.query('voice.getProducers'));
      await _consumeRemoteIds(producers);
    } catch (e) {
      _log('getProducers: $e');
    }
    _scheduleProducerResync();
    PlatformBridge.resumePlayback();
    voiceState = 'connected';
    voiceError = micFailed ? micUnavailableKey : null;
    if (micFailed) unawaited(_syncVoiceState());
    _voiceConnectedAt = DateTime.now();
    _playbackDeadSince = null;
    _didLightPlaybackRecovery = false;
    _startVoiceStats();
    if (!_silentRejoining) {
      PlatformBridge.playSound(KurierSoundType.ownUserJoinedVoiceChannel);
    }
    syncKeepScreenAwake();
  }

  Future<void> _failVoice(Object e) async {
    voiceError = isPermissionError(e)
        ? missingPermissionKey
        : _voiceErrorText(e);
    notifyError(e);
    _log('joinVoice: $e');
    try {
      await trpc?.mutate('voice.leave');
    } catch (_) {}
    _resetVoiceLocal();
    voiceState = 'failed';
  }

  String _voiceErrorText(Object e) {
    var text = '$e';
    const prefix = 'Bad state: ';
    if (text.startsWith(prefix)) text = text.substring(prefix.length);
    if (text.contains("method not found: 'jsify'")) {
      return 'Voice engine failed to start. Refresh and try again.';
    }
    return text;
  }

  Future<void> _consumeRemoteIds(Map<String, dynamic> producers) async {
    Future<void> eat(String key, String kind) async {
      final ids = producers[key];
      if (ids is! List) return;
      for (final id in ids) {
        try {
          await consumeProducer(kind: kind, remoteId: asInt(id) ?? 0);
        } catch (e) {
          _log('consume $kind $id: $e');
        }
      }
    }

    await eat('remoteAudioIds', StreamKind.audio);
    await eat('remoteVideoIds', StreamKind.video);
  }

  bool _shouldConsumeProducer(String kind, int remoteId) {
    if (StreamKind.shouldAutoConsume(kind)) return true;
    if (kind == StreamKind.screen || kind == StreamKind.screenAudio) {
      return isWatchingStream(remoteId);
    }
    if (kind == StreamKind.externalVideo || kind == StreamKind.externalAudio) {
      return isWatchingStream(remoteId, external: true);
    }
    return false;
  }

  Future<void> consumeProducer({
    required String kind,
    required int remoteId,
    bool replace = false,
  }) async {
    if (remoteId == ownUserId) return;
    if (trpc == null) return;
    final mapKey = '$remoteId:$kind';
    final existing = consumerKeys[mapKey];
    if (existing != null &&
        !replace &&
        PlatformBridge.consumerTrackLive(existing)) {
      return;
    }
    if (existing != null) {
      consumerKeys.remove(mapKey);
      volumes.remove(mapKey);
      PlatformBridge.closeConsumer(existing);
    }
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _consumeProducerOnce(
          kind: kind,
          remoteId: remoteId,
          mapKey: mapKey,
        );
        return;
      } catch (e) {
        lastError = e;
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 250 * (attempt + 1)),
          );
        }
      }
    }
    throw lastError!;
  }

  Future<void> _consumeProducerOnce({
    required String kind,
    required int remoteId,
    required String mapKey,
  }) async {
    final raw = await trpc!.mutate('voice.consume', {
      'kind': kind,
      'remoteId': remoteId,
      'rtpCapabilities': rtpCapabilities ?? {},
    });
    final info = asJsonMap(raw);
    info['remoteId'] = remoteId;
    info['consumerKind'] = kind;
    info['rtpKind'] = kind.contains('audio') ? 'audio' : 'video';
    final key = await PlatformBridge.consume(info);
    consumerKeys[mapKey] = key;
    final streamMuted = StreamKind.startsClientMuted(kind);
    final localVol = kind == StreamKind.audio ? localUserVolume(remoteId) : 1.0;
    volumes[mapKey] = streamMuted ? 0 : localVol;
    if (soundMuted || streamMuted || localVol <= 0) {
      PlatformBridge.setVolume(key, 0);
    }
    PlatformBridge.resumePlayback();
    notifyListeners();
  }

  bool hasStreamConsumer(int remoteId, String kind) =>
      consumerKeys.containsKey('$remoteId:$kind');

  bool isWatchingStream(int remoteId, {bool external = false}) =>
      watchingStreams.contains(
        StreamKind.watchKey(remoteId, external: external),
      );

  bool canWatchStream(int remoteId, {bool external = false}) {
    final cid = connectedVoiceChannelId;
    if (cid == null || voiceState != 'connected') return false;
    if (external) {
      return (externalStreams[cid] ?? []).any((s) => s.streamId == remoteId);
    }
    return voiceMap[cid]?[remoteId]?.sharingScreen == true;
  }

  Future<void> watchStream(int remoteId, {bool external = false}) async {
    if (!canWatchStream(remoteId, external: external)) {
      notifyMissingPermission();
      return;
    }
    watchingStreams.add(StreamKind.watchKey(remoteId, external: external));
    notifyListeners();
    final kinds = external
        ? const [StreamKind.externalVideo, StreamKind.externalAudio]
        : const [StreamKind.screen, StreamKind.screenAudio];
    for (final kind in kinds) {
      try {
        await consumeProducer(kind: kind, remoteId: remoteId);
      } catch (e) {
        _log('watchStream $kind: $e');
      }
    }
    notifyListeners();
  }

  void stopWatching(int remoteId, {bool external = false}) {
    watchingStreams.remove(StreamKind.watchKey(remoteId, external: external));
    final kinds = external
        ? const [StreamKind.externalVideo, StreamKind.externalAudio]
        : const [StreamKind.screen, StreamKind.screenAudio];
    for (final kind in kinds) {
      final mapKey = '$remoteId:$kind';
      final stored = consumerKeys.remove(mapKey);
      volumes.remove(mapKey);
      if (stored != null) PlatformBridge.closeConsumer(stored);
    }
    notifyListeners();
  }

  bool showingWebcam(int userId, VoiceUserState st) {
    if (userId == ownUserId) return webcam;
    return st.webcamEnabled && hasStreamConsumer(userId, StreamKind.video);
  }

  String mediaKeyFor({
    required int remoteId,
    required String kind,
    bool local = false,
  }) {
    if (local) {
      if (kind == StreamKind.screen) return 'local:screen';
      return 'local:video';
    }
    return '$remoteId:$kind';
  }

  bool isStreamMuted(int remoteId, String kind) {
    final mapKey = '$remoteId:$kind';
    if (!consumerKeys.containsKey(mapKey)) return true;
    return (volumes[mapKey] ?? 0) <= 0;
  }

  void toggleStreamMute(int remoteId, String kind) {
    final mapKey = '$remoteId:$kind';
    final bridgeKey = consumerKeys[mapKey];
    if (bridgeKey == null) return;
    final next = isStreamMuted(remoteId, kind) ? 1.0 : 0.0;
    volumes[mapKey] = next;
    if (!soundMuted) PlatformBridge.setVolume(bridgeKey, next);
    notifyListeners();
  }

  void _applyConsumerVolumes() {
    final localSpeaking =
        store.attenuateOthers && (speaking[ownUserId] ?? 0) > 0;
    final factor = localSpeaking
        ? (1 - store.attenuationAmount / 100).clamp(0.0, 1.0)
        : 1.0;
    for (final e in consumerKeys.entries) {
      if (soundMuted) {
        PlatformBridge.setVolume(e.value, 0);
        continue;
      }
      var vol = volumes[e.key] ?? 1;
      if (localSpeaking && !e.key.startsWith('$ownUserId:')) {
        vol *= factor;
      }
      PlatformBridge.setVolume(e.value, vol);
    }
  }

  void _onMsEvent(String name, String payload) {
    if (name == 'speaking') {
      _onSpeaking(payload);
      return;
    }
    () async {
      try {
        if (name == 'connectSend') {
          await trpc!.mutate('voice.connectProducerTransport', {
            'dtlsParameters': jsonDecode(payload),
          });
          PlatformBridge.finishConnectSend(true);
        } else if (name == 'connectRecv') {
          await trpc!.mutate('voice.connectConsumerTransport', {
            'dtlsParameters': jsonDecode(payload),
          });
          PlatformBridge.finishConnectRecv(true);
        } else if (name == 'produce') {
          final body = jsonDecode(payload) as Map<String, dynamic>;
          final raw = await trpc!.mutate(
            'voice.produce',
            voiceProduceMutation(
              transportId: sendTransportId ?? '',
              body: body,
            ),
          );
          final id = raw is String
              ? raw
              : '${_map(raw)['id'] ?? _map(raw)['producerId'] ?? raw}';
          PlatformBridge.finishProduce(id.isEmpty ? null : id);
        } else if (name == 'sendState' || name == 'recvState') {
          _onTransportConnState(name, payload);
        } else if (name == 'visibility' && payload == 'visible') {
          await _restartIceBoth();
          PlatformBridge.resumePlayback();
          await _resyncRemoteProducers();
          await ensureAudioProducer();
          syncKeepScreenAwake();
        } else if (name == 'micEnded') {
          await ensureAudioProducer();
        } else if (name == 'screenEnded') {
          await _stopScreenShare();
        } else if (name == 'devicechange') {
          audioDevicesEpoch++;
          notifyListeners();
        }
      } catch (e) {
        if (name == 'connectSend') PlatformBridge.finishConnectSend(false);
        if (name == 'connectRecv') PlatformBridge.finishConnectRecv(false);
        if (name == 'produce') PlatformBridge.finishProduce(null);
        _log('mediasoup $name: $e');
      }
    }();
  }

  void _onSpeaking(String payload) {
    if (connectedVoiceChannelId == null) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return;
      final key = '${decoded['key'] ?? ''}';
      final uid = speakingUserIdFromKey(key, ownUserId);
      if (uid == null) return;
      var intensity = speakingIntensityFromJson(decoded);
      if (uid == ownUserId && micMuted) intensity = 0;
      _setSpeaking(uid, intensity);
    } catch (_) {}
  }

  void _setSpeaking(int userId, int intensity) {
    final prev = speaking[userId] ?? 0;
    if (intensity <= 0) {
      if (prev == 0) return;
      speaking.remove(userId);
    } else if (prev == intensity) {
      return;
    } else {
      speaking[userId] = intensity;
    }
    if (userId == ownUserId) _applyConsumerVolumes();
    notifyListeners();
  }

  int speakingOf(int userId, {bool micMuted = false}) {
    if (micMuted) return 0;
    if (userId == ownUserId && this.micMuted) return 0;
    return speaking[userId] ?? 0;
  }

  Future<void> leaveVoice() async {
    _autoRejoinAt.clear();
    final wasConnected = connectedVoiceChannelId != null;
    try {
      await trpc?.mutate('voice.leave');
    } catch (_) {}
    _resetVoiceLocal();
    if (wasConnected && !_silentRejoining) {
      PlatformBridge.playSound(KurierSoundType.ownUserLeftVoiceChannel);
    }
    unawaited(_pushPresence());
    notifyListeners();
  }

  void _resetVoiceLocal() {
    connectedVoiceChannelId = null;
    PlatformBridge.setKeepScreenAwake(false);
    PlatformBridge.closeAll();
    unawaited(androidStopVoice());
    webcam = false;
    sharing = false;
    voiceState = 'idle';
    consumerKeys.clear();
    volumes.clear();
    speaking.clear();
    watchingStreams.clear();
    _cancelProducerResyncs();
    _completeRecvConnected();
    _recvConnected = null;
    _stopVoiceStats();
    _sendConnState = '';
    _recvConnState = '';
    _iceDisconnectedSend?.cancel();
    _iceDisconnectedRecv?.cancel();
    _iceDisconnectedSend = null;
    _iceDisconnectedRecv = null;
    _voiceConnectedAt = null;
    _playbackDeadSince = null;
    _didLightPlaybackRecovery = false;
    voiceAudioLocked = false;
  }

  @visibleForTesting
  void applyVoiceLeave(dynamic d) => _onVoiceLeave(d);

  @visibleForTesting
  void applyVoiceMoved(dynamic d) => _onVoiceMoved(d);

  void _startVoiceStats() {
    _voiceStatsTimer?.cancel();
    _voiceStatsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _pollVoiceStats();
    });
    _pollVoiceStats();
  }

  void _stopVoiceStats() {
    _voiceStatsTimer?.cancel();
    _voiceStatsTimer = null;
    transportStats = TransportStatsData.empty;
    voiceRttMs = null;
  }

  Future<void> _pollVoiceStats() async {
    if (voiceState != 'connected') return;
    final next = await PlatformBridge.getTransportStats();
    if (voiceState != 'connected') return;
    transportStats = next;
    voiceRttMs = next.rttMs;
    notifyListeners();
    await _checkVoicePlaybackHealth();
  }

  void syncKeepScreenAwake() {
    final want = connectedVoiceChannelId != null && store.keepScreenOnVoice;
    PlatformBridge.setKeepScreenAwake(want);
  }

  Future<void> setKeepScreenOnVoice(bool v) async {
    await store.setKeepScreenOnVoice(v);
    syncKeepScreenAwake();
    notifyListeners();
  }

  Future<void> setMicMuted(bool v) async {
    micMuted = v;
    PlatformBridge.playSound(
      v ? KurierSoundType.ownUserMutedMic : KurierSoundType.ownUserUnmutedMic,
    );
    if (v) {
      PlatformBridge.pauseMic(true);
      _setSpeaking(ownUserId, 0);
    } else {
      await ensureAudioProducer();
    }
    await _syncVoiceState();
    notifyListeners();
  }

  String? get speakerOutputId => appliedSpeakerDevice ?? store.speakerDevice;

  Future<void> applySpeakerDevice(String? id) async {
    final next = isDefaultAudioOutputId(id) ? null : id;
    final prev = appliedSpeakerDevice;
    appliedSpeakerDevice = next;
    await store.setSpeakerDevice(next);
    try {
      await PlatformBridge.setOutputDevice(next);
    } catch (_) {
      appliedSpeakerDevice = prev;
      await store.setSpeakerDevice(prev);
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> applyMicForOutput(String? id) async {
    final next = id == null || id.isEmpty ? null : id;
    final prev = store.micDevice;
    await store.setMicDevice(next);
    try {
      await PlatformBridge.replaceMicDevice(
        deviceId: next,
        audioConstraints: store.audioConstraints(),
      );
      PlatformBridge.pauseMic(micMuted || soundMuted);
    } catch (_) {
      await store.setMicDevice(prev);
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<void> setSoundMuted(bool v) async {
    soundMuted = v;
    PlatformBridge.playSound(
      v
          ? KurierSoundType.ownUserMutedSound
          : KurierSoundType.ownUserUnmutedSound,
    );
    if (v) {
      micMuted = true;
      _setSpeaking(ownUserId, 0);
    }
    PlatformBridge.pauseMic(micMuted || soundMuted);
    _applyConsumerVolumes();
    await _syncVoiceState();
    notifyListeners();
  }

  Future<void> _syncVoiceState() async {
    if (connectedVoiceChannelId == null) return;
    try {
      await trpc!.mutate('voice.updateState', {
        'micMuted': micMuted,
        'soundMuted': soundMuted,
        'webcamEnabled': webcam,
        'sharingScreen': sharing,
      });
    } catch (_) {}
  }

  Future<void> toggleWebcam() async {
    if (connectedVoiceChannelId == null) return;
    if (webcam) {
      PlatformBridge.closeProducer(StreamKind.video);
      await trpc!.mutate('voice.closeProducer', {'kind': StreamKind.video});
      webcam = false;
      PlatformBridge.playSound(KurierSoundType.ownUserStoppedWebcam);
    } else {
      if (!canEnableWebcam()) {
        notifyMissingPermission();
        return;
      }
      await PlatformBridge.produce(
        StreamKind.video,
        simulcast: simulcastEnabled,
      );
      webcam = true;
      PlatformBridge.playSound(KurierSoundType.ownUserStartedWebcam);
    }
    await androidSyncPip(webcam: webcam, sharing: sharing);
    await _syncVoiceState();
    notifyListeners();
  }

  Future<void> toggleScreen({bool withAudio = false}) async {
    if (connectedVoiceChannelId == null) return;
    if (PlatformBridge.isIos) {
      notifyError('Screen share is not available on iOS Safari.');
      return;
    }
    if (sharing) {
      await _stopScreenShare();
    } else {
      if (!canShareScreen()) {
        notifyMissingPermission();
        return;
      }
      await PlatformBridge.getDisplayMedia(withAudio: withAudio);
      await PlatformBridge.produce(
        StreamKind.screen,
        simulcast: simulcastEnabled,
      );
      if (withAudio) {
        try {
          await PlatformBridge.produce(StreamKind.screenAudio);
        } catch (_) {}
      }
      sharing = true;
      PlatformBridge.playSound(KurierSoundType.ownUserStartedScreenshare);
      await androidSyncPip(webcam: webcam, sharing: sharing);
      await _syncVoiceState();
      notifyListeners();
    }
  }

  Future<void> _stopScreenShare() async {
    PlatformBridge.closeProducer(StreamKind.screen);
    PlatformBridge.closeProducer(StreamKind.screenAudio);
    try {
      await trpc?.mutate('voice.closeProducer', {'kind': StreamKind.screen});
    } catch (_) {}
    if (!sharing) return;
    sharing = false;
    PlatformBridge.playSound(KurierSoundType.ownUserStoppedScreenshare);
    await androidSyncPip(webcam: webcam, sharing: sharing);
    await _syncVoiceState();
    notifyListeners();
  }

  Future<void> changeShareSource({bool withAudio = false}) async {
    if (connectedVoiceChannelId == null || !sharing) return;
    await PlatformBridge.getDisplayMedia(withAudio: withAudio);
    notifyListeners();
  }

  Future<void> _restartIceBoth() async {
    if (connectedVoiceChannelId == null) return;
    if (_isConnBad(_sendConnState)) {
      await _restartIceDirection('send');
    }
    if (_isConnBad(_recvConnState)) {
      await _restartIceDirection('recv');
    }
  }

  bool _isConnBad(String state) => state == 'failed' || state == 'disconnected';

  void _onTransportConnState(String name, String payload) {
    if (name == 'sendState') {
      _sendConnState = payload;
      _armIceRestart(send: true, state: payload);
    } else {
      _recvConnState = payload;
      _armIceRestart(send: false, state: payload);
    }
    if (name == 'recvState' && payload == 'connected') {
      _completeRecvConnected();
      PlatformBridge.resumePlayback();
      unawaited(_resyncRemoteProducers());
    }
  }

  void _armIceRestart({required bool send, required String state}) {
    final timer = send ? _iceDisconnectedSend : _iceDisconnectedRecv;
    timer?.cancel();
    if (send) {
      _iceDisconnectedSend = null;
    } else {
      _iceDisconnectedRecv = null;
    }
    if (state == 'failed') {
      unawaited(_restartIceDirection(send ? 'send' : 'recv'));
      return;
    }
    if (state != 'disconnected') return;
    final next = Timer(const Duration(seconds: 2), () {
      final current = send ? _sendConnState : _recvConnState;
      if (current != 'connected' && current != 'connecting') {
        unawaited(_restartIceDirection(send ? 'send' : 'recv'));
      }
    });
    if (send) {
      _iceDisconnectedSend = next;
    } else {
      _iceDisconnectedRecv = next;
    }
  }

  Future<void> _restartIceDirection(String direction) async {
    if (connectedVoiceChannelId == null || trpc == null) return;
    try {
      final raw = await trpc!.mutate('voice.restartIce', {
        'direction': direction,
      });
      final params = iceParametersOf(raw);
      if (params == null) return;
      await PlatformBridge.restartIce(direction, params);
    } catch (e) {
      _log('restartIce $direction: $e');
    }
  }

  Future<void> _waitForRecvConnected() async {
    final c = _recvConnected;
    if (c == null || c.isCompleted) return;
    try {
      await c.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      _log('recv wait: $e');
    }
  }

  void _completeRecvConnected() {
    final c = _recvConnected;
    if (c != null && !c.isCompleted) c.complete();
  }

  Future<void> _resyncRemoteProducers() async {
    if (connectedVoiceChannelId == null || trpc == null) return;
    try {
      final producers = asJsonMap(await trpc!.query('voice.getProducers'));
      await _consumeRemoteIds(producers);
    } catch (e) {
      _log('resync producers: $e');
    }
  }

  static const _resyncDelaysMs = [400, 1500, 3500];

  void _scheduleProducerResync() {
    _cancelProducerResyncs();
    for (final ms in _resyncDelaysMs) {
      _producerResyncs.add(
        Timer(Duration(milliseconds: ms), _resyncRemoteProducers),
      );
    }
  }

  void _cancelProducerResyncs() {
    for (final t in _producerResyncs) {
      t.cancel();
    }
    _producerResyncs.clear();
  }

  Future<void> _checkVoicePlaybackHealth() async {
    if (_checkingPlayback || _silentRejoining || voiceState != 'connected') {
      return;
    }
    _checkingPlayback = true;
    try {
      final shouldReceive = shouldReceiveVoiceAudio(
        voiceState: voiceState,
        soundMuted: soundMuted,
        hasUnmutedRemote: hasUnmutedRemoteVoiceUser(
          channelId: connectedVoiceChannelId,
          ownUserId: ownUserId,
          voiceMap: voiceMap,
        ),
      );
      if (!shouldReceive) {
        _playbackDeadSince = null;
        _didLightPlaybackRecovery = false;
        if (voiceAudioLocked) {
          voiceAudioLocked = false;
          notifyListeners();
        }
        return;
      }
      final health = await PlatformBridge.playbackHealth();
      if (voiceState != 'connected') return;
      final expected = expectedRemoteAudioKeys(
        channelId: connectedVoiceChannelId,
        ownUserId: ownUserId,
        voiceMap: voiceMap,
        consumerKeys: consumerKeys,
      );
      final healthy = isVoicePlaybackHealthy(
        health: health,
        expectedAudioKeys: expected,
      );
      final now = DateTime.now();
      if (healthy) {
        _playbackDeadSince = null;
        _didLightPlaybackRecovery = false;
        if (voiceAudioLocked) {
          voiceAudioLocked = false;
          notifyListeners();
        }
        return;
      }
      final connectedAt = _voiceConnectedAt;
      final pastGrace =
          connectedAt != null &&
          now.difference(connectedAt) >= kVoicePlaybackGrace;
      if (!pastGrace) return;
      if (isVoicePlaybackGestureLocked(
        health: health,
        expectedAudioKeys: expected,
      )) {
        if (!voiceAudioLocked) {
          voiceAudioLocked = true;
          notifyListeners();
        }
        return;
      }
      if (voiceAudioLocked) {
        voiceAudioLocked = false;
        notifyListeners();
      }
      _playbackDeadSince ??= now;
      if (!_didLightPlaybackRecovery) {
        _didLightPlaybackRecovery = true;
        PlatformBridge.resumePlayback();
        await _resyncRemoteProducers();
        await _restartIceBoth();
        return;
      }
      final heldDead =
          now.difference(_playbackDeadSince!) >= kVoicePlaybackDeadHold;
      if (!shouldSilentRejoinVoice(
        shouldReceive: shouldReceive,
        playbackHealthy: healthy,
        pastGrace: pastGrace,
        heldDead: heldDead,
        rejoinsInWindow: rejoinsInVoiceWindow(_autoRejoinAt, now),
      )) {
        return;
      }
      await _silentRejoinVoice();
    } finally {
      _checkingPlayback = false;
    }
  }

  Future<void> enableVoiceAudio() async {
    await PlatformBridge.unlockAudio();
    PlatformBridge.resumePlayback();
    voiceAudioLocked = false;
    notifyListeners();
  }

  Future<void> _silentRejoinVoice() async {
    final channelId = connectedVoiceChannelId;
    if (channelId == null || _silentRejoining) return;
    _silentRejoining = true;
    _autoRejoinAt.add(DateTime.now());
    _ignoreOwnVoiceLeaveUntil = DateTime.now().add(const Duration(seconds: 4));
    final keepMic = micMuted;
    final keepSound = soundMuted;
    final keepCam = webcam;
    try {
      voiceState = 'connecting';
      notifyListeners();
      try {
        await trpc?.mutate('voice.leave');
      } catch (_) {}
      _resetVoiceLocal();
      voiceState = 'connecting';
      micMuted = keepMic;
      soundMuted = keepSound;
      await Future<void>.delayed(const Duration(milliseconds: 400));
      try {
        await PlatformBridge.unlockAudio();
      } catch (_) {}
      var haveMic = false;
      try {
        await PlatformBridge.getUserMedia(
          audio: true,
          deviceId: store.micDevice,
          audioConstraints: store.audioConstraints(),
        );
        haveMic = true;
      } catch (e) {
        _log('silent rejoin getUserMedia: $e');
      }
      try {
        await PlatformBridge.ensureReady();
        await _establishVoice(channelId, haveMic: haveMic);
        if (keepCam && voiceState == 'connected') {
          try {
            await PlatformBridge.produce(
              StreamKind.video,
              simulcast: simulcastEnabled,
            );
            webcam = true;
            await _syncVoiceState();
          } catch (e) {
            _log('silent rejoin webcam: $e');
          }
        }
      } catch (e) {
        _log('silent rejoin: $e');
        try {
          await trpc?.mutate('voice.leave');
        } catch (_) {}
        _resetVoiceLocal();
      }
    } finally {
      _silentRejoining = false;
      notifyListeners();
    }
  }

  Future<void> ensureAudioProducer() async {
    if (connectedVoiceChannelId == null || voiceState != 'connected') return;
    if (PlatformBridge.audioProducerLive) {
      PlatformBridge.pauseMic(micMuted || soundMuted);
      return;
    }
    try {
      PlatformBridge.closeProducer(StreamKind.audio);
      try {
        await trpc?.mutate('voice.closeProducer', {'kind': StreamKind.audio});
      } catch (_) {}
      await PlatformBridge.getUserMedia(
        audio: true,
        deviceId: store.micDevice,
        audioConstraints: store.audioConstraints(),
      );
      await PlatformBridge.produce(StreamKind.audio);
      PlatformBridge.pauseMic(micMuted || soundMuted);
    } catch (e) {
      _log('ensureAudioProducer: $e');
    }
  }

  Future<void> pttDown() async {
    if (!store.ptt || connectedVoiceChannelId == null) return;
    await ensureAudioProducer();
    PlatformBridge.pauseMic(false);
  }

  Future<void> pttUp() async {
    if (!store.ptt || connectedVoiceChannelId == null) return;
    PlatformBridge.pauseMic(true);
  }

  Future<void> moveUser(int userId, int channelId) async {
    await trpc!.mutate('voice.moveUser', {
      'userId': userId,
      'channelId': channelId,
    });
  }

  Future<dynamic> musicAction(String name, [dynamic payload]) {
    return trpc!.mutate('plugins.executeAction', {
      'pluginId': 'music-bot',
      'actionName': name,
      if (payload != null) 'payload': payload,
    });
  }

  bool get hasMusicBot =>
      pluginsMetadata.any((p) => '$p'.contains('music-bot')) ||
      pluginCommands.any((c) => '$c'.contains('music-bot'));

  Future<void> _persistToken(String host, String t, bool auto) async {
    token = t;
    final idx = hosts.indexWhere((h) => h.host == host);
    if (idx >= 0) {
      hosts[idx].token = t;
      hosts[idx].autoLogin = auto;
    } else {
      hosts = [...hosts, SavedHost(host: host, token: t, autoLogin: auto)];
    }
    await store.saveHosts(hosts);
    await store.setActiveHost(host);
  }

  void handleNotificationAction(String action) {
    if (action == 'mute') {
      setMicMuted(!micMuted);
    } else if (action == 'deafen') {
      setSoundMuted(!soundMuted);
    } else if (action == 'leave') {
      leaveVoice();
    } else if (action == 'disconnect') {
      unawaited(disconnect());
    }
  }

  Future<void> disconnect({bool forgetToken = true}) async {
    _closingByUser = true;
    _recoverTimer?.cancel();
    _recovering = false;
    _recoverAttempts = 0;
    unawaited(androidStopKeepAlive());
    _typingSweep?.cancel();
    _stopVoiceStats();
    PlatformBridge.stopSoundKeepAlive();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    if (connectedVoiceChannelId != null) {
      try {
        await trpc?.mutate('voice.leave');
      } catch (_) {}
      PlatformBridge.closeAll();
    }
    await trpc?.close(silent: true);
    trpc = null;
    if (forgetToken && activeHost != null) {
      final idx = hosts.indexWhere((h) => h.host == activeHost);
      if (idx >= 0) hosts[idx].token = null;
      await store.saveHosts(hosts);
    }
    await androidOnLogout();
    join = null;
    serverKlipyKey = null;
    _klipyDiscover = null;
    users.clear();
    channels.clear();
    messages.clear();
    nextCursor.clear();
    loadingMessages.clear();
    fetchingMessages.clear();
    detachedChannels.clear();
    jumpTargetChannelId = null;
    jumpTargetMessageId = null;
    selectedChannelId = null;
    overlay = null;
    profileUser = null;
    profileAnchor = null;
    phase = SessionPhase.login;
    _closingByUser = false;
    notifyListeners();
  }

  void openOverlay(String name, {String? tab, int? channelId}) {
    overlay = name;
    if (tab != null) settingsTab = tab;
    settingsChannelId = channelId;
    notifyListeners();
  }

  void closeOverlay() {
    overlay = null;
    profileUser = null;
    profileAnchor = null;
    notifyListeners();
  }

  void showProfile(KurierUser user, {Offset? anchor}) {
    profileUser = user;
    profileAnchor = anchor;
    notifyListeners();
  }

  String fileUrl(KurierFile file) => httpApi?.publicUrl(file) ?? '';

  List<CustomEmoji> get customEmojis => emojis.values
      .map((e) => CustomEmoji(name: e.name, url: fileUrl(e.file)))
      .toList();

  void _log(Object e) {
    logs.add('${DateTime.now().toIso8601String()} $e');
    if (logs.length > 200) logs.removeAt(0);
    debugPrint('$e');
  }

  Future<ActivityLogPage> activityLog({
    bool security = false,
    int? cursor,
    String? type,
    int? userId,
  }) async {
    if (trpc == null) return const ActivityLogPage();
    try {
      final raw = await trpc!.query(
        security ? 'activityLog.getSecurity' : 'activityLog.get',
        {
          if (cursor != null) 'cursor': cursor,
          'limit': kActivityLogLimit,
          if (type != null && type.isNotEmpty) 'types': [type],
          if (userId != null) 'userId': userId,
        },
      );
      final map = _map(raw);
      final list = map['items'] as List? ?? (raw is List ? raw : const []);
      return ActivityLogPage(
        items: [
          for (final e in list)
            if (e is Map) Map<String, dynamic>.from(e),
        ],
        nextCursor: asInt(map['nextCursor']),
      );
    } catch (e) {
      _log(e);
      return const ActivityLogPage();
    }
  }

  Future<Map<String, dynamic>> getFullSettings() async {
    return _map(await trpc!.query('others.getSettings'));
  }

  Future<Map<String, dynamic>> getStorageSettings() async {
    if (trpc == null) return {};
    try {
      return _map(await trpc!.query('others.getStorageSettings'));
    } catch (e) {
      _log(e);
      final settings = await getFullSettings();
      return {
        'storageSettings': settings,
        'diskMetrics': {
          'totalSpace': settings['totalSpace'] ?? settings['totalDiskSpace'],
          'freeSpace': settings['freeSpace'] ?? settings['availableSpace'],
          'usedSpace': settings['usedSpace'] ?? settings['systemUsed'],
          'sharkordUsedSpace':
              settings['sharkordUsedSpace'] ??
              settings['usedStorage'] ??
              settings['kurierUsed'],
        },
      };
    }
  }

  Future<void> downloadServerBackup() async {
    if (httpApi == null || token == null) {
      throw ApiException('Backup export failed');
    }
    final backup = await httpApi!.downloadBackup(token!);
    PlatformBridge.downloadBytes(backup.bytes, backup.filename);
  }

  Future<void> updateServerSettings(Map<String, dynamic> input) =>
      trpc!.mutate('others.updateSettings', input);

  Future<dynamic> getUpdate() => trpc!.query('others.getUpdate');
  Future<void> applyUpdate() => trpc!.mutate('others.updateServer');

  Future<List<dynamic>> getInvites() async {
    final raw = await trpc!.query('invites.getAll');
    return raw is List ? raw : List.from(_map(raw)['invites'] as List? ?? []);
  }

  Future<void> addInvite({int? maxUses, int? roleId}) =>
      trpc!.mutate('invites.add', {
        if (maxUses != null) 'maxUses': maxUses,
        if (roleId != null) 'roleId': roleId,
      });

  Future<void> deleteInvite(int id) =>
      trpc!.mutate('invites.delete', {'inviteId': id});

  Future<List<Map<String, dynamic>>> getAccessBans() async {
    if (trpc == null) return const [];
    try {
      final raw = await trpc!.query('accessBans.get', {'limit': 100});
      final map = _map(raw);
      final list = raw is List
          ? raw
          : (map['items'] as List? ?? map['bans'] as List? ?? const []);
      return [
        for (final e in list)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } catch (e) {
      _log(e);
      return const [];
    }
  }

  Future<void> addAccessBan(Map<String, dynamic> input) =>
      trpc!.mutate('accessBans.add', input);
  Future<void> removeAccessBan(int id) =>
      trpc!.mutate('accessBans.remove', {'id': id});

  Future<List<dynamic>> getPlugins() async {
    final raw = await trpc!.query('plugins.get');
    return List.from(_map(raw)['plugins'] as List? ?? const []);
  }

  Future<void> togglePlugin(String id, bool enabled) =>
      trpc!.mutate('plugins.toggle', {'pluginId': id, 'enabled': enabled});
  Future<void> installPlugin(String id, String version) =>
      trpc!.mutate('plugins.install', {'pluginId': id, 'version': version});
  Future<void> removePlugin(String id) =>
      trpc!.mutate('plugins.remove', {'pluginId': id});
  Future<void> updatePlugin(String id) =>
      trpc!.mutate('plugins.update', {'pluginId': id});

  Future<List<dynamic>> fetchMarketplace() async {
    try {
      final res = await http.get(Uri.parse(AppConfig.marketplaceUrl));
      if (res.statusCode != 200) return const [];
      final decoded = jsonDecode(res.body);
      if (decoded is List) return decoded;
      if (decoded is Map && decoded['plugins'] is List) {
        return List.from(decoded['plugins'] as List);
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> addRole(String name) =>
      trpc!.mutate('roles.add', {'name': name});
  Future<void> updateRole(Map<String, dynamic> input) =>
      trpc!.mutate('roles.update', input);
  Future<void> deleteRole(int id) =>
      trpc!.mutate('roles.delete', {'roleId': id});
  Future<void> reorderRoles(List<int> ids) =>
      trpc!.mutate('roles.reorder', {'roleIds': ids});
  Future<void> setDefaultRole(int id) =>
      trpc!.mutate('roles.setDefault', {'roleId': id});

  Future<void> addUserRole(int userId, int roleId) =>
      trpc!.mutate('users.addRole', {'userId': userId, 'roleId': roleId});
  Future<void> removeUserRole(int userId, int roleId) =>
      trpc!.mutate('users.removeRole', {'userId': userId, 'roleId': roleId});

  Future<void> addEmoji(String name, String fileId) =>
      trpc!.mutate('emojis.add', {'name': name, 'fileId': fileId});
  Future<void> deleteEmoji(int id) =>
      trpc!.mutate('emojis.delete', {'emojiId': id});

  Future<void> resetUserPassword(int userId, String password) => trpc!.mutate(
    'users.resetPassword',
    {'userId': userId, 'newPassword': password},
  );

  Future<UserAdminInfo?> getUserInfo(int userId) async {
    final override = userInfoOverride;
    if (override != null) return override(userId);
    if (trpc == null) return null;
    try {
      final raw = await trpc!.query('users.getInfo', {'userId': userId});
      final map = _map(raw);
      final userRaw = map['user'];
      final user = userRaw is Map
          ? KurierUser.fromJson(Map<String, dynamic>.from(userRaw))
          : users[userId];
      if (user == null) return null;
      final loginsRaw = map['logins'] as List? ?? const [];
      final filesRaw = map['files'] as List? ?? const [];
      final messagesRaw = map['messages'] as List? ?? const [];
      final messages = [
        for (final e in messagesRaw)
          if (e is Map) KurierMessage.fromJson(Map<String, dynamic>.from(e)),
      ];
      final files = [
        for (final e in filesRaw)
          if (e is Map) KurierFile.fromJson(Map<String, dynamic>.from(e)),
      ];
      final storageRaw = map['storage'];
      return UserAdminInfo(
        user: user,
        logins: [
          for (final e in loginsRaw)
            if (e is Map) UserLoginInfo.fromJson(Map<String, dynamic>.from(e)),
        ],
        files: files,
        messages: messages,
        storage: storageRaw is Map
            ? UserStorageInfo.fromJson(Map<String, dynamic>.from(storageRaw))
            : UserStorageInfo(fileCount: files.length),
        linkCount: countUniqueLinks(messages.map((m) => m.content)),
      );
    } catch (e) {
      _log(e);
      return null;
    }
  }

  Future<void> changeAvatar(String? fileId) =>
      trpc!.mutate('users.changeAvatar', {'fileId': fileId});
  Future<void> changeBanner(String? fileId) =>
      trpc!.mutate('users.changeBanner', {'fileId': fileId});
  Future<void> changeLogo(String? fileId) =>
      trpc!.mutate('others.changeLogo', {'fileId': fileId});

  Future<Map<String, dynamic>> getChannelPermissions(int channelId) async {
    return _map(
      await trpc!.query('channels.getPermissions', {'channelId': channelId}),
    );
  }

  Future<void> updateChannelPermissions(Map<String, dynamic> input) =>
      trpc!.mutate('channels.updatePermissions', input);

  Future<void> updateChannel(Map<String, dynamic> input) =>
      trpc!.mutate('channels.update', input);

  Future<List<dynamic>> getPluginLogs(String pluginId) async {
    final raw = await trpc!.query('plugins.getLogs', {'pluginId': pluginId});
    return raw is List ? raw : List.from(_map(raw)['logs'] as List? ?? []);
  }

  Future<dynamic> executeCommand(
    String pluginId,
    String command, [
    dynamic payload,
  ]) => trpc!.mutate('plugins.executeCommand', {
    'pluginId': pluginId,
    'command': command,
    if (payload != null) 'payload': payload,
  });

  Future<Map<String, dynamic>> getPluginSettings(String pluginId) async {
    return _map(
      await trpc!.query('plugins.getSettings', {'pluginId': pluginId}),
    );
  }

  Future<void> updatePluginSetting(
    String pluginId,
    String key,
    dynamic value,
  ) => trpc!.mutate('plugins.updateSetting', {
    'pluginId': pluginId,
    'key': key,
    'value': value,
  });

  Future<List<Map<String, dynamic>>> getLockedUsers() async {
    if (trpc == null) return const [];
    try {
      final raw = await trpc!.query('users.getLocked');
      final list = raw is List
          ? raw
          : List.from(_map(raw)['users'] as List? ?? []);
      return [
        for (final e in list)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    } catch (e) {
      _log(e);
      return const [];
    }
  }

  Future<void> unlockUser(int userId) =>
      trpc!.mutate('users.unlock', {'userId': userId});

  @override
  void dispose() {
    _panelWidthSave?.cancel();
    _voiceStatsTimer?.cancel();
    _recoverTimer?.cancel();
    _focusAwayTimer?.cancel();
    _cancelProducerResyncs();
    super.dispose();
  }
}

final sessionProvider = ChangeNotifierProvider<SessionController>((ref) {
  final c = SessionController();
  c.boot();
  return c;
});

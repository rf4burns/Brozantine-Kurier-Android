import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/native_channels.dart';
import '../protocol/trpc_client.dart';
import 'push_inbox.dart';
import 'push_kind.dart';

class PendingShare {
  const PendingShare({this.paths = const [], this.text});
  final List<String> paths;
  final String? text;
}

class PendingDeepLink {
  const PendingDeepLink({this.channelId, this.messageId});
  final int? channelId;
  final int? messageId;
}

const _secure = FlutterSecureStorage();
const _jwtKey = 'kurier.jwt';
const _originKey = 'kurier.origin';
const _lockKey = 'kurier.appLock';
const _fcmKey = 'kurier.fcmToken';
const _inboxKey = 'kurier.pushInbox.v1';

final _inbox = PushInbox();
bool _inboxLoaded = false;

final _notifications = FlutterLocalNotificationsPlugin();
final _auth = LocalAuthentication();

void Function(String action)? onVoiceNotificationAction;
void Function(PendingDeepLink link)? onAndroidNotificationOpened;
void Function(int channelId)? onAndroidMarkRead;

PendingShare? _pendingShare;
PendingDeepLink? _pendingDeepLink;
StreamSubscription? _shareSub;
bool _firebaseReady = false;
bool _appLockEnabled = false;
bool _appForeground = true;
String _keepAliveServer = 'Kurier';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@drawable/ic_stat_kurier');
  await plugin.initialize(
    const InitializationSettings(android: androidInit),
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
  await _ensurePushChannels(plugin);
  await _ensureInboxLoaded();
  final data = Map<String, dynamic>.from(message.data);
  final copy = fcmDisplayText(
    data,
    notificationTitle: message.notification?.title,
    notificationBody: message.notification?.body,
  );
  await _showMessageNotification(
    title: copy.title,
    body: copy.body,
    data: data,
    plugin: plugin,
  );
}

Future<void> _ensureInboxLoaded() async {
  if (_inboxLoaded) return;
  _inboxLoaded = true;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_inboxKey);
    if (raw != null && raw.isNotEmpty) _inbox.loadEncoded(raw);
  } catch (_) {}
}

Future<void> _persistInbox() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_inboxKey, _inbox.encode());
  } catch (_) {}
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  _onNotificationResponse(response);
}

const _messageActions = <AndroidNotificationAction>[
  AndroidNotificationAction(
    'mark_read',
    'Mark as read',
    showsUserInterface: false,
    cancelNotification: true,
    semanticAction: SemanticAction.markAsRead,
  ),
];

Future<void> _ensurePushChannels([
  FlutterLocalNotificationsPlugin? plugin,
]) async {
  final androidPlugin = (plugin ?? _notifications)
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  if (androidPlugin == null) return;
  for (final kind in PushKind.values) {
    await androidPlugin.createNotificationChannel(
      AndroidNotificationChannel(
        kind.androidChannelId,
        kind.androidChannelName,
        importance: Importance.max,
      ),
    );
  }
}

Future<void> _showMessageNotification({
  required String title,
  required String body,
  required Map<String, dynamic> data,
  FlutterLocalNotificationsPlugin? plugin,
  bool silent = false,
}) async {
  await _ensureInboxLoaded();
  final kind = PushKind.parse(data['kind']?.toString());
  final channelId = int.tryParse('${data['channelId'] ?? ''}');
  final messageId = int.tryParse('${data['messageId'] ?? ''}');
  final channelLabel = data['channelName']?.toString().trim();
  final lines = _inbox.add(
    kind,
    PushInboxLine(
      author: title,
      body: body,
      channelId: channelId,
      messageId: messageId,
      channelLabel: (channelLabel != null && channelLabel.isNotEmpty)
          ? channelLabel
          : null,
    ),
  );
  await _persistInbox();
  await _postKind(
    kind,
    data: {
      ...data,
      'kind': kind.wire,
      if (channelId != null) 'channelId': channelId,
      if (messageId != null) 'messageId': messageId,
    },
    latest: lines.last,
    plugin: plugin,
    silent: silent,
  );
}

Future<void> _postKind(
  PushKind kind, {
  required Map<String, dynamic> data,
  PushInboxLine? latest,
  FlutterLocalNotificationsPlugin? plugin,
  bool silent = false,
}) async {
  final view = _inbox.presentation(kind);
  if (view.lines.isEmpty) {
    await _cancelKind(kind, plugin: plugin);
    return;
  }
  final payload = jsonEncode({
    ...data,
    'kind': kind.wire,
    if (latest?.channelId != null) 'channelId': latest!.channelId,
    if (latest?.messageId != null) 'messageId': latest!.messageId,
  });
  var postedNative = false;
  if (plugin == null) {
    try {
      await kurierNative.invokeMethod('notify', {
        'title': view.title,
        'body': view.body,
        'kind': kind.wire,
        'lines': view.lines,
        'chatChannelId': latest?.channelId,
        'chatChannelIds': _inbox.channelIds(kind).toList(),
        'messageId': latest?.messageId,
        'silent': silent,
      });
      postedNative = true;
    } catch (_) {}
  }
  if (postedNative) return;
  final p = plugin ?? _notifications;
  await p.show(
    kind.androidNotificationId,
    view.title,
    view.body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        kind.androidChannelId,
        kind.androidChannelName,
        channelDescription: kind.androidChannelName,
        importance: Importance.max,
        priority: Priority.high,
        icon: '@drawable/ic_stat_kurier',
        category: AndroidNotificationCategory.message,
        visibility: NotificationVisibility.public,
        playSound: !silent,
        enableVibration: !silent,
        silent: silent,
        onlyAlertOnce: silent,
        ticker: view.title,
        autoCancel: true,
        number: view.lines.length,
        styleInformation: InboxStyleInformation(
          view.lines,
          contentTitle: view.title,
          summaryText: kind.inboxTitle(view.lines.length),
        ),
        actions: _messageActions,
      ),
    ),
    payload: payload,
  );
}

Future<void> _cancelKind(
  PushKind kind, {
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  _inbox.clear(kind);
  await _persistInbox();
  try {
    await kurierNative.invokeMethod('cancelNotify', {'kind': kind.wire});
  } catch (_) {}
  try {
    await (plugin ?? _notifications).cancel(kind.androidNotificationId);
  } catch (_) {}
}

void androidSetAppForeground(bool foreground) {
  _appForeground = foreground;
}

bool get androidIsAppForeground => _appForeground;

Future<void> androidShowIncomingNotification({
  required String title,
  required String body,
  required String kind,
  int? channelId,
  int? messageId,
  String? channelName,
}) async {
  if (!Platform.isAndroid) return;
  await _showMessageNotification(
    title: title,
    body: body,
    data: {
      'kind': kind,
      if (channelId != null) 'channelId': channelId,
      if (messageId != null) 'messageId': messageId,
      if (channelName != null && channelName.isNotEmpty)
        'channelName': channelName,
    },
  );
}

Future<void> androidClearChannelNotifications(int channelId) async {
  if (!Platform.isAndroid) return;
  await _ensureInboxLoaded();
  final changed = _inbox.removeChannel(channelId);
  if (changed.isEmpty) return;
  await _persistInbox();
  for (final kind in changed) {
    final remaining = _inbox.lines(kind);
    if (remaining.isEmpty) {
      await _cancelKind(kind);
      continue;
    }
    await _postKind(
      kind,
      data: {
        'kind': kind.wire,
        'channelId': remaining.last.channelId,
        'messageId': remaining.last.messageId,
      },
      latest: remaining.last,
      silent: true,
    );
  }
}

Future<void> initAndroidRuntime() async {
  if (!Platform.isAndroid) return;
  final prefs = await SharedPreferences.getInstance();
  _appLockEnabled = prefs.getBool(_lockKey) ?? false;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _firebaseReady = true;
  } catch (_) {
    _firebaseReady = false;
  }
  const androidInit = AndroidInitializationSettings('@drawable/ic_stat_kurier');
  await _notifications.initialize(
    const InitializationSettings(android: androidInit),
    onDidReceiveNotificationResponse: _onNotificationResponse,
    onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
  );
  await _ensurePushChannels();
  await _ensureInboxLoaded();
  final androidPlugin = _notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  try {
    await androidPlugin?.requestNotificationsPermission();
  } catch (_) {}
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'kurier_voice',
      'Voice',
      importance: Importance.low,
    ),
  );
  kurierNative.setMethodCallHandler((call) async {
    if (call.method == 'voiceAction' && call.arguments is String) {
      onVoiceNotificationAction?.call(call.arguments as String);
      return;
    }
    if (call.method == 'notificationOpened') {
      _onNativeNotificationOpened(call.arguments);
      return;
    }
    if (call.method == 'markRead') {
      unawaited(_onNativeMarkRead(call.arguments));
    }
  });
  _shareSub?.cancel();
  _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(_onShare);
  final initial = await ReceiveSharingIntent.instance.getInitialMedia();
  if (initial.isNotEmpty) _onShare(initial);
  if (_firebaseReady) {
    FirebaseMessaging.onMessage.listen((msg) {
      // foreground: in-app banner already plays via session; skip shade
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_onRemoteTap);
    final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMsg != null) _onRemoteTap(initialMsg);
  }
}

void _onShare(List<SharedMediaFile> files) {
  _pendingShare = PendingShare(
    paths: files.map((f) => f.path).where((p) => p.isNotEmpty).toList(),
    text: files
        .map((f) => f.message ?? '')
        .firstWhere((m) => m.isNotEmpty, orElse: () => ''),
  );
}

void _onRemoteTap(RemoteMessage msg) {
  _pendingDeepLink = PendingDeepLink(
    channelId: int.tryParse('${msg.data['channelId'] ?? ''}'),
    messageId: int.tryParse('${msg.data['messageId'] ?? ''}'),
  );
}

void _onNativeNotificationOpened(dynamic arguments) {
  final data = arguments is Map
      ? Map<String, dynamic>.from(arguments)
      : <String, dynamic>{};
  unawaited(_cancelKind(PushKind.parse(data['kind']?.toString())));
  final channelId = int.tryParse(
    '${data['channelId'] ?? data['chatChannelId'] ?? ''}',
  );
  final messageId = int.tryParse('${data['messageId'] ?? ''}');
  _pendingDeepLink = PendingDeepLink(
    channelId: (channelId != null && channelId != 0) ? channelId : null,
    messageId: (messageId != null && messageId != 0) ? messageId : null,
  );
  final link = _pendingDeepLink;
  if (link != null) onAndroidNotificationOpened?.call(link);
}

Future<void> _onNativeMarkRead(dynamic arguments) async {
  final data = arguments is Map
      ? Map<String, dynamic>.from(arguments)
      : <String, dynamic>{};
  final extraIds = <int>{};
  final rawIds = data['channelIds'];
  if (rawIds is List) {
    for (final value in rawIds) {
      final id = value is int ? value : int.tryParse('$value');
      if (id != null && id != 0) extraIds.add(id);
    }
  }
  await _markKindRead(
    PushKind.parse(data['kind']?.toString()),
    extraChannelIds: extraIds,
  );
}

void _onNotificationResponse(NotificationResponse response) {
  final payload = response.payload;
  Map<String, dynamic> data = {};
  if (payload != null && payload.isNotEmpty) {
    try {
      data = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {}
  }
  if (response.actionId == 'mark_read') {
    unawaited(_markKindRead(PushKind.parse(data['kind']?.toString())));
    return;
  }
  if (response.actionId == 'reply') {
    unawaited(_quickReply(data, response.input));
    return;
  }
  if (data['kind'] != null) {
    unawaited(_cancelKind(PushKind.parse(data['kind']?.toString())));
  }
  _pendingDeepLink = PendingDeepLink(
    channelId: int.tryParse('${data['channelId'] ?? ''}'),
    messageId: int.tryParse('${data['messageId'] ?? ''}'),
  );
  final link = _pendingDeepLink;
  if (link != null) onAndroidNotificationOpened?.call(link);
}

Future<void> _markKindRead(
  PushKind kind, {
  Set<int> extraChannelIds = const {},
}) async {
  await _ensureInboxLoaded();
  final channelIds = {..._inbox.channelIds(kind), ...extraChannelIds};
  await _cancelKind(kind);
  for (final id in channelIds) {
    if (onAndroidMarkRead != null) {
      onAndroidMarkRead!(id);
    } else {
      unawaited(_markRead({'channelId': id}));
    }
  }
}

Future<void> androidConsumePendingShare(dynamic session) async {
  final share = takePendingShare();
  if (share == null || session == null) return;
  final text = share.text?.trim() ?? '';
  if (share.paths.isEmpty && text.isNotEmpty) {
    await session.sendMessage(text);
    return;
  }
  final files = <({String name, Uint8List bytes})>[];
  for (final path in share.paths) {
    try {
      final bytes = await File(path).readAsBytes();
      files.add((name: path.split(RegExp(r'[/\\]')).last, bytes: bytes));
    } catch (_) {}
  }
  if (files.isNotEmpty) await session.sendFiles(files);
}

Future<void> _markRead(Map<String, dynamic> data) async {
  final origin = await _secure.read(key: _originKey);
  final jwt = await _secure.read(key: _jwtKey);
  final channelId = int.tryParse('${data['channelId'] ?? ''}');
  if (origin == null || jwt == null || channelId == null) return;
  final trpc = TrpcClient(
    url: trpcWsUrl(origin),
    connectionParams: () => {'token': jwt, 'deviceToken': ''},
  );
  try {
    await trpc.connect();
    await trpc.mutate('channels.markAsRead', {'channelId': channelId});
  } catch (_) {
  } finally {
    await trpc.close(silent: true);
  }
}

Future<void> _quickReply(Map<String, dynamic> data, String? text) async {
  final origin = await _secure.read(key: _originKey);
  final jwt = await _secure.read(key: _jwtKey);
  final channelId = int.tryParse('${data['channelId'] ?? ''}');
  final content = (text ?? '').trim();
  if (origin == null || jwt == null || channelId == null || content.isEmpty) {
    return;
  }
  final trpc = TrpcClient(
    url: trpcWsUrl(origin),
    connectionParams: () => {'token': jwt, 'deviceToken': ''},
  );
  try {
    await trpc.connect();
    await trpc.mutate('messages.send', {
      'channelId': channelId,
      'content': '<p>${_escape(content)}</p>',
      'files': <int>[],
    });
  } catch (_) {
  } finally {
    await trpc.close(silent: true);
  }
}

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

class AndroidNotifyPrefs {
  const AndroidNotifyPrefs({
    required this.notifyAll,
    required this.mentions,
    required this.dm,
    required this.replies,
  });
  final bool notifyAll;
  final bool mentions;
  final bool dm;
  final bool replies;
}

Future<AndroidNotifyPrefs?> androidLoadPrefs({required dynamic trpc}) async {
  if (!Platform.isAndroid || trpc is! TrpcClient) return null;
  try {
    final raw = await trpc.query('push.getPreferences');
    if (raw is! Map) return null;
    return AndroidNotifyPrefs(
      notifyAll: raw['notifyAll'] == true,
      mentions: raw['mentions'] == true,
      dm: raw['dm'] == true,
      replies: raw['replies'] == true,
    );
  } catch (_) {
    return null;
  }
}

Future<void> androidOpenNotificationSettings() async {
  if (!Platform.isAndroid) return;
  try {
    await kurierNative.invokeMethod('openNotificationSettings');
  } catch (_) {}
}

bool get androidNotificationSettingsAvailable => Platform.isAndroid;

Future<void> androidOnLogin({
  required dynamic trpc,
  required String origin,
  required String jwt,
}) async {
  if (!Platform.isAndroid) return;
  try {
    await Permission.notification.request();
  } catch (_) {}
  await androidStoreSession(origin: origin, jwt: jwt);
  if (trpc is TrpcClient) {
    if (_firebaseReady) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await _secure.write(key: _fcmKey, value: token);
          await trpc.mutate('push.registerToken', {
            'token': token,
            'platform': 'android',
          });
        }
        FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
          await _secure.write(key: _fcmKey, value: t);
          try {
            await trpc.mutate('push.registerToken', {
              'token': t,
              'platform': 'android',
            });
          } catch (_) {}
        });
      } catch (_) {}
    }
  }
}

Future<void> androidOnLogout() async {
  if (!Platform.isAndroid) return;
  try {
    final token = await _secure.read(key: _fcmKey);
    final origin = await _secure.read(key: _originKey);
    final jwt = await _secure.read(key: _jwtKey);
    if (token != null && origin != null && jwt != null) {
      final trpc = TrpcClient(
        url: trpcWsUrl(origin),
        connectionParams: () => {'token': jwt, 'deviceToken': ''},
      );
      try {
        await trpc.connect();
        await trpc.mutate('push.unregisterToken', {'token': token});
      } catch (_) {
      } finally {
        await trpc.close(silent: true);
      }
    }
  } catch (_) {}
  await _secure.delete(key: _jwtKey);
  await _secure.delete(key: _fcmKey);
}

Future<void> androidSyncPrefs({
  required dynamic trpc,
  required bool notifyAll,
  required bool mentions,
  required bool dm,
  required bool replies,
}) async {
  if (!Platform.isAndroid || trpc is! TrpcClient) return;
  try {
    await trpc.mutate('push.setPreferences', {
      'notifyAll': notifyAll,
      'mentions': mentions,
      'dm': dm,
      'replies': replies,
    });
  } catch (_) {}
}

Future<void> androidSyncKeepAlive({
  required String serverName,
  String? voiceChannelName,
}) async {
  if (!Platform.isAndroid) return;
  _keepAliveServer = serverName.isEmpty ? 'Kurier' : serverName;
  final voice = voiceChannelName?.trim() ?? '';
  if (voice.isEmpty) {
    await androidStopKeepAlive();
    return;
  }
  try {
    await Permission.notification.request();
  } catch (_) {}
  try {
    await kurierNative.invokeMethod('startKeepAlive', {
      'serverName': _keepAliveServer,
      'voiceChannelName': voice,
    });
  } catch (_) {}
}

Future<void> androidStopKeepAlive() async {
  if (!Platform.isAndroid) return;
  try {
    await kurierNative.invokeMethod('stopKeepAlive');
  } catch (_) {}
}

Future<void> androidStartVoice({required String channelName}) async {
  await androidSyncKeepAlive(
    serverName: _keepAliveServer,
    voiceChannelName: channelName,
  );
}

Future<void> androidStopVoice() async {
  await androidSyncPip(webcam: false, sharing: false);
  await androidStopKeepAlive();
}

Future<void> androidSyncPip({
  required bool webcam,
  required bool sharing,
}) async {
  if (!Platform.isAndroid) return;
  try {
    await kurierNative.invokeMethod('setPipAuto', {
      'enabled': webcam || sharing,
    });
  } catch (_) {}
}

Future<void> androidStoreSession({
  required String origin,
  required String jwt,
}) async {
  await _secure.write(key: _originKey, value: origin);
  await _secure.write(key: _jwtKey, value: jwt);
}

PendingShare? takePendingShare() {
  final v = _pendingShare;
  _pendingShare = null;
  return v;
}

PendingDeepLink? takePendingDeepLink() {
  final v = _pendingDeepLink;
  _pendingDeepLink = null;
  return v;
}

bool get androidAppLockEnabled => _appLockEnabled;

Future<void> setAndroidAppLockEnabled(bool enabled) async {
  _appLockEnabled = enabled;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_lockKey, enabled);
}

Future<bool> androidUnlock() async {
  if (!Platform.isAndroid || !_appLockEnabled) return true;
  try {
    return await _auth.authenticate(
      localizedReason: 'Unlock Kurier',
      options: const AuthenticationOptions(biometricOnly: false),
    );
  } catch (_) {
    return false;
  }
}

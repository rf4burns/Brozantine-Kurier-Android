import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/native_channels.dart';
import '../protocol/trpc_client.dart';

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

final _notifications = FlutterLocalNotificationsPlugin();
final _auth = LocalAuthentication();

void Function(String action)? onVoiceNotificationAction;

PendingShare? _pendingShare;
PendingDeepLink? _pendingDeepLink;
StreamSubscription? _shareSub;
bool _firebaseReady = false;
bool _appLockEnabled = false;

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
  final data = Map<String, dynamic>.from(message.data);
  final title =
      message.notification?.title ?? data['title']?.toString() ?? 'Kurier';
  final body = message.notification?.body ?? data['body']?.toString() ?? '';
  await _showMessageNotification(
    title: title,
    body: body,
    data: data,
    plugin: plugin,
  );
}

@pragma('vm:entry-point')
void startKurierVoiceTask() {
  FlutterForegroundTask.setTaskHandler(_VoiceTaskHandler());
}

class _VoiceTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onNotificationButtonPressed(String id) {
    FlutterForegroundTask.sendDataToMain({'action': id});
  }
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  _onNotificationResponse(response);
}

const _messageActions = <AndroidNotificationAction>[
  AndroidNotificationAction(
    'reply',
    'Reply',
    inputs: <AndroidNotificationActionInput>[
      AndroidNotificationActionInput(label: 'Reply'),
    ],
  ),
  AndroidNotificationAction('mark_read', 'Mark as read'),
];

Future<void> _showMessageNotification({
  required String title,
  required String body,
  required Map<String, dynamic> data,
  FlutterLocalNotificationsPlugin? plugin,
}) async {
  final p = plugin ?? _notifications;
  final id = int.tryParse('${data['messageId'] ?? ''}') ??
      DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
  await p.show(
    id,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'kurier_messages',
        'Messages',
        channelDescription: 'Chat messages',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_stat_kurier',
        actions: _messageActions,
      ),
    ),
    payload: jsonEncode(data),
  );
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
  final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'kurier_messages',
      'Messages',
      importance: Importance.high,
    ),
  );
  await androidPlugin?.createNotificationChannel(
    const AndroidNotificationChannel(
      'kurier_voice',
      'Voice',
      importance: Importance.low,
    ),
  );
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.addTaskDataCallback(_onFgData);
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

void _onNotificationResponse(NotificationResponse response) {
  final payload = response.payload;
  Map<String, dynamic> data = {};
  if (payload != null && payload.isNotEmpty) {
    try {
      data = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {}
  }
  if (response.actionId == 'mark_read') {
    unawaited(_markRead(data));
    return;
  }
  if (response.actionId == 'reply') {
    unawaited(_quickReply(data, response.input));
    return;
  }
  _pendingDeepLink = PendingDeepLink(
    channelId: int.tryParse('${data['channelId'] ?? ''}'),
    messageId: int.tryParse('${data['messageId'] ?? ''}'),
  );
}

void _onFgData(Object data) {
  if (data is Map && data['action'] is String) {
    onVoiceNotificationAction?.call('${data['action']}');
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

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

Future<void> androidOnLogin({
  required dynamic trpc,
  required String origin,
  required String jwt,
  required bool notifyAll,
  required bool mentions,
  required bool dm,
  required bool replies,
}) async {
  if (!Platform.isAndroid) return;
  await androidStoreSession(origin: origin, jwt: jwt);
  if (trpc is TrpcClient) {
    await androidSyncPrefs(
      trpc: trpc,
      notifyAll: notifyAll,
      mentions: mentions,
      dm: dm,
      replies: replies,
    );
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

Future<void> androidStartVoice({required String channelName}) async {
  if (!Platform.isAndroid) return;
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'kurier_voice',
      channelName: 'Voice',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(15000),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
  await FlutterForegroundTask.startService(
    notificationTitle: 'Kurier',
    notificationText: 'Connected to #$channelName',
    callback: startKurierVoiceTask,
    notificationButtons: const [
      NotificationButton(id: 'mute', text: 'Mute'),
      NotificationButton(id: 'deafen', text: 'Deafen'),
      NotificationButton(id: 'leave', text: 'Disconnect'),
    ],
  );
}

Future<void> androidStopVoice() async {
  if (!Platform.isAndroid) return;
  try {
    await FlutterForegroundTask.stopService();
  } catch (_) {}
  await androidSyncPip(webcam: false, sharing: false);
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

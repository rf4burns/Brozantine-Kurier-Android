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

Future<void> initAndroidRuntime() async {}

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

Future<AndroidNotifyPrefs?> androidLoadPrefs({required dynamic trpc}) async =>
    null;

Future<void> androidOpenNotificationSettings() async {}

bool get androidNotificationSettingsAvailable => false;

Future<void> androidOnLogin({
  required dynamic trpc,
  required String origin,
  required String jwt,
}) async {}

Future<void> androidOnLogout() async {}

Future<void> androidSyncPrefs({
  required dynamic trpc,
  required bool notifyAll,
  required bool mentions,
  required bool dm,
  required bool replies,
}) async {}

Future<void> androidStartVoice({required String channelName}) async {}

Future<void> androidStopVoice() async {}

Future<void> androidSyncKeepAlive({
  required String serverName,
  String? voiceChannelName,
}) async {}

Future<void> androidStopKeepAlive() async {}

Future<void> androidSyncPip({
  required bool webcam,
  required bool sharing,
}) async {}

Future<void> androidStoreSession({
  required String origin,
  required String jwt,
}) async {}

void Function(String action)? onVoiceNotificationAction;
void Function(PendingDeepLink link)? onAndroidNotificationOpened;
Future<void> Function(int channelId)? onAndroidMarkRead;

Future<void> androidConsumePendingShare(dynamic session) async {}

PendingShare? takePendingShare() => null;

PendingDeepLink? takePendingDeepLink() => null;

void androidSetAppForeground(bool foreground) {}

bool get androidIsAppForeground => true;

Future<void> androidShowIncomingNotification({
  required String title,
  required String body,
  required String kind,
  int? channelId,
  int? messageId,
  String? channelName,
}) async {}

Future<void> androidClearChannelNotifications(int channelId) async {}

bool get androidAppLockEnabled => false;

Future<void> setAndroidAppLockEnabled(bool enabled) async {}

Future<bool> androidUnlock() async => true;

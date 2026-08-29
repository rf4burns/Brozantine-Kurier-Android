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

Future<void> androidOnLogin({
  required dynamic trpc,
  required String origin,
  required String jwt,
  required bool notifyAll,
  required bool mentions,
  required bool dm,
  required bool replies,
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

Future<void> androidSyncPip({required bool webcam, required bool sharing}) async {}

Future<void> androidStoreSession({
  required String origin,
  required String jwt,
}) async {}

void Function(String action)? onVoiceNotificationAction;

Future<void> androidConsumePendingShare(dynamic session) async {}

PendingShare? takePendingShare() => null;

PendingDeepLink? takePendingDeepLink() => null;

bool get androidAppLockEnabled => false;

Future<void> setAndroidAppLockEnabled(bool enabled) async {}

Future<bool> androidUnlock() async => true;

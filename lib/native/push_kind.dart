/// FCM / local-notification category. Priority: DM > mention > reply > message.
enum PushKind {
  message,
  mention,
  dm,
  reply;

  static const messageChannelId = 'kurier_messages';
  static const mentionChannelId = 'kurier_mentions';
  static const dmChannelId = 'kurier_dms';
  static const replyChannelId = 'kurier_replies';

  /// Stable shade id so every mention updates one notification, every reply
  /// another, and so on. Must stay in sync with MainActivity.kt.
  static const messageNotificationId = 1001;
  static const mentionNotificationId = 1002;
  static const dmNotificationId = 1003;
  static const replyNotificationId = 1004;

  String get wire => switch (this) {
    message => 'message',
    mention => 'mention',
    dm => 'dm',
    reply => 'reply',
  };

  String get androidChannelId => switch (this) {
    message => messageChannelId,
    mention => mentionChannelId,
    dm => dmChannelId,
    reply => replyChannelId,
  };

  String get androidChannelName => switch (this) {
    message => 'Messages',
    mention => 'Mentions',
    dm => 'Direct messages',
    reply => 'Replies',
  };

  int get androidNotificationId => switch (this) {
    message => messageNotificationId,
    mention => mentionNotificationId,
    dm => dmNotificationId,
    reply => replyNotificationId,
  };

  String inboxTitle(int count) {
    final n = count < 1 ? 1 : count;
    return switch (this) {
      message => n == 1 ? 'Message' : '$n messages',
      mention => n == 1 ? 'Mention' : '$n mentions',
      dm => n == 1 ? 'Direct message' : '$n direct messages',
      reply => n == 1 ? 'Reply' : '$n replies',
    };
  }

  static PushKind classify({
    required bool isDm,
    required bool mentioned,
    required bool replyToMe,
  }) {
    if (isDm) return PushKind.dm;
    if (mentioned) return PushKind.mention;
    if (replyToMe) return PushKind.reply;
    return PushKind.message;
  }

  static PushKind parse(String? raw) {
    return switch (raw) {
      'mention' => PushKind.mention,
      'dm' => PushKind.dm,
      'reply' => PushKind.reply,
      _ => PushKind.message,
    };
  }
}

/// Prefer FCM data fields. [notificationTitle] / [notificationBody] are
/// fallbacks for older hosts that still send a notification block.
({String title, String body}) fcmDisplayText(
  Map<String, dynamic> data, {
  String? notificationTitle,
  String? notificationBody,
}) {
  final dataTitle = data['title']?.toString().trim() ?? '';
  final dataBody = data['body']?.toString();
  final fallbackTitle = notificationTitle?.trim() ?? '';
  return (
    title: dataTitle.isNotEmpty
        ? dataTitle
        : (fallbackTitle.isNotEmpty ? fallbackTitle : 'Kurier'),
    body: (dataBody != null && dataBody.isNotEmpty)
        ? dataBody
        : (notificationBody ?? ''),
  );
}

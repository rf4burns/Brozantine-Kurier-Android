import 'models.dart';

const kActivityLogLimit = 50;

const kSecurityActivityLogTypes = <String>{
  'LOGIN_FAILED_THRESHOLD',
  'SECURITY_ANSWER_FAILED_THRESHOLD',
  'ACCOUNT_LOCKED',
  'ACCOUNT_UNLOCKED',
  'ACCESS_BAN_ADDED',
  'ACCESS_BAN_REMOVED',
  'ACCESS_BAN_BLOCKED',
};

const kAllActivityLogTypes = <String>[
  'SERVER_STARTED',
  'EDIT_SERVER_SETTINGS',
  'USER_CREATED',
  'USER_JOINED',
  'USER_LEFT',
  'USER_KICKED',
  'USER_BANNED',
  'USER_UNBANNED',
  'USER_DELETED',
  'USER_UPDATED_PASSWORD',
  'USER_PASSWORD_RESET',
  'USER_UPDATED_SECURITY_QUESTION',
  'LOGIN_FAILED_THRESHOLD',
  'SECURITY_ANSWER_FAILED_THRESHOLD',
  'ACCOUNT_LOCKED',
  'ACCOUNT_UNLOCKED',
  'ACCESS_BAN_ADDED',
  'ACCESS_BAN_REMOVED',
  'ACCESS_BAN_BLOCKED',
  'USER_ROLE_ADDED',
  'USER_ROLE_REMOVED',
  'USER_MUTED',
  'USER_UNMUTED',
  'USER_DEAFENED',
  'USER_UNDEAFENED',
  'USER_MOVED',
  'USER_NICKNAME_UPDATED',
  'CREATED_ROLE',
  'DELETED_ROLE',
  'UPDATED_ROLE',
  'UPDATED_DEFAULT_ROLE',
  'CREATED_CHANNEL',
  'DELETED_CHANNEL',
  'UPDATED_CHANNEL',
  'UPDATED_CHANNEL_PERMISSIONS',
  'DELETED_CHANNEL_PERMISSIONS',
  'CREATED_INVITE',
  'DELETED_INVITE',
  'USED_INVITE',
  'CREATED_EMOJI',
  'DELETED_EMOJI',
  'UPDATED_EMOJI',
  'CREATED_CATEGORY',
  'DELETED_CATEGORY',
  'UPDATED_CATEGORY',
  'EXECUTED_PLUGIN_COMMAND',
  'EXECUTED_PLUGIN_ACTION',
  'PLUGIN_TOGGLED',
  'TOGGLED_MESSAGE_PIN',
  'MESSAGE_DELETED',
  'MESSAGE_EDITED',
];

final kAuditActivityLogTypes = [
  for (final type in kAllActivityLogTypes)
    if (!kSecurityActivityLogTypes.contains(type)) type,
];

final kSecurityActivityLogTypeList = [
  for (final type in kAllActivityLogTypes)
    if (kSecurityActivityLogTypes.contains(type)) type,
];

const _legacyModeratorKeys = <String, String>{
  'USER_KICKED': 'kickedBy',
  'USER_BANNED': 'bannedBy',
  'USER_UNBANNED': 'unbannedBy',
};

typedef L10nLookup = String Function(String key, [Map<String, String>? args]);

class ActivityLogPage {
  const ActivityLogPage({this.items = const [], this.nextCursor});

  final List<Map<String, dynamic>> items;
  final int? nextCursor;
}

class ActivityLogItem {
  ActivityLogItem({
    required this.id,
    required this.type,
    this.userId,
    this.details,
    this.ip,
    this.createdAt = 0,
  });

  final int id;
  final int? userId;
  final String type;
  final Map<String, dynamic>? details;
  final String? ip;
  final int createdAt;

  factory ActivityLogItem.fromJson(Map<String, dynamic> json) {
    return ActivityLogItem(
      id: asInt(json['id']) ?? 0,
      userId: asInt(json['userId']),
      type: '${json['type'] ?? ''}',
      details: json['details'] is Map
          ? Map<String, dynamic>.from(json['details'] as Map)
          : null,
      ip: json['ip'] == null || '${json['ip']}'.isEmpty
          ? null
          : '${json['ip']}',
      createdAt: parseTimestamp(json['createdAt']),
    );
  }
}

int parseTimestamp(dynamic v) {
  final n = asInt(v);
  if (n != null) {
    return n < 1000000000000 ? n * 1000 : n;
  }
  if (v is String) {
    return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
  }
  return 0;
}

String formatTypeLabel(String type) => type.replaceAll('_', ' ');

String formatDistanceToNow(int ms, {DateTime? now}) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  final current = now ?? DateTime.now();
  var seconds = current.difference(date).inSeconds;
  if (seconds < 0) seconds = 0;
  final minutes = (seconds / 60).round();
  final hours = (minutes / 60).round();
  final days = (hours / 24).round();
  if (seconds < 30) return 'less than a minute ago';
  if (seconds < 90) return '1 minute ago';
  if (minutes < 45) return '$minutes minutes ago';
  if (minutes < 90) return 'about 1 hour ago';
  if (hours < 24) {
    return hours == 1 ? 'about 1 hour ago' : 'about $hours hours ago';
  }
  if (hours < 36) return '1 day ago';
  if (days < 30) return '$days days ago';
  return formatAbsoluteTime(ms);
}

String activityLogTimestamp(int ms, {DateTime? now}) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  final current = now ?? DateTime.now();
  if (current.difference(date).inHours >= 24) {
    return formatAbsoluteTime(ms);
  }
  return formatDistanceToNow(ms, now: current);
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatAbsoluteTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_months[d.month - 1]} ${d.day}, ${d.year}, $hour12:${two(d.minute)}:${two(d.second)} $ampm';
}

String _resolveName(
  Map<int, String> userNameById,
  int? userId,
  String fallback,
) {
  if (userId == null) return fallback;
  return userNameById[userId] ?? fallback;
}

String formatActivityLogEntry({
  required L10nLookup t,
  required String actorName,
  required String type,
  int? userId,
  Map<String, dynamic>? details,
  Map<int, String> userNameById = const {},
}) {
  final mapped = <String, dynamic>{...?details};
  var displayActor = actorName;

  final moderatorKey = _legacyModeratorKeys[type];
  if (moderatorKey != null) {
    final moderatorId = asInt(mapped[moderatorKey]);
    final hasTargetUsername = mapped['targetUsername'] is String;
    if (moderatorId != null &&
        userId != null &&
        moderatorId != userId &&
        !hasTargetUsername) {
      mapped['targetUsername'] = actorName;
      mapped['targetUserId'] = userId;
      displayActor = _resolveName(userNameById, moderatorId, t('auditSystem'));
    }
  }

  if (mapped['targetUsername'] is! String &&
      asInt(mapped['targetUserId']) != null) {
    final targetId = asInt(mapped['targetUserId'])!;
    mapped['targetUsername'] = _resolveName(
      userNameById,
      targetId,
      '#$targetId',
    );
  }

  if (type == 'ACCOUNT_LOCKED') {
    mapped['kind'] = mapped['kind'] == 'securityAnswer'
        ? t('securityKindSecurityAnswer')
        : t('securityKindPassword');
  }

  if (type == 'ACCESS_BAN_BLOCKED' && mapped['sourceUsername'] is! String) {
    mapped['sourceUsername'] = displayActor;
  }

  if (type == 'ACCESS_BAN_ADDED' ||
      type == 'ACCESS_BAN_REMOVED' ||
      type == 'ACCESS_BAN_BLOCKED') {
    mapped['kind'] = switch (mapped['kind']) {
      'mac' => t('accessBanKindMac'),
      'device' => t('accessBanKindDevice'),
      _ => t('accessBanKindIp'),
    };
  }

  final args = <String, String>{
    'actor': displayActor,
    for (final entry in mapped.entries)
      if (entry.value != null) entry.key: '${entry.value}',
  };
  final key = 'audit_$type';
  final translated = t(key, args);
  if (translated != key) return translated;
  return t('auditUnknown', {'actor': displayActor, 'type': type});
}

import '../core/emoji_codec.dart';
import 'config.dart';

int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

bool asBool(dynamic v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v == 1 || v == '1' || v == 'true') return true;
  if (v == 0 || v == '0' || v == 'false') return false;
  return fallback;
}

String? asOptionalString(dynamic v) {
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

/// Accepts `roleIds: [1, 2]` or `roles: [{id: 1}, 2]`.
List<int> parseRoleIds(Map<String, dynamic> json) {
  final raw = json['roleIds'] ?? json['roles'];
  if (raw is! List) return const [];
  return raw
      .map((e) {
        if (e is Map) return asInt(e['id'] ?? e['roleId']);
        return asInt(e);
      })
      .whereType<int>()
      .where((id) => id != 0)
      .toList();
}

/// Role colour as `#RRGGBB`. Server may send a hex string or an int.
String parseRoleColorString(dynamic color) {
  if (color is num) {
    return '#${(color.toInt() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
  final s = '${color ?? ''}'.trim();
  if (s.isEmpty) return '#ffffff';
  if (s.startsWith('#')) return s;
  // 7–8 digit decimal RGB (e.g. "16711680") is not 6-char hex.
  final decimal = int.tryParse(s);
  if (decimal != null && s.length >= 7 && decimal <= 0xFFFFFF) {
    return '#${(decimal & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  }
  if (RegExp(r'^[A-Fa-f0-9]{3}$').hasMatch(s) ||
      RegExp(r'^[A-Fa-f0-9]{6}$').hasMatch(s) ||
      RegExp(r'^[A-Fa-f0-9]{8}$').hasMatch(s)) {
    return '#$s';
  }
  return s;
}

class KurierFile {
  KurierFile({
    required this.id,
    required this.name,
    required this.originalName,
    required this.md5,
    required this.userId,
    required this.size,
    required this.mimeType,
    required this.extension,
    required this.createdAt,
    this.accessToken,
    this.accessTokenExpiresAt,
  });

  final int id;
  final String name;
  final String originalName;
  final String md5;
  final int userId;
  final int size;
  final String mimeType;
  final String extension;
  final int createdAt;
  final String? accessToken;
  final int? accessTokenExpiresAt;

  factory KurierFile.fromJson(Map<String, dynamic> json) {
    var map = json;
    final nested = json['json'];
    if (nested is Map && json.containsKey('meta')) {
      map = Map<String, dynamic>.from(nested);
    }
    return KurierFile(
      id: asInt(map['id']) ?? 0,
      name: '${map['name'] ?? map['url'] ?? ''}',
      originalName: '${map['originalName'] ?? ''}',
      md5: '${map['md5'] ?? ''}',
      userId: asInt(map['userId']) ?? 0,
      size: asInt(map['size']) ?? 0,
      mimeType: '${map['mimeType'] ?? ''}',
      extension: '${map['extension'] ?? ''}',
      createdAt: asInt(map['createdAt']) ?? 0,
      accessToken: _fileToken(map),
      accessTokenExpiresAt:
          asInt(map['_accessTokenExpiresAt']) ?? asInt(map['accessTokenExpiresAt']),
    );
  }

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo =>
      mimeType.startsWith('video/') ||
      videoFileExtensions.contains(resolvedExtension);
  bool get isAudio =>
      mimeType.startsWith('audio/') ||
      audioFileExtensions.contains(resolvedExtension);
  bool get isPdf => mimeType == 'application/pdf' || extension == 'pdf';

  /// MIME `extension`, else the suffix of `originalName` / `name`.
  String get resolvedExtension {
    final fromField = normalizeFileExtension(extension);
    if (fromField.isNotEmpty) return fromField;
    final fromOrig = extensionFromFileName(originalName);
    if (fromOrig.isNotEmpty) return fromOrig;
    return extensionFromFileName(name);
  }
}

const videoFileExtensions = {'mp4', 'webm', 'mov', 'm4v', 'ogv', 'mkv'};
const audioFileExtensions = {
  'mp3',
  'wav',
  'ogg',
  'oga',
  'm4a',
  'aac',
  'flac',
  'opus',
};

String normalizeFileExtension(String raw) {
  var value = raw.trim().toLowerCase();
  if (value.startsWith('.')) value = value.substring(1);
  return value;
}

String extensionFromFileName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  var path = trimmed;
  final query = path.indexOf('?');
  if (query >= 0) path = path.substring(0, query);
  final slash = path.lastIndexOf('/');
  if (slash >= 0) path = path.substring(slash + 1);
  final dot = path.lastIndexOf('.');
  if (dot <= 0 || dot == path.length - 1) return '';
  return normalizeFileExtension(path.substring(dot + 1));
}

String? _fileToken(Map<String, dynamic> json) {
  final v = json['_accessToken'] ?? json['accessToken'];
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty ? null : s;
}

/// Avatar/banner may be a TFile map, a filename, or a `/public/...` path.
KurierFile? fileFromDynamic(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    final raw = value.trim();
    if (raw.isEmpty) return null;
    var name = raw;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      name = Uri.tryParse(raw)?.pathSegments.lastOrNull ?? raw;
    } else if (raw.startsWith('/')) {
      name = raw.split('/').where((p) => p.isNotEmpty).lastOrNull ?? raw;
    }
    if (name.isEmpty) return null;
    return KurierFile(
      id: 0,
      name: name,
      originalName: name,
      md5: '',
      userId: 0,
      size: 0,
      mimeType: '',
      extension: '',
      createdAt: 0,
    );
  }
  if (value is! Map) return null;
  final file = KurierFile.fromJson(Map<String, dynamic>.from(value));
  return file.name.trim().isEmpty ? null : file;
}

/// Keep a still-signed file when an update repeats the same id without tokens.
KurierFile? preferSignedFile(KurierFile? incoming, KurierFile? existing) {
  if (incoming == null) return null;
  if (existing == null) return incoming;
  final incomingTok = incoming.accessToken?.trim() ?? '';
  final existingTok = existing.accessToken?.trim() ?? '';
  if (incoming.id != 0 &&
      incoming.id == existing.id &&
      incomingTok.isEmpty &&
      existingTok.isNotEmpty) {
    return existing;
  }
  return incoming;
}

class KurierUser {
  KurierUser({
    required this.id,
    required this.name,
    this.identity,
    this.nickname,
    this.pronouns,
    this.statusMessage,
    this.bio,
    this.profileColor = '#262626',
    this.avatarId,
    this.bannerId,
    this.avatar,
    this.banner,
    this.roleIds = const [],
    this.status = 'offline',
    this.banned = false,
    this.deleted = false,
    this.serverMuted = false,
    this.serverDeafened = false,
    this.createdAt = 0,
    this.lastLoginAt = 0,
    this.banReason,
    this.bannedAt,
    this.preferences = const {},
  });

  final int id;
  String name;
  String? identity;
  String? nickname;
  String? pronouns;
  String? statusMessage;
  String? bio;
  String profileColor;
  int? avatarId;
  int? bannerId;
  KurierFile? avatar;
  KurierFile? banner;
  List<int> roleIds;
  String status;
  bool banned;
  bool deleted;
  bool serverMuted;
  bool serverDeafened;
  int createdAt;
  int lastLoginAt;
  String? banReason;
  int? bannedAt;
  Map<String, dynamic> preferences;

  static bool isPlaceholderName(String? value) =>
      value == AppConfig.deletedUserName;

  String get displayName {
    final nick = nickname?.trim();
    if (nick != null && nick.isNotEmpty && !isPlaceholderName(nick)) {
      return nick;
    }
    if (name.isNotEmpty && !isPlaceholderName(name)) return name;
    return 'Deleted';
  }

  bool get isOnline =>
      status == 'online' || status == 'idle' || status == 'dnd';

  factory KurierUser.fromJson(
    Map<String, dynamic> json, {
    KurierUser? existing,
  }) {
    final name = json.containsKey('name')
        ? '${json['name'] ?? ''}'
        : (existing?.name ?? '');
    final identity = json.containsKey('identity')
        ? json['identity'] as String?
        : existing?.identity;
    final parsedAvatar = json.containsKey('avatar')
        ? fileFromDynamic(json['avatar'])
        : existing?.avatar;
    final parsedBanner = json.containsKey('banner')
        ? fileFromDynamic(json['banner'])
        : existing?.banner;
    var roleIds = parseRoleIds(json);
    if (roleIds.isEmpty &&
        existing != null &&
        existing.roleIds.isNotEmpty &&
        !json.containsKey('roleIds') &&
        !json.containsKey('roles')) {
      roleIds = List<int>.from(existing.roleIds);
    }
    return KurierUser(
      id: asInt(json['id']) ?? existing?.id ?? 0,
      name: name,
      identity: identity,
      nickname: json.containsKey('nickname')
          ? json['nickname'] as String?
          : existing?.nickname,
      pronouns: json.containsKey('pronouns')
          ? json['pronouns'] as String?
          : existing?.pronouns,
      statusMessage: json.containsKey('statusMessage')
          ? json['statusMessage'] as String?
          : existing?.statusMessage,
      bio: json.containsKey('bio') ? json['bio'] as String? : existing?.bio,
      profileColor: json.containsKey('profileColor')
          ? '${json['profileColor'] ?? '#262626'}'
          : (existing?.profileColor ?? '#262626'),
      avatarId: json.containsKey('avatarId')
          ? asInt(json['avatarId'])
          : existing?.avatarId,
      bannerId: json.containsKey('bannerId')
          ? asInt(json['bannerId'])
          : existing?.bannerId,
      avatar: preferSignedFile(parsedAvatar, existing?.avatar),
      banner: preferSignedFile(parsedBanner, existing?.banner),
      roleIds: roleIds,
      status: json.containsKey('status')
          ? '${json['status'] ?? 'offline'}'
          : (existing?.status ?? 'offline'),
      banned: json.containsKey('banned')
          ? asBool(json['banned'])
          : (existing?.banned ?? false),
      deleted:
          asBool(json['deleted']) ||
          name == AppConfig.deletedUserName ||
          identity == AppConfig.deletedUserName,
      serverMuted: json.containsKey('serverMuted')
          ? asBool(json['serverMuted'])
          : (existing?.serverMuted ?? false),
      serverDeafened: json.containsKey('serverDeafened')
          ? asBool(json['serverDeafened'])
          : (existing?.serverDeafened ?? false),
      createdAt: json.containsKey('createdAt')
          ? asInt(json['createdAt']) ?? 0
          : (existing?.createdAt ?? 0),
      lastLoginAt: json.containsKey('lastLoginAt')
          ? asInt(json['lastLoginAt']) ?? 0
          : (existing?.lastLoginAt ?? 0),
      banReason: json.containsKey('banReason')
          ? json['banReason'] as String?
          : existing?.banReason,
      bannedAt: json.containsKey('bannedAt')
          ? asInt(json['bannedAt'])
          : existing?.bannedAt,
      preferences: json['preferences'] is Map
          ? Map<String, dynamic>.from(json['preferences'] as Map)
          : (existing?.preferences ?? const {}),
    );
  }

  KurierUser copyWith({
    String? name,
    String? nickname,
    String? pronouns,
    String? statusMessage,
    String? bio,
    String? profileColor,
    String? status,
    bool? banned,
    bool? deleted,
    bool? serverMuted,
    bool? serverDeafened,
    List<int>? roleIds,
    KurierFile? avatar,
    KurierFile? banner,
    Map<String, dynamic>? preferences,
  }) {
    return KurierUser(
      id: id,
      name: name ?? this.name,
      identity: identity,
      nickname: nickname ?? this.nickname,
      pronouns: pronouns ?? this.pronouns,
      statusMessage: statusMessage ?? this.statusMessage,
      bio: bio ?? this.bio,
      profileColor: profileColor ?? this.profileColor,
      avatarId: avatarId,
      bannerId: bannerId,
      avatar: avatar ?? this.avatar,
      banner: banner ?? this.banner,
      roleIds: roleIds ?? this.roleIds,
      status: status ?? this.status,
      banned: banned ?? this.banned,
      deleted: deleted ?? this.deleted,
      serverMuted: serverMuted ?? this.serverMuted,
      serverDeafened: serverDeafened ?? this.serverDeafened,
      createdAt: createdAt,
      lastLoginAt: lastLoginAt,
      banReason: banReason,
      bannedAt: bannedAt,
      preferences: preferences ?? this.preferences,
    );
  }
}

class UserLoginInfo {
  const UserLoginInfo({this.ip, this.country, this.city});

  final String? ip;
  final String? country;
  final String? city;

  factory UserLoginInfo.fromJson(Map<String, dynamic> json) {
    return UserLoginInfo(
      ip: json['ip'] as String?,
      country: json['country'] as String?,
      city: json['city'] as String?,
    );
  }
}

class UserStorageInfo {
  const UserStorageInfo({
    this.usedStorage = 0,
    this.quota = 0,
    this.fileCount = 0,
  });

  final int usedStorage;
  final int quota;
  final int fileCount;

  factory UserStorageInfo.fromJson(Map<String, dynamic> json) {
    return UserStorageInfo(
      usedStorage: asInt(json['usedStorage']) ?? 0,
      quota: asInt(json['quota']) ?? 0,
      fileCount: asInt(json['fileCount']) ?? asInt(json['files']) ?? 0,
    );
  }
}

final _httpUrlRe = RegExp(r'''https?://[^\s<"']+''', caseSensitive: false);

int countUniqueLinks(Iterable<String?> contents) {
  final seen = <String>{};
  for (final content in contents) {
    if (content == null || content.isEmpty) continue;
    for (final match in _httpUrlRe.allMatches(content)) {
      seen.add(match.group(0)!);
    }
  }
  return seen.length;
}

class UserAdminInfo {
  const UserAdminInfo({
    required this.user,
    this.logins = const [],
    this.files = const [],
    this.messages = const [],
    this.storage = const UserStorageInfo(),
    this.linkCount = 0,
  });

  final KurierUser user;
  final List<UserLoginInfo> logins;
  final List<KurierFile> files;
  final List<KurierMessage> messages;
  final UserStorageInfo storage;
  final int linkCount;
}

class KurierRole {
  KurierRole({
    required this.id,
    required this.name,
    required this.color,
    required this.position,
    required this.hoist,
    required this.isDefault,
    required this.isPersistent,
    this.permissions = const [],
  });

  final int id;
  String name;
  String color;
  int position;
  bool hoist;
  bool isDefault;
  bool isPersistent;
  List<String> permissions;

  factory KurierRole.fromJson(Map<String, dynamic> json) {
    return KurierRole(
      id: asInt(json['id']) ?? 0,
      name: '${json['name'] ?? ''}',
      color: parseRoleColorString(json['color']),
      position: asInt(json['position']) ?? asInt(json['id']) ?? 0,
      hoist: asBool(json['hoist']),
      isDefault: asBool(json['isDefault']),
      isPersistent: asBool(json['isPersistent']),
      permissions:
          (json['permissions'] as List?)?.map((e) => '$e').toList() ?? const [],
    );
  }
}

class KurierCategory {
  KurierCategory({
    required this.id,
    required this.name,
    required this.position,
  });

  final int id;
  String name;
  int position;

  factory KurierCategory.fromJson(Map<String, dynamic> json) {
    return KurierCategory(
      id: asInt(json['id']) ?? 0,
      name: '${json['name'] ?? ''}',
      position: asInt(json['position']) ?? 0,
    );
  }
}

class KurierChannel {
  KurierChannel({
    required this.id,
    required this.type,
    required this.name,
    required this.position,
    this.topic,
    this.private = false,
    this.isDm = false,
    this.categoryId,
    this.voiceStatus,
  });

  final int id;
  String type;
  String name;
  String? topic;
  bool private;
  bool isDm;
  int position;
  int? categoryId;
  String? voiceStatus;

  bool get isText => type == 'TEXT';
  bool get isVoice => type == 'VOICE';

  /// Voice-channel status line. Server stores this as `topic`.
  String? get displayedVoiceStatus {
    if (!isVoice) return null;
    return asOptionalString(voiceStatus) ?? asOptionalString(topic);
  }

  factory KurierChannel.fromJson(Map<String, dynamic> json) {
    final topic = asOptionalString(json['topic']);
    return KurierChannel(
      id: asInt(json['id']) ?? 0,
      type: '${json['type'] ?? 'TEXT'}',
      name: '${json['name'] ?? ''}',
      topic: topic,
      private: asBool(json['private']),
      isDm: asBool(json['isDm']),
      position: asInt(json['position']) ?? 0,
      categoryId: asInt(json['categoryId']),
      voiceStatus:
          asOptionalString(json['voiceStatus']) ??
          asOptionalString(json['status']) ??
          topic,
    );
  }
}

class MessageReplyPreview {
  MessageReplyPreview({
    required this.id,
    this.content,
    this.userId,
    this.pluginId,
  });

  final int id;
  final String? content;
  final int? userId;
  final String? pluginId;

  factory MessageReplyPreview.fromJson(Map<String, dynamic> json) {
    return MessageReplyPreview(
      id: asInt(json['id']) ?? 0,
      content: json['content'] as String?,
      userId: asInt(json['userId']),
      pluginId: json['pluginId'] as String?,
    );
  }
}

class MessageReaction {
  MessageReaction({
    required this.messageId,
    required this.emoji,
    required this.userId,
    this.file,
    this.count = 1,
    this.me = false,
    this.userIds = const [],
  });

  final int messageId;
  final String emoji;
  final int userId;
  final KurierFile? file;
  final int count;
  final bool me;
  final List<int> userIds;

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    final rawKey = EmojiCodec.reactionEmojiKey(json['emoji']);
    final emoji = EmojiCodec.encodeReactionKey(rawKey, const []);
    return MessageReaction(
      messageId: asInt(json['messageId']) ?? 0,
      emoji: emoji,
      userId: asInt(json['userId']) ?? 0,
      file: json['file'] is Map
          ? KurierFile.fromJson(Map<String, dynamic>.from(json['file'] as Map))
          : null,
      count: asInt(json['count']) ?? 1,
      me: asBool(json['me']) || asBool(json['reacted']),
      userIds: _parseReactionUserIds(json['userIds']),
    );
  }
}

List<int> _parseReactionUserIds(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map(asInt).whereType<int>().where((id) => id != 0).toList();
}

/// Parses `message.reactions` as either per-user rows or aggregated
/// `{emoji, count, me, userIds}` groups. Aggregated rows with `userIds` are
/// expanded so pills, tooltips, and the viewers list share one grouping.
List<MessageReaction> parseMessageReactions(dynamic raw, {int messageId = 0}) {
  if (raw is! List) return const [];
  final out = <MessageReaction>[];
  for (final e in raw.whereType<Map>()) {
    final parsed = MessageReaction.fromJson(Map<String, dynamic>.from(e));
    final mid = parsed.messageId != 0 ? parsed.messageId : messageId;
    if (parsed.userIds.isNotEmpty) {
      for (final uid in parsed.userIds) {
        out.add(
          MessageReaction(
            messageId: mid,
            emoji: parsed.emoji,
            userId: uid,
            file: parsed.file,
            count: 1,
            me: parsed.me,
          ),
        );
      }
    } else {
      out.add(
        parsed.messageId == mid
            ? parsed
            : MessageReaction(
                messageId: mid,
                emoji: parsed.emoji,
                userId: parsed.userId,
                file: parsed.file,
                count: parsed.count,
                me: parsed.me,
                userIds: parsed.userIds,
              ),
      );
    }
  }
  return out;
}

/// Unwraps `messages.onNew` / `messages.onUpdate` payloads (`{message: …}` or
/// a bare message map).
Map<String, dynamic>? extractMessagePayload(dynamic payload) {
  if (payload is! Map) return null;
  final map = Map<String, dynamic>.from(payload);
  final nested = map['message'];
  if (nested is Map) return Map<String, dynamic>.from(nested);
  final data = map['data'];
  if (data is Map) {
    final inner = Map<String, dynamic>.from(data);
    if (inner['content'] != null || inner['id'] != null) return inner;
  }
  if (map['content'] != null || map['id'] != null) return map;
  return null;
}

/// Unwraps `users.onLeave` / `users.onDelete` ids. Kurier emits a bare number;
/// also accepts `{id}` / `{userId}`, `{user: {id}}`, and superjson `{json: N}`.
int? extractUserId(dynamic payload) {
  final direct = asInt(payload);
  if (direct != null) return direct;
  if (payload is! Map) return null;
  final map = Map<String, dynamic>.from(payload);
  if (map.containsKey('json') && map.containsKey('meta')) {
    final nested = extractUserId(map['json']);
    if (nested != null) return nested;
  }
  final user = map['user'];
  if (user is Map) {
    final nested = asInt(user['id']) ?? asInt(user['userId']);
    if (nested != null) return nested;
  }
  return asInt(map['id']) ?? asInt(map['userId']);
}

/// Unwraps `users.onJoin` / `users.onUpdate` payloads (`{user: …}`, a bare
/// user map, or superjson `{json: {…}, meta}`).
Map<String, dynamic>? extractUserPayload(dynamic payload) {
  if (payload is! Map) return null;
  var map = Map<String, dynamic>.from(payload);
  final json = map['json'];
  if (json is Map && map.containsKey('meta')) {
    map = Map<String, dynamic>.from(json);
  }
  final nested = map['user'];
  if (nested is Map) return Map<String, dynamic>.from(nested);
  if (map['id'] != null || map['name'] != null || map['nickname'] != null) {
    return map;
  }
  return null;
}

/// Local add/remove of [ownUserId]'s reaction [key] (GitHub shortcode / custom name).
List<MessageReaction> withToggledReaction({
  required List<MessageReaction> reactions,
  required String key,
  required int ownUserId,
  required int messageId,
}) {
  bool sameKey(MessageReaction r) {
    final encoded = EmojiCodec.encodeReactionKey(r.emoji, const []);
    return encoded == key || EmojiCodec.reactionEmojiKey(r.emoji) == key;
  }

  final hasOwn = reactions.any(
    (r) => sameKey(r) && (r.userId == ownUserId || (r.me && r.userId == 0)),
  );

  if (hasOwn) {
    final out = <MessageReaction>[];
    for (final r in reactions) {
      if (!sameKey(r)) {
        out.add(r);
        continue;
      }
      if (r.userId == ownUserId) continue;
      if (r.userId == 0 && (r.me || r.count > 1 || r.userIds.isNotEmpty)) {
        final nextCount = (r.count > 1 ? r.count : 1) - 1;
        if (nextCount <= 0) continue;
        out.add(
          MessageReaction(
            messageId: r.messageId,
            emoji: r.emoji,
            userId: 0,
            file: r.file,
            count: nextCount,
            me: false,
            userIds: r.userIds.where((id) => id != ownUserId).toList(),
          ),
        );
        continue;
      }
      out.add(r);
    }
    return out;
  }

  final out = List<MessageReaction>.from(reactions);
  final aggIdx = out.indexWhere(
    (r) => sameKey(r) && r.userId == 0 && r.count > 1,
  );
  if (aggIdx >= 0) {
    final r = out[aggIdx];
    final ids = [...r.userIds];
    if (ownUserId != 0 && !ids.contains(ownUserId)) ids.add(ownUserId);
    out[aggIdx] = MessageReaction(
      messageId: r.messageId,
      emoji: r.emoji,
      userId: 0,
      file: r.file,
      count: r.count + 1,
      me: true,
      userIds: ids,
    );
    return out;
  }
  out.add(
    MessageReaction(
      messageId: messageId,
      emoji: key,
      userId: ownUserId,
      count: 1,
      me: true,
    ),
  );
  return out;
}

class KurierMessage {
  KurierMessage({
    required this.id,
    required this.channelId,
    required this.createdAt,
    this.content,
    this.userId,
    this.pluginId,
    this.parentMessageId,
    this.replyToMessageId,
    this.editable = true,
    this.pinned = false,
    this.pinnedAt,
    this.pinnedBy,
    this.editedAt,
    this.files = const [],
    this.reactions = const [],
    this.replyCount = 0,
    this.replyTo,
    this.metadata = const [],
    this.optimistic = false,
    this.localPreviewUrl,
  });

  final int id;
  String? content;
  int? userId;
  String? pluginId;
  int channelId;
  int? parentMessageId;
  int? replyToMessageId;
  bool editable;
  bool pinned;
  int? pinnedAt;
  int? pinnedBy;
  int createdAt;
  int? editedAt;
  List<KurierFile> files;
  List<MessageReaction> reactions;
  int replyCount;
  MessageReplyPreview? replyTo;
  List<dynamic> metadata;
  bool optimistic;
  String? localPreviewUrl;

  factory KurierMessage.fromJson(Map<String, dynamic> json) {
    return KurierMessage(
      id: asInt(json['id']) ?? 0,
      content: json['content'] as String?,
      userId: asInt(json['userId']),
      pluginId: json['pluginId'] as String?,
      channelId: asInt(json['channelId']) ?? 0,
      parentMessageId: asInt(json['parentMessageId']),
      replyToMessageId: asInt(json['replyToMessageId']),
      editable: asBool(json['editable'], true),
      pinned: asBool(json['pinned']),
      pinnedAt: asInt(json['pinnedAt']),
      pinnedBy: asInt(json['pinnedBy']),
      createdAt: asInt(json['createdAt']) ?? 0,
      editedAt: asInt(json['editedAt']),
      files:
          (json['files'] as List?)
              ?.whereType<Map>()
              .map((e) => KurierFile.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      reactions: parseMessageReactions(
        json['reactions'],
        messageId: asInt(json['id']) ?? 0,
      ),
      replyCount: asInt(json['replyCount']) ?? 0,
      replyTo: json['replyTo'] is Map
          ? MessageReplyPreview.fromJson(
              Map<String, dynamic>.from(json['replyTo'] as Map),
            )
          : null,
      metadata: json['metadata'] is List
          ? List.from(json['metadata'] as List)
          : const [],
    );
  }
}

class KurierEmoji {
  KurierEmoji({required this.id, required this.name, required this.file});

  final int id;
  final String name;
  final KurierFile file;

  factory KurierEmoji.fromJson(Map<String, dynamic> json) {
    return KurierEmoji(
      id: asInt(json['id']) ?? 0,
      name: '${json['name'] ?? ''}',
      file: KurierFile.fromJson(
        Map<String, dynamic>.from((json['file'] as Map?) ?? const {}),
      ),
    );
  }
}

class ServerInfo {
  ServerInfo({
    required this.serverId,
    required this.name,
    required this.version,
    required this.allowNewUsers,
    this.description,
    this.logo,
  });

  final String serverId;
  final String name;
  final String version;
  final bool allowNewUsers;
  final String? description;
  final KurierFile? logo;

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      serverId: '${json['serverId'] ?? ''}',
      name: '${json['name'] ?? 'Kurier'}',
      version: '${json['version'] ?? ''}',
      allowNewUsers: asBool(json['allowNewUsers'], true),
      description: json['description'] as String?,
      logo: json['logo'] is Map
          ? KurierFile.fromJson(Map<String, dynamic>.from(json['logo'] as Map))
          : null,
    );
  }
}

class DmConversation {
  DmConversation({
    required this.channelId,
    required this.userId,
    required this.unreadCount,
    required this.lastMessageAt,
  });

  final int channelId;
  final int userId;
  int unreadCount;
  int lastMessageAt;

  factory DmConversation.fromJson(Map<String, dynamic> json) {
    return DmConversation(
      channelId: asInt(json['channelId']) ?? 0,
      userId: asInt(json['userId']) ?? 0,
      unreadCount: asInt(json['unreadCount']) ?? 0,
      lastMessageAt: asInt(json['lastMessageAt']) ?? 0,
    );
  }
}

class VoiceUserState {
  VoiceUserState({
    this.micMuted = false,
    this.soundMuted = false,
    this.serverMuted = false,
    this.serverDeafened = false,
    this.webcamEnabled = false,
    this.sharingScreen = false,
    this.joinedAt = 0,
  });

  bool micMuted;
  bool soundMuted;
  bool serverMuted;
  bool serverDeafened;
  bool webcamEnabled;
  bool sharingScreen;
  int joinedAt;

  factory VoiceUserState.fromJson(Map<String, dynamic> json) {
    return VoiceUserState(
      micMuted: asBool(json['micMuted']),
      soundMuted: asBool(json['soundMuted']),
      serverMuted: asBool(json['serverMuted']),
      serverDeafened: asBool(json['serverDeafened']),
      webcamEnabled: asBool(json['webcamEnabled']),
      sharingScreen: asBool(json['sharingScreen']),
      joinedAt: asInt(json['joinedAt']) ?? 0,
    );
  }
}

class ExternalStream {
  ExternalStream({
    required this.title,
    required this.key,
    required this.pluginId,
    this.streamId = 0,
    this.avatarUrl,
    this.bannerUrl,
  });

  final String title;
  final String key;
  final String pluginId;
  final int streamId;
  final String? avatarUrl;
  final String? bannerUrl;

  factory ExternalStream.fromJson(Map<String, dynamic> json) {
    return ExternalStream(
      title: '${json['title'] ?? ''}',
      key: '${json['key'] ?? ''}',
      pluginId: '${json['pluginId'] ?? ''}',
      streamId: asInt(json['streamId']) ?? asInt(json['id']) ?? 0,
      avatarUrl: json['avatarUrl'] as String?,
      bannerUrl: json['bannerUrl'] as String?,
    );
  }
}

class ChannelPerms {
  ChannelPerms(this.raw);
  final Map<String, bool> raw;
  bool get(String key) => raw[key] ?? false;
}

Map<String, ChannelPerms> parseChannelPermissions(dynamic raw) {
  final perms = <String, ChannelPerms>{};
  if (raw is! Map) return perms;
  raw.forEach((key, value) {
    if (value is! Map) return;
    final map = Map<String, dynamic>.from(value);
    final inner = map['permissions'] is Map
        ? Map<String, dynamic>.from(map['permissions'] as Map)
        : map;
    final id = map['channelId'] ?? key;
    perms['$id'] = ChannelPerms(inner.map((k, v) => MapEntry('$k', asBool(v))));
  });
  return perms;
}

class SavedHost {
  SavedHost({required this.host, this.name, this.token, this.autoLogin = true});

  final String host;
  String? name;
  String? token;
  bool autoLogin;

  Map<String, dynamic> toJson() => {
    'host': host,
    'name': name,
    'token': token,
    'autoLogin': autoLogin,
  };

  factory SavedHost.fromJson(Map<String, dynamic> json) {
    return SavedHost(
      host: '${json['host']}',
      name: json['name'] as String?,
      token: json['token'] as String?,
      autoLogin: asBool(json['autoLogin'], true),
    );
  }
}

class JoinPayload {
  JoinPayload({
    required this.categories,
    required this.channels,
    required this.users,
    required this.roles,
    required this.emojis,
    required this.serverId,
    required this.serverName,
    required this.ownUserId,
    required this.voiceMap,
    required this.publicSettings,
    required this.channelPermissions,
    required this.readStates,
    required this.notificationOverrides,
    required this.commands,
    required this.pluginsMetadata,
    required this.externalStreamsMap,
    required this.showWelcomeDialog,
  });

  final List<KurierCategory> categories;
  final List<KurierChannel> channels;
  final List<KurierUser> users;
  final List<KurierRole> roles;
  final List<KurierEmoji> emojis;
  final String serverId;
  final String serverName;
  final int ownUserId;
  final Map<String, dynamic> voiceMap;
  final Map<String, dynamic> publicSettings;
  final Map<String, ChannelPerms> channelPermissions;
  final Map<int, int> readStates;
  final Map<int, String> notificationOverrides;
  final List<dynamic> commands;
  final List<dynamic> pluginsMetadata;
  final Map<String, dynamic> externalStreamsMap;
  final bool showWelcomeDialog;

  factory JoinPayload.fromJson(Map<String, dynamic> json) {
    final perms = parseChannelPermissions(json['channelPermissions']);
    final reads = <int, int>{};
    final rawReads = json['readStates'];
    if (rawReads is Map) {
      rawReads.forEach((k, v) {
        reads[asInt(k) ?? 0] = asInt(v) ?? 0;
      });
    }
    final overrides = <int, String>{};
    final rawOv = json['notificationOverrides'];
    if (rawOv is Map) {
      rawOv.forEach((k, v) {
        overrides[asInt(k) ?? 0] = '$v';
      });
    }
    return JoinPayload(
      categories:
          (json['categories'] as List?)
              ?.whereType<Map>()
              .map((e) => KurierCategory.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      channels:
          (json['channels'] as List?)
              ?.whereType<Map>()
              .map((e) => KurierChannel.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      users:
          (json['users'] as List?)
              ?.whereType<Map>()
              .map((e) => KurierUser.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      roles:
          (json['roles'] as List?)
              ?.whereType<Map>()
              .map((e) => KurierRole.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      emojis:
          (json['emojis'] as List?)
              ?.whereType<Map>()
              .map((e) => KurierEmoji.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      serverId: '${json['serverId'] ?? ''}',
      serverName: '${json['serverName'] ?? ''}',
      ownUserId: asInt(json['ownUserId']) ?? 0,
      voiceMap: json['voiceMap'] is Map
          ? Map<String, dynamic>.from(json['voiceMap'] as Map)
          : {},
      publicSettings: json['publicSettings'] is Map
          ? Map<String, dynamic>.from(json['publicSettings'] as Map)
          : {},
      channelPermissions: perms,
      readStates: reads,
      notificationOverrides: overrides,
      commands: json['commands'] is List
          ? List.from(json['commands'] as List)
          : const [],
      pluginsMetadata: json['pluginsMetadata'] is List
          ? List.from(json['pluginsMetadata'] as List)
          : const [],
      externalStreamsMap: json['externalStreamsMap'] is Map
          ? Map<String, dynamic>.from(json['externalStreamsMap'] as Map)
          : {},
      showWelcomeDialog: asBool(json['showWelcomeDialog']),
    );
  }
}

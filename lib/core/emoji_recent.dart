import 'dart:convert';

import '../session/hosts_store.dart';

/// Recently picked emojis (unicode or custom server names), most recent first.
class EmojiRecent {
  EmojiRecent._();

  static const _max = 24;
  static HostsStore? store;

  static List<String> load() {
    final raw = store?.recentEmojiKeysJson;
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// [value] is a unicode character or custom emoji name.
  static Future<void> record(String value, {required bool isCustom}) async {
    final s = store;
    if (s == null) return;
    final bare = value.trim();
    if (bare.isEmpty) return;
    final key = isCustom ? 'c:$bare' : bare;
    final list = load();
    list.remove(key);
    list.insert(0, key);
    if (list.length > _max) list.removeRange(_max, list.length);
    await s.setRecentEmojiKeysJson(jsonEncode(list));
  }

  static bool isCustomKey(String key) => key.startsWith('c:');

  static String customNameFromKey(String key) =>
      key.startsWith('c:') ? key.substring(2) : key;
}

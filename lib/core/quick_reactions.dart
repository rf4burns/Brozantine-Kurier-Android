import 'dart:convert';

import '../session/hosts_store.dart';
import 'emoji_codec.dart';

/// Tracks which emoji reactions the user picks most often and surfaces the top
/// few as one-tap "quick reactions" on hover and in the message context menu.
class QuickReactions {
  QuickReactions._();

  static HostsStore? store;

  static Map<String, int> _load() {
    final raw = store?.quickReactionCountsJson;
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return {};
      return map.map((k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0));
    } catch (_) {
      return {};
    }
  }

  static Future<void> record(String emojiKey) async {
    final s = store;
    if (s == null || emojiKey.isEmpty) return;
    final counts = _load();
    counts[emojiKey] = (counts[emojiKey] ?? 0) + 1;
    await s.setQuickReactionCountsJson(jsonEncode(counts));
  }

  /// Returns up to [count] reaction keys (shortcodes), most-used first.
  static List<String> top({int count = 3}) {
    final counts = _load();
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final out = <String>[];
    for (final e in sorted) {
      if (e.key.isEmpty) continue;
      if (!out.contains(e.key)) out.add(e.key);
      if (out.length >= count) break;
    }
    for (final d in EmojiCodec.defaultReactionKeys) {
      if (out.length >= count) break;
      if (!out.contains(d)) out.add(d);
    }
    return out.take(count).toList();
  }
}

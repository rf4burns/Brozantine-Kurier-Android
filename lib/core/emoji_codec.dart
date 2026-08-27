import 'package:characters/characters.dart';

import 'custom_emoji.dart';
import 'discord_emoji_shortcodes.dart';
import 'emoji_catalog.dart';

/// Encodes/decodes reaction keys and custom emoji tokens to match the Sharkord
/// web client (GitHub emoji shortcodes + server custom names).
class EmojiCodec {
  EmojiCodec._();

  /// Unicode emoji shown in the native picker (full categorized catalog).
  static List<String> get nativePickerEmojis => EmojiCatalog.allUnicode;

  /// Default quick-reaction keys (GitHub shortcodes, not raw Unicode).
  static const List<String> defaultReactionKeys = ['+1', 'skull', 'joy'];

  /// Discord names that differ from GitHub shortcodes the Sharkord API expects.
  static const Map<String, String> _apiShortcodeAliases = {
    'thumbsup': '+1',
    'thumbsdown': '-1',
  };

  static final Map<String, String> _unicodeToShortcode =
      Map<String, String>.from(discordUnicodeToShortcode);

  static final Map<String, String> _shortcodeToUnicode = {
    for (final e in _unicodeToShortcode.entries) e.value: e.key,
    '+1': '👍',
    '-1': '👎',
  };

  /// Extracts the reaction emoji key from a server reaction payload field.
  static String reactionEmojiKey(dynamic raw) {
    if (raw == null) return '';
    if (raw is Map) {
      final name = raw['name']?.toString();
      if (name != null && name.isNotEmpty) return name;
      final emoji = raw['emoji']?.toString();
      if (emoji != null && emoji.isNotEmpty) return emoji;
      return '';
    }
    return raw.toString();
  }

  static String _stripColonWrap(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2 &&
        trimmed.startsWith(':') &&
        trimmed.endsWith(':')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  static bool _isCustomName(String name, List<CustomEmoji> customEmojis) {
    for (final e in customEmojis) {
      if (e.name == name) return true;
    }
    return false;
  }

  static bool _looksLikeShortcode(String value) {
    if (value.isEmpty) return false;
    return RegExp(r'^[a-zA-Z0-9_+\-]+$').hasMatch(value);
  }

  /// Normalizes a picker / quick-reaction value for `messages.toggleReaction`.
  static String encodeReactionKey(String value, List<CustomEmoji> customEmojis) {
    final bare = _stripColonWrap(value);
    if (bare.isEmpty) return bare;

    if (_isCustomName(bare, customEmojis)) return bare;

    String encoded;
    final fromUnicode = _unicodeToShortcode[bare];
    if (fromUnicode != null) {
      encoded = fromUnicode;
    } else if (_looksLikeShortcode(bare) ||
        _shortcodeToUnicode.containsKey(bare)) {
      encoded = bare;
    } else {
      encoded = bare;
    }
    return _apiShortcodeAliases[encoded] ?? encoded;
  }

  /// Discord/GitHub shortcode for a unicode emoji, if known.
  static String? shortcodeForUnicode(String emoji) {
    final discord = _unicodeToShortcode[emoji];
    if (discord == null) return null;
    return _apiShortcodeAliases[discord] ?? discord;
  }

  /// Unicode glyph for a reaction key (shortcode or custom name).
  static String? unicodeForKey(String key) {
    final bare = _stripColonWrap(key);
    final fromShortcode = _shortcodeToUnicode[bare];
    if (fromShortcode != null) return fromShortcode;
    if (twemojiUrlsForUnicode(bare).isNotEmpty) return bare;
    return null;
  }

  /// Twemoji CDN bases (newer first — Discord set includes Unicode 14/15 glyphs).
  static const _twemojiVersions = ['15.1.1', '14.0.2'];

  /// Codepoint slug(s) for Twemoji filenames, with fallbacks for ZWJ chains.
  static List<String> twemojiUrlsForUnicode(String emoji) {
    if (emoji.isEmpty) return const [];

    final primary = _twemojiCodepoint(emoji);
    if (primary.isEmpty) return const [];

    final codes = <String>{primary};
    final withoutZwJ = primary.replaceAll('-200d', '');
    if (withoutZwJ.isNotEmpty) codes.add(withoutZwJ);

    final urls = <String>[];
    for (final ver in _twemojiVersions) {
      final base =
          'https://cdn.jsdelivr.net/gh/twitter/twemoji@$ver/assets/72x72';
      for (final c in codes) {
        urls.add('$base/$c.png');
      }
    }
    return urls;
  }

  /// Twemoji CDN URL for a Unicode emoji character.
  static String? twemojiUrlForUnicode(String emoji) {
    final urls = twemojiUrlsForUnicode(emoji);
    return urls.isEmpty ? null : urls.first;
  }

  static String _twemojiCodepoint(String emoji) {
    final runes = <int>[];
    for (final rune in emoji.runes) {
      if (rune != 0xFE0F) runes.add(rune);
    }
    if (runes.isEmpty) return '';
    return runes.map((r) => r.toRadixString(16)).join('-');
  }

  /// True when [src] is a Twemoji or emoji-datasource CDN sprite URL.
  static bool isTwemojiOrEmojiDatasourceUrl(String src) {
    final lower = src.toLowerCase();
    return lower.contains('twemoji') || lower.contains('emoji-datasource');
  }

  /// Twemoji URL for a reaction key (shortcode or raw unicode).
  static String? twemojiUrlForKey(String key) {
    final bare = _stripColonWrap(key);
    final unicode = _shortcodeToUnicode[bare] ?? bare;
    if (unicode == bare && !_unicodeToShortcode.containsKey(bare)) {
      return null;
    }
    return twemojiUrlForUnicode(unicode);
  }

  static CustomEmoji? findCustomEmoji(String key, List<CustomEmoji> customEmojis) {
    final bare = _stripColonWrap(key);
    for (final e in customEmojis) {
      if (e.name == bare) return e;
    }
    return null;
  }

  /// Display label for tooltips (`:name:` or unicode).
  static String displayLabel(String key) {
    final bare = _stripColonWrap(key);
    final customLike =
        _looksLikeShortcode(bare) && !_shortcodeToUnicode.containsKey(bare);
    if (customLike && !_unicodeToShortcode.containsKey(bare)) {
      return ':$bare:';
    }
    final unicode = unicodeForKey(bare);
    if (unicode != null) return unicode;
    return bare;
  }

  /// Replaces `:customName:` tokens in escaped HTML with inline emoji images.
  static String expandCustomEmojisInEscapedHtml(
    String escaped,
    List<CustomEmoji> customEmojis,
  ) {
    if (customEmojis.isEmpty) return escaped;
    final byName = <String, CustomEmoji>{
      for (final e in customEmojis) e.name: e,
    };
    return escaped.replaceAllMapped(
      RegExp(r':([a-zA-Z0-9_]{1,32}):'),
      (m) {
        final name = m.group(1)!;
        final emoji = byName[name];
        final url = emoji?.url;
        if (url == null || url.isEmpty) return m.group(0)!;
        final safeUrl = url.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
        return '<img src="$safeUrl" class="emoji-image" alt=":$name:" />';
      },
    );
  }

  /// Replaces raw Unicode emoji in plain/escaped text with Twemoji `<img>` tags.
  /// Only true emoji graphemes are converted — never ASCII letters/digits.
  static String expandUnicodeEmojisInText(String text) {
    if (text.isEmpty) return text;
    final out = StringBuffer();
    for (final cluster in text.characters) {
      if (_isEmojiCluster(cluster)) {
        out.write(_twemojiImgTag(cluster));
      } else {
        out.write(cluster);
      }
    }
    return out.toString();
  }

  /// Reverts messages corrupted by an earlier bug that wrapped every character
  /// in Twemoji `<img>` tags (alt was the original character).
  static String repairOverExpandedEmojiHtml(String html) {
    if (html.isEmpty) return html;
    return html.replaceAllMapped(
      RegExp(
        r'<img\b[^>]*\bclass="emoji-image"[^>]*\balt="([^"]*)"[^>]*/?\s*>',
        caseSensitive: false,
      ),
      (m) {
        final alt = _unescapeHtmlAttr(m.group(1)!);
        if (_wasWronglyExpandedAsEmoji(alt)) return alt;
        return m.group(0)!;
      },
    );
  }

  /// Same as [expandUnicodeEmojisInText] but skips HTML tag contents.
  static String expandUnicodeEmojisInHtml(String html) {
    if (html.isEmpty) return html;
    final repaired = repairOverExpandedEmojiHtml(html);
    final tagRe = RegExp(r'(<[^>]*>)');
    final out = StringBuffer();
    var lastEnd = 0;
    for (final m in tagRe.allMatches(repaired)) {
      out.write(expandUnicodeEmojisInText(repaired.substring(lastEnd, m.start)));
      out.write(m.group(0));
      lastEnd = m.end;
    }
    out.write(expandUnicodeEmojisInText(repaired.substring(lastEnd)));
    return out.toString();
  }

  static bool isEmojiCluster(String cluster) {
    if (cluster.isEmpty) return false;
    if (_wasWronglyExpandedAsEmoji(cluster)) return false;
    // Analyzer does not model Unicode property escapes; valid at runtime.
    // ignore: valid_regexps
    if (!RegExp(r'\p{Extended_Pictographic}|\p{Regional_Indicator}',
            unicode: true)
        .hasMatch(cluster)) {
      return false;
    }
    return twemojiUrlsForUnicode(cluster).isNotEmpty;
  }

  static bool _isEmojiCluster(String cluster) => isEmojiCluster(cluster);

  static bool _wasWronglyExpandedAsEmoji(String text) {
    if (text.isEmpty) return true;
    // Plain ASCII / Latin-1 text must never become emoji images.
    return text.runes.every((r) => r <= 0x024F);
  }

  static String _unescapeHtmlAttr(String value) {
    return value
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  static String _twemojiImgTag(String unicode) {
    final url = twemojiUrlForUnicode(unicode)!;
    final safeUrl = url.replaceAll('&', '&amp;').replaceAll('"', '&quot;');
    final safeAlt = unicode
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '<img src="$safeUrl" class="emoji-image" alt="$safeAlt" />';
  }
}

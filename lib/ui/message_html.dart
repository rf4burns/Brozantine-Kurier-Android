import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/custom_emoji.dart';
import '../core/emoji_codec.dart';
import '../protocol/mentions.dart';
import '../protocol/models.dart';
import 'emoji_glyph.dart';

const kMessageFontSize = 16.0;
/// Vanilla `.msg-content { line-height: 1.6 }` with Tailwind preflight (no `<p>` margins).
const kMessageLineHeight = 1.6;

/// TipTap/Kurier message HTML rendered without flutter_html's paragraph
/// margins, which were stretching chat to roughly triple Discord spacing.
class MessageBody extends StatelessWidget {
  const MessageBody({
    super.key,
    required this.html,
    required this.color,
    required this.linkColor,
    this.ownUserId,
    this.customEmojis = const [],
    this.mentionUsers,
    this.onLink,
    this.onMention,
  });

  final String html;
  final Color color;
  final Color linkColor;
  final int? ownUserId;
  final List<CustomEmoji> customEmojis;
  final Map<int, KurierUser>? mentionUsers;
  final ValueChanged<String>? onLink;
  final void Function(int userId, Offset globalPosition)? onMention;

  @override
  Widget build(BuildContext context) {
    final spans = messageHtmlSpans(
      html,
      color: color,
      linkColor: linkColor,
      mentionBg: linkColor.withValues(alpha: 0.10),
      selfMentionFg: const Color(0xFFFACC15),
      selfMentionBg: linkColor.withValues(alpha: 0.10),
      ownUserId: ownUserId,
      customEmojis: customEmojis,
      mentionUsers: mentionUsers,
      onLink: onLink,
      onMention: onMention,
    );
    if (spans.isEmpty) return const SizedBox.shrink();
    final hasWidgets = spans.any((s) => s is WidgetSpan);
    return Text.rich(
      TextSpan(
        style: TextStyle(
          color: color,
          fontSize: kMessageFontSize,
          height: kMessageLineHeight,
        ),
        children: spans,
      ),
      strutStyle: hasWidgets
          ? null
          : const StrutStyle(
              fontSize: kMessageFontSize,
              height: kMessageLineHeight,
              leading: 0,
              forceStrutHeight: true,
            ),
    );
  }
}

List<InlineSpan> messageHtmlSpans(
  String html, {
  required Color color,
  required Color linkColor,
  Color? mentionBg,
  Color? selfMentionFg,
  Color? selfMentionBg,
  int? ownUserId,
  List<CustomEmoji> customEmojis = const [],
  Map<int, KurierUser>? mentionUsers,
  ValueChanged<String>? onLink,
  void Function(int userId, Offset globalPosition)? onMention,
}) {
  final tokens = _tokenize(html);
  final spans = <InlineSpan>[];
  final styles = <_HtmlStyle>[];
  var pendingBreak = false;
  var liveMentionEmitted = false;

  void flushBreak() {
    if (pendingBreak && spans.isNotEmpty) {
      spans.add(const TextSpan(text: '\n'));
    }
    pendingBreak = false;
  }

  void pushText(String raw) {
    if (raw.isEmpty) return;
    var text = _decodeEntities(raw);
    if (text.isEmpty) return;
    flushBreak();
    final style = styles.isEmpty ? const _HtmlStyle() : styles.last;
    final mentionId = style.mention ? style.mentionUserId : null;
    final mentionUser =
        mentionId == null || mentionUsers == null ? null : mentionUsers[mentionId];
    if (mentionUser != null) {
      if (liveMentionEmitted) return;
      liveMentionEmitted = true;
      text = '@${mentionUser.displayName}';
    }
    TapGestureRecognizer? recognizer;
    if (style.href != null && onLink != null) {
      final href = style.href!;
      recognizer = TapGestureRecognizer()..onTap = () => onLink(href);
    } else if (style.mentionUserId != null && onMention != null) {
      Offset? pos;
      final userId = style.mentionUserId!;
      recognizer = TapGestureRecognizer()
        ..onTapDown = (d) {
          pos = d.globalPosition;
        }
        ..onTap = () => onMention(userId, pos ?? Offset.zero);
    }
    final isSelfMention = style.mention &&
        (style.mentionKind == 'everyone' ||
            style.mentionKind == 'here' ||
            (style.mentionUserId != null && style.mentionUserId == ownUserId));
    final mentionColor = isSelfMention ? (selfMentionFg ?? linkColor) : linkColor;
    final textStyle = TextStyle(
      color: style.href != null || style.mention ? mentionColor : color,
      backgroundColor: style.mention
          ? (isSelfMention ? selfMentionBg : mentionBg)
          : null,
      fontWeight: style.mention || style.bold
          ? FontWeight.w600
          : FontWeight.normal,
      fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
      decoration: style.href != null || style.underline
          ? TextDecoration.underline
          : style.strike
              ? TextDecoration.lineThrough
              : TextDecoration.none,
      decorationColor: style.href != null ? linkColor : null,
      decorationThickness: style.href != null ? 1 : null,
      fontFamily: style.code ? 'monospace' : null,
      fontSize: style.code ? 13.5 : kMessageFontSize,
      height: kMessageLineHeight,
    );
    if (style.code) {
      spans.add(TextSpan(text: text, style: textStyle, recognizer: recognizer));
      return;
    }
    final buf = StringBuffer();
    void flushText() {
      if (buf.isEmpty) return;
      spans.add(
        TextSpan(
          text: buf.toString(),
          style: textStyle,
          recognizer: recognizer,
        ),
      );
      buf.clear();
    }

    for (final cluster in text.characters) {
      if (EmojiCodec.isEmojiCluster(cluster)) {
        flushText();
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: ChatEmojiImage(
                emojiKey: cluster,
                customEmojis: customEmojis,
                size: 20,
              ),
            ),
          ),
        );
      } else {
        buf.write(cluster);
      }
    }
    flushText();
  }

  var skipEmojiSpanText = false;

  for (final token in tokens) {
    if (token is _TextTok) {
      if (!skipEmojiSpanText) pushText(token.text);
      continue;
    }
    final tag = token as _TagTok;
    final name = tag.name;
    if (tag.closing) {
      if (name == 'span' && skipEmojiSpanText) skipEmojiSpanText = false;
      if (styles.isNotEmpty) {
        final popped = styles.removeLast();
        if (popped.mention) liveMentionEmitted = false;
      }
      if (name == 'p' ||
          name == 'div' ||
          name == 'pre' ||
          name == 'li' ||
          name == 'h1' ||
          name == 'h2' ||
          name == 'h3') {
        pendingBreak = true;
      }
      continue;
    }
    if (name == 'br') {
      flushBreak();
      if (spans.isNotEmpty) spans.add(const TextSpan(text: '\n'));
      continue;
    }
    if (name == 'img') {
      flushBreak();
      final src = tag.attr('src') ?? '';
      final alt = tag.attr('alt') ?? '';
      final cls = tag.attr('class') ?? '';
      final isEmoji = cls.contains('emoji-image') ||
          EmojiCodec.isTwemojiOrEmojiDatasourceUrl(src);
      if (isEmoji) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: ChatEmojiImage(
                src: src,
                emojiKey: alt,
                customEmojis: customEmojis,
                size: 20,
              ),
            ),
          ),
        );
      }
      continue;
    }
    if (name == 'span' && tag.attr('data-type') == 'emoji') {
      flushBreak();
      final key = (tag.attr('data-name') ?? '').trim();
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: ChatEmojiImage(
              emojiKey: key,
              customEmojis: customEmojis,
              size: 20,
            ),
          ),
        ),
      );
      skipEmojiSpanText = true;
      styles.add(styles.isEmpty ? const _HtmlStyle() : styles.last);
      continue;
    }
    final prev = styles.isEmpty ? const _HtmlStyle() : styles.last;
    final isMention = name == 'span' &&
        (tag.attr('data-type') == 'mention' ||
            tag.attr('data-mention-kind') != null);
    styles.add(
      prev.copyWith(
        bold: name == 'strong' || name == 'b' ? true : null,
        italic: name == 'em' || name == 'i' ? true : null,
        underline: name == 'u' ? true : null,
        strike: name == 's' || name == 'del' ? true : null,
        code: name == 'code' || name == 'pre' ? true : null,
        href: name == 'a' ? tag.attr('href') : null,
        mention: isMention ? true : null,
        mentionKind: isMention ? tag.attr('data-mention-kind') : null,
        mentionUserId: isMention
            ? int.tryParse(tag.attr('data-user-id') ?? '')
            : null,
      ),
    );
    if (name == 'p' ||
        name == 'div' ||
        name == 'li' ||
        name == 'pre' ||
        name == 'h1' ||
        name == 'h2' ||
        name == 'h3') {
      pendingBreak = spans.isNotEmpty;
    }
  }

  if (spans.isEmpty) {
    final plain = htmlToPlainText(html);
    if (plain.isEmpty) return const [];
    return [TextSpan(text: plain)];
  }
  return spans;
}

class _HtmlStyle {
  const _HtmlStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.code = false,
    this.mention = false,
    this.mentionKind,
    this.mentionUserId,
    this.href,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool code;
  final bool mention;
  final String? mentionKind;
  final int? mentionUserId;
  final String? href;

  _HtmlStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strike,
    bool? code,
    bool? mention,
    String? mentionKind,
    int? mentionUserId,
    String? href,
  }) {
    return _HtmlStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strike: strike ?? this.strike,
      code: code ?? this.code,
      mention: mention ?? this.mention,
      mentionKind: mentionKind ?? this.mentionKind,
      mentionUserId: mentionUserId ?? this.mentionUserId,
      href: href ?? this.href,
    );
  }
}

sealed class _Tok {}

class _TextTok extends _Tok {
  _TextTok(this.text);
  final String text;
}

class _TagTok extends _Tok {
  _TagTok(this.name, this.attrs, {required this.closing});
  final String name;
  final Map<String, String> attrs;
  final bool closing;
  String? attr(String key) => attrs[key];
}

final _tagRe = RegExp(r'<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*)>|([^<]+)', dotAll: true);
final _attrRe = RegExp(r'''([a-zA-Z0-9:-]+)\s*=\s*("([^"]*)"|'([^']*)'|(\S+))''');

List<_Tok> _tokenize(String html) {
  final out = <_Tok>[];
  for (final m in _tagRe.allMatches(html)) {
    final text = m.group(4);
    if (text != null) {
      out.add(_TextTok(text));
      continue;
    }
    final closing = m.group(1) == '/';
    final name = (m.group(2) ?? '').toLowerCase();
    final rawAttrs = m.group(3) ?? '';
    final attrs = <String, String>{};
    for (final a in _attrRe.allMatches(rawAttrs)) {
      attrs[a.group(1)!.toLowerCase()] =
          a.group(3) ?? a.group(4) ?? a.group(5) ?? '';
    }
    out.add(_TagTok(name, attrs, closing: closing));
  }
  return out;
}

String _decodeEntities(String text) {
  return text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final n = int.tryParse(m.group(1)!);
        return n == null ? m.group(0)! : String.fromCharCode(n);
      });
}

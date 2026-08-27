import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/custom_emoji.dart';
import '../core/emoji_codec.dart';

/// Renders a reaction/picker emoji: custom server image, Twemoji, or text fallback.
class EmojiGlyph extends StatelessWidget {
  const EmojiGlyph({
    super.key,
    required this.emojiKey,
    required this.customEmojis,
    this.size = 16,
    this.fontSize,
  });

  final String emojiKey;
  final List<CustomEmoji> customEmojis;
  final double size;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final custom = EmojiCodec.findCustomEmoji(emojiKey, customEmojis);
    if (custom?.url != null) {
      return Image.network(
        custom!.url!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, error, stack) => _textFallback(':${custom.name}:'),
      );
    }

    final unicode = EmojiCodec.unicodeForKey(emojiKey) ?? emojiKey;
    if (EmojiCodec.twemojiUrlsForUnicode(unicode).isNotEmpty) {
      return TwemojiGlyph(
        unicode: unicode,
        size: size,
        fontSize: fontSize,
      );
    }

    return _textFallback(unicode);
  }

  Widget _textFallback(String text) {
    return Text(
      text,
      style: TextStyle(fontSize: fontSize ?? size * 0.9),
    );
  }
}

/// Picker cell for a native Unicode emoji (Twemoji preview).
class NativeEmojiGlyph extends StatelessWidget {
  const NativeEmojiGlyph({
    super.key,
    required this.unicode,
    this.size = 22,
  });

  final String unicode;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TwemojiGlyph(unicode: unicode, size: size);
  }
}

/// Inline emoji in chat message HTML — same Twemoji sprites as reactions.
class ChatEmojiImage extends StatelessWidget {
  const ChatEmojiImage({
    super.key,
    this.src,
    required this.emojiKey,
    required this.customEmojis,
    this.size = 20,
  });

  final String? src;
  final String emojiKey;
  final List<CustomEmoji> customEmojis;
  final double size;

  @override
  Widget build(BuildContext context) {
    var key = emojiKey.trim();
    if (key.isEmpty) {
      key = (src ?? '').trim();
    }
    return EmojiGlyph(
      emojiKey: key,
      customEmojis: customEmojis,
      size: size,
      fontSize: size * 0.9,
    );
  }
}

/// Inline spans for the message composer — same Twemoji/custom sprites as chat.
class ComposerInlineSpans {
  ComposerInlineSpans._();

  static final _customToken = RegExp(r':([a-zA-Z0-9_]{1,32}):');

  static List<InlineSpan> forText(
    String text,
    TextStyle style, {
    List<CustomEmoji> customEmojis = const [],
    double emojiSize = 20,
  }) {
    if (text.isEmpty) return [TextSpan(text: '', style: style)];
    final spans = <InlineSpan>[];
    var i = 0;
    for (final m in _customToken.allMatches(text)) {
      if (m.start > i) {
        spans.addAll(_unicodeSpans(
          text.substring(i, m.start),
          style,
          customEmojis: customEmojis,
          emojiSize: emojiSize,
        ));
      }
      final name = m.group(1)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: EmojiGlyph(
          emojiKey: name,
          customEmojis: customEmojis,
          size: emojiSize,
          fontSize: emojiSize * 0.9,
        ),
      ));
      i = m.end;
    }
    if (i < text.length) {
      spans.addAll(_unicodeSpans(
        text.substring(i),
        style,
        customEmojis: customEmojis,
        emojiSize: emojiSize,
      ));
    }
    return spans;
  }

  static List<InlineSpan> _unicodeSpans(
    String text,
    TextStyle style, {
    required List<CustomEmoji> customEmojis,
    required double emojiSize,
  }) {
    if (text.isEmpty) return const [];
    final spans = <InlineSpan>[];
    for (final cluster in text.characters) {
      if (EmojiCodec.isEmojiCluster(cluster)) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: EmojiGlyph(
            emojiKey: cluster,
            customEmojis: customEmojis,
            size: emojiSize,
            fontSize: emojiSize * 0.9,
          ),
        ));
      } else {
        spans.add(TextSpan(text: cluster, style: style));
      }
    }
    return spans;
  }
}

/// Twemoji sprite with CDN URL fallbacks for ZWJ sequences.
class TwemojiGlyph extends StatefulWidget {
  const TwemojiGlyph({
    super.key,
    required this.unicode,
    required this.size,
    this.fontSize,
  });

  final String unicode;
  final double size;
  final double? fontSize;

  @override
  State<TwemojiGlyph> createState() => _TwemojiGlyphState();
}

class _TwemojiGlyphState extends State<TwemojiGlyph> {
  int _urlIndex = 0;
  bool _failed = false;

  List<String> get _urls => EmojiCodec.twemojiUrlsForUnicode(widget.unicode);

  @override
  void didUpdateWidget(covariant TwemojiGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unicode != widget.unicode) {
      _urlIndex = 0;
      _failed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed || _urlIndex >= _urls.length) {
      return Text(
        widget.unicode,
        style: TextStyle(fontSize: widget.fontSize ?? widget.size),
      );
    }
    return Image.network(
      _urls[_urlIndex],
      width: widget.size,
      height: widget.size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            if (_urlIndex + 1 < _urls.length) {
              _urlIndex++;
            } else {
              _failed = true;
            }
          });
        });
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: Text(
              widget.unicode,
              style: TextStyle(
                fontSize: (widget.fontSize ?? widget.size) * 0.85,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Picker cell for a custom server emoji.
class CustomEmojiGlyph extends StatelessWidget {
  const CustomEmojiGlyph({
    super.key,
    required this.emoji,
    this.size = 24,
  });

  final CustomEmoji emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (emoji.url != null) {
      return Image.network(
        emoji.url!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => Text(
          ':${emoji.name}:',
          style: TextStyle(fontSize: 11, color: context.p.faint),
        ),
      );
    }
    return Text(
      ':${emoji.name}:',
      style: TextStyle(fontSize: 11, color: context.p.faint),
    );
  }
}

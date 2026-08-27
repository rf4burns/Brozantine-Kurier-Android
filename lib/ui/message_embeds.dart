import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../app/theme.dart';
import '../protocol/mentions.dart';
import '../protocol/models.dart';
import '../session/session_controller.dart';
import 'gif_favourite_star.dart';
import 'youtube_iframe_stub.dart'
    if (dart.library.js_interop) 'youtube_iframe_web.dart';

final _urlPattern = RegExp(r'''https?://[^\s<>"']+''', caseSensitive: false);
final _youtubeIdPattern = RegExp(r'^[\w-]{11}$');
final _trailingUrlPunct = RegExp(r'[),.;]+$');

const _youtubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtube-nocookie.com',
  'www.youtube-nocookie.com',
};

const _gifHostRoots = {'klipy.com', 'tenor.com', 'giphy.com', 'gfycat.com'};

const kYoutubeEmbedAccent = Color(0xFFFF0000);
const kTwitterEmbedAccent = Color(0xFF1D9BF0);
const kEmbedCardMaxWidth = 432.0;

Key youtubeEmbedKey(String videoId) => Key('youtube-embed-$videoId');

Key ogImageKey(String url) => Key('og-image-$url');

Key gifEmbedKey(String url) => Key('gif-embed-$url');

final _youtubeOEmbedCache = <String, YoutubeOEmbed>{};

/// Override in tests to skip the network. Null uses the live YouTube oEmbed API.
Future<YoutubeOEmbed?> Function(String videoId)? youtubeOEmbedLookup;

class YoutubeOEmbed {
  const YoutubeOEmbed({this.title, this.author});

  final String? title;
  final String? author;
}

Color embedAccentForUrl(String? url, [Color fallback = defaultAccent]) {
  final host = _hostOf(url);
  if (host == null) return fallback;
  if (host == 'youtu.be' ||
      host.endsWith('.youtu.be') ||
      _youtubeHosts.contains(host) ||
      host.endsWith('.youtube.com')) {
    return kYoutubeEmbedAccent;
  }
  if (host == 'x.com' ||
      host.endsWith('.x.com') ||
      host == 'twitter.com' ||
      host.endsWith('.twitter.com') ||
      host == 't.co' ||
      host.endsWith('.t.co')) {
    return kTwitterEmbedAccent;
  }
  return fallback;
}

String? _hostOf(String? raw) {
  if (raw == null) return null;
  var value = raw.trim();
  if (value.isEmpty) return null;
  if (!value.contains('://')) value = 'https://$value';
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.host.toLowerCase();
}

String? _nonEmptyString(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? ogAuthor(Map<String, dynamic>? data) {
  if (data == null) return null;
  return _nonEmptyString(data['author']) ??
      _nonEmptyString(data['authorName']) ??
      _nonEmptyString(data['author_name']);
}

bool isImageMediaType(String? type) {
  if (type == null || type.isEmpty) return false;
  return type == 'image' || type.startsWith('image/');
}

List<String> ogImageUrls(dynamic images) {
  if (images is! List) return const [];
  final out = <String>[];
  for (final item in images) {
    if (item is String && item.isNotEmpty) {
      out.add(item);
    } else if (item is Map) {
      final url = item['url'] ?? item['src'];
      if (url is String && url.isNotEmpty) out.add(url);
    }
  }
  return out;
}

String? youtubeVideoIdFromUrl(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;
  value = value.replaceAll(RegExp(r'[),.;]+$'), '');
  if (!value.contains('://')) value = 'https://$value';
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  if (host == 'youtu.be' || host.endsWith('.youtu.be')) {
    if (uri.pathSegments.isEmpty) return null;
    return _validYoutubeId(uri.pathSegments.first);
  }
  if (_youtubeHosts.contains(host) || host.endsWith('.youtube.com')) {
    final v = uri.queryParameters['v'];
    if (v != null) return _validYoutubeId(v);
    if (uri.pathSegments.length >= 2) {
      final kind = uri.pathSegments.first;
      if (kind == 'shorts' ||
          kind == 'embed' ||
          kind == 'live' ||
          kind == 'v') {
        return _validYoutubeId(uri.pathSegments[1]);
      }
    }
  }
  return null;
}

Set<String> youtubeIdsIn(String? content, [List<dynamic> metadata = const []]) {
  final ids = <String>{};
  void consider(String? text) {
    if (text == null || text.isEmpty) return;
    final direct = youtubeVideoIdFromUrl(text);
    if (direct != null) ids.add(direct);
    for (final match in _urlPattern.allMatches(text)) {
      final id = youtubeVideoIdFromUrl(match.group(0)!);
      if (id != null) ids.add(id);
    }
  }

  consider(content);
  for (final meta in metadata) {
    if (meta is! Map) continue;
    final url = meta['url'];
    if (url is String) consider(url);
  }
  return ids;
}

String? _validYoutubeId(String? id) {
  if (id == null || !_youtubeIdPattern.hasMatch(id)) return null;
  return id;
}

Map<String, dynamic>? openGraphForYoutube(
  List<dynamic> metadata,
  String videoId,
) {
  for (final meta in metadata) {
    if (meta is! Map) continue;
    final url = meta['url'];
    if (url is String && youtubeVideoIdFromUrl(url) == videoId) {
      return Map<String, dynamic>.from(meta);
    }
  }
  return null;
}

YoutubeEmbed youtubeEmbedFor(String videoId, [Map<String, dynamic>? og]) {
  return YoutubeEmbed(
    key: youtubeEmbedKey(videoId),
    videoId: videoId,
    title: _nonEmptyString(og?['title']),
    author: ogAuthor(og),
  );
}

Future<YoutubeOEmbed?> fetchYoutubeOEmbed(String videoId) async {
  final cached = _youtubeOEmbedCache[videoId];
  if (cached != null) return cached;
  final lookup = youtubeOEmbedLookup ?? _fetchYoutubeOEmbed;
  final data = await lookup(videoId);
  if (data != null) _youtubeOEmbedCache[videoId] = data;
  return data;
}

Future<YoutubeOEmbed?> _fetchYoutubeOEmbed(String videoId) async {
  final uri = Uri.https('www.youtube.com', '/oembed', {
    'url': 'https://www.youtube.com/watch?v=$videoId',
    'format': 'json',
  });
  final res = await http.get(uri).timeout(const Duration(seconds: 4));
  if (res.statusCode != 200) return null;
  final json = jsonDecode(res.body);
  if (json is! Map) return null;
  final title = _nonEmptyString(json['title']);
  final author = _nonEmptyString(json['author_name']);
  if (title == null && author == null) return null;
  return YoutubeOEmbed(title: title, author: author);
}

String _cleanUrl(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return value;
  return value.replaceAll(_trailingUrlPunct, '');
}

String _absoluteUrl(String value) {
  if (!value.contains('://')) return 'https://$value';
  return value;
}

bool _isGifHost(String host) {
  var value = host.toLowerCase();
  if (value.startsWith('www.')) value = value.substring(4);
  if (value == 'gph.is') return true;
  for (final root in _gifHostRoots) {
    if (value == root || value.endsWith('.$root')) return true;
  }
  return false;
}

bool isGifUrl(String raw) {
  final cleaned = _cleanUrl(raw);
  if (cleaned.isEmpty) return false;
  final uri = Uri.tryParse(_absoluteUrl(cleaned));
  if (uri == null || uri.host.isEmpty) return false;
  if (_isGifHost(uri.host)) return true;
  final path = uri.path.toLowerCase();
  return path.endsWith('.gif') || path.endsWith('.gifv');
}

String? _canonicalGifUrl(String raw) {
  final cleaned = _cleanUrl(raw);
  if (cleaned.isEmpty || !isGifUrl(cleaned)) return null;
  return _absoluteUrl(cleaned);
}

Set<String> gifUrlsIn(String? content, [List<dynamic> metadata = const []]) {
  final urls = <String>{};
  void consider(String? text) {
    if (text == null || text.isEmpty) return;
    final direct = _canonicalGifUrl(text);
    if (direct != null) urls.add(direct);
    for (final match in _urlPattern.allMatches(text)) {
      final url = _canonicalGifUrl(match.group(0)!);
      if (url != null) urls.add(url);
    }
  }

  consider(content);
  for (final meta in metadata) {
    if (meta is! Map) continue;
    final url = meta['url'];
    if (url is String) {
      consider(url);
      if (meta['kind'] == 'media' && '${meta['mediaType']}' == 'image/gif') {
        final cleaned = _cleanUrl(url);
        if (cleaned.isNotEmpty) urls.add(_absoluteUrl(cleaned));
      }
    }
  }
  return urls;
}

String hideGifUrlsInHtml(String html) {
  if (html.isEmpty) return html;
  return html.replaceAllMapped(_urlPattern, (match) {
    final raw = match.group(0)!;
    return isGifUrl(raw) ? '' : raw;
  });
}

bool messageHtmlHasVisibleText(String html) {
  return htmlToPlainText(html).isNotEmpty;
}

String _gifEmbedUrlFromOg(Map<String, dynamic> data, String fallback) {
  final images = ogImageUrls(data['images']);
  for (final image in images) {
    if (isGifUrl(image)) return image;
  }
  if (images.isNotEmpty) return images.first;
  return fallback;
}

void _openUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  launchUrl(uri);
}

class MessageEmbeds extends StatelessWidget {
  const MessageEmbeds({super.key, required this.message, this.session});

  final KurierMessage message;
  final SessionController? session;

  @override
  Widget build(BuildContext context) {
    if (session == null) return _embeds();
    return ListenableBuilder(
      listenable: session!,
      builder: (context, _) => _embeds(),
    );
  }

  Widget _embeds() {
    final children = <Widget>[];
    final emittedYoutube = <String>{};
    final emittedGifs = <String>{};

    Widget gifEmbed(String url) {
      return _MediaImage(
        key: gifEmbedKey(url),
        url: url,
        session: session,
        showFavourite: session != null,
      );
    }

    for (final meta in message.metadata) {
      if (meta is! Map) continue;
      final map = Map<String, dynamic>.from(meta);
      final kind = map['kind'];
      if (kind == 'media' && map['url'] is String) {
        final url = map['url'] as String;
        final gif = isGifUrl(url) || '${map['mediaType']}' == 'image/gif';
        if (gif) {
          if (emittedGifs.add(url)) children.add(gifEmbed(url));
        } else if (isImageMediaType('${map['mediaType']}')) {
          children.add(_MediaImage(url: url));
        }
      } else if (kind == 'open_graph') {
        final url = map['url'] is String ? map['url'] as String : null;
        final yt = url == null ? null : youtubeVideoIdFromUrl(url);
        if (yt != null) {
          if (emittedYoutube.add(yt)) {
            children.add(youtubeEmbedFor(yt, map));
          }
          continue;
        }
        if (url != null && isGifUrl(url)) {
          final embedUrl = _gifEmbedUrlFromOg(map, url);
          emittedGifs.add(url);
          emittedGifs.add(embedUrl);
          children.add(gifEmbed(embedUrl));
          continue;
        }
        children.add(_OpenGraphCard(data: map));
      }
    }

    for (final url in gifUrlsIn(message.content, message.metadata)) {
      if (emittedGifs.add(url)) children.add(gifEmbed(url));
    }

    for (final id in youtubeIdsIn(message.content, message.metadata)) {
      if (emittedYoutube.add(id)) {
        children.add(
          youtubeEmbedFor(id, openGraphForYoutube(message.metadata, id)),
        );
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class YoutubeEmbed extends StatefulWidget {
  const YoutubeEmbed({
    super.key,
    required this.videoId,
    this.title,
    this.author,
  });

  final String videoId;
  final String? title;
  final String? author;

  @override
  State<YoutubeEmbed> createState() => _YoutubeEmbedState();
}

class _YoutubeEmbedState extends State<YoutubeEmbed> {
  bool _playing = false;
  String? _oembedTitle;
  String? _oembedAuthor;

  String get _watchUrl => 'https://www.youtube.com/watch?v=${widget.videoId}';

  String get _thumbUrl =>
      'https://i.ytimg.com/vi/${widget.videoId}/hqdefault.jpg';

  String? get _title => _nonEmptyString(widget.title) ?? _oembedTitle;

  String? get _author => _nonEmptyString(widget.author) ?? _oembedAuthor;

  @override
  void initState() {
    super.initState();
    if (_nonEmptyString(widget.author) == null) {
      _loadOEmbed();
    }
  }

  Future<void> _loadOEmbed() async {
    try {
      final data = await fetchYoutubeOEmbed(widget.videoId);
      if (!mounted || data == null) return;
      setState(() {
        _oembedTitle = data.title;
        _oembedAuthor = data.author;
      });
    } catch (_) {}
  }

  void _play() {
    if (kCanEmbedYoutubeIFrame) {
      setState(() => _playing = true);
      return;
    }
    _openUrl(_watchUrl);
  }

  @override
  Widget build(BuildContext context) {
    return _EmbedCard(
      accent: kYoutubeEmbedAccent,
      siteName: 'YouTube',
      author: _author,
      title: _title,
      titleUrl: _watchUrl,
      media: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: _playing && kCanEmbedYoutubeIFrame
              ? youtubeIFrameView(widget.videoId)
              : _thumbnail(),
        ),
      ),
    );
  }

  Widget _thumbnail() {
    return Material(
      color: Colors.black,
      child: InkWell(
        onTap: _play,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              _thumbUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(color: Colors.black),
            ),
            const ColoredBox(color: Color(0x33000000)),
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 64,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaImage extends StatelessWidget {
  const _MediaImage({
    super.key,
    required this.url,
    this.session,
    this.showFavourite = false,
  });

  final String url;
  final SessionController? session;
  final bool showFavourite;

  @override
  Widget build(BuildContext context) {
    Widget image = GestureDetector(
      onTap: () => _openUrl(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400, maxHeight: 300),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => showFavourite
                ? const SizedBox(
                    width: 240,
                    height: 160,
                    child: ColoredBox(color: Color(0x33000000)),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );

    if (showFavourite && session != null) {
      final fav = session!.store.favoriteGifs().contains(url);
      image = Align(
        alignment: Alignment.centerLeft,
        child: Stack(
          children: [
            image,
            Positioned(
              top: 4,
              right: 4,
              child: GifFavouriteStar(
                key: gifFavouriteStarKey(url),
                favourited: fav,
                onPressed: () => session!.toggleFavoriteGif(url),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(padding: const EdgeInsets.only(top: 4), child: image);
  }
}

class _OpenGraphCard extends StatelessWidget {
  const _OpenGraphCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final url = data['url'] is String ? data['url'] as String : null;
    final title = '${data['title'] ?? url ?? ''}'.trim();
    if (title.isEmpty && url == null) return const SizedBox.shrink();

    final description = '${data['description'] ?? ''}'.trim();
    var siteName = '${data['siteName'] ?? ''}'.trim();
    if (siteName.isEmpty && url != null) {
      siteName = Uri.tryParse(url)?.host ?? '';
    }
    final images = ogImageUrls(data['images']);
    final imageUrl = images.isEmpty ? null : images.first;
    final favicons = ogImageUrls(data['favicons']);
    final faviconUrl = favicons.isEmpty ? null : favicons.first;

    return _EmbedCard(
      accent: embedAccentForUrl(url, context.k.accent),
      siteName: siteName.isEmpty ? null : siteName,
      author: ogAuthor(data),
      title: title.isEmpty ? null : title,
      titleUrl: url,
      description: description.isEmpty ? null : description,
      thumbnailUrl: imageUrl,
      footerIconUrl: faviconUrl,
      footerText: faviconUrl == null
          ? null
          : (siteName.isEmpty ? null : siteName),
      onTap: url == null ? null : () => _openUrl(url),
    );
  }
}

class _EmbedCard extends StatelessWidget {
  const _EmbedCard({
    required this.accent,
    this.siteName,
    this.author,
    this.title,
    this.titleUrl,
    this.description,
    this.thumbnailUrl,
    this.footerIconUrl,
    this.footerText,
    this.media,
    this.onTap,
  });

  final Color accent;
  final String? siteName;
  final String? author;
  final String? title;
  final String? titleUrl;
  final String? description;
  final String? thumbnailUrl;
  final String? footerIconUrl;
  final String? footerText;
  final Widget? media;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasFooter = footerIconUrl != null || (footerText ?? '').isNotEmpty;
    final body = ColoredBox(
      color: context.p.card,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _textColumn(context)),
                if (thumbnailUrl != null) ...[
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      thumbnailUrl!,
                      key: ogImageKey(thumbnailUrl!),
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ],
            ),
            if (media != null) ...[const SizedBox(height: 8), media!],
            if (hasFooter) ...[const SizedBox(height: 8), _footer(context)],
          ],
        ),
      ),
    );

    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.p.card,
          border: Border(left: BorderSide(color: accent, width: 4)),
        ),
        child: body,
      ),
    );

    if (onTap != null) {
      card = GestureDetector(onTap: onTap, child: card);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kEmbedCardMaxWidth),
        child: card,
      ),
    );
  }

  Widget _textColumn(BuildContext context) {
    final children = <Widget>[];

    void addGap() {
      if (children.isNotEmpty) children.add(const SizedBox(height: 4));
    }

    if ((siteName ?? '').isNotEmpty) {
      children.add(
        Text(
          siteName!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.p.muted, fontSize: 11, height: 1.2),
        ),
      );
    }
    if ((author ?? '').isNotEmpty) {
      addGap();
      children.add(
        Text(
          author!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.p.foreground,
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
      );
    }
    if ((title ?? '').isNotEmpty) {
      addGap();
      Widget titleText = Text(
        title!,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: context.k.accent,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
      );
      if (titleUrl != null) {
        titleText = GestureDetector(
          onTap: () => _openUrl(titleUrl!),
          child: titleText,
        );
      }
      children.add(titleText);
    }
    if ((description ?? '').isNotEmpty) {
      addGap();
      children.add(
        Text(
          description!,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.p.foreground,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _footer(BuildContext context) {
    return Row(
      children: [
        if (footerIconUrl != null)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Image.network(
                footerIconUrl!,
                width: 16,
                height: 16,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        if ((footerText ?? '').isNotEmpty)
          Expanded(
            child: Text(
              footerText!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.p.muted,
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ),
      ],
    );
  }
}

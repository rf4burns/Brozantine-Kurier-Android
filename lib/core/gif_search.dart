import 'dart:convert';

import 'package:http/http.dart' as http;

/// Pulls GIF URLs out of KLIPY or vanilla `gifs.search` payloads.
List<String> gifUrlsFromJson(dynamic decoded) {
  final list = <dynamic>[];
  if (decoded is Map) {
    final data = decoded['data'];
    if (data is Map && data['data'] is List) {
      list.addAll(data['data'] as List);
    } else if (data is List) {
      list.addAll(data);
    } else if (decoded['result'] is List) {
      list.addAll(decoded['result'] as List);
    } else if (decoded['results'] is List) {
      list.addAll(decoded['results'] as List);
    }
  } else if (decoded is List) {
    list.addAll(decoded);
  }
  final found = <String>[];
  for (final item in list) {
    final url = gifUrlFromItem(item);
    if (url != null) found.add(url);
  }
  return found;
}

String? _httpUrl(dynamic value) {
  if (value is String && value.startsWith('http')) return value;
  return null;
}

/// KLIPY size object: `{ gif: { url }, webp: { url } }`.
String? _urlAt(dynamic sized) {
  if (sized is! Map) return _httpUrl(sized);
  final gif = sized['gif'];
  if (gif is Map) {
    final url = _httpUrl(gif['url']);
    if (url != null) return url;
  }
  final gifUrl = _httpUrl(gif);
  if (gifUrl != null) return gifUrl;
  final webp = sized['webp'];
  if (webp is Map) {
    final url = _httpUrl(webp['url']);
    if (url != null) return url;
  }
  return _httpUrl(webp);
}

String? gifUrlFromItem(dynamic item) {
  if (item is String) return _httpUrl(item);
  if (item is! Map) return null;
  final file = item['file'] ?? item['files'];
  if (file is Map) {
    final original =
        _urlAt(file['hd']) ??
        _urlAt(file['md']) ??
        _urlAt(file['sm']) ??
        _urlAt(file['xs']) ??
        _urlAt(file['gif']) ??
        _httpUrl(file['gif']) ??
        _httpUrl(file['url']) ??
        _httpUrl(file['previewUrl']);
    if (original != null) return original;
  }
  final fileUrl = _httpUrl(file);
  if (fileUrl != null) return fileUrl;
  return _httpUrl(item['url']) ?? _httpUrl(item['previewUrl']);
}

String? gifPreviewUrlFromItem(dynamic item) {
  if (item is! Map) return gifUrlFromItem(item);
  final file = item['file'] ?? item['files'];
  if (file is Map) {
    final preview =
        _urlAt(file['sm']) ??
        _urlAt(file['xs']) ??
        _urlAt(file['md']) ??
        _urlAt(file['hd']);
    if (preview != null) return preview;
  }
  return gifUrlFromItem(item);
}

Future<List<String>> fetchKlipyGifs({
  required String apiKey,
  required String query,
}) async {
  final q = query.trim();
  final path = q.isEmpty ? 'gifs/trending' : 'gifs/search';
  final params = q.isEmpty
      ? 'per_page=24'
      : 'q=${Uri.encodeQueryComponent(q)}&per_page=24';
  final uri = Uri.parse('https://api.klipy.com/api/v1/$apiKey/$path?$params');
  final res = await http.get(uri);
  if (res.statusCode != 200) {
    throw Exception('GIF search failed (${res.statusCode})');
  }
  return gifUrlsFromJson(jsonDecode(res.body));
}

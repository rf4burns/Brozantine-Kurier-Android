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

String? gifUrlFromItem(dynamic item) {
  if (item is String && item.startsWith('http')) return item;
  if (item is! Map) return null;
  final file =
      item['file'] ?? item['files'] ?? item['url'] ?? item['previewUrl'];
  String? url;
  if (file is String) {
    url = file;
  } else if (file is Map) {
    url =
        '${file['hd']?['gif']?['url'] ?? file['md']?['gif']?['url'] ?? file['gif']?['url'] ?? file['gif'] ?? file['url'] ?? file['previewUrl'] ?? ''}';
  }
  url ??= '${item['url'] ?? item['previewUrl'] ?? ''}';
  if (url.startsWith('http')) return url;
  return null;
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

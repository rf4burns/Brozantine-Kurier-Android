import 'package:http/http.dart' as http;

/// Pulls a GIF API key out of a vanilla Kurier/Sharkord JS bundle.
///
/// The stock client bakes `https://api.klipy.com/api/v1/{key}/gifs/trending`
/// into the Vite index bundle so native clients can scrape it.
String? extractKlipyKeyFromJs(String js) {
  final patterns = <RegExp>[
    RegExp(r'''api\.klipy\.com/api/v1/([A-Za-z0-9_-]{16,80})/'''),
    RegExp(
      r'''(?:KLIPY|KLIPPY)[_-]?API[_-]?KEY|klipyApiKey|klippyApiKey|VITE_[A-Z0-9_]*(?:KLIPY|KLIPPY|GIPHY)[A-Z0-9_]*["\s:=]+["']([A-Za-z0-9_-]{16,80})["']''',
      caseSensitive: false,
    ),
    RegExp(r'''api\.giphy\.com[^"'\s]{0,120}api_key=([A-Za-z0-9_-]{16,64})'''),
    RegExp(
      r'''(?:GIPHY[_-]?API[_-]?KEY|giphyApiKey)["\s:=]+["']([A-Za-z0-9_-]{16,64})["']''',
      caseSensitive: false,
    ),
  ];
  for (final re in patterns) {
    final match = re.firstMatch(js);
    final value = match?.group(1);
    if (value != null && value.length >= 16) return value;
  }
  return null;
}

/// Join / settings maps may expose a KLIPY or GIPHY key under several names.
String? klipyKeyFromServerMap(Map<String, dynamic> raw) {
  for (final entry in raw.entries) {
    final key = entry.key.toLowerCase();
    if (!(key.contains('klipy') ||
        key.contains('klippy') ||
        key.contains('giphy') ||
        key == 'gifapikey' ||
        key == 'gif_api_key')) {
      continue;
    }
    final value = '${entry.value ?? ''}'.trim();
    if (value.isNotEmpty) return value;
  }
  for (final nestedKey in const ['publicSettings', 'settings']) {
    final nested = raw[nestedKey];
    if (nested is Map) {
      final found = klipyKeyFromServerMap(Map<String, dynamic>.from(nested));
      if (found != null) return found;
    }
  }
  return null;
}

String? vanillaIndexScriptPath(String html) {
  return RegExp(
    r'''src=["']([^"']*assets/index-[^"']+\.js)["']''',
  ).firstMatch(html)?.group(1);
}

String resolveOriginUrl(String origin, String path) {
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final base = origin.replaceAll(RegExp(r'/$'), '');
  if (path.startsWith('/')) return '$base$path';
  return '$base/$path';
}

/// Best-effort scrape of the host's vanilla web client. Never throws.
Future<String?> tryDiscoverKlipyKey({
  required String origin,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  final owned = client == null;
  try {
    final html = await _firstHtml(httpClient, origin);
    if (html == null) return null;
    final scriptPath = vanillaIndexScriptPath(html);
    if (scriptPath == null) return null;
    final jsRes = await httpClient
        .get(Uri.parse(resolveOriginUrl(origin, scriptPath)))
        .timeout(const Duration(seconds: 20));
    if (jsRes.statusCode != 200) return null;
    return extractKlipyKeyFromJs(jsRes.body);
  } catch (_) {
    return null;
  } finally {
    if (owned) httpClient.close();
  }
}

Future<String?> _firstHtml(http.Client client, String origin) async {
  for (final path in const ['/vanilla/client', '/vanilla/', '/']) {
    try {
      final res = await client
          .get(Uri.parse(resolveOriginUrl(origin, path)))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200 && res.body.isNotEmpty) return res.body;
    } catch (_) {}
  }
  return null;
}

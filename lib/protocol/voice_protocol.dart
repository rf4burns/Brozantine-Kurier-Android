import 'dart:convert';

Map<String, dynamic> asJsonMap(dynamic raw) {
  if (raw is! Map) return <String, dynamic>{};
  var map = Map<String, dynamic>.from(raw);
  final nested = map['json'];
  if (nested is Map && map.containsKey('meta') && !map.containsKey('codecs')) {
    map = Map<String, dynamic>.from(nested);
  }
  return map;
}

Map<String, dynamic>? routerRtpCapabilitiesOf(dynamic raw) {
  final map = asJsonMap(raw);
  dynamic caps = map['routerRtpCapabilities'] ?? map['rtpCapabilities'];
  if (caps == null && map['codecs'] is List) caps = map;
  if (caps is Map) {
    final out = Map<String, dynamic>.from(caps);
    if (out['codecs'] is List) return out;
  }
  return null;
}

bool isAlreadyInVoiceError(Object error) {
  final text = '$error'.toLowerCase();
  return text.contains('already in a voice channel') ||
      text.contains('already in voice');
}

/// JS async methods resolve to `{"ok":true,"v":"..."}` so Dart never has to
/// convert a rejected JS Error (which dart2js can surface as a `jsify`
/// NoSuchMethodError). Plain strings from older bridges pass through.
String unpackVoiceEngineResult(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map && decoded.containsKey('ok')) {
        if (decoded['ok'] == true) return '${decoded['v'] ?? ''}';
        final err = '${decoded['v'] ?? decoded['e'] ?? 'Voice engine error'}';
        throw StateError(err.isEmpty ? 'Voice engine error' : err);
      }
    } on StateError {
      rethrow;
    } catch (_) {}
  }
  return raw;
}

bool isVoiceJoinRateLimited(Object error) {
  final text = '$error'.toLowerCase();
  return text.contains('too many requests') ||
      text.contains('try again shortly');
}

int? _asVoiceId(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

/// Server voice events use `userId` or `remoteId` for the same person.
int? voiceEventUserId(Map<dynamic, dynamic> m) =>
    _asVoiceId(m['userId']) ?? _asVoiceId(m['remoteId']);

/// Maps a mediasoup meter key (`local` or `$userId:audio`) to a user id.
int? speakingUserIdFromKey(String key, int ownUserId) {
  if (key == 'local') return ownUserId;
  final colon = key.indexOf(':');
  if (colon <= 0) return null;
  final kind = key.substring(colon + 1);
  if (kind != 'audio' && kind != 'external_audio') return null;
  return int.tryParse(key.substring(0, colon));
}

int speakingIntensityFromJson(Map<dynamic, dynamic> json) {
  final raw = json['intensity'];
  final value = raw is int
      ? raw
      : raw is num
      ? raw.toInt()
      : int.tryParse('$raw') ?? 0;
  if (value < 0) return 0;
  if (value > 3) return 3;
  return value;
}

/// Body for `voice.produce`, including simulcast `qualityLayers` from appData.
Map<String, dynamic> voiceProduceMutation({
  required String transportId,
  required Map<String, dynamic> body,
}) {
  final appData = body['appData'] is Map
      ? Map<String, dynamic>.from(body['appData'] as Map)
      : const <String, dynamic>{};
  final layers = body['qualityLayers'] ?? appData['qualityLayers'];
  return {
    'transportId': transportId,
    'kind': '${body['kind'] ?? appData['kind'] ?? ''}',
    'rtpParameters': body['rtpParameters'] ?? const <String, dynamic>{},
    if (layers is List && layers.isNotEmpty) 'qualityLayers': layers,
  };
}

import 'dart:convert';

import 'models.dart';

Map<String, dynamic> asJsonMap(dynamic raw) {
  if (raw is! Map) return <String, dynamic>{};
  var map = Map<String, dynamic>.from(raw);
  final nested = map['json'];
  if (nested is Map && map.containsKey('meta') && !map.containsKey('codecs')) {
    map = Map<String, dynamic>.from(nested);
  }
  return map;
}

Map<String, dynamic>? iceParametersOf(dynamic raw) {
  final map = asJsonMap(raw);
  dynamic params = map['iceParameters'];
  if (params == null && map['usernameFragment'] != null) params = map;
  if (params is Map) {
    final out = Map<String, dynamic>.from(params);
    final ufrag = '${out['usernameFragment'] ?? ''}'.trim();
    final password = '${out['password'] ?? ''}'.trim();
    if (ufrag.isNotEmpty && password.isNotEmpty) return out;
  }
  return null;
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

const kVoicePlaybackGrace = Duration(seconds: 4);
const kVoicePlaybackDeadHold = Duration(seconds: 3);
const kVoiceAutoRejoinWindow = Duration(seconds: 60);
const kMaxVoiceAutoRejoins = 2;

class VoicePlaybackHealth {
  const VoicePlaybackHealth({
    this.ctxRunning = false,
    this.keepAlive = false,
    this.recvState = '',
    this.sendState = '',
    this.liveAudioKeys = const [],
    this.graphKeys = const [],
    this.playingKeys = const [],
  });

  final bool ctxRunning;
  final bool keepAlive;
  final String recvState;
  final String sendState;
  final List<String> liveAudioKeys;
  final List<String> graphKeys;
  final List<String> playingKeys;

  static const dead = VoicePlaybackHealth();

  factory VoicePlaybackHealth.fromJson(Map json) {
    List<String> keys(dynamic raw) {
      if (raw is! List) return const [];
      return raw.map((e) => '$e').where((s) => s.isNotEmpty).toList();
    }

    return VoicePlaybackHealth(
      ctxRunning: json['ctxRunning'] == true,
      keepAlive: json['keepAlive'] == true,
      recvState: '${json['recvState'] ?? ''}',
      sendState: '${json['sendState'] ?? ''}',
      liveAudioKeys: keys(json['liveAudioKeys']),
      graphKeys: keys(json['graphKeys']),
      playingKeys: keys(json['playingKeys']),
    );
  }
}

bool hasUnmutedRemoteVoiceUser({
  required int? channelId,
  required int ownUserId,
  required Map<int, Map<int, VoiceUserState>> voiceMap,
}) {
  if (channelId == null) return false;
  final occupants = voiceMap[channelId];
  if (occupants == null) return false;
  for (final e in occupants.entries) {
    if (e.key == ownUserId) continue;
    if (!e.value.micMuted && !e.value.serverMuted) return true;
  }
  return false;
}

List<String> expectedRemoteAudioKeys({
  required int? channelId,
  required int ownUserId,
  required Map<int, Map<int, VoiceUserState>> voiceMap,
  required Map<String, String> consumerKeys,
}) {
  if (channelId == null) return const [];
  final occupants = voiceMap[channelId];
  if (occupants == null) return const [];
  final keys = <String>[];
  for (final e in occupants.entries) {
    if (e.key == ownUserId) continue;
    if (e.value.micMuted || e.value.serverMuted) continue;
    final mapKey = '${e.key}:audio';
    keys.add(consumerKeys[mapKey] ?? mapKey);
  }
  return keys;
}

bool shouldReceiveVoiceAudio({
  required String voiceState,
  required bool soundMuted,
  required bool hasUnmutedRemote,
}) => voiceState == 'connected' && !soundMuted && hasUnmutedRemote;

const micUnavailableKey = 'micUnavailable';

bool isVoicePlaybackHealthy({
  required VoicePlaybackHealth health,
  required Iterable<String> expectedAudioKeys,
}) {
  if (health.recvState == 'failed' || health.recvState == 'disconnected') {
    return false;
  }
  final live = health.liveAudioKeys.toSet();
  final graphs = health.graphKeys.toSet();
  final playing = health.playingKeys.toSet();
  var needsGraphCtx = false;
  for (final key in expectedAudioKeys) {
    if (!live.contains(key)) return false;
    final hasGraph = graphs.contains(key);
    final hasPlaying = playing.contains(key);
    if (!hasGraph && !hasPlaying) return false;
    if (hasGraph && !hasPlaying) needsGraphCtx = true;
  }
  if (needsGraphCtx || expectedAudioKeys.isEmpty) {
    if (!health.ctxRunning || !health.keepAlive) return false;
  }
  return true;
}

/// Tracks are live but output is locked (Safari autoplay / suspended context).
bool isVoicePlaybackGestureLocked({
  required VoicePlaybackHealth health,
  required Iterable<String> expectedAudioKeys,
}) {
  if (expectedAudioKeys.isEmpty) return false;
  if (health.recvState == 'failed' || health.recvState == 'disconnected') {
    return false;
  }
  final live = health.liveAudioKeys.toSet();
  for (final key in expectedAudioKeys) {
    if (!live.contains(key)) return false;
  }
  return !isVoicePlaybackHealthy(
    health: health,
    expectedAudioKeys: expectedAudioKeys,
  );
}

int rejoinsInVoiceWindow(List<DateTime> times, DateTime now) {
  times.removeWhere((t) => now.difference(t) > kVoiceAutoRejoinWindow);
  return times.length;
}

bool shouldSilentRejoinVoice({
  required bool shouldReceive,
  required bool playbackHealthy,
  required bool pastGrace,
  required bool heldDead,
  required int rejoinsInWindow,
}) =>
    shouldReceive &&
    !playbackHealthy &&
    pastGrace &&
    heldDead &&
    rejoinsInWindow < kMaxVoiceAutoRejoins;

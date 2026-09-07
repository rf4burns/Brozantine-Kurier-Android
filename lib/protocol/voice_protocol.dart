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

List<String> jsonStringList(dynamic raw) {
  if (raw is! List) return <String>[];
  return [for (final e in raw) '$e'];
}

Map<String, dynamic> jsonObject(dynamic raw) {
  if (raw is Map<String, dynamic>) return Map<String, dynamic>.from(raw);
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> jsonObjectList(dynamic raw) {
  if (raw is! List) return <Map<String, dynamic>>[];
  return [for (final e in raw) jsonObject(e)];
}

/// mediasoup's `RtpCapabilities.fromMap` types `fecMechanisms` as
/// `List<String>`. JSON (and `List.from` / `?? <dynamic>[]`) is `List<dynamic>`.
Map<String, dynamic> nativeRtpCapabilitiesMap(Map<String, dynamic> caps) {
  final out = Map<String, dynamic>.from(caps);
  // `fromMap` casts headerExtensions to List<dynamic>; List is invariant.
  out['headerExtensions'] = <dynamic>[
    for (final ext in jsonObjectList(out['headerExtensions'])) ext,
  ];
  out['fecMechanisms'] = jsonStringList(out['fecMechanisms']);
  out['codecs'] = <dynamic>[
    for (final codec in jsonObjectList(out['codecs'])) nativeRtpCodecMap(codec),
  ];
  return out;
}

Map<String, dynamic> nativeRtpParametersMap(Map<String, dynamic> rtp) {
  final out = Map<String, dynamic>.from(rtp);
  out['codecs'] = [
    for (final codec in jsonObjectList(out['codecs'])) nativeRtpCodecMap(codec),
  ];
  out['headerExtensions'] = [
    for (final ext in jsonObjectList(out['headerExtensions']))
      nativeRtpHeaderExtensionParametersMap(ext),
  ];
  out['encodings'] = jsonObjectList(out['encodings']);
  if (out['rtcp'] != null) out['rtcp'] = jsonObject(out['rtcp']);
  return out;
}

Map<String, dynamic> nativeRtpCodecMap(Map<String, dynamic> codec) {
  final out = Map<String, dynamic>.from(codec);
  out['parameters'] = jsonObject(out['parameters']);
  out['rtcpFeedback'] = jsonObjectList(out['rtcpFeedback']);
  return out;
}

Map<String, dynamic> nativeRtpHeaderExtensionParametersMap(
  Map<String, dynamic> ext,
) {
  final out = Map<String, dynamic>.from(ext);
  out['parameters'] = jsonObject(out['parameters']);
  return out;
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
const kVoicePacketStall = Duration(seconds: 4);
const kVoicePacketStallHold = Duration(seconds: 3);
const kVoicePacketRepairCooldown = Duration(seconds: 15);

enum VoicePacketRepairAction { none, light, replace }

class VoicePlaybackHealth {
  const VoicePlaybackHealth({
    this.ctxRunning = false,
    this.keepAlive = false,
    this.recvState = '',
    this.sendState = '',
    this.liveAudioKeys = const [],
    this.graphKeys = const [],
    this.playingKeys = const [],
    this.mutedAudioKeys = const [],
    this.audioPackets = const {},
  });

  final bool ctxRunning;
  final bool keepAlive;
  final String recvState;
  final String sendState;
  final List<String> liveAudioKeys;
  final List<String> graphKeys;
  final List<String> playingKeys;
  final List<String> mutedAudioKeys;
  final Map<String, int> audioPackets;

  static const dead = VoicePlaybackHealth();

  factory VoicePlaybackHealth.fromJson(Map json) {
    List<String> keys(dynamic raw) {
      if (raw is! List) return const [];
      return raw.map((e) => '$e').where((s) => s.isNotEmpty).toList();
    }

    Map<String, int> packets(dynamic raw) {
      if (raw is! Map) return const {};
      final out = <String, int>{};
      raw.forEach((key, value) {
        final name = '$key';
        if (name.isEmpty) return;
        if (value is num) {
          out[name] = value.round();
        } else {
          out[name] = int.tryParse('$value') ?? 0;
        }
      });
      return out;
    }

    return VoicePlaybackHealth(
      ctxRunning: json['ctxRunning'] == true,
      keepAlive: json['keepAlive'] == true,
      recvState: '${json['recvState'] ?? ''}',
      sendState: '${json['sendState'] ?? ''}',
      liveAudioKeys: keys(json['liveAudioKeys']),
      graphKeys: keys(json['graphKeys']),
      playingKeys: keys(json['playingKeys']),
      mutedAudioKeys: keys(json['mutedAudioKeys']),
      audioPackets: packets(json['audioPackets']),
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
  final muted = health.mutedAudioKeys.toSet();
  var needsGraphCtx = false;
  for (final key in expectedAudioKeys) {
    if (!live.contains(key)) return false;
    final hasGraph = graphs.contains(key);
    final hasPlaying = playing.contains(key);
    final trackMuted = muted.contains(key);
    if (trackMuted) {
      if (!hasPlaying) return false;
      continue;
    }
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
  final playing = health.playingKeys.toSet();
  for (final key in expectedAudioKeys) {
    if (!live.contains(key)) return false;
    if (playing.contains(key)) return false;
  }
  return !health.ctxRunning || !health.keepAlive;
}

bool shouldSkipConsumerReplace({
  required bool replace,
  required bool existingUsable,
}) => !replace && existingUsable;

bool canConsumeRemoteProducers({required bool recvTransportCreated}) =>
    recvTransportCreated;

bool isVoiceRecvTransportDead(String recvState) =>
    recvState == 'failed' || recvState == 'disconnected';

bool healthHasKey(Iterable<String> keys, String bridgeKey, String mapKey) =>
    keys.contains(bridgeKey) || keys.contains(mapKey);

bool remoteAudioIsAudible({
  required bool htmlPlaying,
  required bool hasGraph,
  required bool trackMuted,
}) => htmlPlaying || (hasGraph && !trackMuted);

bool shouldConsumeOnRemoteUnmute({
  required bool wasMicOpen,
  required bool isMicOpen,
  required bool isOwnUser,
  required bool inCurrentChannel,
  required bool hasLiveConsumer,
}) {
  if (isOwnUser || !inCurrentChannel || wasMicOpen || !isMicOpen) {
    return false;
  }
  return !hasLiveConsumer;
}

VoicePacketRepairAction voicePacketRepairAction({
  required bool soundMuted,
  required bool remoteMicOpen,
  required bool gestureLocked,
  required bool consumeInFlight,
  required bool hasConsumer,
  required bool hasPacketTelemetry,
  required bool packetsIncreased,
  required DateTime now,
  DateTime? stallSince,
  DateTime? lastReplaceAt,
  DateTime? consumerCreatedAt,
  DateTime? missingSince,
  bool didLightRepair = false,
}) {
  if (soundMuted || !remoteMicOpen || gestureLocked || consumeInFlight) {
    return VoicePacketRepairAction.none;
  }
  if (lastReplaceAt != null &&
      now.difference(lastReplaceAt) < kVoicePacketRepairCooldown) {
    return VoicePacketRepairAction.none;
  }
  final startedAt = hasConsumer ? consumerCreatedAt : missingSince;
  if (startedAt != null && now.difference(startedAt) < kVoicePlaybackGrace) {
    return VoicePacketRepairAction.none;
  }
  if (!hasConsumer) return VoicePacketRepairAction.replace;
  if (!hasPacketTelemetry || packetsIncreased) {
    return VoicePacketRepairAction.none;
  }
  if (stallSince == null) return VoicePacketRepairAction.none;
  if (now.difference(stallSince) < kVoicePacketStall) {
    return VoicePacketRepairAction.none;
  }
  if (!didLightRepair) return VoicePacketRepairAction.light;
  if (now.difference(stallSince) < kVoicePacketStall + kVoicePacketStallHold) {
    return VoicePacketRepairAction.none;
  }
  return VoicePacketRepairAction.replace;
}

VoicePacketRepairAction voiceInaudibleRepairAction({
  required bool soundMuted,
  required bool remoteMicOpen,
  required bool gestureLocked,
  required bool consumeInFlight,
  required bool hasConsumer,
  required bool trackMuted,
  required bool htmlPlaying,
  required bool hasGraph,
  required DateTime now,
  DateTime? lastReplaceAt,
  DateTime? consumerCreatedAt,
  bool didLightRepair = false,
}) {
  if (soundMuted ||
      !remoteMicOpen ||
      gestureLocked ||
      consumeInFlight ||
      !hasConsumer) {
    return VoicePacketRepairAction.none;
  }
  if (lastReplaceAt != null &&
      now.difference(lastReplaceAt) < kVoicePacketRepairCooldown) {
    return VoicePacketRepairAction.none;
  }
  if (consumerCreatedAt != null &&
      now.difference(consumerCreatedAt) < kVoicePlaybackGrace) {
    return VoicePacketRepairAction.none;
  }
  if (remoteAudioIsAudible(
    htmlPlaying: htmlPlaying,
    hasGraph: hasGraph,
    trackMuted: trackMuted,
  )) {
    return VoicePacketRepairAction.none;
  }
  if (!didLightRepair) return VoicePacketRepairAction.light;
  return VoicePacketRepairAction.replace;
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

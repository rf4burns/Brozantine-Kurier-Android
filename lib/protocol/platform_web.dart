import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'device_token.dart';
import 'voice_protocol.dart';
import 'voice_stats.dart';

@JS('KurierMediasoup')
external JSObject? get _ms;

@JS('KurierMediasoup.ready')
external JSPromise<JSAny?> _ready(JSNumber timeoutMs);

@JS('KurierMediasoup.loadDevice')
external JSPromise<JSAny?> _loadDevice(JSString caps);

@JS('KurierMediasoup.createSendTransport')
external JSPromise<JSAny?> _createSend(JSString params, JSString ice);

@JS('KurierMediasoup.createRecvTransport')
external JSPromise<JSAny?> _createRecv(JSString params, JSString ice);

@JS('KurierMediasoup.finishConnectSend')
external void _finishConnectSend(JSBoolean ok);

@JS('KurierMediasoup.finishConnectRecv')
external void _finishConnectRecv(JSBoolean ok);

@JS('KurierMediasoup.finishProduce')
external void _finishProduce(JSString? id);

@JS('KurierMediasoup.getUserMedia')
external JSPromise<JSAny?> _getUserMedia(
  JSBoolean audio,
  JSBoolean video,
  JSString? deviceId,
  JSString? constraints,
);

@JS('KurierMediasoup.startMicTest')
external JSPromise<JSAny?> _startMicTest(
  JSString? deviceId,
  JSString? constraints,
);

@JS('KurierMediasoup.stopMicTest')
external void _stopMicTest();

@JS('KurierMediasoup.micTestLevel')
external JSNumber _micTestLevel();

@JS('KurierMediasoup.startVideoPreview')
external JSPromise<JSAny?> _startVideoPreview(JSString? deviceId);

@JS('KurierMediasoup.stopVideoPreview')
external void _stopVideoPreview();

@JS('KurierMediasoup.setOutputDevice')
external JSPromise<JSAny?> _setOutputDevice(JSString? deviceId);

@JS('KurierMediasoup.replaceMicDevice')
external JSPromise<JSAny?> _replaceMicDevice(
  JSString? deviceId,
  JSString? constraints,
);

@JS('KurierMediasoup.setCameraDevice')
external void _setCameraDevice(JSString? deviceId);

@JS('KurierMediasoup.getDisplayMedia')
external JSPromise<JSAny?> _getDisplay(JSBoolean withAudio);

@JS('KurierMediasoup.produceKind')
external JSPromise<JSAny?> _produceKind(JSString kind, JSBoolean simulcast);

@JS('KurierMediasoup.consume')
external JSPromise<JSAny?> _consume(JSString json);

@JS('KurierMediasoup.closeProducer')
external void _closeProducer(JSString kind);

@JS('KurierMediasoup.pauseMic')
external void _pauseMic(JSBoolean paused);

@JS('KurierMediasoup.setWakeLock')
external void _setWakeLock(JSBoolean wanted);

@JS('KurierMediasoup.consumerTrackLive')
external JSBoolean _consumerTrackLive(JSString key);

@JS('KurierMediasoup.audioProducerLive')
external JSBoolean _audioProducerLive();

@JS('KurierMediasoup.closeConsumer')
external void _closeConsumer(JSString key);

@JS('KurierMediasoup.closeAll')
external void _closeAll();

@JS('KurierMediasoup.restartIce')
external JSPromise<JSAny?> _restartIce(JSString direction, JSString params);

@JS('KurierMediasoup.playbackHealthy')
external JSPromise<JSAny?> _playbackHealthy();

@JS('KurierMediasoup.setConsumerVolume')
external void _setVolume(JSString key, JSNumber volume);

@JS('KurierMediasoup.bindMediaElement')
external void _bindMedia(JSString key, JSAny el);

@JS('KurierMediasoup.getMediaStats')
external JSPromise<JSAny?> _getMediaStats(JSString key);

@JS('KurierMediasoup.getTransportStats')
external JSPromise<JSAny?> _getTransportStats();

@JS('KurierMediasoup.enumerate')
external JSPromise<JSAny?> _enumerate();

@JS('KurierMediasoup.canShareScreen')
external JSBoolean _canShare();

@JS('KurierMediasoup.isIos')
external JSBoolean _isIos();

@JS('KurierMediasoup.canSetOutputDevice')
external JSBoolean _canSetOutputDevice();

@JS('KurierMediasoup.unlockAudio')
external JSPromise<JSAny?> _unlock();

@JS('KurierMediasoup.resumePlayback')
external void _resumePlayback();

@JS('KurierSounds')
external JSObject? get _sounds;

@JS('KurierSounds.playSound')
external void _playSound(JSString type);

@JS('KurierSounds.stopKeepAlive')
external void _stopSoundKeepAlive();

@JS('KurierMediasoup.notify')
external void _notify(JSString title, JSString body);

@JS('KurierMediasoup.requestNotifications')
external JSPromise<JSAny?> _requestNotes();

@JS('KurierMediasoup.notificationPermission')
external JSString _notePerm();

@JS('KurierMediasoup.copyText')
external JSPromise<JSAny?> _copy(JSString text);

@JS('KurierMediasoup.on')
external void _on(JSString name, JSFunction fn);

@JS('KurierMediasoup.evtPayload')
external JSString get _evtPayload;

class MediaDeviceInfo {
  MediaDeviceInfo({
    required this.deviceId,
    required this.kind,
    required this.label,
  });
  final String deviceId;
  final String kind;
  final String label;
}

class MediaStats {
  const MediaStats({this.fps = 0, this.bytesPerSec = 0});
  final double fps;
  final double bytesPerSec;
}

class PlatformBridge {
  static final List<JSFunction> _retained = [];

  static bool get available => _ms != null;

  static bool get isIos => available && _isIos().toDart;
  static bool get canSetOutputDevice =>
      available && _canSetOutputDevice().toDart;
  static bool get canShareScreen => available && _canShare().toDart;

  static Future<void> ensureReady() async {
    if (!available) {
      throw StateError(
        'Voice engine is not loaded yet. Refresh and try again.',
      );
    }
    await _awaitPacked(_ready(12000.toJS));
  }

  static Future<Map<String, dynamic>> loadDevice(dynamic caps) async {
    final encoded = caps is String ? caps : jsonEncode(caps);
    final json = await _awaitPacked(_loadDevice(encoded.toJS));
    return jsonDecode(json) as Map<String, dynamic>;
  }

  static Future<String> createSendTransport(
    Map<String, dynamic> params,
    List<Map<String, String>> ice,
  ) async {
    return _awaitPacked(
      _createSend(jsonEncode(params).toJS, jsonEncode(ice).toJS),
    );
  }

  static Future<String> createRecvTransport(
    Map<String, dynamic> params,
    List<Map<String, String>> ice,
  ) async {
    return _awaitPacked(
      _createRecv(jsonEncode(params).toJS, jsonEncode(ice).toJS),
    );
  }

  static void finishConnectSend(bool ok) => _finishConnectSend(ok.toJS);
  static void finishConnectRecv(bool ok) => _finishConnectRecv(ok.toJS);
  static void finishProduce(String? id) => _finishProduce(id?.toJS);

  static Future<void> getUserMedia({
    bool audio = true,
    bool video = false,
    String? deviceId,
    Map<String, dynamic>? audioConstraints,
  }) async {
    await _awaitPacked(
      _getUserMedia(
        audio.toJS,
        video.toJS,
        deviceId?.toJS,
        audioConstraints == null ? null : jsonEncode(audioConstraints).toJS,
      ),
    );
  }

  static Future<void> startMicTest({
    String? deviceId,
    Map<String, dynamic>? audioConstraints,
  }) async {
    if (!available) return;
    await _awaitPacked(
      _startMicTest(
        deviceId?.toJS,
        audioConstraints == null ? null : jsonEncode(audioConstraints).toJS,
      ),
    );
  }

  static void stopMicTest() {
    if (available) _stopMicTest();
  }

  static double micTestLevel() {
    if (!available) return 0;
    return _micTestLevel().toDartDouble;
  }

  static Future<void> startVideoPreview({String? deviceId}) async {
    if (!available) return;
    await _awaitPacked(_startVideoPreview(deviceId?.toJS));
  }

  static void stopVideoPreview() {
    if (available) _stopVideoPreview();
  }

  static Future<void> setOutputDevice(String? deviceId) async {
    if (!available) return;
    await _awaitPacked(_setOutputDevice(deviceId?.toJS));
  }

  static Future<void> replaceMicDevice({
    String? deviceId,
    Map<String, dynamic>? audioConstraints,
  }) async {
    if (!available) return;
    await _awaitPacked(
      _replaceMicDevice(
        deviceId?.toJS,
        audioConstraints == null ? null : jsonEncode(audioConstraints).toJS,
      ),
    );
  }

  static void setCameraDevice(String? deviceId) {
    if (available) _setCameraDevice(deviceId?.toJS);
  }

  static Future<void> getDisplayMedia({bool withAudio = false}) async {
    await _awaitPacked(_getDisplay(withAudio.toJS));
  }

  static Future<String> produce(String kind, {bool simulcast = false}) async {
    return _awaitPacked(_produceKind(kind.toJS, simulcast.toJS));
  }

  static Future<String> consume(Map<String, dynamic> info) async {
    return _awaitPacked(_consume(jsonEncode(info).toJS));
  }

  static void closeProducer(String kind) => _closeProducer(kind.toJS);
  static void pauseMic(bool paused) => _pauseMic(paused.toJS);
  static void setKeepScreenAwake(bool on) {
    if (available) _setWakeLock(on.toJS);
  }

  static bool consumerTrackLive(String key) =>
      available && _consumerTrackLive(key.toJS).toDart;
  static bool get audioProducerLive => available && _audioProducerLive().toDart;
  static void closeConsumer(String key) => _closeConsumer(key.toJS);
  static void closeAll() => _closeAll();

  static Future<void> restartIce(
    String direction,
    Map<String, dynamic> iceParameters,
  ) async {
    if (!available) return;
    await _awaitPacked(
      _restartIce(direction.toJS, jsonEncode(iceParameters).toJS),
    );
  }

  static Future<VoicePlaybackHealth> playbackHealth() async {
    if (!available) return VoicePlaybackHealth.dead;
    try {
      final raw = await _awaitPacked(_playbackHealthy());
      if (raw.isEmpty) return VoicePlaybackHealth.dead;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return VoicePlaybackHealth.dead;
      return VoicePlaybackHealth.fromJson(decoded);
    } catch (_) {
      return VoicePlaybackHealth.dead;
    }
  }

  static void setVolume(String key, double volume) =>
      _setVolume(key.toJS, volume.toJS);

  static void bindMediaElement(String key, JSAny el) {
    if (!available) return;
    _bindMedia(key.toJS, el);
  }

  static Future<MediaStats> getMediaStats(String key) async {
    if (!available) return const MediaStats();
    try {
      final raw = await _awaitPacked(_getMediaStats(key.toJS));
      if (raw.isEmpty) return const MediaStats();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const MediaStats();
      return MediaStats(
        fps: (decoded['fps'] as num?)?.toDouble() ?? 0,
        bytesPerSec: (decoded['bytesPerSec'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return const MediaStats();
    }
  }

  static Future<TransportStatsData> getTransportStats() async {
    if (!available) return TransportStatsData.empty;
    try {
      final raw = await _awaitPacked(_getTransportStats());
      if (raw.isEmpty) return TransportStatsData.empty;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return TransportStatsData.empty;
      return TransportStatsData.fromJson(decoded);
    } catch (_) {
      return TransportStatsData.empty;
    }
  }

  static Future<List<MediaDeviceInfo>> enumerate() async {
    final raw = await _awaitPacked(_enumerate());
    final list = jsonDecode(raw) as List;
    return list
        .whereType<Map>()
        .map(
          (e) => MediaDeviceInfo(
            deviceId: '${e['deviceId']}',
            kind: '${e['kind']}',
            label: '${e['label']}',
          ),
        )
        .toList();
  }

  static Future<void> unlockAudio() async {
    if (available) await _awaitPacked(_unlock());
  }

  static void resumePlayback() {
    if (available) _resumePlayback();
  }

  static void playSound(String type) {
    if (_sounds != null) _playSound(type.toJS);
  }

  static void playPing() {
    playSound('message_received');
  }

  static void stopSoundKeepAlive() {
    if (_sounds != null) _stopSoundKeepAlive();
  }

  static void notify(String title, String body) {
    if (available) _notify(title.toJS, body.toJS);
  }

  static Future<String> requestNotifications() async {
    if (!available) return 'unsupported';
    return _awaitPacked(_requestNotes());
  }

  static String notificationPermission() {
    if (!available) return 'unsupported';
    return _asDartString(_notePerm());
  }

  static Future<void> copyText(String text) async {
    if (available) await _awaitPacked(_copy(text.toJS));
  }

  static void downloadBytes(
    List<int> bytes,
    String filename, {
    String mime = 'application/zip',
  }) {
    final data = Uint8List.fromList(bytes);
    final blob = web.Blob([data.toJS].toJS, web.BlobPropertyBag(type: mime));
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = filename
      ..style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }

  static void applyBrowserBranding({required String title, String? iconUrl}) {
    web.document.title = title;
    if (iconUrl != null && iconUrl.isNotEmpty) {
      _setOrCreateLink('icon', iconUrl);
      _setOrCreateLink('apple-touch-icon', iconUrl);
    }
  }

  static String? randomUuid() {
    try {
      final uuid = web.window.crypto.randomUUID();
      return uuid.isEmpty ? null : uuid;
    } catch (_) {
      return null;
    }
  }

  static String? vanillaDeviceTokenLocalStorage() {
    try {
      return web.window.localStorage.getItem(kDeviceTokenStorageKey);
    } catch (_) {
      return null;
    }
  }

  static String? vanillaDeviceTokenCookie() {
    try {
      return namedCookieValue(web.document.cookie, kDeviceTokenStorageKey);
    } catch (_) {
      return null;
    }
  }

  static void persistVanillaDeviceToken(String token) {
    try {
      web.window.localStorage.setItem(kDeviceTokenStorageKey, token);
    } catch (_) {}
    try {
      web.document.cookie = deviceTokenCookieAssignment(
        token,
        secure: web.window.isSecureContext,
      );
    } catch (_) {}
  }

  static void _setOrCreateLink(String rel, String href) {
    final existing = web.document.head?.querySelector('link[rel="$rel"]');
    if (existing != null) {
      final link = existing as web.HTMLLinkElement;
      link.removeAttribute('type');
      link.href = href;
      return;
    }
    final link = web.document.createElement('link') as web.HTMLLinkElement;
    link.rel = rel;
    link.href = href;
    web.document.head?.append(link);
  }

  static void listen(void Function(String name, String payload) handler) {
    if (!available) return;
    void bind(String name) {
      // Zero-arg callback: dart2js Function.toJS + dartify/jsify of a JS
      // string argument is what produced `method not found: 'jsify'`.
      final fn = (() {
        handler(name, _asDartString(_evtPayload));
      }).toJS;
      _retained.add(fn);
      _on(name.toJS, fn);
    }

    bind('connectSend');
    bind('connectRecv');
    bind('produce');
    bind('sendState');
    bind('recvState');
    bind('visibility');
    bind('speaking');
    bind('micEnded');
    bind('screenEnded');
    bind('devicechange');
  }

  static Future<String> _awaitPacked(JSPromise<JSAny?> promise) async {
    final value = await promise.toDart;
    return unpackVoiceEngineResult(_asDartString(value));
  }

  static String _asDartString(JSAny? value) {
    if (value == null) return '';
    final Object raw = value;
    if (raw is String) return raw;
    if (value.typeofEquals('string')) {
      return (value as JSString).toDart;
    }
    if (value.typeofEquals('boolean')) {
      return (value as JSBoolean).toDart ? 'true' : 'false';
    }
    return '';
  }
}

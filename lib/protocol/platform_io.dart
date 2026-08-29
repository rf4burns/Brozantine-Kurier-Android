import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:mediasfu_mediasoup_client/mediasfu_mediasoup_client.dart'
    hide MediaDeviceInfo;
// ignore: implementation_imports
import 'package:mediasfu_mediasoup_client/src/handlers/handler_interface.dart'
    as msice;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../native/android_runtime.dart';
import 'native_channels.dart';
import 'voice_protocol.dart';
import 'voice_stats.dart';

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

final Map<String, webrtc.MediaStream> _videoStreams = {};

webrtc.MediaStream? nativeVideoStream(String key) => _videoStreams[key];

class PlatformBridge {
  static final AudioPlayer _sfx = AudioPlayer();
  static Device? _device;
  static Transport? _send;
  static Transport? _recv;
  static final Map<String, Producer> _producers = {};
  static final Map<String, Consumer> _consumers = {};
  static final Map<String, webrtc.RTCVideoRenderer> renderers = {};
  static webrtc.MediaStream? _mic;
  static webrtc.MediaStream? _cam;
  static webrtc.MediaStream? _screen;
  static webrtc.MediaStream? _preview;
  static String? _cameraDeviceId;
  static void Function(String name, String payload)? _handler;
  static Function? _connectSendCb;
  static Function? _connectSendErr;
  static Function? _connectRecvCb;
  static Function? _connectRecvErr;
  static Function? _produceCb;
  static Function? _produceErr;
  static Completer<Producer>? _producerReady;
  static Completer<Consumer>? _consumerReady;
  static Timer? _meter;
  static double _micLevel = 0;
  static bool _ready = false;
  static String _sendState = '';
  static String _recvState = '';

  static bool get available => Platform.isAndroid || Platform.isIOS;
  static bool get isIos => Platform.isIOS;
  static bool get isAndroid => Platform.isAndroid;
  static bool get canSetOutputDevice => Platform.isAndroid;
  static bool get canShareScreen => Platform.isAndroid;

  static IceParameters _iceParams(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    m['iceLite'] = m['iceLite'] == true;
    return IceParameters.fromMap(m);
  }

  static List<IceCandidate> _iceCandidates(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final c in raw)
        if (c is Map)
          IceCandidate.fromMap({
            ...Map<String, dynamic>.from(c),
            'ip': c['ip'] ?? c['address'],
            'port': (c['port'] as num?)?.toInt() ?? 0,
            'priority': (c['priority'] as num?)?.toInt() ?? 0,
            'type': c['type'] ?? 'host',
          }),
    ];
  }

  static DtlsParameters _dtls(dynamic raw) {
    return DtlsParameters.fromMap(Map<String, dynamic>.from(raw as Map));
  }

  static List<msice.RTCIceServer> _ice(List<Map<String, String>> ice) {
    return [
      for (final e in ice)
        msice.RTCIceServer(
          urls: [e['urls'] ?? ''],
          username: e['username'] ?? '',
          credential: e['credential'],
          credentialType: msice.RTCIceCredentialType.password,
        ),
    ];
  }

  static Future<void> ensureReady() async {
    if (!available) return;
    await Permission.microphone.request();
    _ready = true;
  }

  static Future<Map<String, dynamic>> loadDevice(dynamic caps) async {
    if (!available) return {};
    final raw = caps is Map
        ? Map<String, dynamic>.from(caps)
        : jsonDecode(caps is String ? caps : jsonEncode(caps))
              as Map<String, dynamic>;
    final map = nativeRtpCapabilitiesMap(raw);
    _device = Device();
    await _device!.load(routerRtpCapabilities: RtpCapabilities.fromMap(map));
    final rtp = _device!.rtpCapabilities;
    return {
      'codecs': rtp.codecs.map((c) => c.toMap()).toList(),
      'headerExtensions': [
        for (final e in rtp.headerExtensions)
          {
            if (e.kind != null) 'kind': RTCRtpMediaTypeExtension.value(e.kind!),
            'uri': e.uri,
            'preferredId': e.preferredId,
            'preferredEncrypt': e.preferredEncrypt ?? false,
            if (e.direction != null)
              'direction': RtpHeaderDirectionExtension.values[e.direction],
          },
      ],
    };
  }

  static Future<String> createSendTransport(
    Map<String, dynamic> params,
    List<Map<String, String>> ice,
  ) async {
    final device = _device;
    if (device == null) throw StateError('Voice device is not loaded');
    _send = device.createSendTransport(
      id: '${params['id']}',
      iceParameters: _iceParams(params['iceParameters']),
      iceCandidates: _iceCandidates(params['iceCandidates']),
      dtlsParameters: _dtls(params['dtlsParameters']),
      iceServers: _ice(ice),
      producerCallback: (Producer p) {
        _producerReady?.complete(p);
      },
    );
    _send!.on('connect', (data) {
      _connectSendCb = data['callback'] as Function?;
      _connectSendErr = data['errback'] as Function?;
      _emit(
        'connectSend',
        jsonEncode((data['dtlsParameters'] as DtlsParameters).toMap()),
      );
    });
    _send!.on('produce', (data) {
      _produceCb = data['callback'] as Function?;
      _produceErr = data['errback'] as Function?;
      final rtp = data['rtpParameters'];
      final app = data['appData'] is Map
          ? Map<String, dynamic>.from(data['appData'] as Map)
          : <String, dynamic>{};
      _emit(
        'produce',
        jsonEncode({
          'kind': data['kind'] ?? app['kind'],
          'rtpParameters': rtp is RtpParameters ? rtp.toMap() : rtp,
          'appData': app,
          'qualityLayers': app['qualityLayers'],
        }),
      );
    });
    _send!.on('connectionstatechange', (data) {
      _sendState = '${data['connectionState'] ?? ''}';
      _emit('sendState', _sendState);
    });
    return _send!.id;
  }

  static Future<String> createRecvTransport(
    Map<String, dynamic> params,
    List<Map<String, String>> ice,
  ) async {
    final device = _device;
    if (device == null) throw StateError('Voice device is not loaded');
    _recv = device.createRecvTransport(
      id: '${params['id']}',
      iceParameters: _iceParams(params['iceParameters']),
      iceCandidates: _iceCandidates(params['iceCandidates']),
      dtlsParameters: _dtls(params['dtlsParameters']),
      iceServers: _ice(ice),
      consumerCallback: (Consumer c, dynamic accept) {
        final pending = _consumerReady;
        if (pending != null && !pending.isCompleted) pending.complete(c);
      },
    );
    _recv!.on('connect', (data) {
      _connectRecvCb = data['callback'] as Function?;
      _connectRecvErr = data['errback'] as Function?;
      _emit(
        'connectRecv',
        jsonEncode((data['dtlsParameters'] as DtlsParameters).toMap()),
      );
    });
    _recv!.on('connectionstatechange', (data) {
      _recvState = '${data['connectionState'] ?? ''}';
      _emit('recvState', _recvState);
    });
    return _recv!.id;
  }

  static void finishConnectSend(bool ok) {
    if (ok) {
      _connectSendCb?.call();
    } else {
      _connectSendErr?.call('connect send failed');
    }
    _connectSendCb = null;
    _connectSendErr = null;
  }

  static void finishConnectRecv(bool ok) {
    if (ok) {
      _connectRecvCb?.call();
    } else {
      _connectRecvErr?.call('connect recv failed');
    }
    _connectRecvCb = null;
    _connectRecvErr = null;
  }

  static void finishProduce(String? id) {
    if (id == null || id.isEmpty) {
      _produceErr?.call('produce failed');
    } else {
      _produceCb?.call(id);
    }
    _produceCb = null;
    _produceErr = null;
  }

  static Map<String, dynamic> _audioConstraints(
    String? deviceId,
    Map<String, dynamic>? extra,
  ) {
    final out = <String, dynamic>{
      'echoCancellation': extra?['echoCancellation'] ?? true,
      'noiseSuppression': extra?['noiseSuppression'] ?? false,
      'autoGainControl': extra?['autoGainControl'] ?? false,
    };
    if (deviceId != null && deviceId.isNotEmpty) {
      out['deviceId'] = deviceId;
    }
    return out;
  }

  static Future<void> getUserMedia({
    bool audio = true,
    bool video = false,
    String? deviceId,
    Map<String, dynamic>? audioConstraints,
  }) async {
    if (!available) return;
    if (audio) {
      _mic?.getTracks().forEach((t) => t.stop());
      _mic = await webrtc.navigator.mediaDevices.getUserMedia({
        'audio': _audioConstraints(deviceId, audioConstraints),
        'video': false,
      });
    }
    if (video) {
      await startVideoPreview(deviceId: deviceId ?? _cameraDeviceId);
    }
  }

  static Future<void> startMicTest({
    String? deviceId,
    Map<String, dynamic>? audioConstraints,
  }) async {
    if (!available) return;
    await getUserMedia(deviceId: deviceId, audioConstraints: audioConstraints);
    _meter?.cancel();
    _meter = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _micLevel = 0.05 + Random().nextDouble() * 0.2;
    });
  }

  static void stopMicTest() {
    _meter?.cancel();
    _meter = null;
    _micLevel = 0;
  }

  static double micTestLevel() => _micLevel;

  static Future<void> startVideoPreview({String? deviceId}) async {
    if (!available) return;
    stopVideoPreview();
    final video = <String, dynamic>{
      'width': {'ideal': 1280},
      'height': {'ideal': 720},
    };
    final id = deviceId ?? _cameraDeviceId;
    if (id != null && id.isNotEmpty) video['deviceId'] = {'exact': id};
    _preview = await webrtc.navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': video,
    });
    _videoStreams['preview:video'] = _preview!;
    await _bindRenderer('preview:video', _preview!);
  }

  static void stopVideoPreview() {
    _preview?.getTracks().forEach((t) => t.stop());
    _preview = null;
    _videoStreams.remove('preview:video');
  }

  static Future<void> setOutputDevice(String? deviceId) async {
    if (!available) return;
    final id = deviceId?.trim() ?? '';
    try {
      await kurierAudio.invokeMethod('setOutput', {'deviceId': id});
    } catch (_) {
      if (id.isEmpty || id.toLowerCase().contains('speaker')) {
        await webrtc.Helper.setSpeakerphoneOn(true);
      } else {
        await webrtc.Helper.setSpeakerphoneOnButPreferBluetooth();
      }
    }
    if (id.isNotEmpty) {
      try {
        await webrtc.Helper.selectAudioOutput(id);
      } catch (_) {}
    }
  }

  static Future<void> replaceMicDevice({
    String? deviceId,
    Map<String, dynamic>? audioConstraints,
  }) async {
    if (!available) return;
    await getUserMedia(deviceId: deviceId, audioConstraints: audioConstraints);
    final track = _mic?.getAudioTracks().firstOrNull;
    final existing = _producers['audio'];
    if (track != null && existing != null) {
      await existing.replaceTrack(track);
    }
  }

  static void setCameraDevice(String? deviceId) {
    _cameraDeviceId = deviceId;
  }

  static Future<void> getDisplayMedia({bool withAudio = false}) async {
    if (!available) return;
    await Permission.systemAlertWindow.request();
    _screen?.getTracks().forEach((t) => t.stop());
    _screen = await webrtc.navigator.mediaDevices.getDisplayMedia({
      'video': true,
      'audio': withAudio,
    });
    _videoStreams['local:screen'] = _screen!;
    await _bindRenderer('local:screen', _screen!);
    final video = _screen!.getVideoTracks().firstOrNull;
    video?.onEnded = () => _emit('screenEnded', '');
    final existing = _producers['screen'];
    if (existing != null && video != null) {
      await existing.replaceTrack(video);
    }
    final audio = _screen!.getAudioTracks().firstOrNull;
    final existingAudio = _producers['screen_audio'];
    if (existingAudio != null && audio != null) {
      await existingAudio.replaceTrack(audio);
    }
  }

  static Future<String> produce(String kind, {bool simulcast = false}) async {
    if (!available) return '';
    final send = _send;
    if (send == null) throw StateError('send transport missing');
    webrtc.MediaStream? stream;
    webrtc.MediaStreamTrack? track;
    if (kind == 'audio') {
      stream = _mic;
      track = _mic?.getAudioTracks().firstOrNull;
    } else if (kind == 'video') {
      if (_cam == null) {
        final video = <String, dynamic>{
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        };
        if (_cameraDeviceId != null && _cameraDeviceId!.isNotEmpty) {
          video['deviceId'] = {'exact': _cameraDeviceId};
        }
        _cam = await webrtc.navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': video,
        });
      }
      stream = _cam;
      track = _cam?.getVideoTracks().firstOrNull;
      if (stream != null) {
        _videoStreams['local:video'] = stream;
        await _bindRenderer('local:video', stream);
      }
    } else if (kind == 'screen') {
      stream = _screen;
      track = _screen?.getVideoTracks().firstOrNull;
    } else if (kind == 'screen_audio') {
      stream = _screen;
      track = _screen?.getAudioTracks().firstOrNull;
    }
    if (track == null || stream == null) {
      throw StateError('no local track for $kind');
    }
    _producers[kind]?.close();
    _producers.remove(kind);
    _producerReady = Completer<Producer>();
    send.produce(
      track: track,
      stream: stream,
      source: kind,
      stopTracks: false,
      appData: {'kind': kind},
    );
    final producer = await _producerReady!.future.timeout(
      const Duration(seconds: 20),
    );
    _producers[kind] = producer;
    return producer.id;
  }

  static Future<String> consume(Map<String, dynamic> info) async {
    if (!available) return '';
    final recv = _recv;
    if (recv == null) throw StateError('recv transport missing');
    final kind = '${info['rtpKind'] ?? info['consumerKind'] ?? 'video'}';
    final rtpKind = kind.contains('audio')
        ? RTCRtpMediaType.RTCRtpMediaTypeAudio
        : RTCRtpMediaType.RTCRtpMediaTypeVideo;
    final id = '${info['consumerId'] ?? info['id']}';
    final producerId = '${info['producerId']}';
    final rtp = info['consumerRtpParameters'] ?? info['rtpParameters'];
    _consumerReady = Completer<Consumer>();
    recv.consume(
      id: id,
      producerId: producerId,
      peerId: '${info['remoteId'] ?? ''}',
      kind: rtpKind,
      rtpParameters: RtpParameters.fromMap(
        nativeRtpParametersMap(Map<String, dynamic>.from(rtp as Map)),
      ),
      appData: {'kind': info['consumerKind'], 'remoteId': info['remoteId']},
    );
    final consumer = await _consumerReady!.future.timeout(
      const Duration(seconds: 20),
    );
    final key = '${info['remoteId']}:${info['consumerKind']}';
    _consumers[key] = consumer;
    if (consumer.track.kind == 'video') {
      _videoStreams[key] = consumer.stream;
      await _bindRenderer(key, consumer.stream);
    }
    return key;
  }

  static Future<void> _bindRenderer(
    String key,
    webrtc.MediaStream stream,
  ) async {
    var renderer = renderers[key];
    if (renderer == null) {
      renderer = webrtc.RTCVideoRenderer();
      await renderer.initialize();
      renderers[key] = renderer;
    }
    renderer.srcObject = stream;
  }

  static void closeProducer(String kind) {
    _producers.remove(kind)?.close();
    if (kind == 'video') {
      _cam?.getTracks().forEach((t) => t.stop());
      _cam = null;
      _videoStreams.remove('local:video');
    }
    if (kind == 'screen' || kind == 'screen_audio') {
      if (kind == 'screen') {
        _screen?.getTracks().forEach((t) => t.stop());
        _screen = null;
        _videoStreams.remove('local:screen');
      }
    }
  }

  static void pauseMic(bool paused) {
    final p = _producers['audio'];
    if (p == null) {
      _mic?.getAudioTracks().forEach((t) => t.enabled = !paused);
      return;
    }
    if (paused) {
      p.pause();
    } else {
      p.resume();
    }
  }

  static void setKeepScreenAwake(bool on) {
    if (!available) return;
    if (on) {
      unawaited(WakelockPlus.enable());
    } else {
      unawaited(WakelockPlus.disable());
    }
  }

  static bool consumerTrackLive(String key) {
    final c = _consumers[key];
    return c != null && !c.closed && c.track.enabled;
  }

  static bool get audioProducerLive {
    final p = _producers['audio'];
    return p != null && !p.closed;
  }

  static void closeConsumer(String key) {
    _consumers.remove(key)?.close();
    _videoStreams.remove(key);
    renderers.remove(key)?.srcObject = null;
  }

  static void closeAll() {
    for (final p in _producers.values) {
      p.close();
    }
    _producers.clear();
    for (final c in _consumers.values) {
      c.close();
    }
    _consumers.clear();
    _send?.close();
    _recv?.close();
    _send = null;
    _recv = null;
    _device = null;
    _mic?.getTracks().forEach((t) => t.stop());
    _cam?.getTracks().forEach((t) => t.stop());
    _screen?.getTracks().forEach((t) => t.stop());
    _mic = null;
    _cam = null;
    _screen = null;
    _videoStreams.clear();
    for (final r in renderers.values) {
      r.srcObject = null;
    }
    _connectSendCb = null;
    _connectRecvCb = null;
    _produceCb = null;
    _ready = false;
  }

  static Future<void> restartIce(
    String direction,
    Map<String, dynamic> iceParameters,
  ) async {
    if (!available) return;
    final t = direction == 'send' ? _send : _recv;
    t?.restartIce(_iceParams(iceParameters));
  }

  static Future<VoicePlaybackHealth> playbackHealth() async {
    final live = _consumers.entries
        .where((e) => e.key.contains('audio') && !e.value.closed)
        .map((e) => e.key)
        .toList();
    return VoicePlaybackHealth(
      ctxRunning: _ready,
      keepAlive: _ready,
      recvState: _recvState,
      sendState: _sendState,
      liveAudioKeys: live,
      graphKeys: live,
      playingKeys: live,
    );
  }

  static void setVolume(String key, double volume) {
    final c = _consumers[key];
    if (c == null) return;
    c.track.enabled = volume > 0.001;
  }

  static void bindMediaElement(String key, Object el) {}

  static Future<MediaStats> getMediaStats(String key) async =>
      const MediaStats();

  static Future<TransportStatsData> getTransportStats() async =>
      TransportStatsData.empty;

  static Future<List<MediaDeviceInfo>> enumerate() async {
    if (!available) return const [];
    final out = <MediaDeviceInfo>[];
    final seenOutputs = <String>{};
    try {
      final list = await webrtc.navigator.mediaDevices.enumerateDevices();
      for (final d in list) {
        out.add(
          MediaDeviceInfo(
            deviceId: d.deviceId,
            kind: d.kind ?? '',
            label: d.label,
          ),
        );
      }
    } catch (_) {}
    try {
      final native = await kurierAudio.invokeMethod<List<dynamic>>(
        'listOutputs',
      );
      for (final raw in native ?? const []) {
        if (raw is! Map) continue;
        final id = '${raw['id']}';
        if (!seenOutputs.add(id)) continue;
        out.removeWhere((d) => d.kind == 'audiooutput' && d.deviceId == id);
        out.add(
          MediaDeviceInfo(
            deviceId: id,
            kind: 'audiooutput',
            label: '${raw['label']}',
          ),
        );
      }
    } catch (_) {}
    return out;
  }

  static Future<void> unlockAudio() async {
    if (!available) return;
    try {
      await webrtc.Helper.setSpeakerphoneOn(false);
    } catch (_) {}
  }

  static void resumePlayback() {
    for (final c in _consumers.values) {
      if (c.paused) c.resume();
    }
  }

  static void playSound(String type) {
    if (!available) return;
    unawaited(_playTone(type));
  }

  static void playPing() => playSound('message_received');

  static void stopSoundKeepAlive() {}

  static Future<void> _playTone(String type) async {
    try {
      await _sfx.play(BytesSource(_toneWav(type.hashCode)));
    } catch (_) {}
  }

  static Uint8List _toneWav(int seed) {
    const sampleRate = 22050;
    const samples = 4410;
    final freq = 440.0 + (seed % 8) * 55;
    final data = BytesBuilder();
    data.add('RIFF'.codeUnits);
    data.add(_le32(36 + samples * 2));
    data.add('WAVE'.codeUnits);
    data.add('fmt '.codeUnits);
    data.add(_le32(16));
    data.add(_le16(1));
    data.add(_le16(1));
    data.add(_le32(sampleRate));
    data.add(_le32(sampleRate * 2));
    data.add(_le16(2));
    data.add(_le16(16));
    data.add('data'.codeUnits);
    data.add(_le32(samples * 2));
    for (var i = 0; i < samples; i++) {
      final env = 1 - i / samples;
      final v = (sin(2 * pi * freq * i / sampleRate) * 8000 * env).round();
      data.add(_le16(v));
    }
    return data.toBytes();
  }

  static List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
  static List<int> _le32(int v) => [
    v & 0xff,
    (v >> 8) & 0xff,
    (v >> 16) & 0xff,
    (v >> 24) & 0xff,
  ];

  static PermissionStatus? _notificationStatus;

  static void notify(String title, String body, {String? kind}) {
    if (!available) return;
    unawaited(
      androidShowIncomingNotification(
        title: title,
        body: body,
        kind: kind ?? 'message',
      ),
    );
  }

  static Future<void> refreshNotificationPermission() async {
    if (!available) return;
    _notificationStatus = await Permission.notification.status;
  }

  static Future<String> requestNotifications() async {
    if (!available) return 'unsupported';
    final status = await Permission.notification.request();
    _notificationStatus = status;
    return status.isGranted ? 'granted' : 'denied';
  }

  static String notificationPermission() {
    if (!available) return 'unsupported';
    return _notificationStatus?.isGranted == true ? 'granted' : 'denied';
  }

  static Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  static void downloadBytes(
    List<int> bytes,
    String filename, {
    String mime = 'application/zip',
  }) {
    if (!available) return;
    unawaited(_saveFile(bytes, filename));
  }

  static Future<void> _saveFile(List<int> bytes, String filename) async {
    try {
      final dir =
          await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
    } catch (_) {}
  }

  static void listen(void Function(String name, String payload) handler) {
    _handler = handler;
  }

  static void _emit(String name, String payload) {
    _handler?.call(name, payload);
  }

  static void applyBrowserBranding({required String title, String? iconUrl}) {}

  static String? randomUuid() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static String? vanillaDeviceTokenLocalStorage() => null;
  static String? vanillaDeviceTokenCookie() => null;
  static void persistVanillaDeviceToken(String token) {}
}

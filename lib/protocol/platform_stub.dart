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

class PlatformBridge {
  static bool get available => false;
  static bool get isIos => false;
  static bool get canShareScreen => false;

  static Future<void> ensureReady() async {}
  static Future<Map<String, dynamic>> loadDevice(dynamic caps) async => {};
  static Future<String> createSendTransport(
    Map<String, dynamic> params,
    List<Map<String, String>> ice,
  ) async => '';
  static Future<String> createRecvTransport(
    Map<String, dynamic> params,
    List<Map<String, String>> ice,
  ) async => '';
  static void finishConnectSend(bool ok) {}
  static void finishConnectRecv(bool ok) {}
  static void finishProduce(String? id) {}
  static Future<void> getUserMedia({
    bool audio = true,
    bool video = false,
    String? deviceId,
    Map<String, dynamic>? audioConstraints,
  }) async {}
  static Future<void> startMicTest({
    String? deviceId,
    Map<String, dynamic>? audioConstraints,
  }) async {}
  static void stopMicTest() {}
  static double micTestLevel() => 0;
  static Future<void> startVideoPreview({String? deviceId}) async {}
  static void stopVideoPreview() {}
  static void setOutputDevice(String? deviceId) {}
  static void setCameraDevice(String? deviceId) {}
  static Future<void> getDisplayMedia({bool withAudio = false}) async {}
  static Future<String> produce(String kind, {bool simulcast = false}) async =>
      '';
  static Future<String> consume(Map<String, dynamic> info) async => '';
  static void closeProducer(String kind) {}
  static void pauseMic(bool paused) {}
  static bool consumerTrackLive(String key) => false;
  static bool get audioProducerLive => false;
  static void closeConsumer(String key) {}
  static void closeAll() {}
  static Future<void> restartIce(
    String direction,
    Map<String, dynamic> iceParameters,
  ) async {}
  static Future<VoicePlaybackHealth> playbackHealth() async =>
      VoicePlaybackHealth.dead;
  static void setVolume(String key, double volume) {}
  static void bindMediaElement(String key, Object el) {}
  static Future<MediaStats> getMediaStats(String key) async =>
      const MediaStats();
  static Future<TransportStatsData> getTransportStats() async =>
      TransportStatsData.empty;
  static Future<List<MediaDeviceInfo>> enumerate() async => const [];
  static Future<void> unlockAudio() async {}
  static void resumePlayback() {}
  static void playSound(String type) {}
  static void playPing() {}
  static void stopSoundKeepAlive() {}
  static void notify(String title, String body) {}
  static Future<String> requestNotifications() async => 'unsupported';
  static String notificationPermission() => 'unsupported';
  static Future<void> copyText(String text) async {}
  static void downloadBytes(
    List<int> bytes,
    String filename, {
    String mime = 'application/zip',
  }) {}
  static void listen(void Function(String name, String payload) handler) {}
  static void applyBrowserBranding({required String title, String? iconUrl}) {}
  static String? randomUuid() => null;
  static String? vanillaDeviceTokenLocalStorage() => null;
  static String? vanillaDeviceTokenCookie() => null;
  static void persistVanillaDeviceToken(String token) {}
}

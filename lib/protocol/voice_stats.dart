class TransportRtpStats {
  const TransportRtpStats({
    this.bytesReceived = 0,
    this.bytesSent = 0,
    this.packetsReceived = 0,
    this.packetsSent = 0,
    this.packetsLost = 0,
    this.rtt = 0,
    this.jitter = 0,
    this.timestamp = 0,
  });

  final double bytesReceived;
  final double bytesSent;
  final double packetsReceived;
  final double packetsSent;
  final double packetsLost;
  final double rtt;
  final double jitter;
  final int timestamp;

  factory TransportRtpStats.fromJson(Map json) {
    return TransportRtpStats(
      bytesReceived: _num(json['bytesReceived']),
      bytesSent: _num(json['bytesSent']),
      packetsReceived: _num(json['packetsReceived']),
      packetsSent: _num(json['packetsSent']),
      packetsLost: _num(json['packetsLost']),
      rtt: _num(json['rtt']),
      jitter: _num(json['jitter']),
      timestamp: _num(json['timestamp']).round(),
    );
  }
}

class ScreenShareLayerStats {
  const ScreenShareLayerStats({
    this.id = '',
    this.rid = '',
    this.codec = '',
    this.width = 0,
    this.height = 0,
    this.frameRate = 0,
    this.bitrate = 0,
    this.packetsSent = 0,
    this.bytesSent = 0,
    this.keyFramesEncoded = 0,
    this.framesEncoded = 0,
    this.qualityLimitationReason = 'none',
  });

  final String id;
  final String rid;
  final String codec;
  final double width;
  final double height;
  final double frameRate;
  final double bitrate;
  final double packetsSent;
  final double bytesSent;
  final double keyFramesEncoded;
  final double framesEncoded;
  final String qualityLimitationReason;

  factory ScreenShareLayerStats.fromJson(Map json) {
    return ScreenShareLayerStats(
      id: '${json['id'] ?? ''}',
      rid: '${json['rid'] ?? ''}',
      codec: '${json['codec'] ?? ''}',
      width: _num(json['width']),
      height: _num(json['height']),
      frameRate: _num(json['frameRate']),
      bitrate: _num(json['bitrate']),
      packetsSent: _num(json['packetsSent']),
      bytesSent: _num(json['bytesSent']),
      keyFramesEncoded: _num(json['keyFramesEncoded']),
      framesEncoded: _num(json['framesEncoded']),
      qualityLimitationReason: '${json['qualityLimitationReason'] ?? 'none'}',
    );
  }
}

class ScreenShareTransportStats {
  const ScreenShareTransportStats({
    this.codec = '',
    this.encoderImplementation = '',
    this.width = 0,
    this.height = 0,
    this.frameRate = 0,
    this.bitrate = 0,
    this.packetsSent = 0,
    this.bytesSent = 0,
    this.keyFramesEncoded = 0,
    this.framesEncoded = 0,
    this.qualityLimitationReason = 'none',
    this.simulcast = false,
    this.layers = const [],
    this.timestamp = 0,
  });

  final String codec;
  final String encoderImplementation;
  final double width;
  final double height;
  final double frameRate;
  final double bitrate;
  final double packetsSent;
  final double bytesSent;
  final double keyFramesEncoded;
  final double framesEncoded;
  final String qualityLimitationReason;
  final bool simulcast;
  final List<ScreenShareLayerStats> layers;
  final int timestamp;

  factory ScreenShareTransportStats.fromJson(Map json) {
    final rawLayers = json['layers'];
    return ScreenShareTransportStats(
      codec: '${json['codec'] ?? ''}',
      encoderImplementation: '${json['encoderImplementation'] ?? ''}',
      width: _num(json['width']),
      height: _num(json['height']),
      frameRate: _num(json['frameRate']),
      bitrate: _num(json['bitrate']),
      packetsSent: _num(json['packetsSent']),
      bytesSent: _num(json['bytesSent']),
      keyFramesEncoded: _num(json['keyFramesEncoded']),
      framesEncoded: _num(json['framesEncoded']),
      qualityLimitationReason: '${json['qualityLimitationReason'] ?? 'none'}',
      simulcast: json['simulcast'] == true,
      layers: rawLayers is List
          ? rawLayers
                .whereType<Map>()
                .map(ScreenShareLayerStats.fromJson)
                .toList()
          : const [],
      timestamp: _num(json['timestamp']).round(),
    );
  }
}

class TransportStatsData {
  const TransportStatsData({
    this.producer,
    this.consumer,
    this.screenShare,
    this.totalBytesReceived = 0,
    this.totalBytesSent = 0,
    this.currentBitrateSent = 0,
    this.currentBitrateReceived = 0,
  });

  static const empty = TransportStatsData();

  final TransportRtpStats? producer;
  final TransportRtpStats? consumer;
  final ScreenShareTransportStats? screenShare;
  final double totalBytesReceived;
  final double totalBytesSent;
  final double currentBitrateSent;
  final double currentBitrateReceived;

  int? get rttMs {
    final producerRtt = producer?.rtt ?? 0;
    if (producerRtt > 0) return producerRtt.round();
    final consumerRtt = consumer?.rtt ?? 0;
    if (consumerRtt > 0) return consumerRtt.round();
    return null;
  }

  factory TransportStatsData.fromJson(Map json) {
    return TransportStatsData(
      producer: json['producer'] is Map
          ? TransportRtpStats.fromJson(json['producer'] as Map)
          : null,
      consumer: json['consumer'] is Map
          ? TransportRtpStats.fromJson(json['consumer'] as Map)
          : null,
      screenShare: json['screenShare'] is Map
          ? ScreenShareTransportStats.fromJson(json['screenShare'] as Map)
          : null,
      totalBytesReceived: _num(json['totalBytesReceived']),
      totalBytesSent: _num(json['totalBytesSent']),
      currentBitrateSent: _num(json['currentBitrateSent']),
      currentBitrateReceived: _num(json['currentBitrateReceived']),
    );
  }
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

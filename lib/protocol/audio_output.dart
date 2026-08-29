import 'platform.dart';

enum AudioOutputRoute { earpiece, speaker, bluetooth, unknown }

enum AudioOutputToggle { toDevice, noOtherDevices, pickDevice }

class ClassifiedAudioOutputs {
  const ClassifiedAudioOutputs({
    this.earpieces = const [],
    this.speakers = const [],
    this.externals = const [],
  });

  final List<MediaDeviceInfo> earpieces;
  final List<MediaDeviceInfo> speakers;
  final List<MediaDeviceInfo> externals;

  bool get hasEarpiece => earpieces.isNotEmpty;
  bool get hasSpeaker => speakers.isNotEmpty;
  bool get hasExternal => externals.isNotEmpty;

  List<MediaDeviceInfo> get realDevices => [
    ...earpieces,
    ...speakers,
    ...externals,
  ];
}

class AudioOutputToggleResult {
  const AudioOutputToggleResult._(this.kind, this.deviceId);

  const AudioOutputToggleResult.toDevice(String? id)
    : this._(AudioOutputToggle.toDevice, id);

  const AudioOutputToggleResult.noOtherDevices()
    : this._(AudioOutputToggle.noOtherDevices, null);

  const AudioOutputToggleResult.pickDevice()
    : this._(AudioOutputToggle.pickDevice, null);

  final AudioOutputToggle kind;
  final String? deviceId;
}

bool isVirtualAudioOutput(MediaDeviceInfo device) {
  final id = device.deviceId.trim().toLowerCase();
  final label = device.label.trim().toLowerCase();
  if (id.isEmpty || id == 'default' || id == 'communications') return true;
  if (label == 'default' || label == 'communications') return true;
  return false;
}

bool isEarpieceOutputLabel(String label) {
  final l = label.toLowerCase();
  return l.contains('earpiece') ||
      l.contains('handset') ||
      l.contains('telephony') ||
      l.contains('receiver');
}

bool isSpeakerOutputLabel(String label) {
  if (isEarpieceOutputLabel(label)) return false;
  final l = label.toLowerCase();
  return l.contains('speakerphone') ||
      l.contains('speaker') ||
      l.contains('built-in');
}

AudioOutputRoute routeForOutputLabel(String label) {
  if (isEarpieceOutputLabel(label)) return AudioOutputRoute.earpiece;
  if (isSpeakerOutputLabel(label)) return AudioOutputRoute.speaker;
  return AudioOutputRoute.bluetooth;
}

ClassifiedAudioOutputs classifyAudioOutputs(Iterable<MediaDeviceInfo> devices) {
  final real = devices
      .where((d) => d.kind == 'audiooutput' && !isVirtualAudioOutput(d))
      .toList();
  return ClassifiedAudioOutputs(
    earpieces: real.where((d) => isEarpieceOutputLabel(d.label)).toList(),
    speakers: real.where((d) => isSpeakerOutputLabel(d.label)).toList(),
    externals: real
        .where(
          (d) =>
              !isEarpieceOutputLabel(d.label) && !isSpeakerOutputLabel(d.label),
        )
        .toList(),
  );
}

AudioOutputRoute audioOutputRoute(
  String? storedId,
  ClassifiedAudioOutputs classified,
) {
  final id = storedId?.trim() ?? '';
  if (id.isEmpty) return AudioOutputRoute.earpiece;
  if (classified.earpieces.any((d) => d.deviceId == id)) {
    return AudioOutputRoute.earpiece;
  }
  if (classified.speakers.any((d) => d.deviceId == id)) {
    return AudioOutputRoute.speaker;
  }
  if (classified.externals.any((d) => d.deviceId == id)) {
    return AudioOutputRoute.bluetooth;
  }
  return AudioOutputRoute.unknown;
}

AudioOutputToggleResult nextAudioOutput({
  required String? currentId,
  required ClassifiedAudioOutputs classified,
  String? lastExternalId,
}) {
  if (classified.realDevices.isEmpty) {
    return const AudioOutputToggleResult.noOtherDevices();
  }
  final route = audioOutputRoute(currentId, classified);
  switch (route) {
    case AudioOutputRoute.speaker:
      final external = preferredExternal(classified, lastExternalId);
      if (external != null) {
        return AudioOutputToggleResult.toDevice(external.deviceId);
      }
      return AudioOutputToggleResult.toDevice(_earpieceId(classified));
    case AudioOutputRoute.bluetooth:
      return AudioOutputToggleResult.toDevice(_earpieceId(classified));
    case AudioOutputRoute.earpiece:
    case AudioOutputRoute.unknown:
      if (classified.hasSpeaker) {
        return AudioOutputToggleResult.toDevice(
          classified.speakers.first.deviceId,
        );
      }
      final external = preferredExternal(classified, lastExternalId);
      if (external != null) {
        return AudioOutputToggleResult.toDevice(external.deviceId);
      }
      return const AudioOutputToggleResult.noOtherDevices();
  }
}

MediaDeviceInfo? preferredExternal(
  ClassifiedAudioOutputs classified,
  String? lastExternalId,
) {
  final last = lastExternalId?.trim() ?? '';
  if (last.isNotEmpty) {
    for (final d in classified.externals) {
      if (d.deviceId == last) return d;
    }
  }
  if (classified.externals.isEmpty) return null;
  return classified.externals.first;
}

String? _earpieceId(ClassifiedAudioOutputs classified) {
  if (classified.earpieces.isEmpty) return null;
  return classified.earpieces.first.deviceId;
}

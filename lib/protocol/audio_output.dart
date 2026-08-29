import 'platform.dart';

enum AudioOutputRoute { speaker, bluetooth, unknown }

enum AudioOutputToggle { toDevice, noOtherDevices, pickDevice }

class ClassifiedAudioOutputs {
  const ClassifiedAudioOutputs({
    this.speakers = const [],
    this.externals = const [],
  });

  final List<MediaDeviceInfo> speakers;
  final List<MediaDeviceInfo> externals;

  bool get hasSpeaker => speakers.isNotEmpty;
  bool get hasExternal => externals.isNotEmpty;

  List<MediaDeviceInfo> get realDevices => [...speakers, ...externals];
}

class AudioOutputToggleResult {
  const AudioOutputToggleResult._(this.kind, this.deviceId);

  const AudioOutputToggleResult.toDevice(String id)
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

bool isSpeakerOutputLabel(String label) {
  final l = label.toLowerCase();
  return l.contains('speakerphone') ||
      l.contains('speaker') ||
      l.contains('built-in');
}

ClassifiedAudioOutputs classifyAudioOutputs(Iterable<MediaDeviceInfo> devices) {
  final real = devices
      .where((d) => d.kind == 'audiooutput' && !isVirtualAudioOutput(d))
      .toList();
  return ClassifiedAudioOutputs(
    speakers: real.where((d) => isSpeakerOutputLabel(d.label)).toList(),
    externals: real.where((d) => !isSpeakerOutputLabel(d.label)).toList(),
  );
}

AudioOutputRoute audioOutputRoute(
  String? storedId,
  ClassifiedAudioOutputs classified,
) {
  final id = storedId?.trim() ?? '';
  if (id.isEmpty) return AudioOutputRoute.unknown;
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
  if (!classified.hasSpeaker) {
    return const AudioOutputToggleResult.pickDevice();
  }
  final route = audioOutputRoute(currentId, classified);
  if (route == AudioOutputRoute.speaker) {
    final external = preferredExternal(classified, lastExternalId);
    if (external == null) {
      return const AudioOutputToggleResult.noOtherDevices();
    }
    return AudioOutputToggleResult.toDevice(external.deviceId);
  }
  return AudioOutputToggleResult.toDevice(classified.speakers.first.deviceId);
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

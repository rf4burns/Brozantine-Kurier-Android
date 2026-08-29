import 'platform.dart';

const kDefaultAudioOutputId = 'default';

enum AudioOutputRoute { speaker, bluetooth, unknown }

enum AudioOutputToggle { toDevice, noOtherDevices, pickDevice }

class ClassifiedAudioOutputs {
  const ClassifiedAudioOutputs({
    this.speakers = const [],
    this.externals = const [],
    this.hasDefaultSink = false,
  });

  final List<MediaDeviceInfo> speakers;
  final List<MediaDeviceInfo> externals;
  final bool hasDefaultSink;

  bool get hasSpeaker => speakers.isNotEmpty;
  bool get hasExternal => externals.isNotEmpty;

  /// Android Chrome lists Bluetooth as the system default, not a named sink.
  bool get usesDefaultAsBluetooth =>
      hasSpeaker && externals.isEmpty && hasDefaultSink;

  List<MediaDeviceInfo> get realDevices {
    if (!usesDefaultAsBluetooth) return [...speakers, ...externals];
    return [
      ...speakers,
      MediaDeviceInfo(
        deviceId: kDefaultAudioOutputId,
        kind: 'audiooutput',
        label: '',
      ),
    ];
  }
}

class AudioOutputPlan {
  const AudioOutputPlan({
    this.classified = const ClassifiedAudioOutputs(),
    this.usesMicRoute = false,
  });

  final ClassifiedAudioOutputs classified;
  final bool usesMicRoute;
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

bool isDefaultAudioOutputId(String? id) {
  final v = id?.trim().toLowerCase() ?? '';
  return v.isEmpty || v == kDefaultAudioOutputId;
}

bool isDefaultAudioOutput(MediaDeviceInfo device) {
  final id = device.deviceId.trim().toLowerCase();
  final label = device.label.trim().toLowerCase();
  if (id == 'communications' || label == 'communications') return false;
  return id.isEmpty || id == kDefaultAudioOutputId || label == 'default';
}

bool isVirtualAudioOutput(MediaDeviceInfo device) {
  final id = device.deviceId.trim().toLowerCase();
  final label = device.label.trim().toLowerCase();
  if (id.isEmpty || id == kDefaultAudioOutputId || id == 'communications') {
    return true;
  }
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
  if (isSpeakerOutputLabel(label)) return AudioOutputRoute.speaker;
  return AudioOutputRoute.bluetooth;
}

bool isBluetoothInputLabel(String label) {
  final l = label.toLowerCase();
  return l.contains('bluetooth') ||
      l.contains('airpod') ||
      l.contains('headset') ||
      l.contains('hands-free') ||
      l.contains('handsfree') ||
      l.contains('hands free') ||
      l.contains('hfp') ||
      l.contains('a2dp') ||
      l.contains('earbuds') ||
      l.contains('earbud') ||
      l.contains('headphones') ||
      l.contains('carplay') ||
      l.contains('android auto');
}

bool isBuiltInInputLabel(String label) {
  if (isBluetoothInputLabel(label)) return false;
  final l = label.toLowerCase();
  return l.contains('built-in') ||
      l.contains('builtin') ||
      l.contains('iphone') ||
      l.contains('ipad') ||
      l.contains('internal') ||
      l.contains('camcorder') ||
      l.contains('voice recognition') ||
      l.contains('voice communication') ||
      l.contains('microphone');
}

/// Older iOS has no audiooutput list. Output follows the selected mic, so
/// built-in mics map to speaker and everything else to Bluetooth.
ClassifiedAudioOutputs classifyAudioInputsForOutput(
  Iterable<MediaDeviceInfo> devices,
) {
  final real = devices
      .where((d) => d.kind == 'audioinput' && !isVirtualAudioOutput(d))
      .toList();
  return ClassifiedAudioOutputs(
    speakers: real.where((d) => isBuiltInInputLabel(d.label)).toList(),
    externals: real.where((d) => !isBuiltInInputLabel(d.label)).toList(),
  );
}

ClassifiedAudioOutputs classifyAudioOutputs(Iterable<MediaDeviceInfo> devices) {
  final outputs = devices.where((d) => d.kind == 'audiooutput').toList();
  final hasDefaultSink = outputs.any(isDefaultAudioOutput);
  final real = outputs
      .where((d) => !isVirtualAudioOutput(d) && !isEarpieceOutputLabel(d.label))
      .toList();
  return ClassifiedAudioOutputs(
    speakers: real.where((d) => isSpeakerOutputLabel(d.label)).toList(),
    externals: real.where((d) => !isSpeakerOutputLabel(d.label)).toList(),
    hasDefaultSink: hasDefaultSink,
  );
}

bool audioOutputCanToggle(ClassifiedAudioOutputs classified) {
  return classified.usesDefaultAsBluetooth || classified.hasExternal;
}

bool audioInputRouteCanToggle(ClassifiedAudioOutputs classified) {
  return classified.hasSpeaker && classified.hasExternal;
}

/// Prefer named sinks when the browser can switch them. Otherwise, on phones,
/// treat built-in vs Bluetooth/car mics as speaker vs headset because output
/// follows the selected communication device.
AudioOutputPlan resolveAudioOutput({
  required Iterable<MediaDeviceInfo> devices,
  required bool canSetOutputDevice,
  required bool outputFollowsMic,
}) {
  final outputs = classifyAudioOutputs(devices);
  if (canSetOutputDevice && audioOutputCanToggle(outputs)) {
    return AudioOutputPlan(classified: outputs, usesMicRoute: false);
  }
  final inputs = classifyAudioInputsForOutput(devices);
  if (outputFollowsMic && audioInputRouteCanToggle(inputs)) {
    return AudioOutputPlan(classified: inputs, usesMicRoute: true);
  }
  return AudioOutputPlan(classified: outputs, usesMicRoute: false);
}

AudioOutputRoute audioOutputRoute(
  String? storedId,
  ClassifiedAudioOutputs classified,
) {
  if (isDefaultAudioOutputId(storedId)) {
    if (classified.usesDefaultAsBluetooth) return AudioOutputRoute.bluetooth;
    return AudioOutputRoute.unknown;
  }
  final id = storedId!.trim();
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
      if (classified.usesDefaultAsBluetooth) {
        return const AudioOutputToggleResult.toDevice(null);
      }
      return const AudioOutputToggleResult.noOtherDevices();
    case AudioOutputRoute.bluetooth:
      if (classified.hasSpeaker) {
        return AudioOutputToggleResult.toDevice(
          classified.speakers.first.deviceId,
        );
      }
      return const AudioOutputToggleResult.noOtherDevices();
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
  if (last.isNotEmpty && !isDefaultAudioOutputId(last)) {
    for (final d in classified.externals) {
      if (d.deviceId == last) return d;
    }
  }
  if (classified.externals.isEmpty) return null;
  return classified.externals.first;
}

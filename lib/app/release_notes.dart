class ReleaseNote {
  const ReleaseNote({required this.version, required this.notes});

  final String version;
  final List<String> notes;
}

class ThirdPartyProgram {
  const ThirdPartyProgram({required this.name, required this.usage});

  final String name;
  final String usage;
}

/// Latest first. English only — per-build copy is not sent through l10n.
const releaseNotes = <ReleaseNote>[
  ReleaseNote(
    version: '1.0.1',
    notes: [
      'Build 1.0.1.',
    ],
  ),

  ReleaseNote(
    version: '1.0.0',
    notes: [
      'First Android client: add your own host, then chat, DM, and join voice.',
      'App lock, notifications, and optional closed-app alerts via Firebase.',
      'Share photos and files into Kurier from other apps.',
    ],
  ),
];

/// Software and services the Android client uses. Not a full OSS license dump.
const thirdPartyPrograms = <ThirdPartyProgram>[
  ThirdPartyProgram(
    name: 'Flutter / Dart',
    usage: 'UI toolkit and app runtime (Google).',
  ),
  ThirdPartyProgram(
    name: 'Firebase Cloud Messaging',
    usage: 'Closed-app push notifications.',
  ),
  ThirdPartyProgram(
    name: 'Google Play services',
    usage: 'Required on Android for Firebase Cloud Messaging.',
  ),
  ThirdPartyProgram(
    name: 'mediasoup / mediasoup-client',
    usage: 'Voice, video, and screen share on the Kurier host.',
  ),
  ThirdPartyProgram(
    name: 'WebRTC (flutter_webrtc)',
    usage: 'Real-time audio and video capture and playback.',
  ),
  ThirdPartyProgram(
    name: 'Twemoji (Twitter)',
    usage: 'Emoji artwork, licensed CC-BY 4.0.',
  ),
  ThirdPartyProgram(name: 'KLIPY', usage: 'GIF search and picker.'),
  ThirdPartyProgram(
    name: 'Google public STUN',
    usage: 'ICE for WebRTC when no TURN server is configured.',
  ),
  ThirdPartyProgram(name: 'Riverpod', usage: 'App state.'),
  ThirdPartyProgram(
    name: 'flutter_secure_storage',
    usage: 'Encrypted credentials on device.',
  ),
  ThirdPartyProgram(
    name: 'flutter_local_notifications',
    usage: 'Local notification banners.',
  ),
  ThirdPartyProgram(
    name: 'flutter_foreground_task',
    usage: 'Ongoing notification while you are in a voice call.',
  ),
  ThirdPartyProgram(
    name: 'local_auth',
    usage: 'App lock with biometrics or device PIN.',
  ),
  ThirdPartyProgram(
    name: 'permission_handler',
    usage: 'Microphone, camera, Bluetooth, and notification prompts.',
  ),
  ThirdPartyProgram(
    name: 'receive_sharing_intent / share_plus',
    usage: 'Share into and out of Kurier.',
  ),
  ThirdPartyProgram(
    name: 'just_audio / audioplayers',
    usage: 'Notification and UI sounds.',
  ),
  ThirdPartyProgram(
    name: 'video_player / webview_flutter',
    usage: 'Inline video and embedded web content.',
  ),
  ThirdPartyProgram(
    name: 'file_picker / path_provider / shared_preferences',
    usage: 'Files, paths, and local settings.',
  ),
  ThirdPartyProgram(
    name: 'http / web_socket_channel / url_launcher',
    usage: 'HTTP, tRPC WebSocket, and opening links.',
  ),
  ThirdPartyProgram(
    name: 'flutter_html / intl / collection / characters',
    usage: 'Message HTML, dates, and text helpers.',
  ),
  ThirdPartyProgram(
    name: 'wakelock_plus',
    usage: 'Keep the screen on during voice when you enable it.',
  ),
  ThirdPartyProgram(
    name: 'mediasfu_mediasoup_client',
    usage: 'Native mediasoup client used on Android.',
  ),
];

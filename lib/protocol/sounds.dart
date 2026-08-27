/// Vanilla Sharkord [SoundType] strings and incoming-message gating.
class KurierSoundType {
  static const messageReceived = 'message_received';
  static const messageSent = 'message_sent';
  static const serverDisconnected = 'server_disconnected';
  static const ownUserLeftVoiceChannel = 'own_user_left_voice_channel';
  static const ownUserJoinedVoiceChannel = 'own_user_joined_voice_channel';
  static const ownUserMutedMic = 'own_user_muted_mic';
  static const ownUserUnmutedMic = 'own_user_unmuted_mic';
  static const ownUserMutedSound = 'own_user_muted_sound';
  static const ownUserUnmutedSound = 'own_user_unmuted_sound';
  static const ownUserStartedWebcam = 'own_user_started_webcam';
  static const ownUserStoppedWebcam = 'own_user_stopped_webcam';
  static const ownUserStartedScreenshare = 'own_user_started_screenshare';
  static const ownUserStoppedScreenshare = 'own_user_stopped_screenshare';
  static const remoteUserJoinedVoiceChannel =
      'remote_user_joined_voice_channel';
  static const remoteUserLeftVoiceChannel = 'remote_user_left_voice_channel';
  static const remoteUserStartedScreenshare = 'remote_user_started_screenshare';
  static const remoteUserStoppedScreenshare = 'remote_user_stopped_screenshare';

  static const all = <String>[
    messageReceived,
    messageSent,
    serverDisconnected,
    ownUserJoinedVoiceChannel,
    ownUserLeftVoiceChannel,
    ownUserMutedMic,
    ownUserUnmutedMic,
    ownUserMutedSound,
    ownUserUnmutedSound,
    ownUserStartedWebcam,
    ownUserStoppedWebcam,
    ownUserStartedScreenshare,
    ownUserStoppedScreenshare,
    remoteUserJoinedVoiceChannel,
    remoteUserLeftVoiceChannel,
    remoteUserStartedScreenshare,
    remoteUserStoppedScreenshare,
  ];

  static const l10nKeys = <String, String>{
    messageReceived: 'sfxMessageReceived',
    messageSent: 'sfxMessageSent',
    serverDisconnected: 'sfxServerDisconnected',
    ownUserJoinedVoiceChannel: 'sfxOwnJoinedVoice',
    ownUserLeftVoiceChannel: 'sfxOwnLeftVoice',
    ownUserMutedMic: 'sfxOwnMutedMic',
    ownUserUnmutedMic: 'sfxOwnUnmutedMic',
    ownUserMutedSound: 'sfxOwnMutedSound',
    ownUserUnmutedSound: 'sfxOwnUnmutedSound',
    ownUserStartedWebcam: 'sfxOwnStartedWebcam',
    ownUserStoppedWebcam: 'sfxOwnStoppedWebcam',
    ownUserStartedScreenshare: 'sfxOwnStartedScreenshare',
    ownUserStoppedScreenshare: 'sfxOwnStoppedScreenshare',
    remoteUserJoinedVoiceChannel: 'sfxRemoteJoinedVoice',
    remoteUserLeftVoiceChannel: 'sfxRemoteLeftVoice',
    remoteUserStartedScreenshare: 'sfxRemoteStartedScreenshare',
    remoteUserStoppedScreenshare: 'sfxRemoteStoppedScreenshare',
  };
}

bool shouldPlayIncomingMessageSound({
  required bool isOwn,
  required bool mentioned,
  required String? channelOverride,
  required bool soundMention,
  required bool soundMessage,
}) {
  if (isOwn) return false;
  if (channelOverride == 'nothing') return false;
  if (mentioned) return soundMention;
  return soundMessage;
}

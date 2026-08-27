class Permission {
  static const sendMessages = 'SEND_MESSAGES';
  static const reactToMessages = 'REACT_TO_MESSAGES';
  static const pinMessages = 'PIN_MESSAGES';
  static const uploadFiles = 'UPLOAD_FILES';
  static const joinVoiceChannels = 'JOIN_VOICE_CHANNELS';
  static const shareScreen = 'SHARE_SCREEN';
  static const enableWebcam = 'ENABLE_WEBCAM';
  static const manageChannels = 'MANAGE_CHANNELS';
  static const manageChannelPermissions = 'MANAGE_CHANNEL_PERMISSIONS';
  static const manageCategories = 'MANAGE_CATEGORIES';
  static const manageRoles = 'MANAGE_ROLES';
  static const manageEmojis = 'MANAGE_EMOJIS';
  static const manageSettings = 'MANAGE_SETTINGS';
  static const manageUsers = 'MANAGE_USERS';
  static const kickMembers = 'KICK_MEMBERS';
  static const banMembers = 'BAN_MEMBERS';
  static const muteMembers = 'MUTE_MEMBERS';
  static const deafenMembers = 'DEAFEN_MEMBERS';
  static const deleteUsers = 'DELETE_USERS';
  static const viewAuditLog = 'VIEW_AUDIT_LOG';
  static const moveMembers = 'MOVE_MEMBERS';
  static const mentionEveryone = 'MENTION_EVERYONE';
  static const changeNickname = 'CHANGE_NICKNAME';
  static const manageNicknames = 'MANAGE_NICKNAMES';
  static const embedLinks = 'EMBED_LINKS';
  static const manageMessages = 'MANAGE_MESSAGES';
  static const manageStorage = 'MANAGE_STORAGE';
  static const manageInvites = 'MANAGE_INVITES';
  static const manageUpdates = 'MANAGE_UPDATES';
  static const managePlugins = 'MANAGE_PLUGINS';
  static const usePlugins = 'USE_PLUGINS';
  static const viewUserSensitiveData = 'VIEW_USER_SENSITIVE_DATA';
  static const setVoiceChannelStatus = 'SET_VOICE_CHANNEL_STATUS';

  static const all = [
    sendMessages,
    reactToMessages,
    pinMessages,
    uploadFiles,
    joinVoiceChannels,
    shareScreen,
    enableWebcam,
    manageChannels,
    manageChannelPermissions,
    manageCategories,
    manageRoles,
    manageEmojis,
    manageSettings,
    manageUsers,
    kickMembers,
    banMembers,
    muteMembers,
    deafenMembers,
    deleteUsers,
    viewAuditLog,
    moveMembers,
    mentionEveryone,
    changeNickname,
    manageNicknames,
    embedLinks,
    manageMessages,
    manageStorage,
    manageInvites,
    manageUpdates,
    managePlugins,
    usePlugins,
    viewUserSensitiveData,
    setVoiceChannelStatus,
  ];
}

class ChannelPermission {
  static const viewChannel = 'VIEW_CHANNEL';
  static const sendMessages = 'SEND_MESSAGES';
  static const join = 'JOIN';
  static const speak = 'SPEAK';
  static const shareScreen = 'SHARE_SCREEN';
  static const webcam = 'WEBCAM';
}

const missingPermissionKey = 'missingPermission';

class StreamKind {
  static const audio = 'audio';
  static const video = 'video';
  static const screen = 'screen';
  static const screenAudio = 'screen_audio';
  static const externalVideo = 'external_video';
  static const externalAudio = 'external_audio';

  static bool isPlaybackStream(String kind) =>
      kind == screenAudio || kind == externalAudio;

  /// Screen-share and music-bot / plugin audio stay muted until the user unmutes.
  static bool startsClientMuted(String kind) => isPlaybackStream(kind);

  static bool shouldAutoConsume(String kind) => kind == audio || kind == video;

  static bool isExternal(String kind) =>
      kind == externalVideo || kind == externalAudio;

  static String watchKey(int remoteId, {required bool external}) =>
      external ? '$remoteId:external' : '$remoteId:screen';
}

class DisconnectCode {
  static const unexpected = 1006;
  static const kicked = 40000;
  static const banned = 40001;
  static const serverShutdown = 40002;
  static const deleted = 40003;
}

const securityQuestionIds = [
  'first_game',
  'favorite_cartoon',
  'first_console',
  'fictional_world',
  'favorite_board_game',
  'movie_on_repeat',
  'gaming_snack',
  'first_character',
  'favorite_video_game',
  'favorite_book',
];

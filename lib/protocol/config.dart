class AppConfig {
  static const webStamp = String.fromEnvironment(
    'KURIER_WEB_STAMP',
    defaultValue: 'dev',
  );
  static const turnHost = String.fromEnvironment('KURIER_TURN_HOST');
  static const turnUser = String.fromEnvironment('KURIER_TURN_USER');
  static const turnPass = String.fromEnvironment('KURIER_TURN_PASS');
  static const klipyKey = String.fromEnvironment('KURIER_KLIPY_KEY');
  static const marketplaceUrl =
      'https://raw.githubusercontent.com/Sharkord/plugins/refs/heads/main/plugins.json?raw=true';
  static const defaultHost = 'sharkord.brozantine.com';
  static const githubUrl =
      'https://github.com/rf4burns/brozantine-sharkord-server';

  static const ownerRoleId = 1;
  static const defaultMessagesLimit = 100;
  static const maxNicknameLength = 24;
  static const maxPronounsLength = 32;
  static const maxStatusLength = 128;
  static const maxMessageLength = 4000;
  static const deletedUserName = '__deleted_user__';

  static String get versionLabel =>
      webStamp == 'dev' ? 'WEB (dev)' : 'WEB v$webStamp';

  static List<Map<String, String>> iceServers() {
    final servers = <Map<String, String>>[
      {'urls': 'stun:stun.l.google.com:19302'},
    ];
    if (turnHost.isNotEmpty) {
      servers.add({
        'urls': 'turn:$turnHost',
        'username': turnUser,
        'credential': turnPass,
      });
    }
    return servers;
  }
}

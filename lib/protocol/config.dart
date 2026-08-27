class AppConfig {
  static const webStamp = String.fromEnvironment(
    'KURIER_WEB_STAMP',
    defaultValue: 'dev',
  );
  static const turnHost = String.fromEnvironment('KURIER_TURN_HOST');
  static const turnUser = String.fromEnvironment('KURIER_TURN_USER');
  static const turnPass = String.fromEnvironment('KURIER_TURN_PASS');
  static const klipyKey = String.fromEnvironment('KURIER_KLIPY_KEY');

  /// Public Brozantine KLIPY key already shipped in the vanilla JS client.
  static const brozantineKlipyKey =
      'WmZTDWDZXh8KkYtNSmGMwWGP77phaLAnid4qSHsE8yDO0eaHYEGW5PFi5fHLv2vp';

  static const marketplaceUrl =
      'https://raw.githubusercontent.com/Sharkord/plugins/refs/heads/main/plugins.json?raw=true';
  static const defaultHost = 'sharkord.brozantine.com';
  static const githubUrl =
      'https://github.com/rf4burns/brozantine-sharkord-server';

  static bool isBrozantineHost(String? host) {
    final h = (host ?? '').toLowerCase().split(':').first.trim();
    if (h.isEmpty) return false;
    return h == defaultHost ||
        h == 'kurier.brozantine.com' ||
        h.endsWith('.brozantine.com');
  }

  /// Settings and `--dart-define=KURIER_KLIPY_KEY` win. Brozantine hosts
  /// fall back to the baked vanilla-client key.
  static String klipyKeyFor({String? stored, String? host}) {
    final local = (stored ?? '').trim();
    if (local.isNotEmpty) return local;
    if (klipyKey.isNotEmpty) return klipyKey;
    if (isBrozantineHost(host)) return brozantineKlipyKey;
    return '';
  }

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

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../app/breakpoints.dart';
import '../protocol/models.dart';

class HostsStore {
  static const _hostsKey = 'kurier.hosts';
  static const _activeKey = 'kurier.activeHost';
  static const _deviceKey = 'kurier.deviceToken';
  static const _presetKey = 'kurier.themePreset';
  static const _accentKey = 'kurier.themeAccent';
  static const _localeKey = 'kurier.locale';
  static const _klipyKey = 'kurier.klipy';
  static const _notifyAllKey = 'kurier.notifyAll';
  static const _notifyMentionsKey = 'kurier.notifyMentions';
  static const _notifyDmKey = 'kurier.notifyDm';
  static const _soundMentionKey = 'kurier.soundMention';
  static const _soundMessageKey = 'kurier.soundMessage';
  static const _lastChannelKey = 'kurier.lastChannel';
  static const _autoJoinKey = 'kurier.autoJoin';
  static const _compactKey = 'kurier.compact';
  static const _pttKey = 'kurier.ptt';
  static const _sidebarWidthKey = 'kurier.sidebarWidth';
  static const _membersWidthKey = 'kurier.membersWidth';
  static const _micKey = 'kurier.micDevice';
  static const _speakerKey = 'kurier.speakerDevice';
  static const _cameraKey = 'kurier.cameraDevice';
  static const _noiseKey = 'kurier.noiseSuppression';
  static const _echoKey = 'kurier.echoCancellation';
  static const _agcKey = 'kurier.autoGainControl';
  static const _vadKey = 'kurier.vadSensitivity';
  static const _attenuateKey = 'kurier.attenuateOthers';
  static const _attenuationAmtKey = 'kurier.attenuationAmount';
  static const _skipDeviceCheckKey = 'kurier.skipDeviceCheck';
  static const _notifyRepliesKey = 'kurier.notifyReplies';
  static const _collapsedKey = 'kurier.collapsedCats';
  static const _recentEmojisKey = 'recent_emoji_keys_v1';
  static const _quickReactionsKey = 'quick_reaction_counts_v1';
  static const _favoriteGifsKey = 'kurier.favoriteGifs';

  SharedPreferences? _p;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
  }

  List<SavedHost> hosts() {
    final raw = _p?.getString(_hostsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => SavedHost.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHosts(List<SavedHost> hosts) async {
    await _p?.setString(
      _hostsKey,
      jsonEncode(hosts.map((h) => h.toJson()).toList()),
    );
  }

  String? get activeHost => _p?.getString(_activeKey);
  Future<void> setActiveHost(String? host) async {
    if (host == null) {
      await _p?.remove(_activeKey);
    } else {
      await _p?.setString(_activeKey, host);
    }
  }

  String deviceToken() {
    var t = _p?.getString(_deviceKey);
    if (t == null || t.isEmpty) {
      t = _randomToken();
      _p?.setString(_deviceKey, t);
    }
    return t;
  }

  String get preset => _p?.getString(_presetKey) ?? 'dark';
  Future<void> setPreset(String v) => _p!.setString(_presetKey, v);

  String get accent => _p?.getString(_accentKey) ?? '#5865F2';
  Future<void> setAccent(String v) => _p!.setString(_accentKey, v);

  String get locale => _p?.getString(_localeKey) ?? 'en';
  Future<void> setLocale(String v) => _p!.setString(_localeKey, v);

  String? get klipy => _p?.getString(_klipyKey);
  Future<void> setKlipy(String v) => _p!.setString(_klipyKey, v);

  bool get notifyAll => _p?.getBool(_notifyAllKey) ?? false;
  bool get notifyMentions => _p?.getBool(_notifyMentionsKey) ?? true;
  bool get notifyDm => _p?.getBool(_notifyDmKey) ?? true;
  bool get notifyReplies => _p?.getBool(_notifyRepliesKey) ?? false;
  bool get soundMention => _p?.getBool(_soundMentionKey) ?? true;
  bool get soundMessage => _p?.getBool(_soundMessageKey) ?? false;
  bool get autoJoin => _p?.getBool(_autoJoinKey) ?? false;
  bool get compact => _p?.getBool(_compactKey) ?? false;
  bool get ptt => _p?.getBool(_pttKey) ?? false;
  bool get echoCancellation => _p?.getBool(_echoKey) ?? true;
  bool get autoGainControl => _p?.getBool(_agcKey) ?? false;
  bool get vadSensitivity => _p?.getBool(_vadKey) ?? true;
  bool get attenuateOthers => _p?.getBool(_attenuateKey) ?? false;
  bool get skipDeviceCheck => _p?.getBool(_skipDeviceCheckKey) ?? true;
  String get noiseSuppression => _p?.getString(_noiseKey) ?? 'none';
  double get attenuationAmount {
    final v = _p?.getDouble(_attenuationAmtKey);
    return (v ?? 80).clamp(0, 100).toDouble();
  }

  Future<void> setBool(String key, bool v) => _p!.setBool(key, v);

  Future<void> setNotifyAll(bool v) => setBool(_notifyAllKey, v);
  Future<void> setNotifyMentions(bool v) => setBool(_notifyMentionsKey, v);
  Future<void> setNotifyDm(bool v) => setBool(_notifyDmKey, v);
  Future<void> setNotifyReplies(bool v) => setBool(_notifyRepliesKey, v);
  Future<void> setSoundMention(bool v) => setBool(_soundMentionKey, v);
  Future<void> setSoundMessage(bool v) => setBool(_soundMessageKey, v);
  Future<void> setAutoJoin(bool v) => setBool(_autoJoinKey, v);
  Future<void> setCompact(bool v) => setBool(_compactKey, v);
  Future<void> setPtt(bool v) => setBool(_pttKey, v);
  Future<void> setEchoCancellation(bool v) => setBool(_echoKey, v);
  Future<void> setAutoGainControl(bool v) => setBool(_agcKey, v);
  Future<void> setVadSensitivity(bool v) => setBool(_vadKey, v);
  Future<void> setAttenuateOthers(bool v) => setBool(_attenuateKey, v);
  Future<void> setSkipDeviceCheck(bool v) => setBool(_skipDeviceCheckKey, v);
  Future<void> setNoiseSuppression(String v) => _p!.setString(_noiseKey, v);
  Future<void> setAttenuationAmount(double v) =>
      _p!.setDouble(_attenuationAmtKey, v.clamp(0, 100));

  double get sidebarWidth {
    final v = _p?.getDouble(_sidebarWidthKey);
    if (v == null) return kSidebarWidth;
    return v.clamp(kSidebarMinWidth, kSidebarMaxWidth).toDouble();
  }

  Future<void> setSidebarWidth(double v) async {
    await _p?.setDouble(_sidebarWidthKey, v);
  }

  double get membersWidth {
    final v = _p?.getDouble(_membersWidthKey);
    if (v == null) return kSidebarWidth;
    return v.clamp(kSidebarMinWidth, kSidebarMaxWidth).toDouble();
  }

  Future<void> setMembersWidth(double v) async {
    await _p?.setDouble(_membersWidthKey, v);
  }

  int? lastChannel(String host) => _p?.getInt('$_lastChannelKey.$host');
  Future<void> setLastChannel(String host, int id) =>
      _p!.setInt('$_lastChannelKey.$host', id);

  String? get micDevice => _p?.getString(_micKey);
  Future<void> setMicDevice(String? id) async {
    if (id == null || id.isEmpty) {
      await _p?.remove(_micKey);
    } else {
      await _p?.setString(_micKey, id);
    }
  }

  String? get speakerDevice => _p?.getString(_speakerKey);
  Future<void> setSpeakerDevice(String? id) async {
    if (id == null || id.isEmpty) {
      await _p?.remove(_speakerKey);
    } else {
      await _p?.setString(_speakerKey, id);
    }
  }

  String? get cameraDevice => _p?.getString(_cameraKey);
  Future<void> setCameraDevice(String? id) async {
    if (id == null || id.isEmpty) {
      await _p?.remove(_cameraKey);
    } else {
      await _p?.setString(_cameraKey, id);
    }
  }

  Map<String, dynamic> audioConstraints() => {
    'echoCancellation': echoCancellation,
    'autoGainControl': autoGainControl,
    'noiseSuppression': noiseSuppression != 'none',
  };

  Set<int> collapsedCats() {
    final raw = _p?.getString(_collapsedKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as List).map((e) => (e as num).toInt()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> setCollapsedCats(Set<int> ids) =>
      _p!.setString(_collapsedKey, jsonEncode(ids.toList()));

  String? get recentEmojiKeysJson => _p?.getString(_recentEmojisKey);
  Future<void> setRecentEmojiKeysJson(String json) =>
      _p!.setString(_recentEmojisKey, json);

  List<String> favoriteGifs() {
    final raw = _p?.getString(_favoriteGifsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list
          .map((e) => e.toString())
          .where((s) => s.startsWith('http'))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> setFavoriteGifs(List<String> urls) async {
    await _p?.setString(_favoriteGifsKey, jsonEncode(urls));
  }

  String? get quickReactionCountsJson => _p?.getString(_quickReactionsKey);
  Future<void> setQuickReactionCountsJson(String json) =>
      _p!.setString(_quickReactionsKey, json);

  String _randomToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }
}

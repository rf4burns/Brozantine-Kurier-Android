import 'dart:math';

/// Vanilla cookie and localStorage key (`kurier-device-token`).
const kDeviceTokenStorageKey = 'kurier-device-token';

/// Vanilla cookie lifetime: two years.
const kDeviceTokenCookieMaxAge = 60 * 60 * 24 * 365 * 2;

final _hex32 = RegExp(r'^[0-9a-f]{32}$');

/// Shared `normalizeDeviceToken`: 32 hex chars, optional `{}-`, hyphenated UUID.
String? normalizeDeviceToken(String? value) {
  if (value == null) return null;
  final hex = value.trim().toLowerCase().replaceAll(RegExp(r'[{}-]'), '');
  if (!_hex32.hasMatch(hex)) return null;
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String generateDeviceToken([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return normalizeDeviceToken(hex)!;
}

/// Overlay prefs first, then vanilla localStorage, then cookie, then create.
String resolveDeviceToken({
  String? fromPrefs,
  String? fromLocalStorage,
  String? fromCookie,
  String Function()? create,
}) {
  for (final candidate in [fromPrefs, fromLocalStorage, fromCookie]) {
    final normalized = normalizeDeviceToken(candidate);
    if (normalized != null) return normalized;
  }
  return create?.call() ?? generateDeviceToken();
}

String deviceTokenCookieAssignment(String token, {bool secure = false}) {
  final flags =
      '$kDeviceTokenStorageKey=$token; max-age=$kDeviceTokenCookieMaxAge; '
      'path=/; samesite=lax';
  return secure ? '$flags; Secure' : flags;
}

String? namedCookieValue(String header, String name) {
  for (final part in header.split(';')) {
    final idx = part.indexOf('=');
    if (idx == -1) continue;
    final key = part.substring(0, idx).trim();
    if (key != name) continue;
    final raw = part.substring(idx + 1).trim();
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }
  return null;
}

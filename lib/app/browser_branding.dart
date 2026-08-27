const kAppName = 'Kurier';

/// Chrome tab title: `{server} - Kurier`, matching the vanilla client.
String browserTabTitle({String serverName = '', String infoName = ''}) {
  final name = serverName.trim().isNotEmpty
      ? serverName.trim()
      : infoName.trim();
  if (name.isEmpty || name == kAppName) return kAppName;
  return '$name - $kAppName';
}

/// Favicon URL: server logo, else the host's `/favicon.ico`.
String? browserTabIconUrl({String? logoUrl, String? origin}) {
  if (logoUrl != null && logoUrl.isNotEmpty) return logoUrl;
  if (origin == null || origin.isEmpty) return null;
  return '$origin/favicon.ico';
}

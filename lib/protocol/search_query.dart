const searchHasValues = ['link', 'file', 'image', 'video', 'sound'];
const searchOperatorKeys = [
  'from',
  'mentions',
  'in',
  'has',
  'before',
  'after',
  'during',
  'pinned',
];

class ParsedSearchQuery {
  ParsedSearchQuery({this.text = ''});

  String text;
  String? from;
  String? mentions;
  String? inChannel;
  String? has;
  int? before;
  int? after;
  int? duringStart;
  int? duringEnd;
  bool? pinned;

  bool get hasFilters =>
      from != null ||
      mentions != null ||
      inChannel != null ||
      has != null ||
      before != null ||
      after != null ||
      duringStart != null ||
      pinned != null;
}

bool isValidSearchQuery(ParsedSearchQuery parsed, {int minTextLength = 2}) {
  if (parsed.hasFilters) return true;
  return parsed.text.length >= minTextLength;
}

List<String> tokenizeSearchQuery(String query) {
  final tokens = <String>[];
  var current = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < query.length; i++) {
    final char = query[i];
    if (char == '"') {
      inQuotes = !inQuotes;
      current.write(char);
      continue;
    }
    if (char == ' ' && !inQuotes) {
      if (current.isNotEmpty) {
        tokens.add(current.toString());
        current = StringBuffer();
      }
      continue;
    }
    current.write(char);
  }
  if (current.isNotEmpty) tokens.add(current.toString());
  return tokens;
}

String unwrapQuotedValue(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

int? parseDateDayStartUtc(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date.millisecondsSinceEpoch;
}

const _msPerDay = 24 * 60 * 60 * 1000;

bool _applyOperator(ParsedSearchQuery parsed, String key, String rawValue) {
  final value = unwrapQuotedValue(rawValue);
  if (value.isEmpty) return false;
  switch (key) {
    case 'from':
      parsed.from = value;
      return true;
    case 'mentions':
      parsed.mentions = value;
      return true;
    case 'in':
      parsed.inChannel = value.startsWith('#') ? value.substring(1) : value;
      return true;
    case 'has':
      final lowered = value.toLowerCase();
      if (!searchHasValues.contains(lowered)) return false;
      parsed.has = lowered;
      return true;
    case 'before':
      final day = parseDateDayStartUtc(value);
      if (day == null) return false;
      parsed.before = day;
      return true;
    case 'after':
      final day = parseDateDayStartUtc(value);
      if (day == null) return false;
      parsed.after = day + _msPerDay;
      return true;
    case 'during':
      final day = parseDateDayStartUtc(value);
      if (day == null) return false;
      parsed.duringStart = day;
      parsed.duringEnd = day + _msPerDay;
      return true;
    case 'pinned':
      final lowered = value.toLowerCase();
      if (lowered != 'true' && lowered != 'false') return false;
      parsed.pinned = lowered == 'true';
      return true;
    default:
      return false;
  }
}

ParsedSearchQuery parseSearchQuery(String query) {
  final parsed = ParsedSearchQuery();
  final textParts = <String>[];
  for (final token in tokenizeSearchQuery(query.trim())) {
    final colon = token.indexOf(':');
    if (colon <= 0) {
      textParts.add(token);
      continue;
    }
    final key = token.substring(0, colon).toLowerCase();
    final rawValue = token.substring(colon + 1);
    if (!searchOperatorKeys.contains(key)) {
      textParts.add(token);
      continue;
    }
    if (!_applyOperator(parsed, key, rawValue)) {
      textParts.add(token);
    }
  }
  parsed.text = textParts.join(' ').trim();
  return parsed;
}

String quoteIfNeeded(String value) {
  if (RegExp(r'[\s"]').hasMatch(value)) {
    return '"${value.replaceAll('"', '')}"';
  }
  return value;
}

String serializeSearchQuery(ParsedSearchQuery parsed) {
  final parts = <String>[];
  if (parsed.from != null) parts.add('from:${quoteIfNeeded(parsed.from!)}');
  if (parsed.mentions != null) {
    parts.add('mentions:${quoteIfNeeded(parsed.mentions!)}');
  }
  if (parsed.inChannel != null) {
    parts.add('in:${quoteIfNeeded(parsed.inChannel!)}');
  }
  if (parsed.has != null) parts.add('has:${parsed.has}');
  String ymd(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  if (parsed.before != null) parts.add('before:${ymd(parsed.before!)}');
  if (parsed.after != null) parts.add('after:${ymd(parsed.after! - _msPerDay)}');
  if (parsed.duringStart != null) {
    parts.add('during:${ymd(parsed.duringStart!)}');
  }
  if (parsed.pinned != null) parts.add('pinned:${parsed.pinned}');
  if (parsed.text.isNotEmpty) parts.add(parsed.text);
  return parts.join(' ');
}

String formatSearchOperatorToken(String key, [String? value]) {
  if (value == null || value.isEmpty) return '$key:';
  return '$key:${quoteIfNeeded(value)}';
}

String formatSearchDate(DateTime date) {
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  return '${date.year}-$mm-$dd';
}

class ActiveSearchToken {
  const ActiveSearchToken({
    required this.start,
    required this.end,
    required this.raw,
    this.key,
    this.value,
  });

  final int start;
  final int end;
  final String raw;
  final String? key;
  final String? value;
}

String unwrapSearchValuePrefix(String rawValue) {
  var value = rawValue;
  if (value.startsWith('"')) value = value.substring(1);
  if (value.endsWith('"') && value.isNotEmpty) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}

ActiveSearchToken activeSearchToken(String query) {
  var inQuotes = false;
  var lastSpace = -1;
  for (var i = 0; i < query.length; i++) {
    final char = query[i];
    if (char == '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (char == ' ' && !inQuotes) lastSpace = i;
  }
  final start = lastSpace + 1;
  final raw = query.substring(start);
  final colon = raw.indexOf(':');
  if (colon <= 0) {
    return ActiveSearchToken(start: start, end: query.length, raw: raw);
  }
  return ActiveSearchToken(
    start: start,
    end: query.length,
    raw: raw,
    key: raw.substring(0, colon).toLowerCase(),
    value: unwrapSearchValuePrefix(raw.substring(colon + 1)),
  );
}

Set<String> usedSearchOperators(String query) {
  final active = activeSearchToken(query);
  final parsed = parseSearchQuery(query.substring(0, active.start));
  return {
    if (parsed.from != null) 'from',
    if (parsed.mentions != null) 'mentions',
    if (parsed.inChannel != null) 'in',
    if (parsed.has != null) 'has',
    if (parsed.before != null) 'before',
    if (parsed.after != null) 'after',
    if (parsed.duringStart != null) 'during',
    if (parsed.pinned != null) 'pinned',
  };
}

List<String> matchingSearchOperators(String query) {
  final active = activeSearchToken(query);
  if (active.key != null) return const [];
  final prefix = active.raw.toLowerCase();
  if (prefix.contains(':')) return const [];
  final used = usedSearchOperators(query);
  return [
    for (final key in searchOperatorKeys)
      if (!used.contains(key) && (prefix.isEmpty || key.startsWith(prefix)))
        key,
  ];
}

String replaceActiveSearchToken(
  String query,
  String token, {
  bool trailingSpace = false,
}) {
  final active = activeSearchToken(query);
  return '${query.substring(0, active.start)}$token${trailingSpace ? ' ' : ''}';
}

import 'models.dart';

bool hasUserMention(String content, int userId) {
  final pattern = RegExp(
    '<span[^>]*(?:\\bdata-type="mention"[^>]*\\bdata-user-id="$userId"|\\bdata-user-id="$userId"[^>]*\\bdata-type="mention")[^>]*>',
  );
  return pattern.hasMatch(content);
}

bool hasEveryoneMention(String content) {
  return RegExp(
    r'<span[^>]*(?:\bdata-type="mention"[^>]*\bdata-mention-kind="everyone"|\bdata-mention-kind="everyone"[^>]*\bdata-type="mention")[^>]*>',
    caseSensitive: false,
  ).hasMatch(content);
}

bool hasHereMention(String content) {
  return RegExp(
    r'<span[^>]*(?:\bdata-type="mention"[^>]*\bdata-mention-kind="here"|\bdata-mention-kind="here"[^>]*\bdata-type="mention")[^>]*>',
    caseSensitive: false,
  ).hasMatch(content);
}

bool hasMention(String? content, int? userId, {bool isOnline = true}) {
  if (content == null || content.isEmpty || userId == null) return false;
  if (hasEveryoneMention(content)) return true;
  if (isOnline && hasHereMention(content)) return true;
  return hasUserMention(content, userId);
}

String escapeHtml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String textToMessageHtml(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final escaped = escapeHtml(normalized).replaceAll('\n', '<br>');
  return '<p>$escaped</p>';
}

String mentionSpan({required String label, int? userId, String kind = 'user'}) {
  final idAttr = userId != null ? ' data-user-id="$userId"' : '';
  return '<span data-type="mention" data-mention-kind="$kind"$idAttr>@$label</span>';
}

String htmlToPlainText(String html) {
  return html
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&nbsp;', ' ')
      .trim();
}

class MentionQuery {
  const MentionQuery({required this.atIndex, required this.query});

  /// Index of the `@` that starts the active mention token.
  final int atIndex;

  /// Text after `@` up to the cursor (no spaces).
  final String query;
}

/// Active `@query` token immediately before [cursor], or null.
///
/// Does not trigger mid-word (`email@x`).
MentionQuery? mentionQueryAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final before = text.substring(0, cursor);
  final at = before.lastIndexOf('@');
  if (at < 0) return null;
  if (at > 0 && !_isMentionBoundary(before.codeUnitAt(at - 1))) return null;
  final query = before.substring(at + 1);
  if (query.contains(RegExp(r'\s'))) return null;
  return MentionQuery(atIndex: at, query: query);
}

bool _isMentionBoundary(int codeUnit) {
  return codeUnit == 0x20 ||
      codeUnit == 0x09 ||
      codeUnit == 0x0A ||
      codeUnit == 0x0D;
}

const mentionCandidateLimit = 20;

enum MentionKind { user, everyone, here }

class MentionCandidate {
  const MentionCandidate._({required this.kind, required this.key, this.user});

  factory MentionCandidate.user(KurierUser user) {
    return MentionCandidate._(
      kind: MentionKind.user,
      key: 'user-${user.id}',
      user: user,
    );
  }

  factory MentionCandidate.everyone() {
    return const MentionCandidate._(
      kind: MentionKind.everyone,
      key: 'everyone',
    );
  }

  factory MentionCandidate.here() {
    return const MentionCandidate._(kind: MentionKind.here, key: 'here');
  }

  final MentionKind kind;
  final String key;
  final KurierUser? user;

  String get insert {
    switch (kind) {
      case MentionKind.everyone:
        return 'everyone';
      case MentionKind.here:
        return 'here';
      case MentionKind.user:
        return user!.name;
    }
  }

  String get label {
    switch (kind) {
      case MentionKind.everyone:
        return '@everyone';
      case MentionKind.here:
        return '@here';
      case MentionKind.user:
        return user!.displayName;
    }
  }

  String? get subtitle {
    if (kind != MentionKind.user) return null;
    final name = user!.name;
    if (name.isEmpty) return null;
    if (name.toLowerCase() == user!.displayName.toLowerCase()) return null;
    return name;
  }
}

List<MentionCandidate> mentionCandidates({
  required Iterable<KurierUser> users,
  required String query,
  bool canMentionEveryone = false,
}) {
  final q = query.toLowerCase();
  final specials = <MentionCandidate>[];
  if (canMentionEveryone) {
    if (q.isEmpty || 'everyone'.startsWith(q)) {
      specials.add(MentionCandidate.everyone());
    }
    if (q.isEmpty || 'here'.startsWith(q)) {
      specials.add(MentionCandidate.here());
    }
  }

  bool matches(KurierUser u) {
    if (u.deleted || u.banned) return false;
    if (q.isEmpty) return true;
    if (u.name.toLowerCase().contains(q)) return true;
    if (u.displayName.toLowerCase().contains(q)) return true;
    final nick = u.nickname?.toLowerCase() ?? '';
    return nick.contains(q);
  }

  int rank(KurierUser u) {
    if (q.isEmpty) return 1;
    if (u.displayName.toLowerCase().startsWith(q)) return 0;
    if (u.name.toLowerCase().startsWith(q)) return 0;
    final nick = u.nickname?.toLowerCase() ?? '';
    if (nick.startsWith(q)) return 0;
    return 1;
  }

  final matched = users.where(matches).toList()
    ..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

  final slots = mentionCandidateLimit - specials.length;
  final picked = slots <= 0 ? const <KurierUser>[] : matched.take(slots);
  return [...specials, for (final u in picked) MentionCandidate.user(u)];
}

class _MentionJob {
  const _MentionJob(this.token, this.span);
  final String token;
  final String span;
}

/// Replace `@name` / `@displayName` / `@everyone` / `@here` in already-escaped
/// [html] with mention spans. Longest token first so prefixes do not steal
/// longer names. Case-insensitive.
String injectMentions(
  String html,
  String text, {
  required Iterable<KurierUser> users,
  bool everyone = false,
  bool here = false,
}) {
  final jobs = <_MentionJob>[];
  if (everyone) {
    jobs.add(
      _MentionJob('everyone', mentionSpan(label: 'everyone', kind: 'everyone')),
    );
  }
  if (here) {
    jobs.add(_MentionJob('here', mentionSpan(label: 'here', kind: 'here')));
  }
  for (final u in users) {
    if (u.deleted) continue;
    if (u.name.isNotEmpty) {
      jobs.add(_MentionJob(u.name, mentionSpan(label: u.name, userId: u.id)));
    }
    final display = u.displayName;
    if (display.isNotEmpty && display.toLowerCase() != u.name.toLowerCase()) {
      jobs.add(_MentionJob(display, mentionSpan(label: u.name, userId: u.id)));
    }
  }
  jobs.sort((a, b) {
    final byLen = b.token.length.compareTo(a.token.length);
    if (byLen != 0) return byLen;
    return a.token.toLowerCase().compareTo(b.token.toLowerCase());
  });

  var out = html;
  final slots = <String>[];
  for (final job in jobs) {
    final re = RegExp('@${RegExp.escape(job.token)}\\b', caseSensitive: false);
    for (final match in re.allMatches(text)) {
      final escaped = escapeHtml(match.group(0)!);
      final index = out.indexOf(escaped);
      if (index < 0) continue;
      final id = slots.length;
      slots.add(job.span);
      out = out.replaceFirst(escaped, '\u0001KURIERM$id\u0001');
    }
  }
  for (var i = 0; i < slots.length; i++) {
    out = out.replaceAll('\u0001KURIERM$i\u0001', slots[i]);
  }
  return out;
}

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

bool hasMention(
  String? content,
  int? userId, {
  bool isOnline = true,
}) {
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

String mentionSpan({
  required String label,
  int? userId,
  String kind = 'user',
}) {
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

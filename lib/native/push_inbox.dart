import 'dart:convert';

import 'push_kind.dart';

class PushInboxLine {
  const PushInboxLine({
    required this.author,
    required this.body,
    this.channelId,
    this.messageId,
    this.channelLabel,
  });

  final String author;
  final String body;
  final int? channelId;
  final int? messageId;
  final String? channelLabel;

  String get heading {
    final label = channelLabel?.trim() ?? '';
    if (label.isNotEmpty) return label;
    return author;
  }

  String get summary {
    final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    final clipped = text.length > 80 ? '${text.substring(0, 77)}...' : text;
    if (clipped.isEmpty) return author;
    return '$author: $clipped';
  }

  Map<String, dynamic> toJson() => {
    'author': author,
    'body': body,
    if (channelId != null) 'channelId': channelId,
    if (messageId != null) 'messageId': messageId,
    if (channelLabel != null && channelLabel!.isNotEmpty)
      'channelLabel': channelLabel,
  };

  factory PushInboxLine.fromJson(Map<String, dynamic> json) => PushInboxLine(
    author: json['author']?.toString() ?? 'Kurier',
    body: json['body']?.toString() ?? '',
    channelId: _asInt(json['channelId']),
    messageId: _asInt(json['messageId']),
    channelLabel: json['channelLabel']?.toString(),
  );
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  return int.tryParse('$v');
}

/// One stacked inbox per [PushKind], so the shade has a single mention
/// notification, a single reply notification, and so on.
class PushInbox {
  static const maxLines = 7;

  final Map<PushKind, List<PushInboxLine>> _byKind = {
    for (final kind in PushKind.values) kind: <PushInboxLine>[],
  };

  List<PushInboxLine> lines(PushKind kind) =>
      List<PushInboxLine>.unmodifiable(_byKind[kind] ?? const []);

  List<PushInboxLine> add(PushKind kind, PushInboxLine line) {
    final list = _byKind[kind]!;
    if (line.messageId != null) {
      list.removeWhere((existing) => existing.messageId == line.messageId);
    }
    list.add(line);
    if (list.length > maxLines) {
      list.removeRange(0, list.length - maxLines);
    }
    return lines(kind);
  }

  Set<PushKind> removeChannel(int channelId) {
    final changed = <PushKind>{};
    for (final kind in PushKind.values) {
      final list = _byKind[kind]!;
      final before = list.length;
      list.removeWhere((line) => line.channelId == channelId);
      if (list.length != before) changed.add(kind);
    }
    return changed;
  }

  void clear(PushKind kind) => _byKind[kind]!.clear();

  void clearAll() {
    for (final kind in PushKind.values) {
      _byKind[kind]!.clear();
    }
  }

  String encode() => jsonEncode({
    for (final kind in PushKind.values)
      kind.wire: _byKind[kind]!.map((line) => line.toJson()).toList(),
  });

  void loadEncoded(String raw) {
    clearAll();
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    for (final entry in decoded.entries) {
      final kind = PushKind.parse(entry.key.toString());
      final value = entry.value;
      if (value is! List) continue;
      for (final item in value) {
        if (item is Map) {
          _byKind[kind]!.add(
            PushInboxLine.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
  }

  ({String title, String body, List<String> lines}) presentation(PushKind kind) {
    final items = lines(kind);
    final summaries = items.map((line) => line.summary).toList();
    if (items.isEmpty) {
      return (title: kind.androidChannelName, body: '', lines: const []);
    }
    if (items.length == 1) {
      final line = items.first;
      final preview = line.body.trim().isEmpty
          ? kind.inboxTitle(1)
          : line.body.trim().replaceAll(RegExp(r'\s+'), ' ');
      return (title: line.heading, body: preview, lines: summaries);
    }
    final headings = items.map((line) => line.heading).toSet();
    return (
      title: headings.length == 1
          ? headings.first
          : kind.inboxTitle(items.length),
      body: summaries.last,
      lines: summaries,
    );
  }
}

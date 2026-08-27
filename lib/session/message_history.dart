import '../protocol/config.dart';
import '../protocol/models.dart';

/// Vanilla groups consecutive same-author messages closer than 1 minute,
/// and never groups a message that has an inline reply.
const kMessageGroupWindowMs = 60 * 1000;

/// Kurier paginates with a `createdAt` int. Upstream Sharkord uses
/// `{ createdAt, id }`. Send whichever shape we last received.
class MessagesCursor {
  const MessagesCursor({required this.createdAt, this.id});

  final int createdAt;
  final int? id;

  dynamic toJson() {
    if (id != null) {
      return {'createdAt': createdAt, 'id': id};
    }
    return createdAt;
  }

  static MessagesCursor? parse(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) {
      final createdAt = asInt(raw['createdAt']);
      if (createdAt == null) return null;
      return MessagesCursor(createdAt: createdAt, id: asInt(raw['id']));
    }
    final n = asInt(raw);
    if (n == null) return null;
    return MessagesCursor(createdAt: n);
  }

  @override
  bool operator ==(Object other) =>
      other is MessagesCursor && other.createdAt == createdAt && other.id == id;

  @override
  int get hashCode => Object.hash(createdAt, id);
}

class ChannelHistoryState {
  ChannelHistoryState({
    List<KurierMessage>? messages,
    this.nextCursor,
    this.detached = false,
  }) : messages = messages ?? [];

  List<KurierMessage> messages;
  MessagesCursor? nextCursor;
  bool detached;
}

int compareKurierMessages(KurierMessage a, KurierMessage b) {
  final byTime = a.createdAt.compareTo(b.createdAt);
  if (byTime != 0) return byTime;
  return a.id.compareTo(b.id);
}

List<KurierMessage> rootMessagesOf(Iterable<KurierMessage> incoming) {
  return [for (final m in incoming) if (m.parentMessageId == null) m];
}

List<KurierMessage> dedupeIncoming(
  List<KurierMessage> existing,
  List<KurierMessage> incoming,
) {
  if (incoming.isEmpty) return incoming;
  final incomingIds = incoming.map((m) => m.id).toSet();
  for (final m in existing) {
    incomingIds.remove(m.id);
    if (incomingIds.isEmpty) break;
  }
  if (incomingIds.length == incoming.length) return incoming;
  return [for (final m in incoming) if (incomingIds.contains(m.id)) m];
}

/// Vanilla `mergeMessagesChronologically`: keep both sides sorted oldest-first
/// and splice without a full re-sort when the new page is entirely older or newer.
List<KurierMessage> mergeMessagesChronologically(
  List<KurierMessage> existing,
  List<KurierMessage> incoming,
) {
  if (incoming.isEmpty) return existing;
  final sortedIncoming = [...incoming]..sort(compareKurierMessages);
  if (existing.isEmpty) return sortedIncoming;

  final firstExisting = existing.first;
  final lastExisting = existing.last;
  final firstIncoming = sortedIncoming.first;
  final lastIncoming = sortedIncoming.last;

  if (compareKurierMessages(lastExisting, firstIncoming) <= 0) {
    return [...existing, ...sortedIncoming];
  }
  if (compareKurierMessages(lastIncoming, firstExisting) <= 0) {
    return [...sortedIncoming, ...existing];
  }

  final merged = <KurierMessage>[];
  var existingIndex = 0;
  var incomingIndex = 0;
  while (existingIndex < existing.length &&
      incomingIndex < sortedIncoming.length) {
    if (compareKurierMessages(
          existing[existingIndex],
          sortedIncoming[incomingIndex],
        ) <=
        0) {
      merged.add(existing[existingIndex]);
      existingIndex += 1;
    } else {
      merged.add(sortedIncoming[incomingIndex]);
      incomingIndex += 1;
    }
  }
  if (existingIndex < existing.length) {
    merged.addAll(existing.skip(existingIndex));
  }
  if (incomingIndex < sortedIncoming.length) {
    merged.addAll(sortedIncoming.skip(incomingIndex));
  }
  return merged;
}

/// Vanilla `addMessages`. Live events are dropped while the channel is showing
/// a jump window that does not reach the present.
void addHistoryMessages(
  ChannelHistoryState state,
  List<KurierMessage> incoming, {
  required bool isLive,
}) {
  if (isLive && state.detached) return;
  final unique = dedupeIncoming(state.messages, rootMessagesOf(incoming));
  if (unique.isEmpty) return;
  state.messages = mergeMessagesChronologically(state.messages, unique);
}

void setHistoryMessages(
  ChannelHistoryState state,
  List<KurierMessage> messages, {
  required bool detached,
}) {
  state.messages = [...rootMessagesOf(messages)]..sort(compareKurierMessages);
  state.detached = detached;
}

/// Vanilla `trimChannelMessages`: drop a detached window outright; otherwise
/// keep the newest [AppConfig.defaultMessagesLimit] messages.
void trimHistoryMessages(ChannelHistoryState state) {
  if (state.detached) {
    state.messages = [];
    state.nextCursor = null;
    state.detached = false;
    return;
  }
  final limit = AppConfig.defaultMessagesLimit;
  if (state.messages.length <= limit) return;
  state.messages = state.messages.sublist(state.messages.length - limit);
}

/// Vanilla first-page / older-page fetch: merge, then take the response cursor.
void applyFetchedPage(
  ChannelHistoryState state, {
  required List<KurierMessage> page,
  MessagesCursor? nextCursor,
}) {
  addHistoryMessages(state, page, isLive: false);
  state.nextCursor = nextCursor;
}

/// Vanilla `returnToPresent`.
void applyPresentPage(
  ChannelHistoryState state, {
  required List<KurierMessage> page,
  MessagesCursor? nextCursor,
}) {
  setHistoryMessages(state, page, detached: false);
  state.nextCursor = nextCursor;
}

/// Vanilla `scrollToMessage` after `messages.get` with `targetMessageId`.
void applyJumpWindow(
  ChannelHistoryState state, {
  required List<KurierMessage> page,
  required bool hasNewer,
  MessagesCursor? nextCursor,
}) {
  if (hasNewer) {
    setHistoryMessages(state, page, detached: true);
  } else if (state.detached) {
    setHistoryMessages(state, page, detached: false);
  } else {
    addHistoryMessages(state, page, isLive: false);
  }
  state.nextCursor = nextCursor;
}

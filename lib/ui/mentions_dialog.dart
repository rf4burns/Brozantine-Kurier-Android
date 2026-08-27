import 'package:flutter/material.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/mentions.dart';
import '../protocol/models.dart';
import '../session/session_controller.dart';
import 'shared.dart';

class MentionsDialog extends StatefulWidget {
  const MentionsDialog({super.key, required this.session});
  final SessionController session;

  @override
  State<MentionsDialog> createState() => _MentionsDialogState();
}

class _MentionsDialogState extends State<MentionsDialog> {
  SessionController get s => widget.session;

  void _jump(KurierMessage m) {
    Navigator.pop(context);
    s.jumpToMessage(m.channelId, m.id);
  }

  String _channelLabel(L10n l, KurierMessage m) {
    final channel = s.channels[m.channelId];
    if (channel == null) return '';
    if (channel.isDm) {
      final dm = s.dms.where((d) => d.channelId == channel.id).firstOrNull;
      final name = dm != null ? s.users[dm.userId]?.displayName : null;
      return name ?? channel.name;
    }
    return '#${channel.name}';
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Dialog(
      key: const ValueKey('mentions-dialog'),
      child: SizedBox(
        width: 560,
        height: 520,
        child: ListenableBuilder(
          listenable: s,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l('mentions'),
                          style: TextStyle(
                            color: context.p.foreground,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      CompactIconButton(
                        tooltip: l('close'),
                        icon: Icons.close,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l('mentionsDesc'),
                    style: TextStyle(color: context.p.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Expanded(child: _results(l)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _results(L10n l) {
    if (s.loadingMentions) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s.mentionMessages.isEmpty) {
      return EmptyHint(l('noMentions'));
    }
    return ListView.separated(
      itemCount: s.mentionMessages.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = s.mentionMessages[i];
        return _MentionResultCard(
          key: ValueKey('mention-result-${m.id}'),
          session: s,
          message: m,
          channelLabel: _channelLabel(l, m),
          onTap: () => _jump(m),
        );
      },
    );
  }
}

class _MentionResultCard extends StatelessWidget {
  const _MentionResultCard({
    super.key,
    required this.session,
    required this.message,
    required this.channelLabel,
    required this.onTap,
  });

  final SessionController session;
  final KurierMessage message;
  final String channelLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final author = resolveMessageAuthor(
      session,
      l,
      userId: message.userId,
      pluginId: message.pluginId,
    );
    final user = author.user;
    final nameColor = user != null
        ? (userRoleColor(user, session.roles) ?? context.p.foreground)
        : context.p.foreground;
    final snippet = htmlToPlainText(message.content ?? '');

    return Material(
      color: context.p.card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(
                user: user,
                session: session,
                size: 32,
                showStatus: user != null,
                imageUrl: author.imageUrl,
                fallbackName: author.name,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Text(
                          author.name,
                          style: TextStyle(
                            color: nameColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          '· ${relativeTime(message.createdAt)}',
                          style: TextStyle(
                            color: context.p.faint,
                            fontSize: 12,
                          ),
                        ),
                        if (channelLabel.isNotEmpty)
                          Text(
                            '· $channelLabel',
                            style: TextStyle(
                              color: context.p.muted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    if (snippet.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        snippet,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.p.foreground,
                          fontSize: 14,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: context.p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

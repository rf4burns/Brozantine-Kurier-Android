import 'package:flutter/material.dart';

import '../app/breakpoints.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/models.dart';
import '../session/session_controller.dart';
import 'shared.dart';

const kPinsPanelWidth = 480.0;
const kPinsPanelHeight = 480.0;

typedef PinMessageBuilder = Widget Function(KurierMessage message);

Future<void> showPinsPopover({
  required BuildContext context,
  required SessionController session,
  required int channelId,
  required Future<void> Function(int messageId) onJumpToMessage,
  required PinMessageBuilder messageBuilder,
}) {
  session.loadPinned(channelId);
  final phone =
      breakpointOf(MediaQuery.sizeOf(context).width) == Breakpoint.phone;

  if (phone) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(ctx).bottom),
        child: Material(
          color: ctx.p.sidebar,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.7,
            child: PinsPanel(
              session: session,
              messageBuilder: messageBuilder,
              onJumpToMessage: (id) async {
                Navigator.pop(ctx);
                await onJumpToMessage(id);
              },
            ),
          ),
        ),
      ),
    );
  }

  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  var origin = Offset.zero;
  var buttonSize = Size.zero;
  if (box != null && overlay != null) {
    origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    buttonSize = box.size;
  }

  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      pageBuilder: (ctx, _, _) => _PinsPopoverPage(
        origin: origin,
        buttonSize: buttonSize,
        session: session,
        messageBuilder: messageBuilder,
        onJumpToMessage: (id) async {
          Navigator.pop(ctx);
          await onJumpToMessage(id);
        },
      ),
    ),
  );
}

class _PinsPopoverPage extends StatelessWidget {
  const _PinsPopoverPage({
    required this.origin,
    required this.buttonSize,
    required this.session,
    required this.messageBuilder,
    required this.onJumpToMessage,
  });

  final Offset origin;
  final Size buttonSize;
  final SessionController session;
  final PinMessageBuilder messageBuilder;
  final Future<void> Function(int messageId) onJumpToMessage;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    var left = origin.dx + buttonSize.width - kPinsPanelWidth;
    var top = origin.dy + buttonSize.height + 8;
    if (left + kPinsPanelWidth > size.width - 8) {
      left = size.width - kPinsPanelWidth - 8;
    }
    if (left < 8) left = 8;
    if (top + 160 > size.height - pad.bottom) {
      top = origin.dy - kPinsPanelHeight - 8;
    }
    if (top < pad.top + 8) top = pad.top + 8;
    final maxH = (size.height - top - pad.bottom - 8).clamp(
      160.0,
      kPinsPanelHeight,
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: SizedBox(
              width: kPinsPanelWidth,
              height: maxH,
              child: Material(
                key: const ValueKey('pins-popover'),
                color: context.p.sidebar,
                elevation: 12,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: PinsPanel(
                  session: session,
                  messageBuilder: messageBuilder,
                  onJumpToMessage: onJumpToMessage,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PinsPanel extends StatelessWidget {
  const PinsPanel({
    super.key,
    required this.session,
    required this.messageBuilder,
    required this.onJumpToMessage,
  });

  final SessionController session;
  final PinMessageBuilder messageBuilder;
  final Future<void> Function(int messageId) onJumpToMessage;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final s = session;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Text(
                l('pins'),
                style: TextStyle(
                  color: context.p.foreground,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            Expanded(
              child: s.loadingPinned
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : s.pinned.isEmpty
                  ? EmptyHint(l('noPins'))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: s.pinned.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final m = s.pinned[i];
                        return PinnedMessageCard(
                          session: s,
                          message: m,
                          onJump: () => onJumpToMessage(m.id),
                          child: messageBuilder(m),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class PinnedMessageCard extends StatelessWidget {
  const PinnedMessageCard({
    super.key,
    required this.session,
    required this.message,
    required this.onJump,
    required this.child,
  });

  final SessionController session;
  final KurierMessage message;
  final VoidCallback onJump;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final pinner = message.pinnedBy == null
        ? null
        : session.users[message.pinnedBy!];
    final pinnerName =
        pinner != null &&
            pinner.name.isNotEmpty &&
            !KurierUser.isPlaceholderName(pinner.name)
        ? pinner.name
        : l('unknownUser');
    final pinTime = message.pinnedAt != null && message.pinnedAt! > 0
        ? relativeTime(message.pinnedAt!)
        : l('unknownTime');
    final pinTimeAbs = message.pinnedAt != null && message.pinnedAt! > 0
        ? formatAbsoluteDateTime(message.pinnedAt!)
        : '';

    return Container(
      decoration: BoxDecoration(
        color: context.p.card.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.p.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            decoration: BoxDecoration(
              color: context.p.rail.withValues(alpha: 0.35),
              border: Border(bottom: BorderSide(color: context.p.divider)),
            ),
            child: Row(
              children: [
                Icon(Icons.push_pin, size: 14, color: context.p.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l('pinnedBy', {'name': pinnerName}),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.p.muted, fontSize: 13),
                  ),
                ),
                if (pinTimeAbs.isNotEmpty)
                  Tooltip(
                    message: pinTimeAbs,
                    child: Text(
                      pinTime,
                      style: TextStyle(color: context.p.faint, fontSize: 12),
                    ),
                  )
                else
                  Text(
                    pinTime,
                    style: TextStyle(color: context.p.faint, fontSize: 12),
                  ),
                CompactIconButton(
                  key: ValueKey('pin-jump-${message.id}'),
                  tooltip: l('scrollToMessage'),
                  icon: Icons.arrow_forward,
                  iconSize: 16,
                  size: 28,
                  onPressed: onJump,
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

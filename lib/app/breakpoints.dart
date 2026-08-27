import 'dart:math' as math;

enum Breakpoint { phone, tablet, desktop }

Breakpoint breakpointOf(double width) {
  // Tailwind md / lg used by the in-tree React client and Discord web.
  if (width < 768) return Breakpoint.phone;
  if (width < 1024) return Breakpoint.tablet;
  return Breakpoint.desktop;
}

const minTap = 44.0;

/// Matches the in-tree React client (`w-[72px]`, `h-12`, default sidebar 240).
const kRailWidth = 72.0;
const kRailIcon = 48.0;
const kSidebarWidth = 240.0;
const kSidebarMinWidth = 180.0;
const kSidebarMaxWidth = 420.0;
const kMainMinWidth = 360.0;
const kResizeHandleWidth = 8.0;
const kHeaderHeight = 48.0;
const kAccountBarHeight = 56.0;

/// Overlay/vanilla channel bar: 18px hash/speaker, 34px rows (`px-2` + 7px).
const kChannelIcon = 18.0;
const kChannelListPad = 8.0;
const kChannelRowPadH = 8.0;
const kChannelRowPadV = 7.0;
const kChannelRowGap = 1.0;
const kCategoryHeaderTop = 12.0;
const kVoiceOccupantIndent = 24.0;
const kVoiceOccupantAvatar = 20.0;

/// Phone VoiceStage in-call circles and Join Voice (Discord-like tap targets).
const kVoiceCtrlBtn = 52.0;
const kVoiceCtrlIcon = 24.0;
const kVoiceJoinHeight = 52.0;
const kVoiceTileAvatarPhone = 96.0;
const kVoiceBarRadius = 16.0;

/// Vanilla `messages-group.tsx`: `h-10 w-10`, `gap-4`, `pl-4 pt-4 pr-4`.
const kMsgAvatar = 40.0;
const kMsgGutter = 16.0;
const kMsgPadH = 16.0;
const kMsgGroupTop = 16.0;
const kMsgFollowUpTop = 0.0;

/// Discord `scrollerSpacer` under the last message, above the composer.
const kMsgScrollerSpacer = 24.0;
const kCompactBtn = 32.0;

/// Shrinks stored sidebar widths so the center column stays at least
/// [kMainMinWidth] when the window is too narrow.
({double sidebar, double members}) fitPanelWidths({
  required double windowWidth,
  required double sidebarWidth,
  required double membersWidth,
  required bool showMembers,
}) {
  var side = sidebarWidth.clamp(kSidebarMinWidth, kSidebarMaxWidth).toDouble();
  var mem = membersWidth.clamp(kSidebarMinWidth, kSidebarMaxWidth).toDouble();
  final handles = kResizeHandleWidth + (showMembers ? kResizeHandleWidth : 0.0);
  var leftover =
      windowWidth - kRailWidth - side - handles - (showMembers ? mem : 0.0);
  if (leftover >= kMainMinWidth) {
    return (sidebar: side, members: mem);
  }
  var deficit = kMainMinWidth - leftover;
  if (showMembers) {
    final take = math.min(deficit, mem - kSidebarMinWidth);
    if (take > 0) {
      mem -= take;
      deficit -= take;
    }
  }
  if (deficit > 0) {
    final take = math.min(deficit, side - kSidebarMinWidth);
    if (take > 0) side -= take;
  }
  return (sidebar: side, members: mem);
}

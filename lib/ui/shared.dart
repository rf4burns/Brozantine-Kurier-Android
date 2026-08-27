import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/breakpoints.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/config.dart';
import '../protocol/models.dart';
import '../session/message_history.dart';
import '../session/session_controller.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    required this.session,
    this.size = 32,
    this.showStatus = true,
    this.speakingIntensity = 0,
    this.statusBorderColor,
    this.imageUrl,
    this.fallbackName,
  });

  final KurierUser? user;
  final SessionController session;
  final double size;
  final bool showStatus;
  final int speakingIntensity;
  final Color? statusBorderColor;
  final String? imageUrl;
  final String? fallbackName;

  static const _quiet = Color(0xFF86EFAC);
  static const _normal = Color(0xFF22C55E);
  static const _loud = Color(0xFF16A34A);

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final override = imageUrl?.trim();
    final url = (override != null && override.isNotEmpty)
        ? override
        : (user?.avatar != null ? session.fileUrl(user!.avatar!) : null);
    Color status;
    switch (user?.status) {
      case 'online':
        status = p.online;
      case 'idle':
        status = p.idle;
      case 'dnd':
        status = p.dnd;
      default:
        status = p.offline;
    }
    final ring = speakingIntensity > 0;
    final ringColor = speakingIntensity >= 3
        ? _loud
        : speakingIntensity >= 2
        ? _normal
        : _quiet;
    final ringWidth = speakingIntensity >= 3
        ? 3.0
        : speakingIntensity >= 2
        ? 2.0
        : 1.5;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          if (ring)
            Positioned(
              left: -ringWidth,
              top: -ringWidth,
              right: -ringWidth,
              bottom: -ringWidth,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: user != null ? ValueKey('speaking-${user!.id}') : null,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ringColor, width: ringWidth),
                    boxShadow: [
                      BoxShadow(
                        color: ringColor.withValues(
                          alpha: speakingIntensity >= 3 ? 0.7 : 0.45,
                        ),
                        blurRadius: speakingIntensity >= 3
                            ? 10
                            : speakingIntensity >= 2
                            ? 7
                            : 4,
                        spreadRadius: speakingIntensity >= 3 ? 2 : 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: url != null
                ? Image.network(
                    url,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _fallback(p),
                  )
                : _fallback(p),
          ),
          if (showStatus)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.32,
                height: size * 0.32,
                decoration: BoxDecoration(
                  color: status,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: statusBorderColor ?? p.sidebar,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallback(Palette p) {
    final fromUser = user?.displayName;
    final fromFallback = fallbackName?.trim();
    final letter =
        (fromUser != null && fromUser.isNotEmpty
                ? fromUser[0]
                : (fromFallback != null && fromFallback.isNotEmpty
                      ? fromFallback[0]
                      : '?'))
            .toUpperCase();
    Color color;
    try {
      color = Color(
        int.parse(
          (user?.profileColor ?? '#5865F2').replaceFirst('#', 'FF'),
          radix: 16,
        ),
      );
    } catch (_) {
      color = const Color(0xFF5865F2);
    }
    return Container(
      width: size,
      height: size,
      color: color,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

const kVoiceLive = Color(0xFF23A55A);

String formatElapsed(int startedAtMs, [int? nowMs]) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final total = ((now - startedAtMs) / 1000).floor();
  final safe = total < 0 ? 0 : total;
  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final seconds = safe % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
  return '$minutes:${two(seconds)}';
}

class ElapsedTime extends StatelessWidget {
  const ElapsedTime({super.key, required this.startedAt, this.style});
  final int startedAt;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (startedAt <= 0) return const SizedBox.shrink();
    return Text(
      formatElapsed(startedAt),
      style: (style ?? TextStyle(color: context.p.muted, fontSize: 10))
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    super.key,
    this.color,
    this.size = 16,
    this.screenSharing = false,
  });

  final Color? color;
  final double size;
  final bool screenSharing;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.p.muted;
    if (screenSharing) {
      return Icon(Icons.visibility, size: size, color: c);
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _WaveformPainter(c)),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    const heights = [0.42, 0.67, 0.5, 0.83, 0.42];
    final barW = size.width / 11;
    for (var i = 0; i < heights.length; i++) {
      final h = size.height * heights[i];
      final x = barW + i * (barW * 2);
      final y = (size.height - h) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, h),
          const Radius.circular(1),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => old.color != color;
}

class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count, this.mention = false});
  final int count;
  final bool mention;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: mention ? context.k.accent : context.p.dnd,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class KurierButton extends StatelessWidget {
  const KurierButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
    this.danger = false,
    this.outline = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    if (outline) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minTap),
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: context.p.foreground,
            side: BorderSide(color: context.p.divider),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(label),
        ),
      );
    }
    final bg = danger
        ? context.p.dnd
        : primary
        ? context.k.accent
        : context.p.card;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minTap),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label),
      ),
    );
  }
}

class CompactIconButton extends StatelessWidget {
  const CompactIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.background,
    this.size = kCompactBtn,
    this.iconSize = 18,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final Color? background;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: size,
      height: size,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          minimumSize: Size(size, size),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, size: iconSize, color: color ?? context.p.muted),
      ),
    );
    if (background == null) return button;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(6),
      child: button,
    );
  }
}

class KurierField extends StatelessWidget {
  const KurierField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.obscure = false,
    this.onSubmitted,
    this.onChanged,
    this.maxLines = 1,
    this.maxLength,
    this.prefix,
    this.dense = false,
    this.focusNode,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final bool obscure;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final int? maxLength;
  final Widget? prefix;
  final bool dense;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      maxLines: maxLines,
      maxLength: maxLength,
      maxLengthEnforcement: maxLength != null
          ? MaxLengthEnforcement.enforced
          : MaxLengthEnforcement.none,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      style: TextStyle(color: context.p.foreground, fontSize: dense ? 15 : 16),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: context.p.faint, fontSize: dense ? 15 : 16),
        prefixIcon: prefix,
        isDense: dense,
        filled: true,
        fillColor: context.p.rail,
        counterText: maxLength != null ? '' : null,
        contentPadding: dense
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: dense
              ? BorderSide.none
              : BorderSide(color: context.p.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: dense
              ? BorderSide.none
              : BorderSide(color: context.p.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: dense
              ? BorderSide.none
              : BorderSide(color: context.k.accent),
        ),
      ),
    );
  }
}

String formatAbsoluteDateTime(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  var hour = d.hour;
  final ampm = hour >= 12 ? 'PM' : 'AM';
  hour = hour % 12;
  if (hour == 0) hour = 12;
  final min = d.minute.toString().padLeft(2, '0');
  final sec = d.second.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day}, ${d.year}, $hour:$min:$sec $ampm';
}

String relativeTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) {
    final n = diff.inMinutes.clamp(1, 59);
    return n == 1 ? 'a minute ago' : '$n minutes ago';
  }
  if (diff.inHours < 24) {
    final n = diff.inHours;
    return n == 1 ? 'about 1 hour ago' : 'about $n hours ago';
  }
  if (diff.inDays < 7) {
    final n = diff.inDays;
    return n == 1 ? 'yesterday' : '$n days ago';
  }
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Discord/date-fns `formatDistanceToNow` style used in the member menu.
String compactRelativeTime(int ms) {
  if (ms <= 0) return '';
  final diff = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(ms),
  );
  if (diff.isNegative || diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) {
    final n = diff.inMinutes.clamp(1, 59);
    return n == 1 ? '1 minute ago' : '$n minutes ago';
  }
  if (diff.inHours < 24) {
    final n = diff.inHours;
    return n == 1 ? '1 hour ago' : '$n hours ago';
  }
  if (diff.inDays < 30) {
    final n = diff.inDays;
    return n == 1 ? '1 day ago' : '$n days ago';
  }
  final months = (diff.inDays / 30).floor();
  if (months < 12) {
    return months == 1 ? '1 month ago' : '$months months ago';
  }
  final years = (diff.inDays / 365).floor().clamp(1, 1000);
  return years == 1 ? '1 year ago' : '$years years ago';
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var n = bytes.toDouble();
  var i = 0;
  while (n >= 1024 && i < units.length - 1) {
    n /= 1024;
    i++;
  }
  if (i == 0) return '$bytes B';
  final s = n >= 10 ? n.toStringAsFixed(1) : n.toStringAsFixed(2);
  return '$s ${units[i]}';
}

class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.role});
  final KurierRole role;

  @override
  Widget build(BuildContext context) {
    final color = parseHexColor(role.color) ?? context.p.muted;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        role.name,
        style: TextStyle(color: color, fontSize: 12, height: 1.1),
      ),
    );
  }
}

class EmptyHint extends StatelessWidget {
  const EmptyHint(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, style: TextStyle(color: context.p.muted)),
      ),
    );
  }
}

/// Owner and the default role (@everyone / Untrusted) never appear as
/// member-list groups. Name colours still use the default role when it
/// has a real colour.
bool isMemberListRole(KurierRole role) =>
    role.id != AppConfig.ownerRoleId && !role.isDefault;

Color? parseHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) {
    h = '${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}';
  }
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  try {
    final n = int.parse(h, radix: 16);
    final rgb = n & 0x00FFFFFF;
    // Discord-style: white and 0 mean "no colour".
    if (rgb == 0x00FFFFFF || rgb == 0) return null;
    return Color(n);
  } catch (_) {
    return null;
  }
}

int _compareRoleRank(KurierRole a, KurierRole b) {
  final byPos = b.position.compareTo(a.position);
  return byPos != 0 ? byPos : a.id.compareTo(b.id);
}

KurierRole? displayRole(
  KurierUser user,
  Map<int, KurierRole> roles, {
  bool hoistedOnly = false,
}) {
  final list =
      user.roleIds
          .map((id) => roles[id])
          .whereType<KurierRole>()
          .where(isMemberListRole)
          .where((r) => !hoistedOnly || r.hoist)
          .toList()
        ..sort(_compareRoleRank);
  return list.isEmpty ? null : list.first;
}

Color? userRoleColor(KurierUser user, Map<int, KurierRole> roles) {
  final list =
      user.roleIds
          .map((id) => roles[id])
          .whereType<KurierRole>()
          .where((r) => r.id != AppConfig.ownerRoleId)
          .toList()
        ..sort(_compareRoleRank);
  for (final role in list) {
    final color = parseHexColor(role.color);
    if (color != null) return color;
  }
  return null;
}

class MessageAuthor {
  const MessageAuthor({
    required this.name,
    this.user,
    this.imageUrl,
    this.isPlugin = false,
    this.isSystem = false,
  });

  final String name;
  final KurierUser? user;
  final String? imageUrl;
  final bool isPlugin;
  final bool isSystem;
}

Map<String, dynamic>? pluginMetadataFor(
  SessionController session,
  String? pluginId,
) {
  if (pluginId == null || pluginId.isEmpty) return null;
  for (final raw in session.pluginsMetadata) {
    if (raw is! Map) continue;
    final map = Map<String, dynamic>.from(raw);
    final id = '${map['pluginId'] ?? map['id'] ?? ''}';
    if (id == pluginId) return map;
  }
  return null;
}

MessageAuthor resolveMessageAuthor(
  SessionController session,
  L10n l, {
  int? userId,
  String? pluginId,
}) {
  final plugin = pluginMetadataFor(session, pluginId);
  if (plugin != null) {
    final rawName = '${plugin['name'] ?? pluginId ?? ''}'.trim();
    final avatar = '${plugin['avatarUrl'] ?? ''}'.trim();
    return MessageAuthor(
      name: rawName.isEmpty ? 'Unknown Plugin' : rawName,
      imageUrl: avatar.isEmpty ? null : avatar,
      isPlugin: true,
    );
  }

  final user = userId != null ? session.users[userId] : null;
  if (user != null) {
    return MessageAuthor(name: user.displayName, user: user);
  }

  final isPluginMessage = pluginId != null && pluginId.isNotEmpty;
  if (userId == null && !isPluginMessage) {
    final serverName = session.serverName.trim();
    final name = serverName.isNotEmpty
        ? l('serverBot', {'name': serverName})
        : l('system');
    final logo = session.info?.logo;
    final url = logo != null ? session.fileUrl(logo) : '';
    return MessageAuthor(
      name: name,
      imageUrl: url.isEmpty ? null : url,
      isSystem: true,
    );
  }

  return MessageAuthor(name: l('unknownUser'), isPlugin: isPluginMessage);
}

bool messagesShareAuthor(KurierMessage a, KurierMessage b) {
  return a.userId == b.userId && (a.pluginId ?? '') == (b.pluginId ?? '');
}

/// Vanilla `useGroupedMessages`: same author, under 1 minute, no inline replies.
bool messagesFormGroup(KurierMessage prev, KurierMessage next) {
  if (prev.replyToMessageId != null || next.replyToMessageId != null) {
    return false;
  }
  if (!messagesShareAuthor(prev, next)) return false;
  return (next.createdAt - prev.createdAt).abs() < kMessageGroupWindowMs;
}

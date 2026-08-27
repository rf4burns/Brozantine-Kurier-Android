import 'package:flutter/material.dart';

import '../app/breakpoints.dart';
import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/voice_stats.dart';
import '../session/session_controller.dart';
import 'shared.dart';

const kTransportStatsWidth = 288.0;

const _hardwareEncoders = [
  'external',
  'hardware',
  'nvenc',
  'vaapi',
  'videotoolbox',
  'qsv',
  'amf',
  'mediacodec',
];

const _softwareEncoders = ['libvpx', 'openh264', 'libaom', 'software'];

Color voicePingColor(int ms) {
  if (ms < 75) return const Color(0xFF23A55A);
  if (ms < 150) return const Color(0xFFF0B232);
  return const Color(0xFFED4245);
}

Future<void> showTransportStatsPopover({
  required BuildContext context,
  required SessionController session,
}) {
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
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
            ),
            child: SingleChildScrollView(
              child: TransportStatsPanel(session: session),
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
      pageBuilder: (ctx, _, _) => _TransportStatsPopoverPage(
        origin: origin,
        buttonSize: buttonSize,
        session: session,
      ),
    ),
  );
}

class _TransportStatsPopoverPage extends StatelessWidget {
  const _TransportStatsPopoverPage({
    required this.origin,
    required this.buttonSize,
    required this.session,
  });

  final Offset origin;
  final Size buttonSize;
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    const estimatedHeight = 280.0;
    var left = origin.dx;
    var top = origin.dy - estimatedHeight - 8;
    if (left + kTransportStatsWidth > size.width - 8) {
      left = size.width - kTransportStatsWidth - 8;
    }
    if (left < 8) left = 8;
    if (top < pad.top + 8) {
      top = origin.dy + buttonSize.height + 8;
    }
    final maxH = (size.height - top - pad.bottom - 8).clamp(160.0, 480.0);

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
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: kTransportStatsWidth,
                maxHeight: maxH,
              ),
              child: Material(
                color: context.p.sidebar,
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  child: TransportStatsPanel(session: session),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TransportStatsPanel extends StatelessWidget {
  const TransportStatsPanel({super.key, required this.session});
  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final l = L10n.of(context);
        final stats = session.transportStats;
        final producer = stats.producer;
        final consumer = stats.consumer;
        final screen = stats.screenShare;
        final noise = session.store.noiseSuppression;
        final hasNoise = noise != 'none';
        return Padding(
          padding: const EdgeInsets.all(12),
          child: DefaultTextStyle(
            style: TextStyle(color: context.p.foreground, fontSize: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l('transportStats'),
                  style: TextStyle(
                    color: context.p.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _column(
                        context,
                        title: l('outgoing'),
                        titleColor: const Color(0xFF4ADE80),
                        child: producer == null
                            ? Text(
                                l('noData'),
                                style: TextStyle(color: context.p.muted),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _line(
                                    context,
                                    l(
                                      'rate',
                                      {
                                        'rate': formatBytes(
                                          stats.currentBitrateSent.round(),
                                        ),
                                      },
                                    ),
                                  ),
                                  _line(
                                    context,
                                    l(
                                      'packets',
                                      {
                                        'packets':
                                            '${producer.packetsSent.round()}',
                                      },
                                    ),
                                  ),
                                  _line(
                                    context,
                                    l(
                                      'rtt',
                                      {'rtt': producer.rtt.toStringAsFixed(1)},
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _column(
                        context,
                        title: l('incoming'),
                        titleColor: const Color(0xFF22D3EE),
                        child: consumer == null
                            ? Text(
                                l('noRemoteStreams'),
                                style: TextStyle(color: context.p.muted),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _line(
                                    context,
                                    l(
                                      'rate',
                                      {
                                        'rate': formatBytes(
                                          stats.currentBitrateReceived.round(),
                                        ),
                                      },
                                    ),
                                  ),
                                  _line(
                                    context,
                                    l(
                                      'packets',
                                      {
                                        'packets':
                                            '${consumer.packetsReceived.round()}',
                                      },
                                    ),
                                  ),
                                  if (consumer.packetsLost > 0)
                                    _line(
                                      context,
                                      l(
                                        'packetsLost',
                                        {
                                          'lost':
                                              '${consumer.packetsLost.round()}',
                                        },
                                      ),
                                      valueColor: const Color(0xFFF87171),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
                if (hasNoise) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: context.p.divider),
                  const SizedBox(height: 8),
                  _column(
                    context,
                    title: l('transportMic'),
                    titleColor: const Color(0xFFC084FC),
                    child: _line(
                      context,
                      '${l('noiseSuppression')}: ${noise == 'standard' ? l('noiseStandard') : l('noiseNone')}',
                    ),
                  ),
                ],
                if (screen != null) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: context.p.divider),
                  const SizedBox(height: 8),
                  _ScreenShareStats(screen: screen),
                ],
                const SizedBox(height: 10),
                Divider(height: 1, color: context.p.divider),
                const SizedBox(height: 8),
                Text(
                  l('sessionTotals'),
                  style: const TextStyle(
                    color: Color(0xFFFACC15),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '↑ ${formatBytes(stats.totalBytesSent.round())}',
                        style: TextStyle(color: context.p.muted, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '↓ ${formatBytes(stats.totalBytesReceived.round())}',
                        style: TextStyle(color: context.p.muted, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _column(
    BuildContext context, {
    required String title,
    required Color titleColor,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: titleColor,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _ScreenShareStats extends StatefulWidget {
  const _ScreenShareStats({required this.screen});
  final ScreenShareTransportStats screen;

  @override
  State<_ScreenShareStats> createState() => _ScreenShareStatsState();
}

class _ScreenShareStatsState extends State<_ScreenShareStats> {
  bool _showLayers = false;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final screen = widget.screen;
    final codec = _codecLabel(screen.codec);
    final encoder = _encoderInfo(l, screen.encoderImplementation);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l('shareScreen'),
          style: const TextStyle(
            color: Color(0xFF60A5FA),
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        if (codec.isNotEmpty)
          _line(context, l('codec', {'codec': codec})),
        if (encoder != null)
          _line(context, '${l('encoder')}: ${encoder.label}', valueColor: encoder.color),
        _line(
          context,
          l(
            'resolution',
            {
              'width': '${screen.width.round()}',
              'height': '${screen.height.round()}',
            },
          ),
        ),
        _line(
          context,
          l('frameRate', {'fps': '${screen.frameRate.round()}'}),
        ),
        _line(
          context,
          l(
            'bitrate',
            {'bitrate': formatBytes(screen.bitrate.round())},
          ),
        ),
        if (screen.simulcast && screen.layers.length > 1) ...[
          GestureDetector(
            onTap: () => setState(() => _showLayers = !_showLayers),
            child: _line(
              context,
              l('simulcastLayers', {'count': '${screen.layers.length}'}),
            ),
          ),
          if (_showLayers)
            for (var i = 0; i < screen.layers.length; i++)
              _layerCard(context, l, screen.layers[i], i),
        ],
        _line(
          context,
          l(
            'framesEncoded',
            {'frames': '${screen.framesEncoded.round()}'},
          ),
        ),
        if (screen.qualityLimitationReason != 'none')
          _line(
            context,
            l('qualityLimited', {'reason': screen.qualityLimitationReason}),
            valueColor: const Color(0xFFFACC15),
          ),
      ],
    );
  }

  Widget _layerCard(
    BuildContext context,
    L10n l,
    ScreenShareLayerStats layer,
    int index,
  ) {
    final codec = _codecLabel(layer.codec);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: context.p.divider),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${l('simulcastLayer', {'layer': layer.rid.isNotEmpty ? layer.rid : '${index + 1}'})}${codec.isNotEmpty ? ' ($codec)' : ''}',
            style: TextStyle(
              color: context.p.foreground,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          _line(
            context,
            l(
              'resolution',
              {
                'width': '${layer.width.round()}',
                'height': '${layer.height.round()}',
              },
            ),
          ),
          _line(
            context,
            l('frameRate', {'fps': '${layer.frameRate.round()}'}),
          ),
          _line(
            context,
            l('bitrate', {'bitrate': formatBytes(layer.bitrate.round())}),
          ),
          _line(
            context,
            l('packets', {'packets': '${layer.packetsSent.round()}'}),
          ),
          if (layer.qualityLimitationReason != 'none')
            _line(
              context,
              l('qualityLimited', {'reason': layer.qualityLimitationReason}),
              valueColor: const Color(0xFFFACC15),
            ),
        ],
      ),
    );
  }
}

class _EncoderInfo {
  const _EncoderInfo(this.label, this.color);
  final String label;
  final Color? color;
}

_EncoderInfo? _encoderInfo(L10n l, String implementation) {
  if (implementation.isEmpty) return null;
  final lower = implementation.toLowerCase();
  if (_hardwareEncoders.any(lower.contains)) {
    return _EncoderInfo(
      l('gpuEncoder', {'encoder': implementation}),
      const Color(0xFF4ADE80),
    );
  }
  if (_softwareEncoders.any(lower.contains)) {
    return _EncoderInfo(
      l('cpuEncoder', {'encoder': implementation}),
      const Color(0xFFFACC15),
    );
  }
  return _EncoderInfo(l('unknownEncoder', {'encoder': implementation}), null);
}

String _codecLabel(String codec) {
  final parts = codec.split('/');
  return parts.length > 1 ? parts[1] : codec;
}

Widget _line(BuildContext context, String text, {Color? valueColor}) {
  final idx = text.indexOf(':');
  if (idx <= 0 || idx == text.length - 1) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(text, style: TextStyle(color: context.p.muted, fontSize: 12)),
    );
  }
  return Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${text.substring(0, idx)}: ',
            style: TextStyle(color: context.p.muted, fontSize: 12),
          ),
          TextSpan(
            text: text.substring(idx + 1).trim(),
            style: TextStyle(
              color: valueColor ?? context.p.foreground,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}

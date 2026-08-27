import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'attachment_media_stub.dart'
    if (dart.library.js_interop) 'attachment_media_web.dart' as impl;

Key videoAttachmentKey(String id) => Key('video-attachment-$id');

Key audioAttachmentKey(String id) => Key('audio-attachment-$id');

const kAttachmentMediaMaxWidth = 400.0;
const kAttachmentVideoMaxHeight = 300.0;
const kAttachmentAudioHeight = 48.0;

String attachmentMediaIdFor({required int fileId, required String name}) {
  if (fileId != 0) return '$fileId';
  return name;
}

/// In-chat video player. Fills the message column up to [kAttachmentMediaMaxWidth]
/// so phone overlay and desktop share the same embed.
class AttachmentVideoPlayer extends StatelessWidget {
  const AttachmentVideoPlayer({
    super.key,
    required this.url,
    required this.id,
  });

  final String url;
  final String id;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          key: videoAttachmentKey(id),
          constraints: const BoxConstraints(
            maxWidth: kAttachmentMediaMaxWidth,
            maxHeight: kAttachmentVideoMaxHeight,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: impl.attachmentVideoView(url: url, viewKey: id),
            ),
          ),
        ),
      ),
    );
  }
}

/// In-chat audio player with optional filename label.
class AttachmentAudioPlayer extends StatelessWidget {
  const AttachmentAudioPlayer({
    super.key,
    required this.url,
    required this.id,
    this.label,
  });

  final String url;
  final String id;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final name = label?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          key: audioAttachmentKey(id),
          constraints: const BoxConstraints(maxWidth: kAttachmentMediaMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.p.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              SizedBox(
                height: kAttachmentAudioHeight,
                width: double.infinity,
                child: impl.attachmentAudioView(url: url, viewKey: id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

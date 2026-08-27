import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurier_web/app/l10n_tables.dart';
import 'package:kurier_web/core/custom_emoji.dart';
import 'package:kurier_web/core/emoji_codec.dart';
import 'package:kurier_web/protocol/activity_log.dart';
import 'package:kurier_web/protocol/config.dart';
import 'package:kurier_web/protocol/mentions.dart';
import 'package:kurier_web/protocol/models.dart';
import 'package:kurier_web/protocol/permissions.dart';
import 'package:kurier_web/protocol/search_query.dart';
import 'package:kurier_web/protocol/trpc_client.dart';
import 'package:kurier_web/protocol/voice_protocol.dart';
import 'package:kurier_web/protocol/voice_stats.dart';
import 'package:kurier_web/session/message_history.dart';
import 'package:kurier_web/session/session_controller.dart';
import 'package:kurier_web/ui/shared.dart';
import 'package:kurier_web/ui/message_embeds.dart';
import 'package:kurier_web/ui/message_html.dart';
import 'package:kurier_web/ui/reactions_viewer.dart';
import 'package:kurier_web/ui/server_settings.dart';

void main() {
  group('search query', () {
    test('parses operators', () {
      final q = parseSearchQuery(
        'hello from:gordon in:#general has:image pinned:true',
      );
      expect(q.text, 'hello');
      expect(q.from, 'gordon');
      expect(q.inChannel, 'general');
      expect(q.has, 'image');
      expect(q.pinned, true);
      expect(isValidSearchQuery(q), isTrue);
    });

    test('requires text or filters', () {
      expect(isValidSearchQuery(parseSearchQuery('a')), isFalse);
      expect(isValidSearchQuery(parseSearchQuery('ab')), isTrue);
      expect(isValidSearchQuery(parseSearchQuery('from:x')), isTrue);
    });

    test('round-trips serialize', () {
      final q = parseSearchQuery('from:"Ada Lovelace" after:2024-01-02 hi');
      final s = serializeSearchQuery(q);
      final again = parseSearchQuery(s);
      expect(again.from, 'Ada Lovelace');
      expect(again.text, 'hi');
    });

    test('suggests operators from an empty or prefix token', () {
      expect(matchingSearchOperators(''), containsAll(searchOperatorKeys));
      expect(matchingSearchOperators('fr'), ['from']);
      expect(matchingSearchOperators('from:'), isEmpty);
      expect(matchingSearchOperators('hello'), isEmpty);
    });

    test('hides operators already applied', () {
      expect(matchingSearchOperators('from:Ada '), isNot(contains('from')));
      expect(matchingSearchOperators('from:Ada '), contains('in'));
    });

    test('replaces the active token', () {
      expect(replaceActiveSearchToken('fr', 'from:'), 'from:');
      expect(
        replaceActiveSearchToken('hello ', 'from:', trailingSpace: false),
        'hello from:',
      );
      expect(
        replaceActiveSearchToken('from:', 'from:Ada', trailingSpace: true),
        'from:Ada ',
      );
    });

    test('reads the active operator value', () {
      expect(activeSearchToken('from:').key, 'from');
      expect(activeSearchToken('from:').value, '');
      expect(activeSearchToken('from:"Ada L"').value, 'Ada L');
      expect(activeSearchToken('in:#gen').value, '#gen');
    });
  });

  group('mentions', () {
    test('detects user mention', () {
      const html =
          '<p>hi <span data-type="mention" data-user-id="7">@ada</span></p>';
      expect(hasUserMention(html, 7), isTrue);
      expect(hasMention(html, 7), isTrue);
      expect(hasMention(html, 8), isFalse);
    });

    test('detects everyone and here', () {
      const everyone =
          '<span data-type="mention" data-mention-kind="everyone">@everyone</span>';
      const here =
          '<span data-mention-kind="here" data-type="mention">@here</span>';
      expect(hasEveryoneMention(everyone), isTrue);
      expect(hasHereMention(here), isTrue);
      expect(hasMention(here, 1, isOnline: false), isFalse);
      expect(hasMention(here, 1, isOnline: true), isTrue);
    });
  });

  group('tRPC keepalive', () {
    test('builds tRPC websocket URL with connectionParams', () {
      expect(
        trpcWsUrl('https://sharkord.brozantine.com').toString(),
        'wss://sharkord.brozantine.com?connectionParams=1',
      );
      expect(
        trpcWsUrl('http://localhost:4991').toString(),
        'ws://localhost:4991?connectionParams=1',
      );
    });

    test('replies to PING frames', () {
      expect(keepAliveReply('PING'), 'PONG');
      expect(keepAliveReply('ping'), 'pong');
      expect(keepAliveReply('{"id":1}'), isNull);
    });
  });

  group('i18n', () {
    test('every locale covers English keys', () {
      for (final entry in l10nTables.entries) {
        expect(
          entry.value.keys.toSet(),
          l10nEn.keys.toSet(),
          reason: '${entry.key} is missing or has extra keys',
        );
      }
    });
  });

  group('voice protocol', () {
    test('unwraps router RTP capabilities', () {
      final caps = routerRtpCapabilitiesOf({
        'routerRtpCapabilities': {
          'codecs': [
            {'mimeType': 'audio/opus'},
          ],
          'headerExtensions': const [],
        },
      });
      expect(caps?['codecs'], isNotEmpty);
    });

    test('unwraps superjson-shaped payloads', () {
      final caps = routerRtpCapabilitiesOf({
        'json': {
          'routerRtpCapabilities': {
            'codecs': [
              {'mimeType': 'audio/opus'},
            ],
          },
        },
        'meta': const {},
      });
      expect(caps?['codecs'], isNotEmpty);
    });

    test('detects already-in-voice and rate-limit errors', () {
      expect(
        isAlreadyInVoiceError(Exception('User already in a voice channel')),
        isTrue,
      );
      expect(
        isVoiceJoinRateLimited('Too many requests. Please try again shortly.'),
        isTrue,
      );
    });

    test('unpacks voice engine envelopes', () {
      expect(unpackVoiceEngineResult('{"ok":true,"v":"abc"}'), 'abc');
      expect(unpackVoiceEngineResult('plain'), 'plain');
      expect(
        () => unpackVoiceEngineResult('{"ok":false,"v":"no mic"}'),
        throwsA(
          isA<StateError>().having((e) => e.message, 'message', 'no mic'),
        ),
      );
      const caps = '{"codecs":[{"mimeType":"audio/opus"}]}';
      expect(
        unpackVoiceEngineResult('{"ok":true,"v":${jsonEncode(caps)}}'),
        caps,
      );
    });

    test('maps speaking meter keys to user ids', () {
      expect(speakingUserIdFromKey('local', 7), 7);
      expect(speakingUserIdFromKey('12:audio', 7), 12);
      expect(speakingUserIdFromKey('9:external_audio', 7), 9);
      expect(speakingUserIdFromKey('12:video', 7), isNull);
      expect(speakingUserIdFromKey('12:screen', 7), isNull);
      expect(speakingUserIdFromKey('12:screen_audio', 7), isNull);
      expect(speakingIntensityFromJson({'intensity': 2}), 2);
      expect(speakingIntensityFromJson({'intensity': 9}), 3);
      expect(speakingIntensityFromJson({'intensity': -1}), 0);
    });

    test('reads voice event user ids from userId or remoteId', () {
      expect(voiceEventUserId({'userId': 12}), 12);
      expect(voiceEventUserId({'remoteId': 9}), 9);
      expect(voiceEventUserId({'userId': 12, 'remoteId': 9}), 12);
      expect(voiceEventUserId({'userId': '4'}), 4);
      expect(voiceEventUserId({}), isNull);
    });

    test('treats screen and external audio as playback streams', () {
      expect(StreamKind.isPlaybackStream(StreamKind.screenAudio), isTrue);
      expect(StreamKind.isPlaybackStream(StreamKind.externalAudio), isTrue);
      expect(StreamKind.isPlaybackStream(StreamKind.audio), isFalse);
      expect(StreamKind.isPlaybackStream(StreamKind.video), isFalse);
      expect(StreamKind.isPlaybackStream(StreamKind.screen), isFalse);
    });

    test('client-mutes music-bot audio until the user unmutes', () {
      expect(
        StreamKind.startsClientMuted(StreamKind.externalAudio, watching: false),
        isTrue,
      );
      expect(
        StreamKind.startsClientMuted(StreamKind.externalAudio, watching: true),
        isTrue,
      );
      expect(
        StreamKind.startsClientMuted(StreamKind.screenAudio, watching: false),
        isTrue,
      );
      expect(
        StreamKind.startsClientMuted(StreamKind.screenAudio, watching: true),
        isFalse,
      );
      expect(
        StreamKind.startsClientMuted(StreamKind.audio, watching: true),
        isFalse,
      );
    });

    test('auto-consumes voice and camera but not screen or external', () {
      expect(StreamKind.shouldAutoConsume(StreamKind.audio), isTrue);
      expect(StreamKind.shouldAutoConsume(StreamKind.video), isTrue);
      expect(StreamKind.shouldAutoConsume(StreamKind.screen), isFalse);
      expect(StreamKind.shouldAutoConsume(StreamKind.screenAudio), isFalse);
      expect(StreamKind.shouldAutoConsume(StreamKind.externalVideo), isFalse);
      expect(StreamKind.shouldAutoConsume(StreamKind.externalAudio), isFalse);
    });

    test('builds watch keys and flags external kinds', () {
      expect(StreamKind.watchKey(12, external: false), '12:screen');
      expect(StreamKind.watchKey(8, external: true), '8:external');
      expect(StreamKind.isExternal(StreamKind.externalVideo), isTrue);
      expect(StreamKind.isExternal(StreamKind.externalAudio), isTrue);
      expect(StreamKind.isExternal(StreamKind.screen), isFalse);
    });
  });

  group('message html', () {
    test('collapses paragraph tags into compact plain text', () {
      const html = '<p>yes i can</p><p>i am m</p><p>use the vanilla link</p>';
      final spans = messageHtmlSpans(
        html,
        color: const Color(0xFFFFFFFF),
        linkColor: const Color(0xFF5865F2),
      );
      final text = spans
          .map((s) => s is TextSpan ? s.toPlainText() : '')
          .join();
      expect(text, 'yes i can\ni am m\nuse the vanilla link');
    });

    test('turns typed newlines into br tags', () {
      expect(textToMessageHtml('hello\n\nworld'), '<p>hello<br><br>world</p>');
      expect(
        textToMessageHtml('hello\r\n\r\nworld'),
        '<p>hello<br><br>world</p>',
      );
    });

    test('preserves blank lines from consecutive br tags', () {
      const html = '<p>hello<br><br>world</p>';
      final spans = messageHtmlSpans(
        html,
        color: const Color(0xFFFFFFFF),
        linkColor: const Color(0xFF5865F2),
      );
      final text = spans
          .map((s) => s is TextSpan ? s.toPlainText() : '')
          .join();
      expect(text, 'hello\n\nworld');
    });

    test('keeps links and mentions', () {
      const html =
          '<p>hi <span data-type="mention" data-user-id="7">@ada</span> '
          '<a href="https://sharkord.brozantine.com/vanilla">vanilla</a></p>';
      final spans = messageHtmlSpans(
        html,
        color: const Color(0xFFFFFFFF),
        linkColor: const Color(0xFF5865F2),
        mentionBg: const Color(0x1A5865F2),
      );
      final text = spans
          .map((s) => s is TextSpan ? s.toPlainText() : '')
          .join();
      expect(text, contains('@ada'));
      expect(text, contains('vanilla'));
      final mention = spans.whereType<TextSpan>().firstWhere(
        (s) => (s.text ?? '').contains('@ada'),
      );
      expect(mention.style?.backgroundColor, const Color(0x1A5865F2));
      expect(mention.style?.color, const Color(0xFF5865F2));
      final link = spans.whereType<TextSpan>().firstWhere(
        (s) => (s.text ?? '').contains('vanilla'),
      );
      expect(link.style?.decoration, TextDecoration.underline);
    });

    test('turns unicode emoji and custom img into widget spans', () {
      const html =
          '<p>hi 👍 <img src="https://cdn.example/e.png" class="emoji-image" alt=":blob:" /></p>';
      final spans = messageHtmlSpans(
        html,
        color: const Color(0xFFFFFFFF),
        linkColor: const Color(0xFF5865F2),
      );
      expect(spans.whereType<WidgetSpan>(), isNotEmpty);
      final text = spans
          .map((s) => s is TextSpan ? s.toPlainText() : '')
          .join();
      expect(text, contains('hi'));
    });
  });

  group('emoji codec', () {
    test('encodes unicode reactions as github shortcodes', () {
      expect(EmojiCodec.encodeReactionKey('👍', const []), '+1');
      expect(EmojiCodec.encodeReactionKey('😂', const []), 'joy');
      expect(EmojiCodec.encodeReactionKey(':thumbsup:', const []), '+1');
    });

    test('keeps custom emoji names', () {
      const custom = [CustomEmoji(name: 'blob', url: 'https://x/e.png')];
      expect(EmojiCodec.encodeReactionKey('blob', custom), 'blob');
      expect(EmojiCodec.encodeReactionKey(':blob:', custom), 'blob');
    });
  });

  group('message reactions', () {
    test('parses object-shaped emoji and colon keys', () {
      final object = MessageReaction.fromJson({
        'messageId': 1,
        'emoji': {'name': 'heart'},
        'userId': 2,
      });
      expect(object.emoji, 'heart');
      expect(object.userId, 2);

      final colon = MessageReaction.fromJson({
        'messageId': 1,
        'emoji': ':thumbsup:',
        'userId': 3,
      });
      expect(colon.emoji, '+1');
    });

    test('expands aggregated count + userIds + me', () {
      final parsed = parseMessageReactions([
        {
          'emoji': {'name': 'joy'},
          'count': 3,
          'me': true,
          'userIds': [1, 2, 3],
        },
      ], messageId: 9);
      expect(parsed, hasLength(3));
      expect(parsed.map((r) => r.userId), [1, 2, 3]);
      expect(parsed.every((r) => r.emoji == 'joy'), isTrue);
      expect(parsed.every((r) => r.me), isTrue);
      expect(parsed.every((r) => r.messageId == 9), isTrue);
    });

    test('keeps per-user rows', () {
      final parsed = parseMessageReactions([
        {'emoji': 'heart', 'userId': 1, 'messageId': 4},
        {'emoji': 'heart', 'userId': 2, 'messageId': 4},
      ]);
      expect(parsed, hasLength(2));
      expect(parsed.map((r) => r.userId), [1, 2]);
      expect(parsed.every((r) => r.count == 1), isTrue);
    });

    test('unwraps nested message payloads', () {
      expect(
        extractMessagePayload({
          'message': {'id': 7, 'content': '<p>hi</p>', 'channelId': 1},
        })?['id'],
        7,
      );
      expect(extractMessagePayload({'id': 8, 'content': '<p>x</p>'})?['id'], 8);
      expect(extractMessagePayload({'foo': 1}), isNull);
    });

    test('unwraps user leave ids', () {
      expect(extractUserId(5), 5);
      expect(extractUserId('5'), 5);
      expect(extractUserId({'json': 5, 'meta': const {}}), 5);
      expect(extractUserId({'userId': 5}), 5);
      expect(
        extractUserId({
          'user': {'id': 5},
        }),
        5,
      );
      expect(extractUserId({'foo': 1}), isNull);
    });

    test('unwraps nested user payloads', () {
      expect(
        extractUserPayload({
          'user': {'id': 7, 'name': 'Ada', 'status': 'online'},
        })?['id'],
        7,
      );
      expect(extractUserPayload({'id': 8, 'name': 'Gordon'})?['id'], 8);
      expect(
        extractUserPayload({
          'json': {'id': 9, 'name': 'Ada'},
          'meta': const {},
        })?['id'],
        9,
      );
      expect(extractUserPayload({'foo': 1}), isNull);
    });

    test('toggles own reaction locally', () {
      final added = withToggledReaction(
        reactions: const [],
        key: 'joy',
        ownUserId: 1,
        messageId: 5,
      );
      expect(added, hasLength(1));
      expect(added.first.emoji, 'joy');
      expect(added.first.userId, 1);

      final removed = withToggledReaction(
        reactions: added,
        key: 'joy',
        ownUserId: 1,
        messageId: 5,
      );
      expect(removed, isEmpty);
    });
  });

  group('reaction groups', () {
    test('groups reactions by emoji key', () {
      final groups = groupMessageReactions([
        MessageReaction(messageId: 1, emoji: 'heart', userId: 1),
        MessageReaction(messageId: 1, emoji: 'heart', userId: 2),
        MessageReaction(messageId: 1, emoji: 'joy', userId: 3),
      ], ownUserId: 1);
      expect(groups.keys.toList(), ['heart', 'joy']);
      expect(groups['heart']!.userIds, [1, 2]);
      expect(groups['heart']!.count, 2);
      expect(groups['heart']!.mine, isTrue);
      expect(groups['joy']!.userIds, [3]);
      expect(groups['joy']!.mine, isFalse);
    });

    test('uses aggregated count and me when userIds are missing', () {
      final groups = groupMessageReactions([
        MessageReaction(
          messageId: 1,
          emoji: 'skull',
          userId: 0,
          count: 5,
          me: true,
        ),
      ], ownUserId: 1);
      expect(groups['skull']!.count, 5);
      expect(groups['skull']!.mine, isTrue);
      expect(groups['skull']!.userIds, isEmpty);
    });
  });

  group('message embeds', () {
    test('extracts YouTube ids from common URL shapes', () {
      expect(
        youtubeVideoIdFromUrl(
          'https://youtu.be/yxo4j0DdnwY?si=CkP3MrVqKwSYduW0',
        ),
        'yxo4j0DdnwY',
      );
      expect(
        youtubeVideoIdFromUrl(
          'https://www.youtube.com/watch?v=yxo4j0DdnwY&t=30s',
        ),
        'yxo4j0DdnwY',
      );
      expect(
        youtubeVideoIdFromUrl('https://youtube.com/shorts/yxo4j0DdnwY'),
        'yxo4j0DdnwY',
      );
      expect(
        youtubeVideoIdFromUrl('https://www.youtube.com/embed/yxo4j0DdnwY'),
        'yxo4j0DdnwY',
      );
      expect(
        youtubeVideoIdFromUrl('https://www.youtube.com/live/yxo4j0DdnwY'),
        'yxo4j0DdnwY',
      );
      expect(youtubeVideoIdFromUrl('youtu.be/yxo4j0DdnwY'), 'yxo4j0DdnwY');
      expect(youtubeVideoIdFromUrl('https://example.com/watch?v=abc'), isNull);
    });

    test('finds YouTube ids in HTML content and metadata', () {
      const html = '<p>https://youtu.be/yxo4j0DdnwY?si=CkP3MrVqKwSYduW0</p>';
      expect(youtubeIdsIn(html), {'yxo4j0DdnwY'});
      expect(
        youtubeIdsIn('<p>hello</p>', [
          {
            'kind': 'open_graph',
            'url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
          },
        ]),
        {'dQw4w9WgXcQ'},
      );
    });

    test('normalizes OG images from strings or maps', () {
      expect(ogImageUrls(null), isEmpty);
      expect(ogImageUrls(['https://cdn.example/a.png']), [
        'https://cdn.example/a.png',
      ]);
      expect(
        ogImageUrls([
          {'url': 'https://cdn.example/b.png'},
          {'src': 'https://cdn.example/c.png'},
          '',
          3,
        ]),
        ['https://cdn.example/b.png', 'https://cdn.example/c.png'],
      );
    });

    test('detects image media types', () {
      expect(isImageMediaType('image'), isTrue);
      expect(isImageMediaType('image/gif'), isTrue);
      expect(isImageMediaType('video'), isFalse);
    });

    test('picks Discord provider accent from host', () {
      expect(
        embedAccentForUrl('https://youtu.be/yxo4j0DdnwY'),
        kYoutubeEmbedAccent,
      );
      expect(
        embedAccentForUrl('https://www.youtube.com/watch?v=abc'),
        kYoutubeEmbedAccent,
      );
      expect(
        embedAccentForUrl('https://x.com/FPSGamesShow'),
        kTwitterEmbedAccent,
      );
      expect(
        embedAccentForUrl('https://twitter.com/FPSGamesShow'),
        kTwitterEmbedAccent,
      );
      expect(
        embedAccentForUrl('https://example.com', const Color(0xFF111111)),
        const Color(0xFF111111),
      );
    });

    test('reads OG author from common keys', () {
      expect(ogAuthor({'author': 'BULKHEAD'}), 'BULKHEAD');
      expect(ogAuthor({'authorName': 'BULKHEAD'}), 'BULKHEAD');
      expect(ogAuthor({'author_name': 'BULKHEAD'}), 'BULKHEAD');
      expect(ogAuthor({'title': 'Nope'}), isNull);
    });

    test('detects GIF urls from extensions and known hosts', () {
      expect(isGifUrl('https://cdn.example/cat.gif'), isTrue);
      expect(isGifUrl('https://cdn.example/cat.GIF?size=hd'), isTrue);
      expect(isGifUrl('https://i.imgur.com/x.gifv'), isTrue);
      expect(isGifUrl('https://media.tenor.com/abc/tenor.gif'), isTrue);
      expect(isGifUrl('https://tenor.com/view/funny-123'), isTrue);
      expect(isGifUrl('https://media.giphy.com/media/abc/giphy.webp'), isTrue);
      expect(isGifUrl('https://gph.is/g/abc'), isTrue);
      expect(isGifUrl('https://cdn.klipy.com/hd/abc'), isTrue);
      expect(isGifUrl('https://gfycat.com/sillycat'), isTrue);
      expect(isGifUrl('https://cdn.example/photo.png'), isFalse);
      expect(isGifUrl('https://example.com/watch?v=abc'), isFalse);
      expect(isGifUrl('not a url'), isFalse);
    });

    test('finds GIF urls in HTML content and metadata', () {
      expect(gifUrlsIn('<p>https://media.tenor.com/abc/tenor.gif</p>'), {
        'https://media.tenor.com/abc/tenor.gif',
      });
      expect(gifUrlsIn('<p>hello https://cdn.example/a.gif.</p>'), {
        'https://cdn.example/a.gif',
      });
      expect(
        gifUrlsIn('<p>hello</p>', [
          {
            'kind': 'media',
            'url': 'https://files.example/clip.bin',
            'mediaType': 'image/gif',
          },
        ]),
        {'https://files.example/clip.bin'},
      );
      expect(gifUrlsIn('<p>https://example.com/photo.png</p>'), isEmpty);
    });

    test('hides GIF urls from message HTML', () {
      expect(hideGifUrlsInHtml('<p>https://cdn.example/a.gif</p>'), '<p></p>');
      expect(
        messageHtmlHasVisibleText(
          hideGifUrlsInHtml('<p>https://cdn.example/a.gif</p>'),
        ),
        isFalse,
      );
      expect(
        hideGifUrlsInHtml('<p>yooo https://cdn.example/a.gif</p>'),
        '<p>yooo </p>',
      );
      expect(
        messageHtmlHasVisibleText(
          hideGifUrlsInHtml('<p>yooo https://cdn.example/a.gif</p>'),
        ),
        isTrue,
      );
    });
  });

  group('roles', () {
    test('parses roleIds from ids or role objects', () {
      expect(
        parseRoleIds({
          'roleIds': [1, '10', 0],
        }),
        [1, 10],
      );
      expect(
        parseRoleIds({
          'roles': [
            {'id': 11},
            {'roleId': 12},
            13,
          ],
        }),
        [11, 12, 13],
      );
    });

    test('parses pin metadata from getPinned payloads', () {
      final m = KurierMessage.fromJson({
        'id': 9,
        'channelId': 10,
        'createdAt': 100,
        'pinned': true,
        'pinnedBy': 2,
        'pinnedAt': 200,
        'content': '<p>hi</p>',
      });
      expect(m.pinned, isTrue);
      expect(m.pinnedBy, 2);
      expect(m.pinnedAt, 200);
    });

    test('normalizes role colours from hex or int', () {
      expect(parseRoleColorString('#EB459E'), '#EB459E');
      expect(parseRoleColorString('23A55A'), '#23A55A');
      expect(parseRoleColorString(0xEB459E), '#eb459e');
      expect(parseRoleColorString(16711680), '#ff0000');
      expect(parseRoleColorString(16711680.0), '#ff0000');
      expect(parseRoleColorString('16711680'), '#ff0000');
      expect(
        KurierRole.fromJson({'id': 10, 'color': 0x23A55A}).color,
        '#23a55a',
      );
      expect(KurierRole.fromJson({'id': 7}).position, 7);
      expect(
        KurierUser.fromJson({
          'id': 2,
          'name': 'Gordon',
          'roles': [
            {'id': 11},
          ],
        }).roleIds,
        [11],
      );
    });
  });

  group('external streams', () {
    test('keeps streamId from json', () {
      final stream = ExternalStream.fromJson({
        'title': 'Radio',
        'key': 'plugin-radio',
        'pluginId': 'music',
        'streamId': 42,
      });
      expect(stream.streamId, 42);
      expect(stream.title, 'Radio');
      expect(stream.key, 'plugin-radio');
    });
  });

  group('activity log', () {
    String t(String key, [Map<String, String>? args]) {
      var value = l10nEn[key] ?? key;
      args?.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
      return value;
    }

    test('formats join and security entries', () {
      expect(
        formatActivityLogEntry(
          t: t,
          actorName: 'rf4burns',
          type: 'USER_JOINED',
        ),
        'rf4burns joined the server.',
      );
      expect(
        formatActivityLogEntry(
          t: t,
          actorName: 'KillerAuzzie',
          type: 'SECURITY_ANSWER_FAILED_THRESHOLD',
        ),
        'KillerAuzzie failed to answer their security question 3 times.',
      );
      expect(
        formatActivityLogEntry(
          t: t,
          actorName: 'rf4burns',
          type: 'ACCESS_BAN_ADDED',
          details: {'kind': 'ip', 'value': '203.132.68.46'},
        ),
        'rf4burns added a permanent IP ban for 203.132.68.46.',
      );
    });

    test('uses relative then absolute timestamps', () {
      final now = DateTime(2026, 8, 27, 12, 59);
      expect(
        activityLogTimestamp(
          now.subtract(const Duration(seconds: 10)).millisecondsSinceEpoch,
          now: now,
        ),
        'less than a minute ago',
      );
      expect(
        activityLogTimestamp(
          now.subtract(const Duration(minutes: 35)).millisecondsSinceEpoch,
          now: now,
        ),
        '35 minutes ago',
      );
      expect(
        activityLogTimestamp(
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          now: now,
        ),
        'about 1 hour ago',
      );
      expect(
        activityLogTimestamp(
          DateTime(2026, 8, 26, 12, 47, 11).millisecondsSinceEpoch,
          now: now,
        ),
        'Aug 26, 2026, 12:47:11 PM',
      );
    });
  });

  group('channel and category visibility', () {
    SessionController memberSession() {
      final s = SessionController();
      s.ownUserId = 1;
      s.users[1] = KurierUser(
        id: 1,
        name: 'Ada',
        status: 'online',
        roleIds: const [2],
      );
      s.roles[2] = KurierRole(
        id: 2,
        name: 'Member',
        color: '#888888',
        position: 0,
        hoist: false,
        isDefault: true,
        isPersistent: true,
      );
      s.categories[1] = KurierCategory(id: 1, name: 'info', position: 0);
      s.categories[2] = KurierCategory(id: 2, name: 'inner gates', position: 1);
      s.categories[3] = KurierCategory(id: 3, name: 'empty', position: 2);
      s.channels[10] = KurierChannel(
        id: 10,
        type: 'TEXT',
        name: 'announcements',
        position: 0,
        categoryId: 1,
      );
      s.channels[11] = KurierChannel(
        id: 11,
        type: 'TEXT',
        name: 'secret',
        position: 0,
        categoryId: 2,
        private: true,
      );
      return s;
    }

    test('parses nested channel permission maps', () {
      final perms = parseChannelPermissions({
        '11': {
          'channelId': 11,
          'permissions': {ChannelPermission.viewChannel: true},
        },
      });
      expect(perms['11']?.get(ChannelPermission.viewChannel), isTrue);
    });

    test('hides private categories without VIEW_CHANNEL', () {
      final s = memberSession();
      expect(s.canSeeCategory(1), isTrue);
      expect(s.canSeeCategory(2), isFalse);
      expect(s.canSeeCategory(3), isFalse);
      expect(s.visibleCategories().map((c) => c.id), [1]);
      expect(s.visibleChannelsIn(2), isEmpty);
      expect(s.canViewChannel(s.channels[11]!), isFalse);
    });

    test('shows a private category once VIEW_CHANNEL is granted', () {
      final s = memberSession();
      s.channelPerms['11'] = ChannelPerms({
        ChannelPermission.viewChannel: true,
      });
      expect(s.canViewChannel(s.channels[11]!), isTrue);
      expect(s.canSeeCategory(2), isTrue);
      expect(s.visibleChannelsIn(2).map((c) => c.id), [11]);
    });

    test('managers still see empty and private categories', () {
      final s = memberSession();
      s.roles[2] = KurierRole(
        id: 2,
        name: 'Mod',
        color: '#888888',
        position: 1,
        hoist: false,
        isDefault: false,
        isPersistent: true,
        permissions: const [
          Permission.manageChannels,
          Permission.manageCategories,
        ],
      );
      expect(s.canSeeCategory(2), isTrue);
      expect(s.canSeeCategory(3), isTrue);
      expect(s.canSeeChannel(s.channels[11]!), isTrue);
      expect(s.canViewChannel(s.channels[11]!), isFalse);
    });

    test('keeps a connected private voice channel visible', () {
      final s = memberSession();
      s.channels[12] = KurierChannel(
        id: 12,
        type: 'VOICE',
        name: 'hidden vc',
        position: 1,
        categoryId: 2,
        private: true,
      );
      s.connectedVoiceChannelId = 12;
      expect(s.canViewChannel(s.channels[12]!), isTrue);
      expect(s.canSeeCategory(2), isTrue);
    });
  });

  group('message history', () {
    KurierMessage msg(
      int id, {
      int createdAt = 0,
      int userId = 1,
      int? parent,
      int? reply,
    }) {
      return KurierMessage(
        id: id,
        channelId: 10,
        createdAt: createdAt,
        userId: userId,
        parentMessageId: parent,
        replyToMessageId: reply,
      );
    }

    test('parses int and object cursors', () {
      expect(MessagesCursor.parse(1234), const MessagesCursor(createdAt: 1234));
      expect(
        MessagesCursor.parse({'createdAt': 50, 'id': 9}),
        const MessagesCursor(createdAt: 50, id: 9),
      );
      expect(MessagesCursor.parse(null), isNull);
      expect(const MessagesCursor(createdAt: 5).toJson(), 5);
      expect(const MessagesCursor(createdAt: 5, id: 2).toJson(), {
        'createdAt': 5,
        'id': 2,
      });
    });

    test('merges older pages in front and live messages at the end', () {
      final state = ChannelHistoryState(messages: [msg(2, createdAt: 20)]);
      applyFetchedPage(
        state,
        page: [msg(1, createdAt: 10)],
        nextCursor: const MessagesCursor(createdAt: 10),
      );
      expect(state.messages.map((m) => m.id), [1, 2]);
      addHistoryMessages(state, [msg(3, createdAt: 30)], isLive: true);
      expect(state.messages.map((m) => m.id), [1, 2, 3]);
    });

    test(
      'drops live messages while detached, then picks them up on present',
      () {
        final state = ChannelHistoryState(messages: [msg(10, createdAt: 100)]);
        applyJumpWindow(
          state,
          page: [msg(2, createdAt: 20), msg(3, createdAt: 30)],
          hasNewer: true,
          nextCursor: const MessagesCursor(createdAt: 20),
        );
        expect(state.detached, isTrue);
        expect(state.messages.map((m) => m.id), [2, 3]);
        addHistoryMessages(state, [msg(99, createdAt: 990)], isLive: true);
        expect(state.messages.map((m) => m.id), [2, 3]);
        applyPresentPage(
          state,
          page: [msg(98, createdAt: 980), msg(99, createdAt: 990)],
          nextCursor: const MessagesCursor(createdAt: 980),
        );
        expect(state.detached, isFalse);
        expect(state.messages.map((m) => m.id), [98, 99]);
      },
    );

    test('replaces a detached window when the jump reaches the present', () {
      final state = ChannelHistoryState(detached: true, messages: [msg(1)]);
      applyJumpWindow(
        state,
        page: [msg(8, createdAt: 80), msg(9, createdAt: 90)],
        hasNewer: false,
      );
      expect(state.detached, isFalse);
      expect(state.messages.map((m) => m.id), [8, 9]);
    });

    test('ignores thread replies in the channel list', () {
      final state = ChannelHistoryState();
      addHistoryMessages(state, [msg(1), msg(2, parent: 1)], isLive: false);
      expect(state.messages.map((m) => m.id), [1]);
    });

    test('trims attached history and drops a detached window', () {
      final attached = ChannelHistoryState(
        messages: [
          for (var i = 1; i <= AppConfig.defaultMessagesLimit + 5; i++)
            msg(i, createdAt: i),
        ],
      );
      trimHistoryMessages(attached);
      expect(attached.messages.length, AppConfig.defaultMessagesLimit);
      expect(attached.messages.first.id, 6);

      final detached = ChannelHistoryState(
        detached: true,
        messages: [msg(1), msg(2)],
        nextCursor: const MessagesCursor(createdAt: 1),
      );
      trimHistoryMessages(detached);
      expect(detached.messages, isEmpty);
      expect(detached.detached, isFalse);
      expect(detached.nextCursor, isNull);
    });

    test('groups like vanilla: 1 minute, replies break the group', () {
      expect(
        messagesFormGroup(msg(1, createdAt: 0), msg(2, createdAt: 59 * 1000)),
        isTrue,
      );
      expect(
        messagesFormGroup(msg(1, createdAt: 0), msg(2, createdAt: 60 * 1000)),
        isFalse,
      );
      expect(
        messagesFormGroup(
          msg(1, createdAt: 0),
          msg(2, createdAt: 10, reply: 1),
        ),
        isFalse,
      );
      expect(
        messagesFormGroup(msg(1, createdAt: 0, userId: 1), msg(2, userId: 2)),
        isFalse,
      );
    });
  });

  group('transport stats', () {
    test('fromJson reads producer RTT and screen share fields', () {
      final stats = TransportStatsData.fromJson({
        'producer': {'rtt': 23.4, 'packetsSent': 12, 'bytesSent': 100},
        'consumer': {
          'packetsReceived': 40,
          'packetsLost': 2,
          'bytesReceived': 200,
        },
        'screenShare': {
          'codec': 'video/VP8',
          'encoderImplementation': 'libvpx',
          'width': 1920,
          'height': 1080,
          'frameRate': 30,
          'bitrate': 150000,
          'simulcast': true,
          'layers': [
            {'id': 'a', 'rid': 'q', 'width': 640, 'height': 360},
          ],
        },
        'totalBytesSent': 9000,
        'currentBitrateSent': 1200,
      });
      expect(stats.rttMs, 23);
      expect(stats.producer?.packetsSent, 12);
      expect(stats.consumer?.packetsLost, 2);
      expect(stats.screenShare?.codec, 'video/VP8');
      expect(stats.screenShare?.layers, hasLength(1));
      expect(stats.screenShare?.layers.first.rid, 'q');
    });
  });

  group('plugin marketplace', () {
    test('uses the official Sharkord plugins registry', () {
      expect(
        AppConfig.marketplaceUrl,
        'https://raw.githubusercontent.com/Sharkord/plugins/refs/heads/main/plugins.json?raw=true',
      );
    });

    test('picks the newest version by timestamp, not array order', () {
      final latest = latestMarketplaceVersion([
        {'version': '0.0.1', 'timestamp': 1774666614697},
        {'version': '0.0.2', 'timestamp': 1775957590667},
      ]);
      expect(latest?['version'], '0.0.2');
    });

    test('falls back to the first entry when timestamps are missing', () {
      final latest = latestMarketplaceVersion([
        {'version': '1.2.0'},
        {'version': '1.0.0'},
      ]);
      expect(latest?['version'], '1.2.0');
    });

    test('returns null for an empty versions list', () {
      expect(latestMarketplaceVersion(const []), isNull);
      expect(latestMarketplaceVersion(null), isNull);
    });
  });
}

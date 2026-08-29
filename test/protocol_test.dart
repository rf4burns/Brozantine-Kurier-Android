import 'dart:convert';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kurier_web/app/l10n_tables.dart';
import 'package:kurier_web/app/client_kind.dart';
import 'package:kurier_web/core/custom_emoji.dart';
import 'package:kurier_web/core/emoji_codec.dart';
import 'package:kurier_web/native/push_inbox.dart';
import 'package:kurier_web/native/push_kind.dart';
import 'package:kurier_web/protocol/activity_log.dart';
import 'package:kurier_web/protocol/audio_output.dart';
import 'package:kurier_web/protocol/config.dart';
import 'package:kurier_web/protocol/device_token.dart';
import 'package:kurier_web/protocol/http_api.dart';
import 'package:kurier_web/protocol/mentions.dart';
import 'package:kurier_web/protocol/models.dart';
import 'package:kurier_web/protocol/permissions.dart';
import 'package:kurier_web/protocol/platform.dart';
import 'package:kurier_web/protocol/presence.dart';
import 'package:kurier_web/protocol/search_query.dart';
import 'package:kurier_web/protocol/sounds.dart';
import 'package:kurier_web/protocol/trpc_client.dart';
import 'package:kurier_web/protocol/voice_protocol.dart';
import 'package:kurier_web/protocol/voice_stats.dart';
import 'package:mediasfu_mediasoup_client/mediasfu_mediasoup_client.dart'
    hide MediaDeviceInfo;
import 'package:kurier_web/session/hosts_store.dart';
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

  group('incoming message sounds', () {
    test('skips own messages', () {
      expect(
        shouldPlayIncomingMessageSound(
          isOwn: true,
          mentioned: true,
          channelOverride: null,
          soundMention: true,
          soundMessage: true,
        ),
        isFalse,
      );
    });

    test('skips muted channels', () {
      expect(
        shouldPlayIncomingMessageSound(
          isOwn: false,
          mentioned: true,
          channelOverride: 'nothing',
          soundMention: true,
          soundMessage: true,
        ),
        isFalse,
      );
    });

    test('respects mention vs message prefs', () {
      expect(
        shouldPlayIncomingMessageSound(
          isOwn: false,
          mentioned: true,
          channelOverride: null,
          soundMention: true,
          soundMessage: false,
        ),
        isTrue,
      );
      expect(
        shouldPlayIncomingMessageSound(
          isOwn: false,
          mentioned: true,
          channelOverride: null,
          soundMention: false,
          soundMessage: true,
        ),
        isFalse,
      );
      expect(
        shouldPlayIncomingMessageSound(
          isOwn: false,
          mentioned: false,
          channelOverride: null,
          soundMention: true,
          soundMessage: false,
        ),
        isFalse,
      );
      expect(
        shouldPlayIncomingMessageSound(
          isOwn: false,
          mentioned: false,
          channelOverride: null,
          soundMention: false,
          soundMessage: true,
        ),
        isTrue,
      );
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

  group('disconnect codes', () {
    test('treats kick/ban/shutdown as fatal disconnects', () {
      expect(isFatalDisconnectCode(40000), isTrue);
      expect(isFatalDisconnectCode(40001), isTrue);
      expect(isFatalDisconnectCode(40002), isTrue);
      expect(isFatalDisconnectCode(40003), isTrue);
      expect(isFatalDisconnectCode(1006), isFalse);
      expect(isFatalDisconnectCode(1001), isFalse);
      expect(isFatalDisconnectCode(1000), isFalse);
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

  group('mobile presence', () {
    test('kurierClientKind is desktop on VM and Windows native', () {
      expect(kurierClientKind(), 'desktop');
    });

    test('fromJson reads mobile and keeps it when omitted', () {
      final mobile = KurierUser.fromJson({
        'id': 2,
        'name': 'Ada',
        'status': 'online',
        'mobile': true,
      });
      expect(mobile.mobile, isTrue);
      final kept = KurierUser.fromJson({
        'id': 2,
        'name': 'Ada',
      }, existing: mobile);
      expect(kept.mobile, isTrue);
      expect(kept.status, 'online');
      final cleared = KurierUser.fromJson({
        'id': 2,
        'name': 'Ada',
        'mobile': false,
      }, existing: mobile);
      expect(cleared.mobile, isFalse);
    });
  });

  group('away presence', () {
    test('voice always reports online', () {
      expect(
        intendedPresenceStatus(manualAway: true, focused: false, inVoice: true),
        'online',
      );
    });

    test('manual away sticks while focused', () {
      expect(
        intendedPresenceStatus(manualAway: true, focused: true, inVoice: false),
        'idle',
      );
    });

    test('unfocused reports idle unless already online-and-focused', () {
      expect(
        intendedPresenceStatus(
          manualAway: false,
          focused: false,
          inVoice: false,
        ),
        'idle',
      );
      expect(
        intendedPresenceStatus(
          manualAway: false,
          focused: true,
          inVoice: false,
        ),
        'online',
      );
    });

    test('labels idle as away', () {
      expect(presenceLabelKey('idle'), 'statusAway');
      expect(presenceLabelKey('online'), 'statusOnline');
      expect(presenceLabelKey('offline'), 'statusOffline');
    });

    test('toggle and unfocus do not override manual away', () async {
      final s = SessionController();
      s.phase = SessionPhase.ready;
      s.ownUserId = 1;
      s.users[1] = KurierUser(id: 1, name: 'Ada', status: 'online');
      s.focusAwayDebounce = Duration.zero;

      s.togglePresence();
      expect(s.manualAway, isTrue);
      expect(s.displayPresence, 'idle');
      expect(s.me?.status, 'idle');

      s.onAppFocusChanged(false);
      await Future<void>.delayed(Duration.zero);
      expect(s.manualAway, isTrue);
      expect(s.displayPresence, 'idle');

      s.onAppFocusChanged(true);
      expect(s.displayPresence, 'idle');

      s.connectedVoiceChannelId = 10;
      expect(s.displayPresence, 'online');
      s.applyLocalPresence();
      expect(s.me?.status, 'online');
    });
  });

  group('audio output', () {
    MediaDeviceInfo out(String id, String label) =>
        MediaDeviceInfo(deviceId: id, kind: 'audiooutput', label: label);

    test('drops virtual default and communications devices', () {
      final classified = classifyAudioOutputs([
        out('default', 'Default'),
        out('communications', 'Communications'),
        out('', 'Default'),
        out('spk', 'Speaker'),
        MediaDeviceInfo(
          deviceId: 'mic',
          kind: 'audioinput',
          label: 'Built-in Microphone',
        ),
      ]);
      expect(classified.speakers.map((d) => d.deviceId), ['spk']);
      expect(classified.externals, isEmpty);
      expect(classified.hasDefaultSink, isTrue);
      expect(classified.usesDefaultAsBluetooth, isTrue);
    });

    test('treats speakerphone and built-in labels as speaker', () {
      final classified = classifyAudioOutputs([
        out('a', 'Speakerphone'),
        out('b', 'Built-in Speaker'),
        out('c', 'BMW X5'),
        out('d', 'Built-in Earpiece'),
      ]);
      expect(classified.speakers.map((d) => d.deviceId), ['a', 'b']);
      expect(classified.externals.map((d) => d.deviceId), ['c']);
    });

    test('car bluetooth names without bluetooth in the label are external', () {
      final classified = classifyAudioOutputs([
        out('spk', 'Speaker'),
        out('car', 'Gordon\'s Car'),
      ]);
      expect(audioOutputRoute('spk', classified), AudioOutputRoute.speaker);
      expect(audioOutputRoute('car', classified), AudioOutputRoute.bluetooth);
      expect(audioOutputRoute(null, classified), AudioOutputRoute.unknown);
    });

    test('toggles from speaker to last external then back to speaker', () {
      final classified = classifyAudioOutputs([
        out('spk', 'Speaker'),
        out('buds', 'AirPods'),
        out('car', 'Car Stereo'),
      ]);
      final toSpeaker = nextAudioOutput(
        currentId: null,
        classified: classified,
      );
      expect(toSpeaker.kind, AudioOutputToggle.toDevice);
      expect(toSpeaker.deviceId, 'spk');

      final toLast = nextAudioOutput(
        currentId: 'spk',
        classified: classified,
        lastExternalId: 'car',
      );
      expect(toLast.kind, AudioOutputToggle.toDevice);
      expect(toLast.deviceId, 'car');

      final toSpeakerAgain = nextAudioOutput(
        currentId: 'car',
        classified: classified,
      );
      expect(toSpeakerAgain.kind, AudioOutputToggle.toDevice);
      expect(toSpeakerAgain.deviceId, 'spk');
    });

    test('toggles from speaker to first external when last is gone', () {
      final classified = classifyAudioOutputs([
        out('spk', 'Speaker'),
        out('buds', 'WH-1000XM4'),
      ]);
      final result = nextAudioOutput(
        currentId: 'spk',
        classified: classified,
        lastExternalId: 'missing',
      );
      expect(result.deviceId, 'buds');
    });

    test('toggles to bluetooth when no labeled speaker exists', () {
      final classified = classifyAudioOutputs([out('car', 'Car Stereo')]);
      final result = nextAudioOutput(currentId: null, classified: classified);
      expect(result.kind, AudioOutputToggle.toDevice);
      expect(result.deviceId, 'car');
    });

    test('reports no other devices when only speaker is present', () {
      final classified = classifyAudioOutputs([out('spk', 'Speaker')]);
      expect(classified.hasDefaultSink, isFalse);
      final result = nextAudioOutput(currentId: 'spk', classified: classified);
      expect(result.kind, AudioOutputToggle.noOtherDevices);
    });

    test('toggles speaker to default bluetooth then back to speaker', () {
      final classified = classifyAudioOutputs([
        out('default', 'Default'),
        out('spk', 'Speakerphone'),
      ]);
      expect(classified.usesDefaultAsBluetooth, isTrue);
      expect(audioOutputRoute(null, classified), AudioOutputRoute.bluetooth);
      expect(
        audioOutputRoute('default', classified),
        AudioOutputRoute.bluetooth,
      );

      final toSpeaker = nextAudioOutput(
        currentId: null,
        classified: classified,
      );
      expect(toSpeaker.kind, AudioOutputToggle.toDevice);
      expect(toSpeaker.deviceId, 'spk');

      final toDefault = nextAudioOutput(
        currentId: 'spk',
        classified: classified,
      );
      expect(toDefault.kind, AudioOutputToggle.toDevice);
      expect(toDefault.deviceId, isNull);
    });

    test('prefers labeled bluetooth over default', () {
      final classified = classifyAudioOutputs([
        out('default', 'Default'),
        out('spk', 'Speaker'),
        out('buds', 'AirPods'),
      ]);
      expect(classified.usesDefaultAsBluetooth, isFalse);
      expect(classified.externals.map((d) => d.deviceId), ['buds']);
      final result = nextAudioOutput(currentId: 'spk', classified: classified);
      expect(result.kind, AudioOutputToggle.toDevice);
      expect(result.deviceId, 'buds');
    });

    MediaDeviceInfo input(String id, String label) =>
        MediaDeviceInfo(deviceId: id, kind: 'audioinput', label: label);

    test('maps iOS built-in mics to speaker and headsets to bluetooth', () {
      final classified = classifyAudioInputsForOutput([
        input('phone', 'iPhone Microphone'),
        input('buds', 'AirPods'),
        input('car', 'BMW Hands-Free'),
        out('spk', 'Speaker'),
      ]);
      expect(classified.speakers.map((d) => d.deviceId), ['phone']);
      expect(classified.externals.map((d) => d.deviceId), ['buds', 'car']);
      expect(classified.usesDefaultAsBluetooth, isFalse);
    });

    test('toggles iOS mic-followed output from speaker to last headset', () {
      final classified = classifyAudioInputsForOutput([
        input('phone', 'iPhone Microphone'),
        input('buds', 'AirPods'),
        input('car', 'Car Hands-Free'),
      ]);
      expect(audioOutputRoute('phone', classified), AudioOutputRoute.speaker);
      expect(audioOutputRoute('buds', classified), AudioOutputRoute.bluetooth);

      final toLast = nextAudioOutput(
        currentId: 'phone',
        classified: classified,
        lastExternalId: 'car',
      );
      expect(toLast.kind, AudioOutputToggle.toDevice);
      expect(toLast.deviceId, 'car');

      final toSpeaker = nextAudioOutput(
        currentId: 'car',
        classified: classified,
      );
      expect(toSpeaker.kind, AudioOutputToggle.toDevice);
      expect(toSpeaker.deviceId, 'phone');
    });

    test('reports no other iOS output when only the built-in mic exists', () {
      final classified = classifyAudioInputsForOutput([
        input('phone', 'iPhone Microphone'),
      ]);
      final result = nextAudioOutput(
        currentId: 'phone',
        classified: classified,
      );
      expect(result.kind, AudioOutputToggle.noOtherDevices);
    });

    test('treats Android camcorder and voice mics as built-in speakers', () {
      final classified = classifyAudioInputsForOutput([
        input('cam', 'Camcorder'),
        input('vr', 'Voice recognition'),
        input('vc', 'Voice communication'),
        input('builtin', 'Builtin Mic'),
        input('def', 'Default - Microphone'),
        input('buds', 'Bluetooth headset'),
      ]);
      expect(classified.speakers.map((d) => d.deviceId), [
        'cam',
        'vr',
        'vc',
        'builtin',
        'def',
      ]);
      expect(classified.externals.map((d) => d.deviceId), ['buds']);
    });

    test('treats CarPlay and Android Auto inputs as bluetooth', () {
      expect(isBluetoothInputLabel('CarPlay'), isTrue);
      expect(isBluetoothInputLabel('Android Auto'), isTrue);
      expect(isBluetoothInputLabel('BMW Hands free'), isTrue);
    });

    test('uses mic-route for default-only outputs on a phone', () {
      final plan = resolveAudioOutput(
        devices: [
          out('default', 'Default'),
          input('mic', 'Built-in Microphone'),
          input('buds', 'Bluetooth headset'),
        ],
        canSetOutputDevice: true,
        outputFollowsMic: true,
      );
      expect(plan.usesMicRoute, isTrue);
      expect(plan.classified.speakers.map((d) => d.deviceId), ['mic']);
      expect(plan.classified.externals.map((d) => d.deviceId), ['buds']);

      final toBt = nextAudioOutput(
        currentId: 'mic',
        classified: plan.classified,
      );
      expect(toBt.kind, AudioOutputToggle.toDevice);
      expect(toBt.deviceId, 'buds');

      final toSpeaker = nextAudioOutput(
        currentId: 'buds',
        classified: plan.classified,
      );
      expect(toSpeaker.kind, AudioOutputToggle.toDevice);
      expect(toSpeaker.deviceId, 'mic');
    });

    test('uses mic-route on Safari even when setSinkId exists', () {
      final plan = resolveAudioOutput(
        devices: [
          out('default', 'Default'),
          input('phone', 'iPhone Microphone'),
          input('buds', 'AirPods'),
        ],
        canSetOutputDevice: true,
        outputFollowsMic: true,
      );
      expect(plan.usesMicRoute, isTrue);
      expect(plan.classified.speakers.map((d) => d.deviceId), ['phone']);
      expect(plan.classified.externals.map((d) => d.deviceId), ['buds']);
    });

    test('keeps setSinkId when Safari lists speaker and bluetooth outputs', () {
      final plan = resolveAudioOutput(
        devices: [
          out('spk', 'Speakerphone'),
          out('buds', 'AirPods'),
          input('phone', 'iPhone Microphone'),
          input('air', 'AirPods'),
        ],
        canSetOutputDevice: true,
        outputFollowsMic: true,
      );
      expect(plan.usesMicRoute, isFalse);
      expect(plan.classified.speakers.map((d) => d.deviceId), ['spk']);
      expect(plan.classified.externals.map((d) => d.deviceId), ['buds']);
    });

    test('does not mic-route default-only outputs on desktop Safari', () {
      final plan = resolveAudioOutput(
        devices: [
          out('default', 'Default'),
          input('mic', 'MacBook Microphone'),
          input('buds', 'AirPods'),
        ],
        canSetOutputDevice: true,
        outputFollowsMic: false,
      );
      expect(plan.usesMicRoute, isFalse);
      expect(plan.classified.realDevices, isEmpty);
    });

    test(
      'uses mic-route for default-only outputs with car hands-free input',
      () {
        final plan = resolveAudioOutput(
          devices: [
            out('default', 'Default'),
            input('phone', 'iPhone Microphone'),
            input('car', 'BMW Hands-Free'),
          ],
          canSetOutputDevice: true,
          outputFollowsMic: true,
        );
        expect(plan.usesMicRoute, isTrue);
        expect(plan.classified.externals.map((d) => d.deviceId), ['car']);

        final result = nextAudioOutput(
          currentId: 'phone',
          classified: plan.classified,
        );
        expect(result.kind, AudioOutputToggle.toDevice);
        expect(result.deviceId, 'car');
      },
    );

    test('uses mic-route for a car name with no bluetooth keyword', () {
      final plan = resolveAudioOutput(
        devices: [
          out('default', 'Default'),
          input('mic', 'Built-in Microphone'),
          input('car', "Gordon's Car"),
        ],
        canSetOutputDevice: true,
        outputFollowsMic: true,
      );
      expect(plan.usesMicRoute, isTrue);
      expect(plan.classified.externals.map((d) => d.deviceId), ['car']);
    });

    test('keeps setSinkId for a named car stereo output', () {
      final plan = resolveAudioOutput(
        devices: [
          out('spk', 'Speaker'),
          out('car', 'Car Stereo'),
          input('mic', 'Built-in Microphone'),
          input('hands', 'BMW Hands-Free'),
        ],
        canSetOutputDevice: true,
        outputFollowsMic: true,
      );
      expect(plan.usesMicRoute, isFalse);
      expect(plan.classified.externals.map((d) => d.deviceId), ['car']);
    });

    test('keeps default-as-bluetooth on speakerphone plus default', () {
      final plan = resolveAudioOutput(
        devices: [
          out('default', 'Default'),
          out('spk', 'Speakerphone'),
          input('mic', 'Built-in Microphone'),
          input('buds', 'Bluetooth headset'),
        ],
        canSetOutputDevice: true,
        outputFollowsMic: true,
      );
      expect(plan.usesMicRoute, isFalse);
      expect(plan.classified.usesDefaultAsBluetooth, isTrue);
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

    test('coerces JSON fecMechanisms to List<String>', () {
      final decoded =
          jsonDecode(
                jsonEncode({
                  'codecs': [
                    {
                      'kind': 'audio',
                      'mimeType': 'audio/opus',
                      'clockRate': 48000,
                      'rtcpFeedback': [
                        {'type': 'nack'},
                      ],
                    },
                  ],
                  'headerExtensions': const [],
                  'fecMechanisms': const <dynamic>[],
                }),
              )
              as Map<String, dynamic>;
      expect(decoded['fecMechanisms'] is List<String>, isFalse);
      expect(
        () => decoded['fecMechanisms'] as List<String>,
        throwsA(isA<TypeError>()),
      );
      final prepared = nativeRtpCapabilitiesMap(decoded);
      expect(prepared['fecMechanisms'], isA<List<String>>());
      expect(prepared['fecMechanisms'] as List<String>, isEmpty);
      expect(prepared['headerExtensions'], isA<List<dynamic>>());
    });

    test('mediasoup fromMap accepts sanitized JSON capabilities', () {
      final decoded =
          jsonDecode(
                jsonEncode({
                  'codecs': [
                    {
                      'kind': 'audio',
                      'mimeType': 'audio/opus',
                      'clockRate': 48000,
                      'channels': 2,
                      'preferredPayloadType': 111,
                      'parameters': {'minptime': 10},
                      'rtcpFeedback': [
                        {'type': 'nack', 'parameter': ''},
                      ],
                    },
                  ],
                  'headerExtensions': [
                    {
                      'kind': 'audio',
                      'uri': 'urn:ietf:params:rtp-hdrext:sdes:mid',
                      'preferredId': 1,
                      'preferredEncrypt': false,
                      'direction': 'sendrecv',
                    },
                  ],
                  'fecMechanisms': <dynamic>[],
                }),
              )
              as Map<String, dynamic>;
      expect(() => RtpCapabilities.fromMap(decoded), throwsA(isA<TypeError>()));
      final caps = RtpCapabilities.fromMap(nativeRtpCapabilitiesMap(decoded));
      expect(caps.codecs, isNotEmpty);
      expect(caps.fecMechanisms, isEmpty);
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

    test('forwards simulcast qualityLayers on voice.produce', () {
      final payload = voiceProduceMutation(
        transportId: 't1',
        body: {
          'kind': 'screen',
          'rtpParameters': {'codecs': []},
          'appData': {
            'kind': 'screen',
            'qualityLayers': [
              {'spatialLayer': 0, 'label': 'Low'},
              {'spatialLayer': 1, 'label': 'Medium'},
              {'spatialLayer': 2, 'label': 'High'},
            ],
          },
        },
      );
      expect(payload['transportId'], 't1');
      expect(payload['kind'], 'screen');
      expect(payload['qualityLayers'], hasLength(3));
      expect((payload['qualityLayers'] as List).first['label'], 'Low');
    });

    test('uses top-level qualityLayers when appData is missing', () {
      final payload = voiceProduceMutation(
        transportId: 't2',
        body: {
          'kind': 'video',
          'rtpParameters': {'mid': '0'},
          'qualityLayers': [
            {'spatialLayer': 0, 'label': 'Low'},
          ],
        },
      );
      expect(payload['kind'], 'video');
      expect(payload.containsKey('qualityLayers'), isTrue);
    });

    test('omits qualityLayers for a simple audio produce', () {
      final payload = voiceProduceMutation(
        transportId: 't3',
        body: {
          'kind': 'audio',
          'rtpParameters': {'codecs': []},
        },
      );
      expect(payload['kind'], 'audio');
      expect(payload.containsKey('qualityLayers'), isFalse);
    });

    test('unwraps bare and nested ICE parameters', () {
      expect(
        iceParametersOf({
          'usernameFragment': 'ufrag',
          'password': 'pwd',
          'iceLite': true,
        })?['usernameFragment'],
        'ufrag',
      );
      expect(
        iceParametersOf({
          'iceParameters': {'usernameFragment': 'nested', 'password': 'secret'},
        })?['password'],
        'secret',
      );
      expect(iceParametersOf({'usernameFragment': 'only'}), isNull);
      expect(iceParametersOf({}), isNull);
    });

    test('detects unmuted remotes for receive-path health', () {
      final map = {
        20: {
          1: VoiceUserState(),
          2: VoiceUserState(micMuted: true),
          3: VoiceUserState(),
        },
      };
      expect(
        hasUnmutedRemoteVoiceUser(channelId: 20, ownUserId: 1, voiceMap: map),
        isTrue,
      );
      map[20]![3] = VoiceUserState(serverMuted: true);
      expect(
        hasUnmutedRemoteVoiceUser(channelId: 20, ownUserId: 1, voiceMap: map),
        isFalse,
      );
    });

    test('playback health requires live graphs for expected audio keys', () {
      const health = VoicePlaybackHealth(
        ctxRunning: true,
        keepAlive: true,
        recvState: 'connected',
        liveAudioKeys: ['2:audio'],
        graphKeys: ['2:audio'],
      );
      expect(
        isVoicePlaybackHealthy(health: health, expectedAudioKeys: ['2:audio']),
        isTrue,
      );
      expect(
        isVoicePlaybackHealthy(health: health, expectedAudioKeys: ['3:audio']),
        isFalse,
      );
      expect(
        isVoicePlaybackHealthy(
          health: VoicePlaybackHealth(
            ctxRunning: false,
            keepAlive: true,
            recvState: 'connected',
            liveAudioKeys: ['2:audio'],
            graphKeys: ['2:audio'],
          ),
          expectedAudioKeys: ['2:audio'],
        ),
        isFalse,
      );
      expect(
        isVoicePlaybackHealthy(
          health: VoicePlaybackHealth(
            ctxRunning: true,
            keepAlive: true,
            recvState: 'disconnected',
            liveAudioKeys: ['2:audio'],
            graphKeys: ['2:audio'],
          ),
          expectedAudioKeys: ['2:audio'],
        ),
        isFalse,
      );
    });

    test('playback health accepts HTML audio without a Web Audio graph', () {
      const html = VoicePlaybackHealth(
        ctxRunning: false,
        keepAlive: false,
        recvState: 'connected',
        liveAudioKeys: ['2:audio'],
        playingKeys: ['2:audio'],
      );
      expect(
        isVoicePlaybackHealthy(health: html, expectedAudioKeys: ['2:audio']),
        isTrue,
      );
      expect(
        isVoicePlaybackHealthy(
          health: VoicePlaybackHealth(
            ctxRunning: true,
            keepAlive: true,
            recvState: 'connected',
            liveAudioKeys: ['2:audio'],
          ),
          expectedAudioKeys: ['2:audio'],
        ),
        isFalse,
      );
    });

    test('gesture-locked when tracks are live but output is silent', () {
      const locked = VoicePlaybackHealth(
        ctxRunning: false,
        keepAlive: false,
        recvState: 'connected',
        liveAudioKeys: ['2:audio'],
      );
      expect(
        isVoicePlaybackGestureLocked(
          health: locked,
          expectedAudioKeys: ['2:audio'],
        ),
        isTrue,
      );
      expect(
        isVoicePlaybackGestureLocked(
          health: VoicePlaybackHealth(
            recvState: 'connected',
            liveAudioKeys: ['2:audio'],
            playingKeys: ['2:audio'],
          ),
          expectedAudioKeys: ['2:audio'],
        ),
        isFalse,
      );
      expect(
        isVoicePlaybackGestureLocked(
          health: VoicePlaybackHealth(
            recvState: 'failed',
            liveAudioKeys: ['2:audio'],
          ),
          expectedAudioKeys: ['2:audio'],
        ),
        isFalse,
      );
    });

    test('does not treat a quiet unmuted room as dead', () {
      expect(
        shouldReceiveVoiceAudio(
          voiceState: 'connected',
          soundMuted: false,
          hasUnmutedRemote: true,
        ),
        isTrue,
      );
      expect(
        shouldReceiveVoiceAudio(
          voiceState: 'connected',
          soundMuted: true,
          hasUnmutedRemote: true,
        ),
        isFalse,
      );
      expect(
        shouldSilentRejoinVoice(
          shouldReceive: true,
          playbackHealthy: true,
          pastGrace: true,
          heldDead: true,
          rejoinsInWindow: 0,
        ),
        isFalse,
      );
    });

    test('silent rejoin requires a dead path after grace and hold', () {
      expect(
        shouldSilentRejoinVoice(
          shouldReceive: true,
          playbackHealthy: false,
          pastGrace: true,
          heldDead: true,
          rejoinsInWindow: 0,
        ),
        isTrue,
      );
      expect(
        shouldSilentRejoinVoice(
          shouldReceive: true,
          playbackHealthy: false,
          pastGrace: false,
          heldDead: true,
          rejoinsInWindow: 0,
        ),
        isFalse,
      );
      expect(
        shouldSilentRejoinVoice(
          shouldReceive: false,
          playbackHealthy: false,
          pastGrace: true,
          heldDead: true,
          rejoinsInWindow: 0,
        ),
        isFalse,
      );
    });

    test('caps silent rejoins inside the cooldown window', () {
      final now = DateTime(2026, 8, 27, 20);
      final times = [
        now.subtract(const Duration(seconds: 10)),
        now.subtract(const Duration(seconds: 5)),
      ];
      expect(rejoinsInVoiceWindow(times, now), 2);
      expect(
        shouldSilentRejoinVoice(
          shouldReceive: true,
          playbackHealthy: false,
          pastGrace: true,
          heldDead: true,
          rejoinsInWindow: rejoinsInVoiceWindow(times, now),
        ),
        isFalse,
      );
      times.add(now.subtract(const Duration(seconds: 70)));
      expect(rejoinsInVoiceWindow(List.of(times), now), 2);
      final pruned = [
        now.subtract(const Duration(seconds: 70)),
        now.subtract(const Duration(seconds: 5)),
      ];
      expect(rejoinsInVoiceWindow(pruned, now), 1);
      expect(
        shouldSilentRejoinVoice(
          shouldReceive: true,
          playbackHealthy: false,
          pastGrace: true,
          heldDead: true,
          rejoinsInWindow: 1,
        ),
        isTrue,
      );
    });

    test('expected remote audio keys use stored consumer keys', () {
      final keys = expectedRemoteAudioKeys(
        channelId: 20,
        ownUserId: 1,
        voiceMap: {
          20: {
            1: VoiceUserState(),
            2: VoiceUserState(),
            3: VoiceUserState(micMuted: true),
          },
        },
        consumerKeys: {'2:audio': '2:audio'},
      );
      expect(keys, ['2:audio']);
    });

    test('reads simulcast from public server settings', () {
      final s = SessionController();
      expect(s.simulcastEnabled, isFalse);
      s.publicSettings['webRtcSimulcastEnabled'] = true;
      expect(s.simulcastEnabled, isTrue);
    });

    test('kick closes the session instead of silently reconnecting', () async {
      final s = SessionController();
      s.phase = SessionPhase.ready;
      await s.handleGatewayClosed(40001, 'banned');
      expect(s.phase, SessionPhase.disconnected);
      expect(s.disconnectCode, 40001);
    });

    test('socket drop without credentials shows disconnected', () async {
      final s = SessionController();
      s.phase = SessionPhase.ready;
      await s.handleGatewayClosed(1006, '');
      expect(s.phase, SessionPhase.disconnected);
      expect(s.disconnectCode, 1006);
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

    test('client-mutes playback streams until the user unmutes', () {
      expect(StreamKind.startsClientMuted(StreamKind.externalAudio), isTrue);
      expect(StreamKind.startsClientMuted(StreamKind.screenAudio), isTrue);
      expect(StreamKind.startsClientMuted(StreamKind.audio), isFalse);
      expect(StreamKind.startsClientMuted(StreamKind.video), isFalse);
      expect(StreamKind.startsClientMuted(StreamKind.screen), isFalse);
    });

    test(
      'allows watching a stream only in the connected voice channel',
      () async {
        final s = SessionController();
        s.ownUserId = 1;
        s.voiceMap[20] = {2: VoiceUserState(sharingScreen: true)};
        s.externalStreams[20] = [
          ExternalStream(
            title: 'Music Bot',
            key: 'music-bot',
            pluginId: 'music-bot',
            streamId: 9,
          ),
        ];
        expect(s.canWatchStream(2), isFalse);
        expect(s.canWatchStream(9, external: true), isFalse);

        s.connectedVoiceChannelId = 20;
        expect(s.canWatchStream(2), isFalse);

        s.voiceState = 'connected';
        expect(s.canWatchStream(2), isTrue);
        expect(s.canWatchStream(3), isFalse);
        expect(s.canWatchStream(9, external: true), isTrue);
        expect(s.canWatchStream(8, external: true), isFalse);

        s.connectedVoiceChannelId = 21;
        expect(s.canWatchStream(2), isFalse);
        expect(s.canWatchStream(9, external: true), isFalse);

        s.connectedVoiceChannelId = null;
        s.voiceState = 'idle';
        await s.watchStream(2);
        expect(s.watchingStreams, isEmpty);
        expect(s.error, missingPermissionKey);
      },
    );

    test('notifies when an action is blocked by permissions', () async {
      final s = SessionController();
      s.ownUserId = 1;
      s.users[1] = KurierUser(id: 1, name: 'Ada', roleIds: const [2]);
      s.roles[2] = KurierRole(
        id: 2,
        name: 'member',
        color: '#fff',
        position: 1,
        hoist: false,
        isDefault: true,
        isPersistent: false,
      );
      s.channels[10] = KurierChannel(
        id: 10,
        type: 'TEXT',
        name: 'general',
        position: 0,
      );
      s.channels[20] = KurierChannel(
        id: 20,
        type: 'VOICE',
        name: 'voice',
        position: 1,
      );
      s.selectedChannelId = 10;

      expect(s.canJoinVoiceChannel(20), isFalse);
      expect(s.canSendInChannel(10), isFalse);
      await s.joinVoice(20);
      expect(s.voiceState, 'idle');
      expect(s.error, missingPermissionKey);

      s.clearError();
      await s.sendMessage('hello');
      expect(s.error, missingPermissionKey);
      expect(s.messages[10], isNull);

      s.connectedVoiceChannelId = 20;
      s.voiceState = 'connected';
      s.voiceMap[20] = {2: VoiceUserState(sharingScreen: true)};
      await s.toggleWebcam();
      expect(s.webcam, isFalse);
      expect(s.error, missingPermissionKey);
    });

    test('detects permission errors from tRPC', () {
      expect(
        isPermissionError(TrpcException('nope', code: 'FORBIDDEN')),
        isTrue,
      );
      expect(
        isPermissionError(TrpcException('nope', code: 'UNAUTHORIZED')),
        isTrue,
      );
      expect(isPermissionError('You are not allowed to do that'), isTrue);
      expect(isPermissionError('permission denied'), isTrue);
      expect(isPermissionError(missingPermissionKey), isTrue);
      expect(isPermissionError('transport failed'), isFalse);
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

  group('voice channel status', () {
    test('fromJson maps topic onto displayedVoiceStatus', () {
      final c = KurierChannel.fromJson({
        'id': 20,
        'type': 'VOICE',
        'name': 'public!!',
        'position': 1,
        'topic': 'Playing games',
      });
      expect(c.topic, 'Playing games');
      expect(c.voiceStatus, 'Playing games');
      expect(c.displayedVoiceStatus, 'Playing games');
    });

    test('fromJson prefers voiceStatus over topic', () {
      final c = KurierChannel.fromJson({
        'id': 20,
        'type': 'VOICE',
        'name': 'public!!',
        'voiceStatus': 'Live',
        'topic': 'Playing games',
      });
      expect(c.displayedVoiceStatus, 'Live');
    });

    test('fromJson accepts status alias', () {
      final c = KurierChannel.fromJson({
        'id': 20,
        'type': 'VOICE',
        'name': 'public!!',
        'status': 'AFK',
      });
      expect(c.displayedVoiceStatus, 'AFK');
    });

    test('text channels do not display voice status', () {
      final c = KurierChannel.fromJson({
        'id': 10,
        'type': 'TEXT',
        'name': 'general',
        'topic': 'rules',
      });
      expect(c.topic, 'rules');
      expect(c.displayedVoiceStatus, isNull);
    });

    test('blank topic is not displayed', () {
      final c = KurierChannel.fromJson({
        'id': 20,
        'type': 'VOICE',
        'name': 'public!!',
        'topic': '  ',
      });
      expect(c.displayedVoiceStatus, isNull);
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

    test('resolves mention labels from live display names', () {
      const html =
          '<p>hi <span data-type="mention" data-user-id="7">@ada</span> '
          '<span data-type="mention" data-mention-kind="everyone">@everyone</span></p>';
      final spans = messageHtmlSpans(
        html,
        color: const Color(0xFFFFFFFF),
        linkColor: const Color(0xFF5865F2),
        mentionUsers: {7: KurierUser(id: 7, name: 'ada', nickname: 'Gordon')},
      );
      final text = spans
          .map((s) => s is TextSpan ? s.toPlainText() : '')
          .join();
      expect(text, contains('@Gordon'));
      expect(text, isNot(contains('@ada')));
      expect(text, contains('@everyone'));
    });

    test('user mentions get a tap recognizer when onMention is set', () {
      var tappedId = 0;
      Offset? tappedPos;
      const html =
          '<p><span data-type="mention" data-mention-kind="user" data-user-id="7">@ada</span> '
          '<span data-type="mention" data-mention-kind="everyone">@everyone</span> '
          '<span data-type="mention" data-mention-kind="here">@here</span></p>';
      final spans = messageHtmlSpans(
        html,
        color: const Color(0xFFFFFFFF),
        linkColor: const Color(0xFF5865F2),
        onMention: (id, pos) {
          tappedId = id;
          tappedPos = pos;
        },
      );
      final mention = spans.whereType<TextSpan>().firstWhere(
        (s) => (s.text ?? '').contains('@ada'),
      );
      expect(mention.recognizer, isA<TapGestureRecognizer>());
      (mention.recognizer! as TapGestureRecognizer).onTap!();
      expect(tappedId, 7);
      expect(tappedPos, Offset.zero);

      final everyone = spans.whereType<TextSpan>().firstWhere(
        (s) => (s.text ?? '').contains('@everyone'),
      );
      expect(everyone.recognizer, isNull);
      final here = spans.whereType<TextSpan>().firstWhere(
        (s) => (s.text ?? '').contains('@here'),
      );
      expect(here.recognizer, isNull);
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

    test('detects video and audio media types', () {
      expect(isVideoMediaType('video'), isTrue);
      expect(isVideoMediaType('video/mp4'), isTrue);
      expect(isVideoMediaType('audio/mpeg'), isFalse);
      expect(isAudioMediaType('audio'), isTrue);
      expect(isAudioMediaType('audio/mpeg'), isTrue);
      expect(isAudioMediaType('video/mp4'), isFalse);
      expect(isVideoFileUrl('https://cdn.example/clip.mp4'), isTrue);
      expect(isVideoFileUrl('https://cdn.example/clip.mp4?token=1'), isTrue);
      expect(isAudioFileUrl('/public/track.mp3'), isTrue);
      expect(isAudioFileUrl('https://cdn.example/photo.png'), isFalse);
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

    test('hides attached video and audio links from message HTML', () {
      final video = KurierFile(
        id: 42,
        name: 'abc.mp4',
        originalName: 'SNEEDING_HAS_STARTED_1.mp4',
        md5: '',
        userId: 1,
        size: 1,
        mimeType: 'video/mp4',
        extension: 'mp4',
        createdAt: 0,
      );
      expect(
        hideEmbeddedMediaUrlsInHtml(
          '<p><a href="https://host/public/abc.mp4">SNEEDING_HAS_STARTED_1.mp4</a></p>',
          [video],
        ),
        '<p></p>',
      );
      expect(
        messageHtmlHasVisibleText(
          hideEmbeddedMediaUrlsInHtml('<p>https://host/public/abc.mp4</p>', [
            video,
          ]),
        ),
        isFalse,
      );
      expect(
        hideEmbeddedMediaUrlsInHtml('<p>hello https://cdn.example/a.mp4</p>', [
          video,
        ]),
        '<p>hello https://cdn.example/a.mp4</p>',
      );
      expect(
        hideEmbeddedMediaUrlsInHtml(
          '<p>https://cdn.example/track.mp3</p>',
          const [],
          [
            {
              'kind': 'media',
              'url': 'https://cdn.example/track.mp3',
              'mediaType': 'audio/mpeg',
            },
          ],
        ),
        '<p></p>',
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

    test('parses deviceToken from user login info', () {
      final login = UserLoginInfo.fromJson({
        'ip': '203.0.113.9',
        'country': 'US',
        'city': 'Austin',
        'deviceToken': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
      });
      expect(login.ip, '203.0.113.9');
      expect(login.deviceToken, 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
      expect(UserLoginInfo.fromJson({'deviceToken': '  '}).deviceToken, isNull);
    });

    test('parses signed file tokens without requiring expires together', () {
      final file = KurierFile.fromJson({
        'id': 9,
        'name': 'pic.png',
        '_accessToken': 'tok',
      });
      expect(file.accessToken, 'tok');
      expect(file.accessTokenExpiresAt, isNull);
      expect(fileFromDynamic('pic.png')?.name, 'pic.png');
      expect(fileFromDynamic({'name': ''}), isNull);
    });

    test('classifies video and audio from mime or extension', () {
      KurierFile file({
        String mime = '',
        String ext = '',
        String name = 'file.bin',
        String original = '',
      }) {
        return KurierFile(
          id: 1,
          name: name,
          originalName: original,
          md5: '',
          userId: 1,
          size: 1,
          mimeType: mime,
          extension: ext,
          createdAt: 0,
        );
      }

      expect(file(mime: 'video/mp4').isVideo, isTrue);
      expect(file(mime: 'audio/mpeg').isAudio, isTrue);
      expect(file(ext: 'mp4').isVideo, isTrue);
      expect(file(ext: '.MP3').isAudio, isTrue);
      expect(file(mime: '', ext: '', original: 'clip.webm').isVideo, isTrue);
      expect(file(mime: '', ext: '', name: 'song.flac').isAudio, isTrue);
      expect(file(mime: 'image/png', ext: 'png').isVideo, isFalse);
      expect(file(mime: 'application/pdf', ext: 'pdf').isAudio, isFalse);
    });

    test('keeps avatar and signed url across a partial user update', () {
      final existing = KurierUser.fromJson({
        'id': 2,
        'name': 'Ruzie',
        'profileColor': '#3BA55D',
        'createdAt': 100,
        'avatar': {
          'id': 9,
          'name': 'pic.png',
          '_accessToken': 'tok',
          '_accessTokenExpiresAt': 99,
        },
        'banner': {
          'id': 10,
          'name': 'banner.png',
          '_accessToken': 'ban',
          '_accessTokenExpiresAt': 99,
        },
      });
      final updated = KurierUser.fromJson({
        'id': 2,
        'name': 'Ruzie',
        'status': 'online',
      }, existing: existing);
      expect(updated.avatar?.name, 'pic.png');
      expect(updated.avatar?.accessToken, 'tok');
      expect(updated.banner?.name, 'banner.png');
      expect(updated.profileColor, '#3BA55D');
      expect(updated.createdAt, 100);

      final unsigned = KurierUser.fromJson({
        'id': 2,
        'name': 'Ruzie',
        'avatar': {'id': 9, 'name': 'pic.png'},
      }, existing: existing);
      expect(unsigned.avatar?.accessToken, 'tok');
    });

    test('clears avatar when the update explicitly sends null', () {
      final existing = KurierUser.fromJson({
        'id': 2,
        'name': 'Ruzie',
        'avatar': {'id': 9, 'name': 'pic.png'},
      });
      final updated = KurierUser.fromJson({
        'id': 2,
        'name': 'Ruzie',
        'avatar': null,
      }, existing: existing);
      expect(updated.avatar, isNull);
    });

    test('builds public file urls with optional access tokens', () {
      final api = HttpApi('https://host');
      expect(
        api.publicUrl(KurierFile.fromJson({'name': 'pic.png'})),
        'https://host/public/pic.png',
      );
      expect(api.publicUrl(KurierFile.fromJson({'name': ''})), '');
      expect(
        api.publicUrl(
          KurierFile.fromJson({
            'name': 'pic.png',
            '_accessToken': 'tok',
            '_accessTokenExpiresAt': 99,
          }),
        ),
        'https://host/public/pic.png?accessToken=tok&expires=99',
      );
      expect(
        api.publicUrl(
          KurierFile.fromJson({'name': 'pic.png', '_accessToken': 'tok'}),
        ),
        'https://host/public/pic.png?accessToken=tok',
      );
    });

    test('treats white profile colour as unset', () {
      expect(profileBannerColor('#ffffff'), const Color(0xFF262626));
      expect(profileBannerColor('#FFFFFF'), const Color(0xFF262626));
      expect(profileBannerColor('#fff'), const Color(0xFF262626));
      expect(profileBannerColor(''), const Color(0xFF262626));
      expect(profileBannerColor('#5865F2'), const Color(0xFF5865F2));
      expect(profileBannerColor('3BA55D'), const Color(0xFF3BA55D));
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

  group('voice same-channel rejoin', () {
    SessionController voiceSession() {
      final s = SessionController();
      s.ownUserId = 1;
      s.users[1] = KurierUser(
        id: 1,
        name: 'Ada',
        roleIds: const [AppConfig.ownerRoleId],
      );
      s.channels[10] = KurierChannel(
        id: 10,
        type: 'TEXT',
        name: 'general',
        position: 0,
      );
      s.channels[20] = KurierChannel(
        id: 20,
        type: 'VOICE',
        name: 'General',
        position: 1,
      );
      s.selectedChannelId = 20;
      return s;
    }

    test(
      'selecting the current voice channel joins when disconnected',
      () async {
        final s = voiceSession();
        expect(s.voiceState, 'idle');
        await s.selectChannel(20);
        expect(s.voiceState, isNot('idle'));
      },
    );

    test('selecting the current text channel does not join voice', () async {
      final s = voiceSession();
      s.selectedChannelId = 10;
      await s.selectChannel(10);
      expect(s.voiceState, 'idle');
    });

    test(
      'selecting the current voice channel is a no-op when connected',
      () async {
        final s = voiceSession();
        s.connectedVoiceChannelId = 20;
        s.voiceState = 'connected';
        await s.selectChannel(20);
        expect(s.voiceState, 'connected');
        expect(s.connectedVoiceChannelId, 20);
      },
    );

    test('own voice.onLeave clears connected state', () {
      final s = voiceSession();
      s.connectedVoiceChannelId = 20;
      s.voiceState = 'connected';
      s.voiceMap[20] = {1: VoiceUserState(), 2: VoiceUserState()};
      s.applyVoiceLeave({'channelId': 20, 'userId': 1});
      expect(s.connectedVoiceChannelId, isNull);
      expect(s.voiceState, 'idle');
      expect(s.voiceMap[20]!.containsKey(1), isFalse);
      expect(s.voiceMap[20]!.containsKey(2), isTrue);
    });

    test('other user voice.onLeave does not disconnect', () {
      final s = voiceSession();
      s.connectedVoiceChannelId = 20;
      s.voiceState = 'connected';
      s.voiceMap[20] = {1: VoiceUserState(), 2: VoiceUserState()};
      s.applyVoiceLeave({'channelId': 20, 'userId': 2});
      expect(s.connectedVoiceChannelId, 20);
      expect(s.voiceState, 'connected');
    });

    test('own voice.onMoved to null clears connected state', () {
      final s = voiceSession();
      s.connectedVoiceChannelId = 20;
      s.voiceState = 'connected';
      s.applyVoiceMoved({
        'userId': 1,
        'fromChannelId': 20,
        'toChannelId': null,
      });
      expect(s.connectedVoiceChannelId, isNull);
      expect(s.voiceState, 'idle');
    });
  });

  group('device token', () {
    const uuid = '550e8400-e29b-41d4-a716-446655440000';
    const hex = '550e8400e29b41d4a716446655440000';

    test('normalizes hyphenated, braced, and uppercase UUIDs', () {
      expect(normalizeDeviceToken(uuid), uuid);
      expect(normalizeDeviceToken(hex), uuid);
      expect(normalizeDeviceToken('{${uuid.toUpperCase()}}'), uuid);
      expect(normalizeDeviceToken('  $uuid  '), uuid);
    });

    test('rejects old overlay alphanumeric tokens and junk', () {
      expect(normalizeDeviceToken('abcdefghijklmnop0123456789abcdef'), isNull);
      expect(normalizeDeviceToken('not-a-uuid'), isNull);
      expect(normalizeDeviceToken(''), isNull);
      expect(normalizeDeviceToken(null), isNull);
      expect(
        normalizeDeviceToken('550e8400-e29b-41d4-a716-44665544000'),
        isNull,
      );
    });

    test('generateDeviceToken is a hyphenated UUID v4', () {
      final token = generateDeviceToken(Random(1));
      expect(normalizeDeviceToken(token), token);
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(token),
        isTrue,
      );
    });

    test('resolve prefers prefs, then localStorage, then cookie', () {
      expect(
        resolveDeviceToken(
          fromPrefs: uuid,
          fromLocalStorage: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          fromCookie: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        ),
        uuid,
      );
      expect(
        resolveDeviceToken(
          fromPrefs: 'legacy-alphanumeric-token-not-hex!!',
          fromLocalStorage: uuid,
          fromCookie: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        ),
        uuid,
      );
      expect(
        resolveDeviceToken(
          fromPrefs: 'not-valid',
          fromLocalStorage: 'also-bad',
          fromCookie: uuid,
        ),
        uuid,
      );
    });

    test('invalid overlay token migrates to a created UUID', () {
      const created = '11111111-1111-4111-8111-111111111111';
      expect(
        resolveDeviceToken(
          fromPrefs: 'abcdefghijklmnopqrstuvwxyz012345',
          fromLocalStorage: null,
          fromCookie: '',
          create: () => created,
        ),
        created,
      );
    });

    test('cookie assignment and parse match vanilla', () {
      final assignment = deviceTokenCookieAssignment(uuid);
      expect(assignment, contains('$kDeviceTokenStorageKey=$uuid'));
      expect(assignment, contains('max-age=$kDeviceTokenCookieMaxAge'));
      expect(assignment, contains('path=/'));
      expect(assignment, contains('samesite=lax'));
      expect(assignment, isNot(contains('Secure')));
      expect(
        namedCookieValue(
          'other=1; $kDeviceTokenStorageKey=$uuid; extra=yes',
          kDeviceTokenStorageKey,
        ),
        uuid,
      );
    });

    test('cookie assignment adds Secure when requested', () {
      final assignment = deviceTokenCookieAssignment(uuid, secure: true);
      expect(assignment, contains('$kDeviceTokenStorageKey=$uuid'));
      expect(assignment, contains('max-age=$kDeviceTokenCookieMaxAge'));
      expect(assignment, contains('path=/'));
      expect(assignment, contains('samesite=lax'));
      expect(assignment, contains('Secure'));
    });

    test(
      'HostsStore keeps a valid UUID and migrates alphanumeric prefs',
      () async {
        SharedPreferences.setMockInitialValues({'kurier.deviceToken': uuid});
        var prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final keep = HostsStore();
        await keep.load();
        expect(keep.deviceToken(), uuid);

        SharedPreferences.setMockInitialValues({
          'kurier.deviceToken': 'abcdefghijklmnopqrstuvwxyz012345',
        });
        prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        final migrate = HostsStore();
        await migrate.load();
        final migrated = migrate.deviceToken();
        expect(normalizeDeviceToken(migrated), migrated);
        expect(migrated, isNot('abcdefghijklmnopqrstuvwxyz012345'));
      },
    );
  });

  group('push kind', () {
    test('classifies with dm first', () {
      expect(
        PushKind.classify(isDm: true, mentioned: true, replyToMe: true),
        PushKind.dm,
      );
      expect(
        PushKind.classify(isDm: false, mentioned: true, replyToMe: true),
        PushKind.mention,
      );
      expect(
        PushKind.classify(isDm: false, mentioned: false, replyToMe: true),
        PushKind.reply,
      );
      expect(
        PushKind.classify(isDm: false, mentioned: false, replyToMe: false),
        PushKind.message,
      );
    });

    test('parses wire values and falls back to message', () {
      expect(PushKind.parse('mention'), PushKind.mention);
      expect(PushKind.parse('dm'), PushKind.dm);
      expect(PushKind.parse('reply'), PushKind.reply);
      expect(PushKind.parse('message'), PushKind.message);
      expect(PushKind.parse(null), PushKind.message);
      expect(PushKind.parse('nope'), PushKind.message);
    });

    test('maps to android channel ids', () {
      expect(PushKind.message.androidChannelId, 'kurier_messages');
      expect(PushKind.mention.androidChannelId, 'kurier_mentions');
      expect(PushKind.dm.androidChannelId, 'kurier_dms');
      expect(PushKind.reply.androidChannelId, 'kurier_replies');
      expect(PushKind.message.androidNotificationId, 1001);
      expect(PushKind.mention.androidNotificationId, 1002);
      expect(PushKind.dm.androidNotificationId, 1003);
      expect(PushKind.reply.androidNotificationId, 1004);
    });

    test('inbox titles count by kind', () {
      expect(PushKind.mention.inboxTitle(1), 'Mention');
      expect(PushKind.mention.inboxTitle(3), '3 mentions');
      expect(PushKind.reply.inboxTitle(1), 'Reply');
      expect(PushKind.reply.inboxTitle(2), '2 replies');
      expect(PushKind.dm.inboxTitle(1), 'Direct message');
      expect(PushKind.dm.inboxTitle(4), '4 direct messages');
      expect(PushKind.message.inboxTitle(1), 'Message');
      expect(PushKind.message.inboxTitle(5), '5 messages');
    });
  });

  group('push inbox', () {
    test('stacks one slot per kind and does not mix types', () {
      final inbox = PushInbox();
      inbox.add(
        PushKind.mention,
        const PushInboxLine(
          author: 'Ada',
          body: 'hi',
          messageId: 1,
          channelLabel: '#lounge',
        ),
      );
      inbox.add(
        PushKind.mention,
        const PushInboxLine(
          author: 'Bob',
          body: 'hey',
          messageId: 2,
          channelLabel: '#lounge',
        ),
      );
      inbox.add(
        PushKind.reply,
        const PushInboxLine(
          author: 'Cy',
          body: 're',
          messageId: 3,
          channelLabel: '#dev',
        ),
      );
      expect(inbox.lines(PushKind.mention).length, 2);
      expect(inbox.lines(PushKind.reply).length, 1);
      expect(inbox.lines(PushKind.dm), isEmpty);
      expect(inbox.presentation(PushKind.mention).title, '#lounge');
      expect(inbox.presentation(PushKind.mention).lines, [
        'Ada: hi',
        'Bob: hey',
      ]);
      expect(inbox.presentation(PushKind.reply).title, '#dev');
      expect(inbox.presentation(PushKind.reply).body, 're');
    });

    test('single mention titles the channel, mixed channels count instead', () {
      final inbox = PushInbox();
      inbox.add(
        PushKind.mention,
        const PushInboxLine(
          author: 'Ada',
          body: '@tester',
          messageId: 1,
          channelLabel: '#general',
        ),
      );
      expect(inbox.presentation(PushKind.mention).title, '#general');
      expect(inbox.presentation(PushKind.mention).body, '@tester');
      inbox.add(
        PushKind.mention,
        const PushInboxLine(
          author: 'Bob',
          body: 'hey',
          messageId: 2,
          channelLabel: '#random',
        ),
      );
      expect(inbox.presentation(PushKind.mention).title, '2 mentions');
    });

    test('channelIds collects unique channels in a kind', () {
      final inbox = PushInbox();
      inbox.add(
        PushKind.mention,
        const PushInboxLine(
          author: 'Ada',
          body: 'a',
          channelId: 10,
          messageId: 1,
        ),
      );
      inbox.add(
        PushKind.mention,
        const PushInboxLine(
          author: 'Bob',
          body: 'b',
          channelId: 11,
          messageId: 2,
        ),
      );
      inbox.add(
        PushKind.mention,
        const PushInboxLine(
          author: 'Cy',
          body: 'c',
          channelId: 10,
          messageId: 3,
        ),
      );
      expect(inbox.channelIds(PushKind.mention), {10, 11});
      expect(inbox.channelIds(PushKind.reply), isEmpty);
    });

    test('dedupes by message id and drops a channel from every kind', () {
      final inbox = PushInbox();
      inbox.add(
        PushKind.mention,
        const PushInboxLine(
          author: 'Ada',
          body: 'one',
          channelId: 10,
          messageId: 1,
        ),
      );
      inbox.add(
        PushKind.mention,
        const PushInboxLine(
          author: 'Ada',
          body: 'one edited',
          channelId: 10,
          messageId: 1,
        ),
      );
      inbox.add(
        PushKind.mention,
        const PushInboxLine(
          author: 'Bob',
          body: 'two',
          channelId: 11,
          messageId: 2,
        ),
      );
      expect(inbox.lines(PushKind.mention).length, 2);
      expect(inbox.lines(PushKind.mention).first.body, 'one edited');
      final changed = inbox.removeChannel(10);
      expect(changed, {PushKind.mention});
      expect(inbox.lines(PushKind.mention).single.body, 'two');
    });

    test('round-trips encoded lines', () {
      final inbox = PushInbox();
      inbox.add(
        PushKind.dm,
        const PushInboxLine(
          author: 'Ada',
          body: 'secret',
          channelId: 8,
          messageId: 9,
        ),
      );
      final copy = PushInbox()..loadEncoded(inbox.encode());
      expect(copy.presentation(PushKind.dm).title, 'Ada');
      expect(copy.lines(PushKind.dm).single.messageId, 9);
    });
  });

  group('notify prefs store', () {
    test('applyNotifyPrefs writes all four flags', () async {
      SharedPreferences.setMockInitialValues({});
      final store = HostsStore();
      await store.load();
      await store.applyNotifyPrefs(
        notifyAll: true,
        mentions: false,
        dm: false,
        replies: true,
      );
      expect(store.notifyAll, isTrue);
      expect(store.notifyMentions, isFalse);
      expect(store.notifyDm, isFalse);
      expect(store.notifyReplies, isTrue);
    });
  });
}

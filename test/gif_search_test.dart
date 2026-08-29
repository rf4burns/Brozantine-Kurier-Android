import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kurier_web/app/l10n.dart';
import 'package:kurier_web/app/theme.dart';
import 'package:kurier_web/core/gif_search.dart';
import 'package:kurier_web/core/klipy_discover.dart';
import 'package:kurier_web/protocol/config.dart';
import 'package:kurier_web/protocol/models.dart';
import 'package:kurier_web/session/session_controller.dart';
import 'package:kurier_web/ui/gif_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('gifUrlsFromJson reads vanilla results and KLIPY nested files', () {
    expect(
      gifUrlsFromJson({
        'results': [
          {'url': 'https://cdn.example/a.gif'},
          {'previewUrl': 'https://cdn.example/b.gif'},
        ],
      }),
      [
        'https://cdn.example/a.gif',
        'https://cdn.example/b.gif',
      ],
    );

    expect(
      gifUrlsFromJson({
        'data': {
          'data': [
            {
              'file': {
                'hd': {
                  'gif': {'url': 'https://klipy.example/hd.gif'},
                },
              },
            },
          ],
        },
      }),
      ['https://klipy.example/hd.gif'],
    );
  });

  test('gifUrlsFromJson reads flat data lists and webp fallbacks', () {
    expect(
      gifUrlsFromJson({
        'data': [
          {
            'file': {
              'sm': {
                'webp': {'url': 'https://klipy.example/sm.webp'},
              },
            },
          },
        ],
      }),
      ['https://klipy.example/sm.webp'],
    );

    expect(
      gifUrlFromItem({
        'file': {
          'hd': {
            'gif': {'url': 'https://klipy.example/hd.gif'},
          },
          'sm': {
            'gif': {'url': 'https://klipy.example/sm.gif'},
          },
        },
      }),
      'https://klipy.example/hd.gif',
    );

    expect(
      gifPreviewUrlFromItem({
        'file': {
          'hd': {
            'gif': {'url': 'https://klipy.example/hd.gif'},
          },
          'sm': {
            'gif': {'url': 'https://klipy.example/sm.gif'},
          },
        },
      }),
      'https://klipy.example/sm.gif',
    );
  });

  test('klipyKeyFor prefers settings, then Brozantine default', () {
    expect(AppConfig.isBrozantineHost(null), isFalse);
    expect(AppConfig.isBrozantineHost('example.com'), isFalse);
    expect(AppConfig.isBrozantineHost(AppConfig.defaultHost), isTrue);
    expect(AppConfig.isBrozantineHost('kurier.brozantine.com'), isTrue);
    expect(AppConfig.isBrozantineHost('chat.brozantine.com:443'), isTrue);

    expect(
      AppConfig.klipyKeyFor(host: AppConfig.defaultHost),
      AppConfig.brozantineKlipyKey,
    );
    expect(AppConfig.klipyKeyFor(host: 'example.com'), isEmpty);
    expect(
      AppConfig.klipyKeyFor(stored: ' user-key ', host: AppConfig.defaultHost),
      'user-key',
    );
    expect(
      AppConfig.klipyKeyFor(host: 'example.com', discovered: ' server-key '),
      'server-key',
    );
    expect(
      AppConfig.klipyKeyFor(
        stored: 'user-key',
        host: 'example.com',
        discovered: 'server-key',
      ),
      'user-key',
    );
  });

  test('extractKlipyKeyFromJs reads vanilla scrape URL and env keys', () {
    expect(
      extractKlipyKeyFromJs(
        'https://api.klipy.com/api/v1/${AppConfig.brozantineKlipyKey}/gifs/trending',
      ),
      AppConfig.brozantineKlipyKey,
    );
    expect(
      extractKlipyKeyFromJs(
        'fetch("https://api.giphy.com/v1/gifs/search?api_key=giphyKeyValue1234")',
      ),
      'giphyKeyValue1234',
    );
    expect(extractKlipyKeyFromJs('no gif keys here'), isNull);
  });

  test('klipyKeyFromServerMap reads join and publicSettings hints', () {
    expect(
      klipyKeyFromServerMap({
        'publicSettings': {'klipyApiKey': 'join-hint-key-1234'},
      }),
      'join-hint-key-1234',
    );
    expect(klipyKeyFromServerMap({'name': 'Kurier'}), isNull);
  });

  test('tryDiscoverKlipyKey scrapes vanilla index bundle', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/vanilla/client') {
        return http.Response(
          '<html><script src="/assets/index-abc123.js"></script></html>',
          200,
        );
      }
      if (req.url.path == '/assets/index-abc123.js') {
        return http.Response(
          'https://api.klipy.com/api/v1/scrapedKlipyKey1234/gifs/trending',
          200,
        );
      }
      return http.Response('', 404);
    });

    expect(
      await tryDiscoverKlipyKey(
        origin: 'https://chat.example',
        client: client,
      ),
      'scrapedKlipyKey1234',
    );
  });

  test('SavedHost persists a baked KLIPY key', () {
    final host = SavedHost(host: 'chat.example', klipy: 'baked-key-abcdef');
    final roundTrip = SavedHost.fromJson(host.toJson());
    expect(roundTrip.klipy, 'baked-key-abcdef');
  });

  test('gifApiKey follows host and stored settings', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SessionController();
    await s.store.load();

    s.activeHost = 'example.com';
    expect(s.gifApiKey, isEmpty);

    s.activeHost = AppConfig.defaultHost;
    expect(s.gifApiKey, AppConfig.brozantineKlipyKey);

    await s.store.setKlipy(' pasted-key ');
    expect(s.gifApiKey, 'pasted-key');
  });

  test('gifApiKey uses a key baked in from the joined server', () async {
    SharedPreferences.setMockInitialValues({});
    final s = SessionController();
    await s.store.load();
    s.activeHost = 'example.com';
    s.serverKlipyKey = 'host-baked-key';
    expect(s.gifApiKey, 'host-baked-key');
  });

  testWidgets('GifPicker asks for a KLIPY key off Brozantine hosts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final s = SessionController();
    s.activeHost = 'example.com';
    await s.store.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(ThemePreset.dark, defaultAccent),
        locale: const Locale('en'),
        localizationsDelegates: const [
          L10nDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(
          body: SizedBox(
            width: 352,
            height: 420,
            child: GifPicker(session: s, onSelect: (_) {}),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('Set a KLIPY API key in Settings to search GIFs'),
      findsOneWidget,
    );
    expect(find.text('No GIFs found'), findsNothing);
  });
}

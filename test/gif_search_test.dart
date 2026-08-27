import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurier_web/app/l10n.dart';
import 'package:kurier_web/app/theme.dart';
import 'package:kurier_web/core/gif_search.dart';
import 'package:kurier_web/protocol/config.dart';
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

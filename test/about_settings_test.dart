import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurier_web/app/l10n.dart';
import 'package:kurier_web/app/theme.dart';
import 'package:kurier_web/session/session_controller.dart';
import 'package:kurier_web/ui/settings_user.dart';

void main() {
  testWidgets('About shows version, changelog, and third-party buttons', (
    tester,
  ) async {
    final s = SessionController();
    s.logs.add('ready');

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
          body: SingleChildScrollView(child: AboutSettingsTab(s: s)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Version:'), findsOneWidget);
    expect(find.text('Changelog'), findsOneWidget);
    expect(find.text('Third Party Usage'), findsOneWidget);
    expect(
      find.textContaining('Emoji artwork from Twemoji'),
      findsNothing,
    );

    await tester.tap(find.text('Changelog'));
    await tester.pumpAndSettle();
    expect(find.text('1.0.6'), findsWidgets);
    expect(
      find.textContaining('YouTube videos play in chat again'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.textContaining('First Android client'),
      80,
      scrollable: find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('1.0.0'), findsWidgets);
    expect(find.textContaining('First Android client'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Third Party Usage'));
    await tester.pumpAndSettle();
    expect(find.text('Twemoji (Twitter)'), findsOneWidget);
    expect(find.textContaining('licensed CC-BY 4.0'), findsOneWidget);
  });
}

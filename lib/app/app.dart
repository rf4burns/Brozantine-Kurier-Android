import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../protocol/platform.dart';
import '../session/session_controller.dart';
import '../ui/home_shell.dart';
import '../ui/login_screen.dart';
import 'browser_branding.dart';
import 'l10n.dart';
import 'theme.dart';

class KurierApp extends ConsumerWidget {
  const KurierApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    ThemePreset preset;
    try {
      preset = ThemePreset.values.firstWhere((p) => p.name == s.themePreset);
    } catch (_) {
      preset = ThemePreset.dark;
    }
    Color accent;
    try {
      accent = Color(int.parse(s.accent.replaceFirst('#', 'FF'), radix: 16));
    } catch (_) {
      accent = defaultAccent;
    }
    final locale = Locale(s.locale);
    final title = browserTabTitle(
      serverName: s.serverName,
      infoName: s.info?.name ?? '',
    );
    final logo = s.info?.logo;
    PlatformBridge.applyBrowserBranding(
      title: title,
      iconUrl: browserTabIconUrl(
        logoUrl: logo != null ? s.fileUrl(logo) : null,
        origin: s.httpApi?.origin,
      ),
    );
    return MaterialApp(
      title: title,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(preset, accent),
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        L10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return GestureDetector(
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            PlatformBridge.unlockAudio();
          },
          child: child,
        );
      },
      home: switch (s.phase) {
        SessionPhase.boot || SessionPhase.connecting => const _Boot(),
        SessionPhase.login => const LoginScreen(),
        SessionPhase.disconnected => const DisconnectScreen(),
        SessionPhase.ready => const HomeShell(),
      },
    );
  }
}

class _Boot extends StatelessWidget {
  const _Boot();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.p.rail,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Kurier',
              style: TextStyle(
                color: context.p.foreground,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

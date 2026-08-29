import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../native/android_runtime.dart';
import '../protocol/platform.dart';
import '../session/session_controller.dart';
import '../ui/home_shell.dart';
import '../ui/login_screen.dart';
import 'app_platform.dart';
import 'browser_branding.dart';
import 'l10n.dart';
import 'theme.dart';

class KurierApp extends ConsumerStatefulWidget {
  const KurierApp({super.key});

  @override
  ConsumerState<KurierApp> createState() => _KurierAppState();
}

class _KurierAppState extends ConsumerState<KurierApp>
    with WidgetsBindingObserver {
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (androidAppLockEnabled) _locked = true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (androidAppLockEnabled) setState(() => _locked = true);
    }
  }

  Future<void> _unlock() async {
    final ok = await androidUnlock();
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
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
      accent = isNativeMobile ? kurierAccent : defaultAccent;
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
      home: Stack(
        children: [
          switch (s.phase) {
            SessionPhase.boot || SessionPhase.connecting => const _Boot(),
            SessionPhase.login => const LoginScreen(),
            SessionPhase.disconnected => const DisconnectScreen(),
            SessionPhase.ready => const HomeShell(),
          },
          if (_locked && androidAppLockEnabled)
            Positioned.fill(
              child: Material(
                color: const Color(0xE60B1F3A),
                child: Center(
                  child: FilledButton.icon(
                    onPressed: _unlock,
                    icon: const Icon(Icons.lock_open),
                    label: const Text('Unlock Kurier'),
                  ),
                ),
              ),
            ),
        ],
      ),
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
            Image.asset(
              'assets/branding/kurier.png',
              width: 96,
              height: 96,
              errorBuilder: (_, _, _) => Text(
                'Kurier',
                style: TextStyle(
                  color: context.p.foreground,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
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

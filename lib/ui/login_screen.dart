import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/l10n.dart';
import '../app/theme.dart';
import '../protocol/config.dart';
import '../protocol/http_api.dart';
import '../protocol/permissions.dart';
import '../session/session_controller.dart';
import 'shared.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final identity = TextEditingController();
  final password = TextEditingController();
  final serverPassword = TextEditingController();
  final hostCtrl = TextEditingController();
  final answer = TextEditingController();
  final newPass = TextEditingController();
  final confirm = TextEditingController();
  bool autoLogin = false;
  bool resetMode = false;
  bool showHosts = false;
  String? questionId;

  @override
  void dispose() {
    identity.dispose();
    password.dispose();
    serverPassword.dispose();
    hostCtrl.dispose();
    answer.dispose();
    newPass.dispose();
    confirm.dispose();
    super.dispose();
  }

  L10n get l => L10n.of(context);

  HttpApi _api(SessionController s) {
    return s.httpApi ?? HttpApi(s.originOf(s.activeHost ?? AppConfig.defaultHost));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sessionProvider);
    final insecure = Uri.base.scheme != 'https' &&
        Uri.base.host != 'localhost' &&
        Uri.base.host != '127.0.0.1';
    return Scaffold(
      backgroundColor: context.p.background,
      body: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: _card(context, s, insecure),
                        ),
                        const SizedBox(height: 16),
                        _footer(s),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: _languageButton(context, s),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, SessionController s, bool insecure) {
    return Container(
      decoration: BoxDecoration(
        color: context.p.sidebar,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.p.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 32,
            offset: Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(s),
          const SizedBox(height: 20),
          if (s.error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(s.error!, style: TextStyle(color: context.p.dnd)),
            ),
          if (resetMode) _resetForm(s) else _loginForm(s, insecure),
        ],
      ),
    );
  }

  Widget _header(SessionController s) {
    final name = s.info?.name;
    final desc = s.info?.description;
    final logoUrl = s.info?.logo != null ? s.fileUrl(s.info!.logo!) : null;
    return Column(
      children: [
        GestureDetector(
          onLongPress: () => setState(() => showHosts = !showHosts),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: logoUrl != null && logoUrl.isNotEmpty
                ? Image.network(
                    logoUrl,
                    height: 80,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => _logoFallback(name),
                  )
                : _logoFallback(name),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          resetMode ? l('resetPassword') : l('welcomeBack'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.p.foreground,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        if (name != null && name.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.p.muted, fontSize: 14),
          ),
        ],
        if (!resetMode && desc != null && desc.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            desc,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.p.muted, fontSize: 14, height: 1.35),
          ),
        ],
        if (s.probing)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  Widget _logoFallback(String? name) {
    final letter = (name != null && name.isNotEmpty) ? name[0].toUpperCase() : 'K';
    return Container(
      width: 80,
      height: 80,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.p.rail,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: context.p.foreground,
          fontSize: 36,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _loginForm(SessionController s, bool insecure) {
    final invite = s.pendingInvite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHosts) ...[
          _hosts(s),
          const SizedBox(height: 16),
        ],
        _labeledField(
          label: l('identity'),
          help: l('identityHelp'),
          child: KurierField(
            controller: identity,
            onSubmitted: (_) => _submit(s),
          ),
        ),
        const SizedBox(height: 14),
        _labeledField(
          label: l('password'),
          child: KurierField(
            controller: password,
            obscure: true,
            onSubmitted: (_) => _submit(s),
          ),
        ),
        if (s.needsServerPassword) ...[
          const SizedBox(height: 14),
          _labeledField(
            label: l('password'),
            child: KurierField(
              controller: serverPassword,
              obscure: true,
            ),
          ),
        ],
        const SizedBox(height: 16),
        InkWell(
          onTap: () => setState(() => autoLogin = !autoLogin),
          borderRadius: BorderRadius.circular(8),
          child: Row(
            children: [
              Switch(
                value: autoLogin,
                onChanged: (v) => setState(() => autoLogin = v),
              ),
              const SizedBox(width: 8),
              Text(
                l('autoLogin'),
                style: TextStyle(color: context.p.foreground, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (insecure)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(l('insecure'), style: TextStyle(color: context.p.dnd, fontSize: 12)),
          ),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: s.phase == SessionPhase.connecting ? null : () => _submit(s),
            style: FilledButton.styleFrom(
              backgroundColor: context.k.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            child: s.phase == SessionPhase.connecting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(l('connect')),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => resetMode = true),
          child: Text(
            l('forgotPassword'),
            style: TextStyle(color: context.k.accent, fontSize: 14),
          ),
        ),
        if (s.info?.allowNewUsers == false && (invite == null || invite.isEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l('registrationClosed'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.p.faint, fontSize: 12),
            ),
          ),
        if (invite != null && invite.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${l('inviteCode')}: $invite',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.p.muted, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _labeledField({
    required String label,
    String? help,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: context.p.foreground,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            if (help != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: help,
                child: Icon(Icons.help_outline, size: 16, color: context.p.faint),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _hosts(SessionController s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final h in s.hosts)
              InputChip(
                selected: h.host == s.activeHost,
                label: Text(h.name ?? h.host),
                onPressed: () => s.switchHost(h.host),
                onDeleted: () => s.removeHost(h.host),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: KurierField(
                controller: hostCtrl,
                hint: l('addServerHint'),
              ),
            ),
            const SizedBox(width: 8),
            KurierButton(
              label: l('confirm'),
              onPressed: () async {
                await s.addHost(hostCtrl.text);
                hostCtrl.clear();
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _resetForm(SessionController s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _labeledField(
          label: l('identity'),
          child: KurierField(controller: identity),
        ),
        if (questionId != null) ...[
          const SizedBox(height: 12),
          Text(l('q_$questionId'), style: TextStyle(color: context.p.muted)),
          const SizedBox(height: 8),
          _labeledField(
            label: l('securityAnswer'),
            child: KurierField(controller: answer),
          ),
          const SizedBox(height: 8),
          _labeledField(
            label: l('newPassword'),
            child: KurierField(controller: newPass, obscure: true),
          ),
          const SizedBox(height: 8),
          _labeledField(
            label: l('confirmPassword'),
            child: KurierField(controller: confirm, obscure: true),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: () => _doReset(s),
            style: FilledButton.styleFrom(
              backgroundColor: context.k.accent,
              foregroundColor: Colors.white,
            ),
            child: Text(questionId == null ? l('continueBtn') : l('resetPassword')),
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            resetMode = false;
            questionId = null;
          }),
          child: Text(l('backToLogin')),
        ),
      ],
    );
  }

  Widget _footer(SessionController s) {
    final version = s.info?.version;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (version != null && version.isNotEmpty) ...[
              Text(
                'v$version',
                style: TextStyle(color: context.p.faint, fontSize: 12),
              ),
              const SizedBox(width: 8),
            ],
            GestureDetector(
              onTap: () => launchUrl(Uri.parse(AppConfig.githubUrl)),
              child: Text(
                l('github'),
                style: TextStyle(color: context.p.faint, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => setState(() => showHosts = !showHosts),
          child: Text(
            s.activeHost ?? AppConfig.defaultHost,
            style: TextStyle(color: context.p.faint, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _languageButton(BuildContext context, SessionController s) {
    return Material(
      color: context.p.sidebar,
      shape: const CircleBorder(),
      child: PopupMenuButton<String>(
        tooltip: l('language'),
        icon: Icon(Icons.language, color: context.p.muted),
        onSelected: (code) {
          s.locale = code;
          s.store.setLocale(code);
          s.refresh();
        },
        itemBuilder: (ctx) => [
          for (final loc in supportedLocales)
            PopupMenuItem(value: loc.languageCode, child: Text(loc.languageCode)),
        ],
      ),
    );
  }

  void _submit(SessionController s) {
    s.login(
      identity: identity.text,
      password: password.text,
      autoLogin: autoLogin,
      serverPassword: serverPassword.text,
    );
  }

  Future<void> _doReset(SessionController s) async {
    try {
      final api = _api(s);
      if (questionId == null) {
        final q = await api.resetQuestion(identity.text);
        setState(() => questionId = q ?? securityQuestionIds.first);
      } else {
        await api.resetPassword(
          identity: identity.text,
          answer: answer.text,
          newPassword: newPass.text,
          confirmNewPassword: confirm.text,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l('resetSuccess'))),
        );
        setState(() {
          resetMode = false;
          questionId = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class DisconnectScreen extends ConsumerWidget {
  const DisconnectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sessionProvider);
    final l = L10n.of(context);
    String msg = l('disconnected');
    switch (s.disconnectCode) {
      case 40000:
        msg = l('kicked');
      case 40001:
        msg = l('banned');
      case 40002:
        msg = l('serverShutdown');
      case 40003:
        msg = l('accountDeleted');
    }
    if (s.disconnectReason.isNotEmpty) {
      msg = '$msg\n${s.disconnectReason}';
    }
    return Scaffold(
      backgroundColor: context.p.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.p.foreground, fontSize: 18),
                ),
                const SizedBox(height: 16),
                KurierButton(
                  label: l('reconnect'),
                  onPressed: () {
                    final host = s.activeHost;
                    final token = s.hosts
                        .where((h) => h.host == host)
                        .firstOrNull
                        ?.token;
                    if (host != null && token != null) {
                      s.connect(host: host, existingToken: token);
                    } else {
                      s.phase = SessionPhase.login;
                      s.refresh();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

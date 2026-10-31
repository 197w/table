import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/email_auth.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'ui.dart';

enum _Mode { login, register, sms }

/// Logowanie e-mailem (e-mail → kod z e-maila → hasło) i rejestracja (numer → e-mail → kod → hasło).
/// Numer konta musi być tym samym, który kierownik wpisał w panelu przy pracowniku: po nim lokal rozpoznaje,
/// kto zaczyna zmianę. Stare konta bez e-maila logują się jeszcze kodem SMS.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _phoneHint = 'Ten sam numer, który podałeś kierownikowi: po nim lokal rozpoznaje, kto zaczyna zmianę.';

  _Mode _mode = _Mode.login;

  @override
  Widget build(BuildContext context) {
    // Po haśle aplikacja sama przechodzi dalej (main.dart patrzy na sesję i AuthPending).
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: switch (_mode) {
            _Mode.login => EmailAuthFlow(
              key: const ValueKey('logowanie'),
              mode: EmailAuthMode.login,
              leading: const _AppBadge(),
              showBack: true,
              phoneHint: _phoneHint,
              onDone: () {},
              onSwitchMode: () => setState(() => _mode = _Mode.register),
              onSmsLogin: () => setState(() => _mode = _Mode.sms),
            ),
            _Mode.register => EmailAuthFlow(
              key: const ValueKey('rejestracja'),
              mode: EmailAuthMode.register,
              leading: const _AppBadge(),
              showBack: true,
              phoneHint: _phoneHint,
              onDone: () {},
              onSwitchMode: () => setState(() => _mode = _Mode.login),
            ),
            _Mode.sms => _SmsLogin(onBack: () => setState(() => _mode = _Mode.login)),
          },
        ),
      ),
    );
  }
}

class _AppBadge extends StatelessWidget {
  const _AppBadge();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.accentTint, borderRadius: BorderRadius.circular(14)),
            child: Glyph(AppIcons.userCheck.duotone, size: 24, color: AppColors.accent),
          ),
          const SizedBox(width: 12),
          Text('Table for employees', style: text.titleMedium),
        ],
      ),
    );
  }
}

/// Stare konto bez e-maila: numer telefonu i kod SMS. Potem e-mail dodaje się w Koncie.
class _SmsLogin extends ConsumerStatefulWidget {
  const _SmsLogin({required this.onBack});

  final VoidCallback onBack;

  @override
  ConsumerState<_SmsLogin> createState() => _SmsLoginState();
}

class _SmsLoginState extends ConsumerState<_SmsLogin> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _sentTo;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final phone = normalizePolishPhone(_phone.text);
    if (phone == null) {
      showMessage(context, 'Wpisz 9-cyfrowy numer telefonu.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(staffRepositoryProvider).sendCode(phone);
      if (mounted) setState(() => _sentTo = phone);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final phone = _sentTo;
    if (phone == null || _busy) return;
    if (_code.text.trim().length != 6) {
      showMessage(context, 'Kod ma 6 cyfr.');
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(staffRepositoryProvider);
    try {
      await repo.verifyCode(phone, _code.text.trim());
    } catch (e) {
      // Sesja już jest, więc kod zadziałał przy wcześniejszej próbie.
      if (mounted && repo.session == null) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sent = _sentTo != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onBack();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _busy ? null : widget.onBack,
              icon: const Glyph(AppIcons.arrowLeft, size: 18),
              label: const Text('Wstecz'),
            ),
          ),
          const _AppBadge(),
          const SizedBox(height: 24),
          Semantics(header: true, child: Text('Konto bez e-maila', style: text.headlineMedium)),
          const SizedBox(height: 8),
          Text(
            sent
                ? 'Wpisz kod z SMS-a wysłanego na $_sentTo.'
                : 'Dla kont założonych numerem telefonu. Po zalogowaniu dodaj e-mail w Koncie: '
                      'odtąd będziesz logować się e-mailem.',
            style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 28),
          if (!sent)
            TextField(
              controller: _phone,
              autofocus: true,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
                LengthLimitingTextInputFormatter(11),
              ],
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                labelText: 'Numer telefonu',
                hintText: '600 700 800',
                prefixText: '+48 ',
              ),
            )
          else
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              style: text.headlineSmall?.copyWith(letterSpacing: 8),
              onChanged: (v) {
                if (v.length == 6) _verify();
              },
              decoration: const InputDecoration(labelText: 'Kod z SMS-a'),
            ),
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : (sent ? _verify : _send),
              child: Text(sent ? 'Zaloguj się' : 'Wyślij kod SMS'),
            ),
          ),
          if (sent) ...[
            const SizedBox(height: 12),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _sentTo = null;
                      _code.clear();
                    }),
              child: const Text('Zmień numer'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Konto → „Dodaj e-mail” (stare konto z logowania SMS).
class AddEmailScreen extends ConsumerWidget {
  const AddEmailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(leading: glassLeading(context), title: const Text('Dodaj e-mail')),
      body: SafeArea(
        child: ContentWidth(
          child: AddEmailFlow(
            onDone: () {
              ref.invalidate(accountProvider);
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }
}

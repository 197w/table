import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'package:table_core/email_auth.dart';

import '../../app/app.dart';
import '../../data/providers.dart';

/// Zamienia wpisany numer na format +48XXXXXXXXX. Na start tylko polskie numery.
String? normalizePolishPhone(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 9) return '+48$digits';
  if (digits.length == 11 && digits.startsWith('48')) return '+$digits';
  return null;
}

/// Dokąd przejść po zalogowaniu. Przyjmujemy tylko ścieżki aplikacji spoza ekranów logowania.
String _safeNext(String? next) {
  final ok =
      next != null &&
      next.startsWith('/') &&
      !next.startsWith(AppRoutes.login) &&
      !next.startsWith(AppRoutes.register);
  return ok ? next : AppRoutes.discover;
}

String _displayPhone(String e164) {
  final d = e164.replaceFirst('+48', '');
  if (d.length != 9) return e164;
  return '+48 ${d.substring(0, 3)} ${d.substring(3, 6)} ${d.substring(6)}';
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(leading: glassLeading(context), ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text(title, style: text.headlineMedium),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 28),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    this.errorText,
    this.onSubmitted,
    this.label = 'Numer telefonu',
  });

  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      keyboardType: TextInputType.phone,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
        LengthLimitingTextInputFormatter(11),
      ],
      textInputAction: TextInputAction.next,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: '600 700 800',
        prefixText: '+48 ',
        errorText: errorText,
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      autofillHints: const [AutofillHints.password],
      textInputAction: TextInputAction.done,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Pokaż hasło' : 'Ukryj hasło',
          icon: Glyph(_obscure ? AppIcons.eye : AppIcons.eyeSlash),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

class _BusyButton extends StatelessWidget {
  const _BusyButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textMuted,
              ),
            )
          : Text(label),
    );
  }
}

// ---------------------------------------------------------------
// Logowanie i rejestracja e-mailem (EmailAuthFlow z table_core)
// ---------------------------------------------------------------

/// Logowanie: e-mail → kod z e-maila → hasło.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, this.next});

  final String? next;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: glassLeading(context), ),
      body: SafeArea(
        child: EmailAuthFlow(
          mode: EmailAuthMode.login,
          onDone: () => context.go(_safeNext(next)),
          onSwitchMode: () => context.pushReplacement(
            AppRoutes.withNext(AppRoutes.register, next),
          ),
          onSmsLogin: () =>
              context.push(AppRoutes.withNext(AppRoutes.smsLogin, next)),
        ),
      ),
    );
  }
}

/// Rejestracja: numer telefonu → e-mail → kod z e-maila → hasło. Jeden numer to jedno konto.
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key, this.next});

  final String? next;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: glassLeading(context), ),
      body: SafeArea(
        child: EmailAuthFlow(
          mode: EmailAuthMode.register,
          onDone: () => context.go(_safeNext(next)),
          onSwitchMode: () => context.pushReplacement(
            AppRoutes.withNext(AppRoutes.login, next),
          ),
          phoneHint: 'Lokale widzą go przy rezerwacjach i zamówieniach.',
        ),
      ),
    );
  }
}

/// Stare konto z logowania SMS: dodanie e-maila (Ustawienia → Konto → Informacje o logowaniu).
class AddEmailScreen extends ConsumerWidget {
  const AddEmailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(leading: glassLeading(context), title: const Text('Dodaj e-mail')),
      body: SafeArea(
        child: AddEmailFlow(
          onDone: () {
            ref.invalidate(profileProvider);
            context.pop();
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Stare konta bez e-maila: logowanie numerem telefonu (kod SMS albo hasło)
// ---------------------------------------------------------------

class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key, this.next});

  final String? next;

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  final _phone = TextEditingController();
  String? _phoneError;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String? _validPhone() {
    final phone = normalizePolishPhone(_phone.text);
    setState(
      () => _phoneError = phone == null
          ? 'Wpisz 9-cyfrowy numer telefonu.'
          : null,
    );
    return phone;
  }

  Future<void> _sendCode() async {
    final phone = _validPhone();
    if (phone == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).sendLoginCode(phone);
      if (!mounted) return;
      context.push(
        AppRoutes.withNext(
          '${AppRoutes.smsLogin}/kod',
          widget.next,
          phone: phone,
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _usePassword() {
    final phone = _validPhone();
    if (phone == null) return;
    context.push(
      AppRoutes.withNext(
        '${AppRoutes.smsLogin}/haslo',
        widget.next,
        phone: phone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Konto bez e-maila',
      subtitle:
          'Dla kont założonych numerem telefonu. Po zalogowaniu dodaj e-mail w ustawieniach konta: '
          'odtąd będziesz logować się e-mailem.',
      children: [
        _PhoneField(
          controller: _phone,
          errorText: _phoneError,
          onSubmitted: (_) => _sendCode(),
        ),
        const SizedBox(height: 24),
        _BusyButton(label: 'Wyślij kod SMS', busy: _busy, onPressed: _sendCode),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : _usePassword,
          child: const Text('Zaloguj się hasłem'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Logowanie: hasło
// ---------------------------------------------------------------

class PasswordLoginScreen extends ConsumerStatefulWidget {
  const PasswordLoginScreen({super.key, required this.phone, this.next});

  final String phone;
  final String? next;

  @override
  ConsumerState<PasswordLoginScreen> createState() =>
      _PasswordLoginScreenState();
}

class _PasswordLoginScreenState extends ConsumerState<PasswordLoginScreen> {
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .signInWithPassword(phone: widget.phone, password: _password.text);
      if (mounted) context.go(_safeNext(widget.next));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Wpisz hasło',
      subtitle: 'Logujesz się numerem ${_displayPhone(widget.phone)}.',
      children: [
        AutofillGroup(
          child: _PasswordField(
            controller: _password,
            label: 'Hasło',
            onSubmitted: (_) => _login(),
          ),
        ),
        const SizedBox(height: 24),
        _BusyButton(label: 'Zaloguj się', busy: _busy, onPressed: _login),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Zmiana numeru telefonu
// ---------------------------------------------------------------

class ChangePhoneScreen extends ConsumerStatefulWidget {
  const ChangePhoneScreen({super.key});

  @override
  ConsumerState<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends ConsumerState<ChangePhoneScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String? _phoneError;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final phone = normalizePolishPhone(_phone.text);
    setState(
      () => _phoneError = phone == null
          ? 'Wpisz 9-cyfrowy numer telefonu.'
          : null,
    );
    if (phone == null) return;
    if (_password.text.isEmpty) {
      showMessage(context, 'Wpisz obecne hasło.');
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .changePhone(newPhone: phone, currentPassword: _password.text);
      ref.invalidate(profileProvider);
      if (!mounted) return;
      showMessage(context, 'Numer telefonu został zmieniony.');
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Zmień numer telefonu',
      subtitle:
          'Jeden numer to jedno konto Table. Numer z innego konta nie przejdzie na to.',
      children: [
        _PhoneField(
          controller: _phone,
          errorText: _phoneError,
          label: 'Nowy numer telefonu',
        ),
        const SizedBox(height: 16),
        AutofillGroup(
          child: _PasswordField(
            controller: _password,
            label: 'Obecne hasło',
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(height: 24),
        _BusyButton(label: 'Zmień numer', busy: _busy, onPressed: _save),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Kod SMS: logowanie starego konta bez e-maila
// ---------------------------------------------------------------

class SmsCodeScreen extends ConsumerStatefulWidget {
  const SmsCodeScreen({super.key, required this.phone, this.next});

  final String phone;
  final String? next;

  @override
  ConsumerState<SmsCodeScreen> createState() => _SmsCodeScreenState();
}

class _SmsCodeScreenState extends ConsumerState<SmsCodeScreen> {
  static const _resendSeconds = 60;

  final _code = TextEditingController();
  Timer? _timer;
  int _secondsLeft = _resendSeconds;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) t.cancel();
      if (mounted) setState(() => _secondsLeft--);
    });
  }

  Future<void> _verify() async {
    // Kod wysyła się sam po wpisaniu 6 cyfr. Drugie wysłanie tego samego kodu
    // kończy się błędem „kod zużyty”, choć logowanie już się udało.
    if (_busy) return;
    final code = _code.text.trim();
    if (code.length != 6) {
      showMessage(context, 'Kod ma 6 cyfr.');
      return;
    }
    setState(() => _busy = true);
    final repository = ref.read(repositoryProvider);

    try {
      await repository.verifySmsCode(phone: widget.phone, code: code);
      if (mounted) context.go(_safeNext(widget.next));
    } catch (e) {
      if (!mounted) return;
      // Sesja już jest, więc kod zadziałał przy wcześniejszej próbie.
      if (repository.session != null) {
        context.go(_safeNext(widget.next));
        return;
      }
      showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final repo = ref.read(repositoryProvider);
    try {
      await repo.sendLoginCode(widget.phone);
      if (!mounted) return;
      _startTimer();
      showMessage(context, 'Wysłaliśmy nowy kod.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitle =
        'Jeśli numer ${_displayPhone(widget.phone)} ma konto, wysłaliśmy na niego 6-cyfrowy kod.';

    return _AuthScaffold(
      title: 'Wpisz kod z SMS-a',
      subtitle: subtitle,
      children: [
        TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 28,
            fontWeight: FontWeight.w600,
            letterSpacing: 12,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
          onChanged: (value) {
            if (value.length == 6) _verify();
          },
          decoration: const InputDecoration(hintText: '000000'),
        ),
        const SizedBox(height: 24),
        _BusyButton(label: 'Potwierdź', busy: _busy, onPressed: _verify),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _secondsLeft > 0 ? null : _resend,
          child: Text(
            _secondsLeft > 0
                ? 'Wyślij ponownie za $_secondsLeft s'
                : 'Wyślij kod ponownie',
          ),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 24),
          Text(
            'Tryb testowy: kod znajdziesz w Supabase, w tabeli private.dev_sms_outbox.',
            style: TextStyle(color: AppColors.warning),
          ),
        ],
      ],
    );
  }
}

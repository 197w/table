import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_icons.dart';
import 'failure.dart';
import 'theme.dart';
import 'toasts.dart';

// Logowanie e-mailem w Table i Table for employees (10.2026, migracja 0069).
// Rejestracja: numer telefonu → e-mail → kod z e-maila → hasło. Logowanie: e-mail → kod z e-maila → hasło.
// Numer telefonu konta jest w profilu (bez SMS-a), jeden numer to jedno konto.

/// Sesja z kodu z e-maila, zanim użytkownik poda hasło. Aplikacje traktują ją jak niezalogowaną, a wyjście
/// z ekranu albo zamknięcie aplikacji w tym czasie wylogowuje.
class AuthPending extends ValueNotifier<bool> {
  AuthPending._() : super(false);

  static final instance = AuthPending._();
  static const _key = 'table_logowanie_bez_hasla';

  /// Przy starcie aplikacji: logowanie przerwane na kroku hasła wylogowuje.
  static Future<void> restore() async {
    try {
      final prefs = SharedPreferencesAsync();
      if (await prefs.getBool(_key) ?? false) {
        await prefs.remove(_key);
        final auth = Supabase.instance.client.auth;
        if (auth.currentSession != null) await auth.signOut();
      }
    } catch (_) {
      // Bez pamięci telefonu zostaje sama sesja.
    }
  }

  Future<void> _set(bool pending) async {
    value = pending;
    try {
      final prefs = SharedPreferencesAsync();
      pending ? await prefs.setBool(_key, true) : await prefs.remove(_key);
    } catch (_) {
      // Jak wyżej.
    }
  }
}

/// Zalogowany: jest sesja i nie czeka na hasło.
bool get signedInWithPassword => Supabase.instance.client.auth.currentSession != null && !AuthPending.instance.value;

/// Stan konta po kodzie z e-maila: czego jeszcze brakuje.
class AccountStatus {
  const AccountStatus({this.phone, this.email, required this.hasPassword});

  /// 48 i 9 cyfr albo null, gdy konto nie ma numeru.
  final String? phone;
  final String? email;
  final bool hasPassword;

  factory AccountStatus.fromJson(Map<String, dynamic> json) => AccountStatus(
    phone: json['phone'] as String?,
    email: json['email'] as String?,
    hasPassword: json['has_password'] as bool? ?? false,
  );
}

/// Zamienia wpisany numer na format +48XXXXXXXXX. Tylko polskie numery.
String? polishPhone(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 9) return '+48$digits';
  if (digits.length == 11 && digits.startsWith('48')) return '+$digits';
  return null;
}

String? _cleanEmail(String input) {
  final e = input.trim().toLowerCase();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e) ? e : null;
}

/// Wywołania Supabase dla logowania e-mailem.
class EmailAuth {
  EmailAuth([this._client]);

  final SupabaseClient? _client;

  // Dopiero przy wywołaniu: sam ekran powstaje bez Supabase (testy wyglądu).
  SupabaseClient get _db => _client ?? Supabase.instance.client;

  /// Rejestracja: numer nie może mieć już konta.
  Future<void> checkPhone(String phone) => _guard(() async {
    final result = await _db.rpc<String?>('auth_signup_check', params: {'p_phone': phone});
    if (result == 'phone_taken') {
      throw const AppFailure('Ten numer telefonu ma już konto Table. Zaloguj się na nie.');
    }
  });

  /// Rejestracja: kod na nowy e-mail (konto powstaje przy kodzie, potwierdza je wpisanie kodu).
  Future<void> sendSignupCode(String email) => _guard(() async {
    final result = await _db.rpc<String?>('auth_signup_check', params: {'p_email': email});
    if (result == 'email_taken') throw const AppFailure('Ten e-mail ma już konto Table. Zaloguj się.');
    await _db.auth.signInWithOtp(email: email, shouldCreateUser: true);
  });

  Future<void> sendLoginCode(String email) => _guard(() async {
    try {
      await _db.auth.signInWithOtp(email: email, shouldCreateUser: false);
    } on AuthException catch (e) {
      final code = e.code ?? '';
      final unknown =
          code == 'otp_disabled' ||
          code == 'user_not_found' ||
          code == 'signup_disabled' ||
          e.message.toLowerCase().contains('signups not allowed');
      if (unknown) throw const AppFailure('Nie ma konta Table z tym e-mailem. Załóż konto.');
      rethrow;
    }
  });

  /// Kod z e-maila. Sesja powstaje od razu, ale do podania hasła liczy się jako niezalogowana.
  Future<AccountStatus> verifyCode(String email, String code) => _guard(() async {
    await AuthPending.instance._set(true);
    try {
      await _db.auth.verifyOTP(type: OtpType.email, email: email, token: code);
    } catch (_) {
      if (_db.auth.currentSession == null) await AuthPending.instance._set(false);
      rethrow;
    }
    return status();
  });

  Future<AccountStatus> status() => _guard(() async {
    final row = await _db.rpc<Map<String, dynamic>?>('account_status');
    return AccountStatus.fromJson(row ?? const {});
  });

  /// Numer telefonu konta. Zwraca 48 i 9 cyfr.
  Future<String> setPhone(String phone) =>
      _guard(() => _db.rpc<String>('account_set_phone', params: {'p_phone': phone}));

  /// Ostatni krok. [create]: nowe hasło (rejestracja, konto bez hasła albo „Nie pamiętasz hasła?”;
  /// e-mail jest już potwierdzony kodem).
  Future<void> finish({required String email, required String password, required bool create}) => _guard(() async {
    if (create) {
      await _db.auth.updateUser(UserAttributes(password: password));
    } else {
      await _db.auth.signInWithPassword(email: email, password: password);
    }
    await AuthPending.instance._set(false);
  });

  /// Wyjście przed hasłem: wylogowuje sesję z kodu.
  Future<void> cancel() async {
    if (!AuthPending.instance.value) return;
    try {
      await _db.auth.signOut();
    } catch (_) {
      // Sesja i tak zniknie przy następnym starcie (AuthPending.restore).
    }
    await AuthPending.instance._set(false);
  }

  /// Stare konto z logowania SMS: dodanie e-maila (kod na nowy adres).
  Future<void> sendEmailChangeCode(String email) => _guard(() async {
    final result = await _db.rpc<String?>('auth_signup_check', params: {'p_email': email});
    if (result == 'email_taken') throw const AppFailure('Ten e-mail ma już inne konto Table.');
    await _db.auth.updateUser(UserAttributes(email: email));
  });

  Future<void> verifyEmailChange(String email, String code) =>
      _guard(() => _db.auth.verifyOTP(type: OtpType.emailChange, email: email, token: code));

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AppFailure {
      rethrow;
    } on AuthException catch (e) {
      throw AppFailure(_authMessage(e));
    } on PostgrestException catch (e) {
      // Komunikaty z funkcji w bazie są już po polsku.
      if (e.code == 'P0001' && e.message.isNotEmpty) throw AppFailure(e.message);
      throw const AppFailure('Nie udało się. Spróbuj ponownie.');
    } catch (_) {
      throw const AppFailure('Brak połączenia z serwerem. Sprawdź internet i spróbuj ponownie.');
    }
  }

  static String _authMessage(AuthException e) {
    final code = e.code ?? '';
    final message = e.message.toLowerCase();
    if (code == 'invalid_credentials' || message.contains('invalid login')) return 'Nieprawidłowe hasło.';
    if (code == 'otp_expired' || message.contains('token has expired') || message.contains('invalid')) {
      return 'Kod jest nieprawidłowy albo wygasł. Wyślij nowy kod.';
    }
    if (code == 'weak_password' || message.contains('password should')) return 'Hasło musi mieć co najmniej 8 znaków.';
    if (code == 'same_password') return 'To jest obecne hasło konta. Wpisz je w kroku logowania albo wybierz inne.';
    if (code == 'email_exists' || message.contains('already been registered')) {
      return 'Ten e-mail ma już inne konto Table.';
    }
    if (code.contains('rate_limit') || message.contains('rate limit') || e.statusCode == '429') {
      return 'Za dużo prób. Odczekaj chwilę i spróbuj ponownie.';
    }
    if (code == 'email_address_invalid' || message.contains('email address')) return 'Wpisz poprawny adres e-mail.';
    return 'Nie udało się. Spróbuj ponownie.';
  }
}

enum EmailAuthMode { login, register }

enum _Step { phone, email, code, password }

/// Kroki logowania i rejestracji e-mailem: rejestracja numer → e-mail → kod → hasło, logowanie e-mail → kod →
/// (numer, gdy konto go nie ma) → hasło. Sam widok kroków; ekran z paskiem daje aplikacja. Systemowe „Wstecz”
/// wraca o krok, a wyjście po kodzie, przed hasłem, wylogowuje.
class EmailAuthFlow extends StatefulWidget {
  const EmailAuthFlow({
    super.key,
    required this.mode,
    required this.onDone,
    this.onSwitchMode,
    this.onSmsLogin,
    this.phoneHint,
    this.leading,
    this.showBack = false,
  });

  final EmailAuthMode mode;
  final VoidCallback onDone;

  /// „Nie masz konta? Załóż je” albo „Masz już konto? Zaloguj się”.
  final VoidCallback? onSwitchMode;

  /// Stare konto bez e-maila: logowanie kodem SMS.
  final VoidCallback? onSmsLogin;

  /// Dodatkowe zdanie przy numerze telefonu (pracownik: ten sam numer, który zna kierownik).
  final String? phoneHint;

  /// Nad tytułem, np. kafelek z ikoną aplikacji.
  final Widget? leading;

  /// Przycisk „Wstecz” w widoku (ekran bez paska u góry).
  final bool showBack;

  @override
  State<EmailAuthFlow> createState() => _EmailAuthFlowState();
}

class _EmailAuthFlowState extends State<EmailAuthFlow> {
  static const _resendSeconds = 60;

  final _auth = EmailAuth();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  late _Step _step = _register ? _Step.phone : _Step.email;
  String? _sentTo;
  String? _phoneE164;
  bool _phoneMissing = false;
  bool _createPassword = false;
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  Timer? _timer;
  int _secondsLeft = 0;

  bool get _register => widget.mode == EmailAuthMode.register;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    // Wyjście z ekranu po kodzie, a przed hasłem.
    unawaited(_auth.cancel());
    super.dispose();
  }

  List<_Step> get _steps => [
    if (_register) _Step.phone,
    _Step.email,
    _Step.code,
    if (!_register && _phoneMissing) _Step.phone,
    _Step.password,
  ];

  bool get _canPop => _step == _steps.first;

  void _go(_Step step) => setState(() {
    _step = step;
    _error = null;
  });

  Future<void> _back() async {
    if (_busy) return;
    switch (_step) {
      case _Step.phone:
        if (_register) return;
        await _auth.cancel();
        _code.clear();
        _phoneMissing = false;
        _go(_Step.email);
      case _Step.email:
        if (_register) _go(_Step.phone);
      case _Step.code:
        _code.clear();
        _go(_Step.email);
      case _Step.password:
        // Po kodzie: powrót zaczyna od e-maila (sesja z kodu znika).
        await _auth.cancel();
        _code.clear();
        _password.clear();
        _phoneMissing = false;
        _createPassword = false;
        _go(_Step.email);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) t.cancel();
      if (mounted) setState(() => _secondsLeft--);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitPhone() async {
    final phone = polishPhone(_phone.text);
    if (phone == null) {
      setState(() => _error = 'Wpisz 9-cyfrowy numer telefonu.');
      return;
    }
    await _run(() async {
      if (_register) {
        await _auth.checkPhone(phone);
        _phoneE164 = phone;
        _go(_Step.email);
      } else {
        await _auth.setPhone(phone);
        _go(_Step.password);
      }
    });
  }

  Future<void> _sendCode({bool again = false}) async {
    final email = again ? _sentTo : _cleanEmail(_email.text);
    if (email == null) {
      setState(() => _error = 'Wpisz poprawny adres e-mail.');
      return;
    }
    await _run(() async {
      if (_register) {
        await _auth.sendSignupCode(email);
      } else {
        await _auth.sendLoginCode(email);
      }
      _sentTo = email;
      _startTimer();
      if (again) {
        if (mounted) showMessage(context, 'Wysłaliśmy nowy kod.');
      } else {
        _code.clear();
        _go(_Step.code);
      }
    });
  }

  Future<void> _verify() async {
    final email = _sentTo;
    final code = _code.text.trim();
    if (email == null) return;
    if (code.length < 6) {
      setState(() => _error = 'Wpisz cały kod z e-maila.');
      return;
    }
    await _run(() async {
      final status = await _auth.verifyCode(email, code);
      if (_register) {
        try {
          await _auth.setPhone(_phoneE164!);
        } catch (_) {
          // Ktoś zajął numer w międzyczasie: konto bez numeru nie powstaje.
          await _auth.cancel();
          _go(_Step.phone);
          rethrow;
        }
        _createPassword = true;
        _go(_Step.password);
        return;
      }
      _createPassword = !status.hasPassword;
      if (status.phone == null) {
        setState(() => _phoneMissing = true);
        _go(_Step.phone);
      } else {
        _go(_Step.password);
      }
    });
  }

  Future<void> _finish() async {
    final email = _sentTo;
    if (email == null) return;
    final password = _password.text;
    if (_createPassword && password.length < 8) {
      setState(() => _error = 'Hasło musi mieć co najmniej 8 znaków.');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Wpisz hasło.');
      return;
    }
    await _run(() async {
      await _auth.finish(email: email, password: password, create: _createPassword);
      if (mounted) widget.onDone();
    });
  }

  ({String title, String subtitle}) get _texts => switch (_step) {
    _Step.phone when _register => (
      title: 'Załóż konto',
      subtitle: 'Zacznij od numeru telefonu. Jeden numer to jedno konto Table.',
    ),
    _Step.phone => (
      title: 'Twój numer telefonu',
      subtitle: 'Konto nie ma jeszcze numeru telefonu. Jeden numer to jedno konto Table.',
    ),
    _Step.email when _register => (
      title: 'Twój e-mail',
      subtitle: 'Wyślemy na niego kod. Odtąd logujesz się e-mailem, kodem z e-maila i hasłem.',
    ),
    _Step.email => (
      title: 'Zaloguj się',
      subtitle: 'Wpisz e-mail konta. Wyślemy na niego kod, a potem poprosimy o hasło.',
    ),
    _Step.code => (
      title: 'Wpisz kod z e-maila',
      subtitle: 'Wysłaliśmy kod na adres $_sentTo. Nie widzisz go? Zajrzyj do spamu.',
    ),
    _Step.password when _createPassword => (
      title: _register ? 'Ustaw hasło' : 'Ustaw nowe hasło',
      subtitle: 'Co najmniej 8 znaków. Podasz je przy każdym logowaniu, po kodzie z e-maila.',
    ),
    _Step.password => (title: 'Wpisz hasło', subtitle: 'Ostatni krok: hasło do konta $_sentTo.'),
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final texts = _texts;
    final steps = _steps;
    final index = steps.indexOf(_step) + 1;

    return PopScope(
      canPop: _canPop && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            if (widget.showBack && !_canPop)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy ? null : _back,
                  icon: const Glyph(AppIcons.arrowLeft, size: 18),
                  label: const Text('Wstecz'),
                ),
              ),
            if (widget.leading != null) ...[widget.leading!, const SizedBox(height: 24)],
            Text('Krok $index z ${steps.length}', style: text.labelLarge?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 6),
            Semantics(header: true, child: Text(texts.title, style: text.headlineMedium)),
            const SizedBox(height: 8),
            Text(texts.subtitle, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 28),
            ..._fields(text),
          ],
        ),
      ),
    );
  }

  List<Widget> _fields(TextTheme text) {
    switch (_step) {
      case _Step.phone:
        return [
          TextField(
            key: const ValueKey('telefon'),
            controller: _phone,
            autofocus: true,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumberNational],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
              LengthLimitingTextInputFormatter(11),
            ],
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _submitPhone(),
            decoration: InputDecoration(
              labelText: 'Numer telefonu',
              hintText: '600 700 800',
              prefixText: '+48 ',
              errorText: _error,
              helperText: widget.phoneHint,
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 24),
          _BusyButton(label: 'Dalej', busy: _busy, onPressed: _submitPhone),
          if (_register && widget.onSwitchMode != null) ...[
            const SizedBox(height: 24),
            _LinkButton(label: 'Masz już konto? Zaloguj się', onPressed: _busy ? null : widget.onSwitchMode),
          ],
        ];
      case _Step.email:
        return [
          TextField(
            key: const ValueKey('email'),
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendCode(),
            decoration: InputDecoration(labelText: 'E-mail', hintText: 'jan@example.com', errorText: _error),
          ),
          const SizedBox(height: 24),
          _BusyButton(label: 'Wyślij kod', busy: _busy, onPressed: _sendCode),
          if (!_register) ...[
            if (widget.onSwitchMode != null) ...[
              const SizedBox(height: 24),
              _LinkButton(label: 'Nie masz konta? Załóż je', onPressed: _busy ? null : widget.onSwitchMode),
            ],
            if (widget.onSmsLogin != null) ...[
              const SizedBox(height: 4),
              _LinkButton(
                label: 'Konto bez e-maila? Zaloguj się kodem SMS',
                onPressed: _busy ? null : widget.onSmsLogin,
              ),
            ],
          ],
        ];
      case _Step.code:
        return [
          TextField(
            key: const ValueKey('kod'),
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _verify(),
            style: const TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 28,
              fontWeight: FontWeight.w600,
              letterSpacing: 10,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(hintText: '000000', errorText: _error),
          ),
          const SizedBox(height: 24),
          _BusyButton(label: 'Dalej', busy: _busy, onPressed: _verify),
          const SizedBox(height: 12),
          _LinkButton(
            label: _secondsLeft > 0 ? 'Wyślij ponownie za $_secondsLeft s' : 'Wyślij kod ponownie',
            onPressed: _secondsLeft > 0 || _busy ? null : () => _sendCode(again: true),
          ),
          _LinkButton(label: 'Zmień e-mail', onPressed: _busy ? null : _back),
          if (kDebugMode) ...[
            const SizedBox(height: 16),
            Text(
              'Tryb testowy: e-maile wysyła poczta Supabase, tylko na adresy osób z zespołu projektu '
              'i kilka na godzinę.',
              style: text.bodySmall?.copyWith(color: AppColors.warning),
            ),
          ],
        ];
      case _Step.password:
        return [
          TextField(
            key: ValueKey('haslo-$_createPassword'),
            controller: _password,
            autofocus: true,
            obscureText: _obscure,
            autofillHints: [_createPassword ? AutofillHints.newPassword : AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _finish(),
            decoration: InputDecoration(
              labelText: _createPassword ? 'Hasło, co najmniej 8 znaków' : 'Hasło',
              errorText: _error,
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Pokaż hasło' : 'Ukryj hasło',
                icon: Glyph(_obscure ? AppIcons.eye : AppIcons.eyeSlash),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _BusyButton(
            label: !_createPassword
                ? 'Zaloguj się'
                : _register
                ? 'Załóż konto'
                : 'Zapisz hasło i zaloguj się',
            busy: _busy,
            onPressed: _finish,
          ),
          if (!_createPassword) ...[
            const SizedBox(height: 12),
            // E-mail jest już potwierdzony kodem, więc nowe hasło można ustawić od razu.
            _LinkButton(
              label: 'Nie pamiętasz hasła? Ustaw nowe',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _createPassword = true;
                      _password.clear();
                      _error = null;
                    }),
            ),
          ],
        ];
    }
  }
}

/// Stare konto z logowania SMS: dodanie e-maila (e-mail → kod). Potem logowanie e-mailem, kodem i hasłem.
class AddEmailFlow extends StatefulWidget {
  const AddEmailFlow({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<AddEmailFlow> createState() => _AddEmailFlowState();
}

class _AddEmailFlowState extends State<AddEmailFlow> {
  final _auth = EmailAuth();
  final _email = TextEditingController();
  final _code = TextEditingController();
  String? _sentTo;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final email = _cleanEmail(_email.text);
    if (email == null) {
      setState(() => _error = 'Wpisz poprawny adres e-mail.');
      return;
    }
    await _run(() async {
      await _auth.sendEmailChangeCode(email);
      setState(() => _sentTo = email);
    });
  }

  Future<void> _verify() async {
    final email = _sentTo;
    if (email == null) return;
    if (_code.text.trim().length < 6) {
      setState(() => _error = 'Wpisz cały kod z e-maila.');
      return;
    }
    await _run(() async {
      await _auth.verifyEmailChange(email, _code.text.trim());
      if (!mounted) return;
      showMessage(context, 'E-mail dodany. Odtąd logujesz się e-mailem.');
      widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sent = _sentTo != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        Text(
          sent
              ? 'Wysłaliśmy kod na adres $_sentTo. Nie widzisz go? Zajrzyj do spamu.'
              : 'Odtąd zalogujesz się e-mailem, kodem z e-maila i hasłem tego konta. Wyślemy kod, żeby '
                    'potwierdzić adres.',
          style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        if (!sent)
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            onSubmitted: (_) => _send(),
            decoration: InputDecoration(labelText: 'E-mail', errorText: _error),
          )
        else
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            onSubmitted: (_) => _verify(),
            decoration: InputDecoration(labelText: 'Kod z e-maila', errorText: _error),
          ),
        const SizedBox(height: 24),
        _BusyButton(label: sent ? 'Potwierdź' : 'Wyślij kod', busy: _busy, onPressed: sent ? _verify : _send),
        if (sent)
          _LinkButton(
            label: 'Zmień e-mail',
            onPressed: _busy
                ? null
                : () => setState(() {
                    _sentTo = null;
                    _code.clear();
                  }),
          ),
      ],
    );
  }
}

class _BusyButton extends StatelessWidget {
  const _BusyButton({required this.label, required this.busy, required this.onPressed});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      onPressed: busy ? null : onPressed,
      child: busy
          ? SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted))
          : Text(label),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      onPressed: onPressed,
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}

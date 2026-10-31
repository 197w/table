import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _emailError;

  /// Zakładanie konta restauracji zamiast logowania.
  bool _signUp = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  /// Konto restauracji na mail firmowy. Po potwierdzeniu maila właściciel tworzy lokal.
  Future<void> _register() async {
    if (_busy) return;
    setState(
      () => _emailError = _validEmail(_email.text) ? null : 'Wpisz firmowy adres e-mail.',
    );
    if (_emailError != null) return;
    if (_password.text.length < 8) {
      showMessage(context, 'Hasło musi mieć co najmniej 8 znaków.');
      return;
    }
    if (_password.text != _repeat.text) {
      showMessage(context, 'Hasła się różnią.');
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      await repo.signUp(email: _email.text, password: _password.text);
      TextInput.finishAutofillContext();
      // Bez potwierdzania maila konto jest od razu zalogowane i panel przechodzi do tworzenia lokalu.
      if (repo.session == null && mounted) {
        setState(() => _signUp = false);
        showMessage(
          context,
          'Wysłaliśmy link na ${_email.text.trim()}. Kliknij go, a potem zaloguj się tutaj.',
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validEmail(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

  Future<void> _signIn() async {
    if (_busy) return;
    setState(
      () => _emailError = _validEmail(_email.text)
          ? null
          : 'Wpisz adres e-mail, na przykład kierownik@lokal.pl.',
    );
    if (_emailError != null) return;
    if (_password.text.isEmpty) {
      showMessage(context, 'Wpisz hasło.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .signIn(email: _email.text, password: _password.text);
      TextInput.finishAutofillContext();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_validEmail(_email.text)) {
      setState(
        () => _emailError = 'Wpisz adres e-mail, na który wyślemy link.',
      );
      return;
    }
    try {
      await ref.read(repositoryProvider).sendPasswordReset(_email.text);
      if (mounted) {
        showMessage(
          context,
          'Jeśli ten adres ma konto, wysłaliśmy na niego link do zmiany hasła.',
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Row(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: SizedBox(
                  width: 380,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Brand(),
                        const SizedBox(height: 40),
                        Text(
                          _signUp ? 'Załóż konto restauracji' : 'Zaloguj się do panelu',
                          style: text.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _signUp
                              ? 'Użyj maila firmowego. Po potwierdzeniu utworzysz lokal i dodasz pracowników.'
                              : 'Rezerwacje, zamówienia, sala, menu i zespół Twojego lokalu.',
                          style: text.bodyMedium?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 28),
                        TextField(
                          controller: _email,
                          autofocus: true,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: _signUp ? 'E-mail firmowy' : 'E-mail',
                            errorText: _emailError,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                          onSubmitted: (_) => _signUp ? null : _signIn(),
                          decoration: InputDecoration(
                            labelText: 'Hasło',
                            suffixIcon: IconButton(
                              tooltip: _obscure ? 'Pokaż hasło' : 'Ukryj hasło',
                              icon: Glyph(
                                _obscure ? AppIcons.eye : AppIcons.eyeSlash,
                                size: 18,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        if (_signUp) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: _repeat,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.newPassword],
                            onSubmitted: (_) => _register(),
                            decoration: const InputDecoration(labelText: 'Powtórz hasło'),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _busy ? null : (_signUp ? _register : _signIn),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                          ),
                          child: _busy
                              ? SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textMuted,
                                  ),
                                )
                              : Text(_signUp ? 'Załóż konto' : 'Zaloguj się'),
                        ),
                        const SizedBox(height: 8),
                        if (!_signUp)
                          TextButton(
                            onPressed: _busy ? null : _resetPassword,
                            child: const Text('Nie pamiętam hasła'),
                          ),
                        TextButton(
                          onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
                          child: Text(
                            _signUp ? 'Mam już konto: zaloguj się' : 'Nowa restauracja? Załóż konto',
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Pracownicy nie zakładają kont w panelu. Właściciel dodaje ich w zakładce „Pracownicy”, '
                          'a oni logują się w panelu kodem QR z aplikacji Table for employees '
                          'albo czterocyfrowym kodem.',
                          style: text.bodySmall?.copyWith(
                            color: AppColors.textDisabled,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        const TableLogo(size: 36),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Table', style: text.titleLarge?.copyWith(height: 1.1)),
            Text(
              'Panel restauracji',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

/// Znak Table: biały stół na miętowym tle, jak ikona aplikacji.
class TableLogo extends StatelessWidget {
  const TableLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF68BC9E), Color(0xFF579C84)],
        ),
        borderRadius: BorderRadius.circular(size * 0.26),
      ),
      child: const CustomPaint(painter: _TableMarkPainter()),
    );
  }
}

/// Sam stół ze znaku Table, bez tła, w jednym kolorze (np. biały w lewym rogu górnego paska panelu).
/// [width] to szerokość blatu z zaokrąglonymi końcami; wysokość wynika z proporcji znaku.
class TableMark extends StatelessWidget {
  const TableMark({super.key, this.width = 28, this.color = Colors.white});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, width * _TableMarkPainter.tightAspect),
    painter: _TableMarkPainter(color: color, tight: true),
  );
}

class _TableMarkPainter extends CustomPainter {
  const _TableMarkPainter({this.color = Colors.white, this.tight = false});

  final Color color;

  /// Sam stół dopasowany do rozmiaru, bez marginesu ikony.
  final bool tight;

  // Proporcje znaku z design/logo/table-1024px.png (ułamki boku ikony).
  static const _stroke = 0.052;
  static const _left = 0.19;
  static const _right = 0.81;
  static const _top = 0.39;
  static const _bottom = 0.70;
  static const _legLeft = 0.27;
  static const _legRight = 0.73;

  /// Wysokość do szerokości samego stołu z zaokrąglonymi końcami kresek.
  static const tightAspect = (_bottom - _top + _stroke) / (_right - _left + _stroke);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (tight) {
      canvas.scale(size.width / (_right - _left + _stroke));
      canvas.translate(-_left + _stroke / 2, -_top + _stroke / 2);
    } else {
      canvas.scale(size.width, size.height);
    }
    final paint = Paint()
      ..color = color
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(_left, _top), const Offset(_right, _top), paint);
    canvas.drawLine(const Offset(_legLeft, _top), const Offset(_legLeft, _bottom), paint);
    canvas.drawLine(const Offset(_legRight, _top), const Offset(_legRight, _bottom), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TableMarkPainter old) => old.color != color || old.tight != tight;
}

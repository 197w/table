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
  bool _obscure = true;
  bool _busy = false;
  String? _emailError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
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
      if (mounted) showMessage(context, errorText(e));
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
      if (mounted) showMessage(context, errorText(e));
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
                        Text('Zaloguj się do panelu', style: text.headlineMedium),
                        const SizedBox(height: 6),
                        Text(
                          'Rezerwacje, plan sali, menu i opinie Twojego lokalu.',
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
                            labelText: 'E-mail',
                            errorText: _emailError,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _signIn(),
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
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _busy ? null : _signIn,
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
                              : const Text('Zaloguj się'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : _resetPassword,
                          child: const Text('Nie pamiętam hasła'),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Konto dla lokalu zakłada zespół Table po weryfikacji restauracji. '
                          'Pracowników dodaje właściciel lokalu.',
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
      child: CustomPaint(painter: _TableMarkPainter()),
    );
  }
}

class _TableMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * 0.052
      ..strokeCap = StrokeCap.round;
    final w = size.width;
    final h = size.height;
    // Proporcje znaku z design/logo/table-1024px.png.
    canvas.drawLine(Offset(w * 0.19, h * 0.39), Offset(w * 0.81, h * 0.39), paint);
    canvas.drawLine(Offset(w * 0.27, h * 0.39), Offset(w * 0.27, h * 0.70), paint);
    canvas.drawLine(Offset(w * 0.73, h * 0.39), Offset(w * 0.73, h * 0.70), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'ui.dart';

/// Logowanie numerem telefonu i kodem SMS. Numer musi być tym samym, który kierownik
/// wpisał w panelu przy pracowniku: po nim lokal rozpoznaje, kto zaczyna zmianę.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
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
    return Scaffold(
      body: SafeArea(
        child: ContentWidth(
          child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accentTint,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Glyph(AppIcons.userCheck.duotone, size: 28, color: AppColors.accent),
            ),
            const SizedBox(height: 24),
            Semantics(header: true, child: Text('Table for employees', style: text.headlineMedium)),
            const SizedBox(height: 8),
            Text(
              sent
                  ? 'Wpisz kod z SMS-a wysłanego na $_sentTo.'
                  : 'Zaloguj się numerem telefonu, który podałeś kierownikowi. '
                        'Potem zaczniesz zmianę, skanując kod z panelu w lokalu.',
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
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
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
        ),
      ),
    );
  }
}

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/providers.dart';

/// Rodzaje kuchni: klucz w bazie i nazwa. Te same klucze zna aplikacja dla gości.
const cuisines = <String, String>{
  'polska': 'Polska',
  'wloska': 'Włoska',
  'francuska': 'Francuska',
  'grecka': 'Grecka',
  'hiszpanska': 'Hiszpańska',
  'gruzinska': 'Gruzińska',
  'turecka': 'Turecka',
  'japonska': 'Japońska',
  'chinska': 'Chińska',
  'tajska': 'Tajska',
  'wietnamska': 'Wietnamska',
  'koreanska': 'Koreańska',
  'indyjska': 'Indyjska',
  'meksykanska': 'Meksykańska',
  'amerykanska': 'Amerykańska',
  'wegetarianska': 'Wegetariańska',
  'weganska': 'Wegańska',
  'srodziemnomorska': 'Śródziemnomorska',
  'kawiarnia': 'Kawiarnia',
  'inna': 'Inna',
};

/// Pierwsze kroki nowego konta restauracji: dane lokalu. Potem właściciel dodaje
/// pracowników, salę i menu. Gościom lokal pokaże się po weryfikacji przez Table.
class CreateRestaurantScreen extends ConsumerStatefulWidget {
  const CreateRestaurantScreen({super.key});

  @override
  ConsumerState<CreateRestaurantScreen> createState() => _CreateRestaurantScreenState();
}

class _CreateRestaurantScreenState extends ConsumerState<CreateRestaurantScreen> {
  final _name = TextEditingController();
  final _nip = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  String? _cuisine;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _nip, _city, _address, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _create() async {
    final nip = _nip.text.replaceAll(RegExp(r'[^0-9]'), '');
    final String? problem;
    if (_name.text.trim().isEmpty) {
      problem = 'Wpisz nazwę lokalu.';
    } else if (nip.length != 10) {
      problem = 'NIP ma 10 cyfr.';
    } else if (_city.text.trim().isEmpty || _address.text.trim().isEmpty) {
      problem = 'Wpisz miasto i adres lokalu.';
    } else if (_phone.text.replaceAll(RegExp(r'[^0-9]'), '').length < 9) {
      problem = 'Wpisz numer telefonu lokalu, co najmniej 9 cyfr.';
    } else if (_cuisine == null) {
      problem = 'Wybierz rodzaj kuchni.';
    } else {
      problem = null;
    }
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await ref.read(repositoryProvider).createRestaurant(
        name: _name.text,
        nip: nip,
        city: _city.text,
        address: _address.text,
        phone: _phone.text,
        cuisine: _cuisine!,
      );
      await ref.read(selectedRestaurantIdProvider.notifier).select(id);
      ref.invalidate(restaurantsProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Utwórz swój lokal', style: text.headlineMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Po utworzeniu dodasz pracowników, salę i menu. Gościom lokal pokaże się w aplikacji '
                    'Table, gdy zweryfikujemy dane firmy.',
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _name,
                    maxLength: 80,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nazwa lokalu', counterText: ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nip,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9\- ]')),
                      LengthLimitingTextInputFormatter(13),
                    ],
                    decoration: const InputDecoration(labelText: 'NIP firmy'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _city,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Miasto'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _address,
                          decoration: const InputDecoration(labelText: 'Ulica i numer'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                          decoration: const InputDecoration(labelText: 'Telefon lokalu'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _cuisine,
                          decoration: const InputDecoration(labelText: 'Kuchnia'),
                          items: [
                            for (final c in cuisines.entries)
                              DropdownMenuItem(value: c.key, child: Text(c.value)),
                          ],
                          onChanged: (v) => setState(() => _cuisine = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _busy ? null : _create,
                      child: Text(_busy ? 'Tworzę lokal…' : 'Utwórz lokal'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.read(repositoryProvider).signOut(),
                    style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                    child: const Text('Wyloguj się'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

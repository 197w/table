import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'settings_widgets.dart';

/// Ustawienia → Adres dostawy: ulica, numer domu, kod pocztowy, miejscowość, a opcjonalnie kod do klatki
/// i jak rozpoznać budynek. Zamówienie z dostawą uzupełnia się z niego samo, a lokal, w którym gość
/// rezerwował albo zamawiał, widzi go w panelu w „Baza klientów”.
class AddressScreen extends ConsumerWidget {
  const AddressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider);
    return SignedInOnly(
      title: 'Adres dostawy',
      next: AppRoutes.deliveryAddress,
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(profileProvider)),
        data: (profile) => profile == null ? const LoadingView() : _AddressForm(profile: profile),
      ),
    );
  }
}

class _AddressForm extends ConsumerStatefulWidget {
  const _AddressForm({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends ConsumerState<_AddressForm> {
  late final _street = TextEditingController(text: widget.profile.addressStreet ?? '');
  late final _house = TextEditingController(text: widget.profile.addressHouse ?? '');
  late final _postcode = TextEditingController(text: widget.profile.addressPostcode ?? '');
  late final _city = TextEditingController(text: widget.profile.addressCity ?? '');
  late final _entryCode = TextEditingController(text: widget.profile.addressEntryCode ?? '');
  late final _building = TextEditingController(text: widget.profile.addressBuilding ?? '');
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_street, _house, _postcode, _city, _entryCode, _building]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save({bool clear = false}) async {
    if (_saving) return;
    if (!clear) {
      String? problem;
      if (_street.text.trim().isEmpty || _house.text.trim().isEmpty || _city.text.trim().isEmpty) {
        problem = 'Podaj ulicę, numer domu i miejscowość.';
      } else if (_postcode.text.trim().isNotEmpty && !RegExp(r'^\d{2}-\d{3}$').hasMatch(_postcode.text.trim())) {
        problem = 'Kod pocztowy wpisz jako 00-000.';
      }
      if (problem != null) {
        showMessage(context, problem, tone: ToastTone.warning);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .updateAddress(
            clear
                ? const GuestAddress()
                : GuestAddress(
                    street: _street.text,
                    house: _house.text,
                    postcode: _postcode.text,
                    city: _city.text,
                    entryCode: _entryCode.text,
                    building: _building.text,
                  ),
          );
      ref.invalidate(profileProvider);
      if (!mounted) return;
      if (clear) {
        for (final c in [_street, _house, _postcode, _city, _entryCode, _building]) {
          c.clear();
        }
      }
      showMessage(context, clear ? 'Adres usunięty.' : 'Adres zapisany.', tone: ToastTone.success);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget hint(String value) => Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 16),
      child: Text(value, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
    );

    return AutofillGroup(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            'Wpisz adres raz, a zamówienia z dostawą uzupełnią się same. Lokal, w którym rezerwujesz albo zamawiasz, '
            'widzi go przy twoich danych.',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _street,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.streetAddressLine1],
            decoration: const InputDecoration(labelText: 'Ulica', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _house,
            maxLength: 20,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Numer domu i mieszkania',
              hintText: 'Na przykład 14/3',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _postcode,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.postalCode],
                  inputFormatters: [_PostcodeFormatter()],
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                  decoration: const InputDecoration(labelText: 'Kod pocztowy', hintText: '00-000'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _city,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.addressCity],
                  decoration: const InputDecoration(labelText: 'Miejscowość', counterText: ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Dla dostawcy (opcjonalnie)', style: text.titleSmall),
          const SizedBox(height: 10),
          TextField(
            controller: _entryCode,
            maxLength: 20,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Kod do klatki', counterText: ''),
          ),
          hint('Domofon albo kod do drzwi wejściowych.'),
          TextField(
            controller: _building,
            maxLength: 200,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Jak rozpoznać budynek',
              hintText: 'Na przykład zielony blok za sklepem, wejście od podwórka',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _saving ? null : _save, child: const Text('Zapisz adres')),
          if (widget.profile.hasAddress) ...[
            const SizedBox(height: 4),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _saving ? null : () => _save(clear: true),
              child: const Text('Usuń adres'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Kod pocztowy jako 00-000: same cyfry, myślnik po dwóch.
class _PostcodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final cut = digits.length > 5 ? digits.substring(0, 5) : digits;
    final text = cut.length > 2 ? '${cut.substring(0, 2)}-${cut.substring(2)}' : cut;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

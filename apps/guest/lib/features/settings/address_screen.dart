import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/settings_list.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'settings_widgets.dart';

/// Konto → Adresy dostawy (0065, drugi adres i domyślny od 0083, prośba użytkownika 10.11.2026): najwyżej dwa adresy
/// i wybór domyślnego. Zamówienie z dostawą uzupełnia się z domyślnego (w koszyku można wybrać drugi), a lokal,
/// w którym gość rezerwował albo zamawiał, widzi domyślny w panelu w „Baza klientów”.
class AddressScreen extends ConsumerWidget {
  const AddressScreen({super.key});

  Future<void> _setDefault(BuildContext context, WidgetRef ref, int slot) async {
    try {
      await ref.read(repositoryProvider).setDefaultAddress(slot);
      ref.invalidate(profileProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider);
    return SignedInOnly(
      title: 'Adresy dostawy',
      next: AppRoutes.deliveryAddress,
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(profileProvider)),
        data: (profile) {
          if (profile == null) return const LoadingView();
          final first = profile.address1;
          final second = profile.address2;
          final chosen = profile.effectiveDefaultSlot;
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
            children: [
              SettingsGroup(
                children: [
                  SettingsRow(
                    icon: first == null ? AppIcons.plus : AppIcons.mapPin,
                    title: first?.summary ?? 'Dodaj adres',
                    value: first != null && second != null && chosen == 1 ? 'Domyślny' : null,
                    onTap: () => context.push(AppRoutes.deliveryAddressEdit(1)),
                  ),
                  if (first != null || second != null)
                    SettingsRow(
                      icon: second == null ? AppIcons.plus : AppIcons.mapPin,
                      title: second?.summary ?? 'Dodaj drugi adres',
                      value: first != null && second != null && chosen == 2 ? 'Domyślny' : null,
                      onTap: () => context.push(AppRoutes.deliveryAddressEdit(2)),
                    ),
                ],
              ),
              if (first != null && second != null) ...[
                const SizedBox(height: 24),
                SettingsGroup(
                  title: 'Domyślny adres',
                  dividerIndent: 14,
                  children: [
                    for (final (slot, address) in [(1, first), (2, second)])
                      SettingsChoiceRow(
                        title: address.summary,
                        selected: chosen == slot,
                        onTap: () => _setDefault(context, ref, slot),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Wpisanie albo zmiana jednego adresu ([slot] 1 albo 2): ulica, numer domu, kod pocztowy, miejscowość, a opcjonalnie
/// kod do klatki i jak rozpoznać budynek.
class AddressEditScreen extends ConsumerWidget {
  const AddressEditScreen({super.key, required this.slot});

  final int slot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider);
    return SignedInOnly(
      title: slot == 2 ? 'Drugi adres' : 'Adres dostawy',
      next: AppRoutes.deliveryAddressEdit(slot),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(profileProvider)),
        data: (profile) => profile == null ? const LoadingView() : _AddressForm(profile: profile, slot: slot),
      ),
    );
  }
}

class _AddressForm extends ConsumerStatefulWidget {
  const _AddressForm({required this.profile, required this.slot});

  final Profile profile;
  final int slot;

  @override
  ConsumerState<_AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends ConsumerState<_AddressForm> {
  late final SavedAddress? _saved = widget.profile.address(widget.slot);
  late final _street = TextEditingController(text: _saved?.street ?? '');
  late final _house = TextEditingController(text: _saved?.house ?? '');
  late final _postcode = TextEditingController(text: _saved?.postcode ?? '');
  late final _city = TextEditingController(text: _saved?.city ?? '');
  late final _entryCode = TextEditingController(text: _saved?.entryCode ?? '');
  late final _building = TextEditingController(text: _saved?.building ?? '');
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
            slot: widget.slot,
          );
      ref.invalidate(profileProvider);
      if (!mounted) return;
      showMessage(context, clear ? 'Adres usunięty.' : 'Adres zapisany.', tone: ToastTone.success);
      context.pop();
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
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
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
          if (_saved != null) ...[
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

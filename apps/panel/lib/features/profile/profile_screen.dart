import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/menu_photo.dart';
import '../../shared/panel_widgets.dart';
import 'schedule_conflicts.dart';

const _weekdays = [
  'Poniedziałek',
  'Wtorek',
  'Środa',
  'Czwartek',
  'Piątek',
  'Sobota',
  'Niedziela',
];

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final async = ref.watch(profileProvider(restaurant.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(),
        if (!restaurant.canManage)
          const ReadOnlyBanner(
            message: 'Dane lokalu i godziny zmienia kierownik albo właściciel.',
          ),
        Expanded(
          child: async.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(profileProvider(restaurant.id)),
            ),
            data: (profile) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LogoCard(profile: profile, editable: restaurant.canManage),
                        const SizedBox(height: 20),
                        _CoverCard(profile: profile, editable: restaurant.canManage),
                        const SizedBox(height: 20),
                        _DetailsForm(
                          key: ValueKey('dane-${profile.id}'),
                          profile: profile,
                          editable: restaurant.canManage,
                        ),
                        // Dane właściciela czyta i zmienia tylko kierownik i właściciel.
                        if (restaurant.canManage) ...[
                          const SizedBox(height: 20),
                          _OwnerCard(restaurantId: profile.id),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HoursForm(
                          key: ValueKey('godziny-${profile.id}'),
                          profile: profile,
                          editable: restaurant.canManage,
                        ),
                        const SizedBox(height: 20),
                        _ExceptionsCard(
                          profile: profile,
                          editable: restaurant.canManage,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// „Ustawienia lokalu”: jak lokal działa w Table. Rezerwacje w aplikacji, grafik pracowników,
/// okres inwentaryzacji oraz dostawa i odbiór. Dane lokalu (adres, godziny, logo) są w „Dane lokalu”.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final async = ref.watch(profileProvider(restaurant.id));
    final canInventory = ref.watch(memberPermissionsProvider).contains('inventory_edit');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(),
        if (!restaurant.canManage)
          const ReadOnlyBanner(message: 'Ustawienia lokalu zmienia kierownik albo właściciel.'),
        Expanded(
          child: async.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(profileProvider(restaurant.id))),
            data: (profile) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ReservationSettingsCard(
                          key: ValueKey('rezerwacje-${profile.id}'),
                          profile: profile,
                          editable: restaurant.canManage,
                        ),
                        const SizedBox(height: 20),
                        _DepositCard(
                          key: ValueKey('zadatek-${profile.id}'),
                          profile: profile,
                          editable: restaurant.canManage,
                        ),
                        const SizedBox(height: 20),
                        _SchedulePeriodCard(profile: profile, editable: restaurant.canManage),
                        const SizedBox(height: 20),
                        _InventoryPeriodCard(profile: profile, editable: canInventory),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: _DeliveryCard(
                      key: ValueKey('dostawa-${profile.id}'),
                      profile: profile,
                      editable: restaurant.canManage,
                      pro: restaurant.isPro,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Rezerwacje w aplikacji Table: co ile minut goście wybierają godzinę i największa grupa w jednej rezerwacji.
class _ReservationSettingsCard extends ConsumerStatefulWidget {
  const _ReservationSettingsCard({super.key, required this.profile, required this.editable});

  final RestaurantProfile profile;
  final bool editable;

  @override
  ConsumerState<_ReservationSettingsCard> createState() => _ReservationSettingsCardState();
}

class _ReservationSettingsCardState extends ConsumerState<_ReservationSettingsCard> {
  late int _interval = widget.profile.slotIntervalMin;
  late int _maxParty = widget.profile.maxPartySize;
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).updateProfile(widget.profile.id, {
        'slot_interval_min': _interval,
        'max_party_size': _maxParty,
      });
      ref.invalidate(profileProvider(widget.profile.id));
      if (mounted) showMessage(context, 'Ustawienia rezerwacji zapisane.', tone: ToastTone.success);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final enabled = widget.editable && !_busy;
    return PanelCard(
      title: 'Rezerwacje w aplikacji',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Co ile minut goście wybierają godzinę', style: text.bodyMedium)),
              IgnorePointer(
                ignoring: !enabled,
                child: SegmentedTabs<int>(
                  options: const [(15, '15 min'), (30, '30 min')],
                  selected: _interval,
                  onChanged: (v) => setState(() => _interval = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text('Największa grupa w jednej rezerwacji', style: text.bodyMedium)),
              IconButton(
                tooltip: 'Mniej osób',
                icon: const Glyph(AppIcons.minus, size: 16),
                onPressed: enabled && _maxParty > 1 ? () => setState(() => _maxParty--) : null,
              ),
              SizedBox(
                width: 64,
                child: Text(
                  Fmt.people(_maxParty),
                  textAlign: TextAlign.center,
                  style: text.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              IconButton(
                tooltip: 'Więcej osób',
                icon: const Glyph(AppIcons.plus, size: 16),
                onPressed: enabled && _maxParty < 30 ? () => setState(() => _maxParty++) : null,
              ),
            ],
          ),
          if (widget.editable) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _busy ? null : _save, child: const Text('Zapisz')),
            ),
          ],
        ],
      ),
    );
  }
}

/// Zadatek przy rezerwacji w aplikacji: od ilu osób i ile za osobę. Gość płaci przy rezerwacji,
/// zadatek odejmuje się od rachunku, odwołanie go zwraca, a nieobecność nie.
class _DepositCard extends ConsumerStatefulWidget {
  const _DepositCard({super.key, required this.profile, required this.editable});

  final RestaurantProfile profile;
  final bool editable;

  @override
  ConsumerState<_DepositCard> createState() => _DepositCardState();
}

class _DepositCardState extends ConsumerState<_DepositCard> {
  late bool _on = widget.profile.depositMinParty != null;
  late int _minParty = widget.profile.depositMinParty ?? 6;
  late final _amount = TextEditingController(
    text: widget.profile.depositPerPersonGrosze == null ? '50' : groszeToText(widget.profile.depositPerPersonGrosze!),
  );
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final perPerson = parseGrosze(_amount.text);
    if (_on && (perPerson == null || perPerson < 100)) {
      showMessage(context, 'Wpisz kwotę za osobę, od 1 zł.', tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).setDeposit(
        widget.profile.id,
        minParty: _on ? _minParty : null,
        perPersonGrosze: _on ? perPerson : null,
      );
      ref.invalidate(profileProvider(widget.profile.id));
      if (mounted) showMessage(context, _on ? 'Zadatek zapisany.' : 'Zadatek wyłączony.', tone: ToastTone.success);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final enabled = widget.editable && !_busy;
    final perPerson = parseGrosze(_amount.text);
    return PanelCard(
      title: 'Zadatek przy rezerwacji',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Gość płaci zadatek w aplikacji Table', style: text.bodyMedium)),
              Switch(value: _on, onChanged: enabled ? (v) => setState(() => _on = v) : null),
            ],
          ),
          if (_on) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Od ilu osób', style: text.bodyMedium)),
                IconButton(
                  tooltip: 'Mniej osób',
                  icon: const Glyph(AppIcons.minus, size: 16),
                  onPressed: enabled && _minParty > 1 ? () => setState(() => _minParty--) : null,
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    Fmt.people(_minParty),
                    textAlign: TextAlign.center,
                    style: text.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
                IconButton(
                  tooltip: 'Więcej osób',
                  icon: const Glyph(AppIcons.plus, size: 16),
                  onPressed: enabled && _minParty < 30 ? () => setState(() => _minParty++) : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Kwota za osobę', style: text.bodyMedium)),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _amount,
                    enabled: enabled,
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(suffixText: 'zł', isDense: true),
                  ),
                ),
              ],
            ),
            if (perPerson != null) ...[
              const SizedBox(height: 8),
              Text(
                'Na przykład ${Fmt.people(_minParty)}: ${Fmt.price(perPerson * _minParty)}. '
                'Odwołanie zwraca zadatek, nieobecność nie.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ],
          if (widget.editable) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _busy ? null : _save, child: const Text('Zapisz')),
            ),
          ],
        ],
      ),
    );
  }
}

/// Co ile lokal robi inwentaryzację. Zmiana z uprawnieniem „Edytowanie składników”.
class _InventoryPeriodCard extends ConsumerStatefulWidget {
  const _InventoryPeriodCard({required this.profile, required this.editable});

  final RestaurantProfile profile;
  final bool editable;

  @override
  ConsumerState<_InventoryPeriodCard> createState() => _InventoryPeriodCardState();
}

class _InventoryPeriodCardState extends ConsumerState<_InventoryPeriodCard> {
  bool _busy = false;

  Future<void> _set(String period) async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).setInventoryPeriod(widget.profile.id, period);
      ref.invalidate(profileProvider(widget.profile.id));
      if (mounted) showMessage(context, 'Inwentaryzacja: ${inventoryPeriodLabel(period).toLowerCase()}.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      title: 'Inwentaryzacja',
      child: Align(
        alignment: Alignment.centerLeft,
        child: IgnorePointer(
          ignoring: !widget.editable || _busy,
          child: SegmentedTabs<String>(
            options: inventoryPeriods,
            selected: widget.profile.inventoryPeriod,
            onChanged: _set,
          ),
        ),
      ),
    );
  }
}

class _DetailsForm extends ConsumerStatefulWidget {
  const _DetailsForm({super.key, required this.profile, required this.editable});

  final RestaurantProfile profile;
  final bool editable;

  @override
  ConsumerState<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends ConsumerState<_DetailsForm> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _description = TextEditingController(
    text: widget.profile.description ?? '',
  );
  late final _address = TextEditingController(text: widget.profile.address);
  late final _city = TextEditingController(text: widget.profile.city);
  late final _phone = TextEditingController(text: widget.profile.phone);
  late String _cuisine = widget.profile.cuisine;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _description, _address, _city, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty ||
        _address.text.trim().isEmpty ||
        _city.text.trim().isEmpty ||
        _phone.text.trim().isEmpty) {
      showMessage(context, 'Uzupełnij nazwę, adres, miasto i telefon.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).updateProfile(widget.profile.id, {
        'name': _name.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'address': _address.text.trim(),
        'city': _city.text.trim(),
        'phone': _phone.text.replaceAll(' ', ''),
        'cuisine': _cuisine,
      });
      ref
        ..invalidate(profileProvider(widget.profile.id))
        ..invalidate(restaurantsProvider);
      if (mounted) showMessage(context, 'Dane lokalu zapisane.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final enabled = widget.editable;
    final cuisines = {...cuisineLabels};
    cuisines.putIfAbsent(_cuisine, () => Fmt.capitalize(_cuisine));

    return PanelCard(
      title: 'Dane lokalu',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            enabled: enabled,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Nazwa', counterText: ''),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _cuisine,
                  decoration: const InputDecoration(labelText: 'Kuchnia'),
                  items: [
                    for (final e in cuisines.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: enabled ? (v) => setState(() => _cuisine = v!) : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _phone,
                  enabled: enabled,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                  ],
                  decoration: const InputDecoration(labelText: 'Telefon do rezerwacji'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _description,
            enabled: enabled,
            minLines: 3,
            maxLines: 6,
            maxLength: 600,
            decoration: const InputDecoration(
              labelText: 'Opis',
              alignLabelWithHint: true,
              hintText: 'Czym wyróżnia się kuchnia, co warto zamówić.',
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _address,
                  enabled: enabled,
                  decoration: const InputDecoration(labelText: 'Adres'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _city,
                  enabled: enabled,
                  decoration: const InputDecoration(labelText: 'Miasto'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                'Poziom cen: ${Fmt.priceLevel(widget.profile.priceLevel)}',
                style: text.bodyMedium,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'liczony z cen podanych w zweryfikowanych opiniach',
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Zapisz dane'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayHours {
  _DayHours({required this.open, required this.opens, required this.closes});

  bool open;
  TimeOfDay opens;
  TimeOfDay closes;
}

class _HoursForm extends ConsumerStatefulWidget {
  const _HoursForm({super.key, required this.profile, required this.editable});

  final RestaurantProfile profile;
  final bool editable;

  @override
  ConsumerState<_HoursForm> createState() => _HoursFormState();
}

class _HoursFormState extends ConsumerState<_HoursForm> {
  late final List<_DayHours> _days = List.generate(7, (i) {
    OpeningHours? h;
    for (final x in widget.profile.hours) {
      if (x.weekday == i + 1) h = x;
    }
    return _DayHours(
      open: h != null,
      opens: _parse(h?.opens ?? '12:00'),
      closes: _parse(h?.closes ?? '22:00'),
    );
  });
  bool _busy = false;

  static TimeOfDay _parse(String hm) {
    final parts = hm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pick(int day, bool opens) async {
    final d = _days[day];
    final picked = await pickTime(
      context,
      initial: opens ? d.opens : d.closes,
      allowEndOfDay: !opens,
      title: opens ? 'Otwarcie' : 'Zamknięcie',
    );
    if (picked == null) return;
    setState(() => opens ? d.opens = picked : d.closes = picked);
  }

  void _copyMondayToAll() {
    final m = _days.first;
    setState(() {
      for (final d in _days.skip(1)) {
        d
          ..open = m.open
          ..opens = m.opens
          ..closes = m.closes;
      }
    });
  }

  Future<void> _save() async {
    final hours = <OpeningHours>[];
    for (var i = 0; i < 7; i++) {
      final d = _days[i];
      if (!d.open) continue;
      final opensMin = d.opens.hour * 60 + d.opens.minute;
      final closesMin = d.closes.hour * 60 + d.closes.minute;
      if (closesMin <= opensMin) {
        showMessage(
          context,
          '${_weekdays[i]}: zamknięcie musi być później niż otwarcie. Lokale otwarte po północy obsłużymy w kolejnej wersji.',
        );
        return;
      }
      hours.add(
        OpeningHours(weekday: i + 1, opens: _format(d.opens), closes: _format(d.closes)),
      );
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(repositoryProvider);
      await repo.setHours(widget.profile.id, hours);
      ref.invalidate(profileProvider(widget.profile.id));
      if (!mounted) return;
      showMessage(context, 'Godziny otwarcia zapisane.');

      // Rezerwacje przyjęte według starych godzin mogą teraz wypadać poza nimi.
      final conflicts = await findScheduleConflicts(
        ref,
        widget.profile.id,
        weekly: hours,
        exceptions: await repo.exceptions(widget.profile.id),
      );
      if (!mounted) return;
      await resolveScheduleConflicts(
        context,
        ref,
        widget.profile.id,
        conflicts,
        reason: 'Odwołana przez lokal: zmiana godzin otwarcia',
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final enabled = widget.editable;
    return PanelCard(
      title: 'Godziny otwarcia',
      trailing: enabled
          ? TextButton(
              onPressed: _copyMondayToAll,
              child: const Text('Jak w poniedziałek'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < 7; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 108,
                    child: Text(_weekdays[i], style: text.bodyMedium),
                  ),
                  Switch(
                    value: _days[i].open,
                    onChanged: enabled
                        ? (v) => setState(() => _days[i].open = v)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  if (_days[i].open) ...[
                    _TimeButton(
                      value: _format(_days[i].opens),
                      onTap: enabled ? () => _pick(i, true) : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('–', style: text.bodyMedium),
                    ),
                    _TimeButton(
                      value: _format(_days[i].closes),
                      onTap: enabled ? () => _pick(i, false) : null,
                    ),
                  ] else
                    Text(
                      'Zamknięte',
                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                ],
              ),
            ),
          if (enabled) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Zapisz godziny'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Dni, w których lokal jest zamknięty albo pracuje w innych godzinach niż zwykle.
/// W te dni aplikacja pokazuje gościom tylko pasujące terminy.
class _ExceptionsCard extends ConsumerWidget {
  const _ExceptionsCard({required this.profile, required this.editable});

  final RestaurantProfile profile;
  final bool editable;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<OpeningException>(
      context: context,
      builder: (_) => const _ExceptionDialog(),
    );
    if (saved == null || !context.mounted) return;
    final repo = ref.read(repositoryProvider);
    try {
      await repo.saveException(profile.id, saved);
      ref.invalidate(exceptionsProvider(profile.id));
      if (!context.mounted) return;
      showMessage(context, 'Dzień wyjątkowy zapisany.');

      final conflicts = await findScheduleConflicts(
        ref,
        profile.id,
        weekly: profile.hours,
        exceptions: await repo.exceptions(profile.id),
      );
      if (!context.mounted) return;
      final day = Fmt.dayShort(saved.day);
      final note = saved.note?.trim();
      await resolveScheduleConflicts(
        context,
        ref,
        profile.id,
        [
          for (final r in conflicts)
            if (_sameDay(r.startsAt.toLocal(), saved.day)) r,
        ],
        reason: saved.closed
            ? 'Odwołana przez lokal: zamknięte $day${note == null || note.isEmpty ? '' : ' ($note)'}'
            : 'Odwołana przez lokal: zmiana godzin $day',
      );
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, OpeningException e) async {
    try {
      await ref.read(repositoryProvider).deleteException(profile.id, e.day);
      ref.invalidate(exceptionsProvider(profile.id));
    } catch (err) {
      if (context.mounted) showError(context, err);
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(exceptionsProvider(profile.id));

    return PanelCard(
      title: 'Dni wyjątkowe',
      trailing: editable
          ? TextButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Glyph(AppIcons.plus, size: 16),
              label: const Text('Dodaj dzień'),
            )
          : null,
      child: async.when(
        loading: () => const SizedBox(height: 60, child: LoadingView()),
        error: (e, _) => Text(errorText(e)),
        data: (items) {
          if (items.isEmpty) {
            return Text(
              'Święto, remont, impreza zamknięta? Dodaj dzień, a goście nie zarezerwują '
              'stolika, kiedy lokal jest zamknięty.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final e in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Fmt.capitalize(Fmt.dayLong(e.day)), style: text.labelLarge),
                            Text(
                              [
                                e.closed ? 'Zamknięte' : '${e.opens}–${e.closes}',
                                if (e.note != null && e.note!.isNotEmpty) e.note!,
                              ].join(' · '),
                              style: text.bodySmall?.copyWith(
                                color: e.closed ? AppColors.error : AppColors.textMuted,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (editable)
                        IconButton(
                          tooltip: 'Usuń dzień wyjątkowy',
                          icon: Glyph(AppIcons.trash, size: 16, color: AppColors.textMuted),
                          onPressed: () => _delete(context, ref, e),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Wybór dnia, zamknięcia albo innych godzin i krótkiej notatki.
class _ExceptionDialog extends StatefulWidget {
  const _ExceptionDialog();

  @override
  State<_ExceptionDialog> createState() => _ExceptionDialogState();
}

class _ExceptionDialogState extends State<_ExceptionDialog> {
  DateTime? _day;
  bool _closed = true;
  TimeOfDay _opens = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _closes = const TimeOfDay(hour: 18, minute: 0);
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  static String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  void _save() {
    final day = _day;
    if (day == null) {
      showMessage(context, 'Wybierz dzień.');
      return;
    }
    if (!_closed && _closes.hour * 60 + _closes.minute <= _opens.hour * 60 + _opens.minute) {
      showMessage(context, 'Zamknięcie musi być później niż otwarcie.');
      return;
    }
    Navigator.pop(
      context,
      OpeningException(
        day: day,
        closed: _closed,
        opens: _closed ? null : _format(_opens),
        closes: _closed ? null : _format(_closes),
        note: _note.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Dzień wyjątkowy'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _pickDay,
              icon: const Glyph(AppIcons.calendar, size: 16),
              label: Text(
                _day == null ? 'Wybierz dzień' : Fmt.capitalize(Fmt.dayLong(_day!)),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedTabs<bool>(
                options: const [(true, 'Zamknięte'), (false, 'Inne godziny')],
                selected: _closed,
                onChanged: (v) => setState(() => _closed = v),
              ),
            ),
            if (!_closed) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  _TimeButton(
                    value: _format(_opens),
                    onTap: () async {
                      final t = await pickTime(context, initial: _opens);
                      if (t != null) setState(() => _opens = t);
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('–', style: text.bodyMedium),
                  ),
                  _TimeButton(
                    value: _format(_closes),
                    onTap: () async {
                      final t = await pickTime(context, initial: _closes, allowEndOfDay: true, title: 'Zamknięcie');
                      if (t != null) setState(() => _closes = t);
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Notatka (opcjonalnie)',
                hintText: 'Wigilia, remont kuchni, impreza zamknięta',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(onPressed: _save, child: const Text('Zapisz')),
      ],
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({required this.value, required this.onTap});

  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(74, 36),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      child: Text(
        value,
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    );
  }
}

class _LogoCard extends ConsumerStatefulWidget {
  const _LogoCard({required this.profile, required this.editable});

  final RestaurantProfile profile;
  final bool editable;

  @override
  ConsumerState<_LogoCard> createState() => _LogoCardState();
}

class _LogoCardState extends ConsumerState<_LogoCard> {
  bool _busy = false;

  static const _maxBytes = 2 * 1024 * 1024;

  Future<void> _pick() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Obrazy',
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
          uniformTypeIdentifiers: ['public.png', 'public.jpeg', 'org.webmproject.webp'],
        ),
      ],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxBytes) {
      if (mounted) showMessage(context, 'Logo może mieć najwyżej 2 MB. Zmniejsz plik i spróbuj ponownie.');
      return;
    }
    final name = file.name.toLowerCase();
    final ext = name.contains('.') ? name.split('.').last : 'png';
    if (!['png', 'jpg', 'jpeg', 'webp'].contains(ext)) {
      if (mounted) showMessage(context, 'Wybierz plik PNG, JPG albo WEBP.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).uploadLogo(
        restaurantId: widget.profile.id,
        bytes: bytes,
        extension: ext,
      );
      ref
        ..invalidate(profileProvider(widget.profile.id))
        ..invalidate(restaurantsProvider);
      if (mounted) showMessage(context, 'Logo zapisane. Goście zobaczą je w aplikacji.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final ok = await confirm(
      context,
      title: 'Usunąć logo?',
      message: 'W aplikacji zamiast logo pojawią się inicjały lokalu.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).removeLogo(widget.profile.id);
      ref
        ..invalidate(profileProvider(widget.profile.id))
        ..invalidate(restaurantsProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final profile = widget.profile;
    return PanelCard(
      title: 'Logo',
      child: Row(
        children: [
          ImageOutline(
            radius: 20,
            child: RestaurantLogo(name: profile.name, logoUrl: profile.logoUrl, size: 88, radius: 20),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logo widzą goście na liście lokali, na stronie lokalu i przy rezerwacjach. '
                  'Najlepiej kwadratowe, PNG, JPG albo WEBP, do 2 MB.',
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
                if (widget.editable) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _pick,
                        icon: const Glyph(AppIcons.plus, size: 16),
                        label: Text(profile.logoUrl == null ? 'Wgraj logo' : 'Zmień logo'),
                      ),
                      if (profile.logoUrl != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _busy ? null : _remove,
                          style: TextButton.styleFrom(foregroundColor: AppColors.error),
                          child: const Text('Usuń'),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Zdjęcie lokalu na liście lokali w aplikacji Table (na całą szerokość karty) i na górze strony lokalu.
/// Bez zdjęcia aplikacja pokazuje pierwsze zdjęcie dania z menu, a bez niego kartę z ikoną kuchni.
class _CoverCard extends ConsumerStatefulWidget {
  const _CoverCard({required this.profile, required this.editable});

  final RestaurantProfile profile;
  final bool editable;

  @override
  ConsumerState<_CoverCard> createState() => _CoverCardState();
}

class _CoverCardState extends ConsumerState<_CoverCard> {
  bool _busy = false;

  Future<void> _pick() async {
    final Uint8List? jpeg;
    try {
      jpeg = await pickMenuPhoto();
    } on FormatException {
      if (mounted) showMessage(context, 'To nie jest zdjęcie. Wybierz plik JPG, PNG albo WEBP.');
      return;
    }
    if (jpeg == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).uploadCover(restaurantId: widget.profile.id, jpeg: jpeg);
      ref.invalidate(profileProvider(widget.profile.id));
      if (mounted) showMessage(context, 'Zdjęcie zapisane. Goście zobaczą je na liście lokali.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final ok = await confirm(
      context,
      title: 'Usunąć zdjęcie lokalu?',
      message: 'Na liście lokali pojawi się pierwsze zdjęcie dania z menu albo karta z ikoną kuchni.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).removeCover(widget.profile.id);
      ref.invalidate(profileProvider(widget.profile.id));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final url = widget.profile.coverUrl;
    return PanelCard(
      title: 'Zdjęcie na liście lokali',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 192,
              height: 108,
              child: url == null
                  ? ColoredBox(
                      color: AppColors.surfaceRaised,
                      child: Center(child: Glyph(AppIcons.forkKnife, size: 28, color: AppColors.textMuted)),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(color: AppColors.surfaceRaised),
                    ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zdjęcie jedzenia albo wnętrza na całą szerokość karty lokalu w aplikacji Table. '
                  'Najlepiej poziome (16:9). Bez niego aplikacja pokazuje pierwsze zdjęcie dania z menu.',
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
                if (widget.editable) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: _busy ? null : _pick,
                        icon: const Glyph(AppIcons.plus, size: 16),
                        label: Text(url == null ? 'Wgraj zdjęcie' : 'Zmień zdjęcie'),
                      ),
                      if (url != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _busy ? null : _remove,
                          style: TextButton.styleFrom(foregroundColor: AppColors.error),
                          child: const Text('Usuń'),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Okres grafiku: na tydzień, 2 tygodnie albo miesiąc pracownicy zgłaszają godziny
/// w aplikacji Table for employees.
class _SchedulePeriodCard extends ConsumerStatefulWidget {
  const _SchedulePeriodCard({required this.profile, required this.editable});

  final RestaurantProfile profile;
  final bool editable;

  @override
  ConsumerState<_SchedulePeriodCard> createState() => _SchedulePeriodCardState();
}

class _SchedulePeriodCardState extends ConsumerState<_SchedulePeriodCard> {
  bool _busy = false;

  Future<void> _set(String period) => _save({'schedule_period': period}, 'Okres grafiku zapisany.');

  Future<void> _save(Map<String, dynamic> values, String done) async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).updateProfile(widget.profile.id, values);
      ref.invalidate(profileProvider(widget.profile.id));
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _weekdays = ['poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota', 'niedziela'];

  Future<void> _pickDeadlineTime() async {
    final parts = widget.profile.scheduleDeadlineTime.split(':');
    final picked = await pickTime(
      context,
      initial: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      title: 'Godzina terminu',
    );
    if (picked == null) return;
    final hm = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    await _save({'schedule_deadline_time': hm}, 'Termin zgłaszania zapisany.');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PanelCard(
      title: 'Grafik pracowników',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Na jaki okres pracownicy zgłaszają w aplikacji Table for employees, od której do której mogą pracować.',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          IgnorePointer(
            ignoring: !widget.editable || _busy,
            child: SegmentedTabs<String>(
              options: const [('week', 'Tydzień'), ('two_weeks', '2 tygodnie'), ('month', 'Miesiąc')],
              selected: widget.profile.schedulePeriod,
              onChanged: (v) {
                if (v != widget.profile.schedulePeriod) _set(v);
              },
            ),
          ),
          const SizedBox(height: 16),
          Text('Termin zgłaszania dyspozycyjności', style: text.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Do kiedy pracownicy wpisują godziny na następny okres. Po terminie wpisywanie w aplikacji się wyłącza, '
            'a dni bez zgłoszenia są „Niedostępny”.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 10),
          IgnorePointer(
            ignoring: !widget.editable || _busy,
            child: Row(
              children: [
                SizedBox(
                  width: 240,
                  child: DropdownButtonFormField<int?>(
                    initialValue: widget.profile.scheduleDeadlineDow,
                    decoration: const InputDecoration(labelText: 'Dzień przed okresem', isDense: true),
                    icon: const Glyph(AppIcons.caretDown, size: 16),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Bez terminu')),
                      for (var d = 1; d <= 7; d++)
                        DropdownMenuItem(value: d, child: Text('${Fmt.capitalize(_weekdays[d - 1])} przed')),
                    ],
                    onChanged: (v) => _save({'schedule_deadline_dow': v}, 'Termin zgłaszania zapisany.'),
                  ),
                ),
                const SizedBox(width: 12),
                if (widget.profile.scheduleDeadlineDow != null)
                  OutlinedButton.icon(
                    onPressed: _pickDeadlineTime,
                    icon: const Glyph(AppIcons.clock, size: 16),
                    label: Text('do ${widget.profile.scheduleDeadlineTime}'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dane właściciela lokalu: osoba, kontakt i firma. Widać je tylko w panelu, u kierownika i właściciela,
/// tylko do odczytu (zmiana w Table Dev). Nie ma ich w aplikacji Table ani w Table for employees.
class _OwnerCard extends ConsumerWidget {
  const _OwnerCard({required this.restaurantId});

  final String restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ownerDetailsProvider(restaurantId));
    return async.when(
      loading: () => const PanelCard(title: 'Dane właściciela', child: SizedBox(height: 120, child: LoadingView())),
      error: (e, _) => PanelCard(
        title: 'Dane właściciela',
        child: ErrorView(error: e, onRetry: () => ref.invalidate(ownerDetailsProvider(restaurantId))),
      ),
      data: (details) => _OwnerView(details: details),
    );
  }
}

/// Dane właściciela tylko do odczytu. Zmienia je zespół Table w Table Dev.
class _OwnerView extends StatelessWidget {
  const _OwnerView({required this.details});

  final OwnerDetails details;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget field(String label, String? value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 3),
        SelectableText(
          value == null || value.isEmpty ? '—' : value,
          style: text.bodyLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
    Widget row(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: a), const SizedBox(width: 16), Expanded(child: b)],
    );
    final nip = details.nip;

    return PanelCard(
      title: 'Dane właściciela',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(AppIcons.lock, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text('Tylko do odczytu', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(field('Imię i nazwisko', details.ownerName), field('Telefon', details.ownerPhone)),
          const SizedBox(height: 14),
          row(field('E-mail', details.ownerEmail), field('NIP', nip == null ? null : _formatNip(nip))),
          const SizedBox(height: 14),
          row(field('Nazwa firmy', details.companyName), field('Adres firmy', details.companyAddress)),
        ],
      ),
    );
  }

  /// NIP w grupach, np. 542-345-67-89.
  static String _formatNip(String nip) => nip.length == 10
      ? '${nip.substring(0, 3)}-${nip.substring(3, 6)}-${nip.substring(6, 8)}-${nip.substring(8)}'
      : nip;
}

/// Dostawa i odbiór osobisty: goście zamawiają w aplikacji Table, płacą kartą online albo (jeśli lokal
/// pozwoli) gotówką. Dostawy rozwożą dostawcy z kolejki w Table for employees.
class _DeliveryCard extends ConsumerStatefulWidget {
  const _DeliveryCard({super.key, required this.profile, required this.editable, required this.pro});

  final RestaurantProfile profile;
  final bool editable;
  final bool pro;

  @override
  ConsumerState<_DeliveryCard> createState() => _DeliveryCardState();
}

class _DeliveryCardState extends ConsumerState<_DeliveryCard> {
  late DeliverySettings _s = widget.profile.delivery;
  late final _fee = TextEditingController(text: groszeToText(widget.profile.delivery.feeGrosze));
  late final _min = TextEditingController(text: groszeToText(widget.profile.delivery.minGrosze));
  late final _area = TextEditingController(text: widget.profile.delivery.area ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _fee.dispose();
    _min.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final fee = _fee.text.trim().isEmpty ? 0 : parseGrosze(_fee.text);
    final min = _min.text.trim().isEmpty ? 0 : parseGrosze(_min.text);
    if (fee == null || min == null) {
      showMessage(context, 'Wpisz kwoty, na przykład 8 albo 8,50.', tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).updateProfile(widget.profile.id, {
        'delivery_enabled': _s.deliveryEnabled,
        'pickup_enabled': _s.pickupEnabled,
        'takeaway_cash': _s.cash,
        'delivery_fee_grosze': fee,
        'delivery_min_grosze': min,
        'delivery_area': _area.text.trim().isEmpty ? null : _area.text.trim(),
      });
      ref.invalidate(profileProvider(widget.profile.id));
      if (mounted) showMessage(context, 'Ustawienia dostawy zapisane.', tone: ToastTone.success);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final enabled = widget.editable && widget.pro && !_busy;
    Widget toggle(String title, bool value, ValueChanged<bool> onChanged) => Row(
      children: [
        Expanded(child: Text(title, style: text.titleSmall)),
        Switch(value: value, onChanged: enabled ? onChanged : null),
      ],
    );
    return PanelCard(
      title: 'Dostawa i odbiór',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.pro) ...[
            Text(
              'Zamówienia z dostawą i na wynos są w planie Pro.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
          ],
          toggle('Dostawa', _s.deliveryEnabled, (v) => setState(() => _s = _copy(delivery: v))),
          const SizedBox(height: 6),
          toggle('Odbiór osobisty', _s.pickupEnabled, (v) => setState(() => _s = _copy(pickup: v))),
          const SizedBox(height: 6),
          toggle('Gotówka', _s.cash, (v) => setState(() => _s = _copy(cash: v))),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fee,
                  enabled: enabled,
                  decoration: const InputDecoration(labelText: 'Opłata za dostawę', suffixText: 'zł'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _min,
                  enabled: enabled,
                  decoration: const InputDecoration(labelText: 'Minimalne zamówienie', suffixText: 'zł'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _area,
            enabled: enabled,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Obszar dostawy dla gości', hintText: 'Na przykład: Białystok, do 5 km'),
          ),
          if (widget.editable && widget.pro)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _busy ? null : _save, child: const Text('Zapisz')),
            ),
        ],
      ),
    );
  }

  DeliverySettings _copy({bool? delivery, bool? pickup, bool? cash}) => DeliverySettings(
    deliveryEnabled: delivery ?? _s.deliveryEnabled,
    pickupEnabled: pickup ?? _s.pickupEnabled,
    cash: cash ?? _s.cash,
    feeGrosze: _s.feeGrosze,
    minGrosze: _s.minGrosze,
    area: _s.area,
  );
}

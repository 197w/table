import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

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
        const PageHeader(
          title: 'Dane lokalu',
          subtitle: 'Dane widoczne dla gości w aplikacji Table.',
        ),
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
                        _DetailsForm(
                          key: ValueKey('dane-${profile.id}'),
                          profile: profile,
                          editable: restaurant.canManage,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 2,
                    child: _HoursForm(
                      key: ValueKey('godziny-${profile.id}'),
                      profile: profile,
                      editable: restaurant.canManage,
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
  late int _interval = widget.profile.slotIntervalMin;
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
        'slot_interval_min': _interval,
      });
      ref
        ..invalidate(profileProvider(widget.profile.id))
        ..invalidate(restaurantsProvider);
      if (mounted) showMessage(context, 'Dane lokalu zapisane.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
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
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              'Punkt na mapie ustawia zespół Table po zmianie adresu.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
          const SizedBox(height: 18),
          Text('Rezerwacje w aplikacji', style: text.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Co ile minut goście mogą wybrać godzinę przyjścia',
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
              ),
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
          const SizedBox(height: 14),
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
    final picked = await pickTime(context, initial: opens ? d.opens : d.closes);
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
      await ref.read(repositoryProvider).setHours(widget.profile.id, hours);
      ref.invalidate(profileProvider(widget.profile.id));
      if (mounted) showMessage(context, 'Godziny otwarcia zapisane.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
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
      if (mounted) showMessage(context, errorText(e));
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
      if (mounted) showMessage(context, errorText(e));
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
          RestaurantLogo(name: profile.name, logoUrl: profile.logoUrl, size: 88, radius: 20),
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

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Nowa rezerwacja telefoniczna, gość z ulicy albo blokada stolika.
/// Zwraca identyfikator utworzonej rezerwacji.
class NewReservationDialog extends ConsumerStatefulWidget {
  const NewReservationDialog({
    super.key,
    required this.restaurantId,
    required this.source,
    required this.day,
  });

  final String restaurantId;
  final ReservationSource source;
  final DateTime day;

  @override
  ConsumerState<NewReservationDialog> createState() => _NewReservationDialogState();
}

class _NewReservationDialogState extends ConsumerState<NewReservationDialog> {
  late ReservationSource _source = widget.source;
  late DateTime _day = widget.day;
  late TimeOfDay _time = _defaultTime();
  int _party = 2;
  int? _duration;
  Occasion? _occasion;
  final Set<String> _tables = {};
  bool _autoTable = true;
  bool _busy = false;
  String? _nameError;

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _message = TextEditingController();
  final _note = TextEditingController();

  bool get _walkIn => _source == ReservationSource.walkIn;
  bool get _block => _source == ReservationSource.block;

  TimeOfDay _defaultTime() {
    final now = DateTime.now();
    if (widget.source == ReservationSource.walkIn) {
      return TimeOfDay(hour: now.hour, minute: now.minute);
    }
    final isToday = dateOnly(now) == widget.day;
    return isToday && now.hour < 22
        ? TimeOfDay(hour: now.hour + 1, minute: 0)
        : const TimeOfDay(hour: 18, minute: 0);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _message.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: dateOnly(DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _day = dateOnly(picked));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!_block && _name.text.trim().isEmpty) {
      setState(() => _nameError = 'Wpisz imię albo nazwę gościa.');
      return;
    }
    if (!_autoTable && _tables.isEmpty) {
      showMessage(context, 'Wybierz stolik albo zaznacz dobór automatyczny.');
      return;
    }

    final now = DateTime.now();
    final day = _walkIn ? dateOnly(now) : _day;
    final startsAt = _walkIn
        ? now
        : DateTime(day.year, day.month, day.day, _time.hour, _time.minute);

    setState(() {
      _busy = true;
      _nameError = null;
    });
    try {
      final id = await ref.read(repositoryProvider).createReservation(
        widget.restaurantId,
        NewReservation(
          startsAt: startsAt,
          partySize: _party,
          source: _source,
          guestName: _name.text,
          guestPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          occasion: _occasion,
          message: _message.text,
          staffNote: _note.text,
          tableIds: _autoTable ? null : _tables.toList(),
          durationMinutes: _duration,
        ),
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tables = ref.watch(tablesProvider(widget.restaurantId)).value ?? const [];
    final activeTables = tables.where((t) => t.active).toList();
    final seats = activeTables
        .where((t) => _tables.contains(t.id))
        .fold(0, (sum, t) => sum + t.seats);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      switch (_source) {
                        ReservationSource.walkIn => 'Gość z ulicy',
                        ReservationSource.block => 'Blokada stolika',
                        _ => 'Nowa rezerwacja',
                      },
                      style: text.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zamknij',
                    icon: const Glyph(AppIcons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SegmentedTabs<ReservationSource>(
                        options: const [
                          (ReservationSource.phone, 'Telefon'),
                          (ReservationSource.walkIn, 'Z ulicy'),
                          (ReservationSource.block, 'Blokada'),
                        ],
                        selected: _source,
                        onChanged: (s) => setState(() => _source = s),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _PickerField(
                            label: 'Dzień',
                            value: _walkIn
                                ? 'Dziś, teraz'
                                : Fmt.capitalize(Fmt.dayShort(_day)),
                            icon: AppIcons.calendar,
                            onTap: _walkIn ? null : _pickDay,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PickerField(
                            label: 'Godzina',
                            value: _walkIn
                                ? Fmt.time(DateTime.now())
                                : _time.format24(),
                            icon: AppIcons.clock,
                            onTap: _walkIn ? null : _pickTime,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _PartyStepper(
                          value: _party,
                          onChanged: (v) => setState(() => _party = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _name,
                            autofocus: !_block,
                            maxLength: 120,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: _block
                                  ? 'Opis blokady (opcjonalnie)'
                                  : 'Imię i nazwisko gościa',
                              errorText: _nameError,
                              counterText: '',
                            ),
                          ),
                        ),
                        if (!_block) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                                LengthLimitingTextInputFormatter(16),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Telefon (opcjonalnie)',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (!_block) ...[
                          Expanded(
                            child: DropdownButtonFormField<Occasion?>(
                              initialValue: _occasion,
                              decoration: const InputDecoration(labelText: 'Okazja'),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Brak')),
                                for (final o in Occasion.values)
                                  DropdownMenuItem(value: o, child: Text(o.label)),
                              ],
                              onChanged: (v) => setState(() => _occasion = v),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: DropdownButtonFormField<int?>(
                            initialValue: _duration,
                            decoration: const InputDecoration(labelText: 'Czas wizyty'),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Standardowy dla tylu osób'),
                              ),
                              for (final m in const [45, 60, 90, 120, 150, 180, 240])
                                DropdownMenuItem(value: m, child: Text(_minutes(m))),
                            ],
                            onChanged: (v) => setState(() => _duration = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text('Stolik', style: text.titleSmall),
                        const Spacer(),
                        Text(
                          'Dobierz automatycznie',
                          style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: _autoTable,
                          onChanged: (v) => setState(() => _autoTable = v),
                        ),
                      ],
                    ),
                    if (!_autoTable) ...[
                      const SizedBox(height: 8),
                      TablePicker(
                        tables: activeTables,
                        selected: _tables,
                        onToggle: (id) => setState(
                          () => _tables.contains(id) ? _tables.remove(id) : _tables.add(id),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _tables.isEmpty
                            ? 'Zaznacz jeden lub kilka stolików.'
                            : 'Miejsc przy wybranych stolikach: $seats, gości: $_party.',
                        style: text.bodySmall?.copyWith(
                          color: seats > 0 && seats < _party
                              ? AppColors.error
                              : AppColors.textMuted,
                          fontFeatures: _tabular,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (!_block) ...[
                      TextField(
                        controller: _message,
                        maxLength: 300,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Prośba gościa (opcjonalnie)',
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextField(
                      controller: _note,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Notatka dla obsługi (opcjonalnie)',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                    child: const Text('Anuluj'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(
                      switch (_source) {
                        ReservationSource.walkIn => 'Posadź gościa',
                        ReservationSource.block => 'Zablokuj stolik',
                        _ => 'Dodaj rezerwację',
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _minutes(int m) {
  final h = m ~/ 60;
  final rest = m % 60;
  if (h == 0) return '$m min';
  return rest == 0 ? '$h h' : '$h h $rest min';
}

extension on TimeOfDay {
  String format24() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final AppIconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: onTap != null,
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Glyph(icon, size: 16, color: AppColors.textMuted),
          ),
          suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 16),
        ),
        child: Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontFeatures: _tabular,
            color: onTap == null ? AppColors.textMuted : AppColors.text,
          ),
        ),
      ),
    );
  }
}

class _PartyStepper extends StatelessWidget {
  const _PartyStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ringStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Mniej osób',
            icon: const Glyph(AppIcons.minus, size: 16),
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 70,
            child: Text(
              Fmt.people(value),
              textAlign: TextAlign.center,
              style: text.labelLarge?.copyWith(fontFeatures: _tabular),
            ),
          ),
          IconButton(
            tooltip: 'Więcej osób',
            icon: const Glyph(AppIcons.plus, size: 16),
            onPressed: value < 30 ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// Wybór stolików jako klikane kafelki z liczbą miejsc.
class TablePicker extends StatelessWidget {
  const TablePicker({
    super.key,
    required this.tables,
    required this.selected,
    required this.onToggle,
  });

  final List<DiningTable> tables;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (tables.isEmpty) {
      return Text(
        'Lokal nie ma jeszcze stolików. Dodaj je w zakładce „Plan sali”.',
        style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in tables)
          FilterChip(
            selected: selected.contains(t.id),
            onSelected: (_) => onToggle(t.id!),
            label: Text(
              '${t.label} · ${t.seats} os. · ${t.zone}',
              style: TextStyle(
                fontFeatures: _tabular,
                color: selected.contains(t.id) ? AppColors.onAccent : AppColors.text,
              ),
            ),
          ),
      ],
    );
  }
}

/// Przeniesienie rezerwacji na inne stoliki. Zwraca true po zapisie.
class MoveReservationDialog extends ConsumerStatefulWidget {
  const MoveReservationDialog({
    super.key,
    required this.reservation,
    required this.restaurantId,
  });

  final PanelReservation reservation;
  final String restaurantId;

  @override
  ConsumerState<MoveReservationDialog> createState() => _MoveReservationDialogState();
}

class _MoveReservationDialogState extends ConsumerState<MoveReservationDialog> {
  late final Set<String> _selected = widget.reservation.tableIds.toSet();
  bool _busy = false;

  Future<void> _save() async {
    if (_selected.isEmpty) {
      showMessage(context, 'Wybierz co najmniej jeden stolik.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .moveReservation(widget.reservation.id, _selected.toList());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = widget.reservation;
    final tables = (ref.watch(tablesProvider(widget.restaurantId)).value ?? const [])
        .where((t) => t.active)
        .toList();
    final seats = tables
        .where((t) => _selected.contains(t.id))
        .fold(0, (sum, t) => sum + t.seats);

    return AlertDialog(
      title: const Text('Zmień stolik'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${r.guestName}, ${Fmt.time(r.startsAt)}–${Fmt.time(r.endsAt)}, ${Fmt.people(r.partySize)}.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            TablePicker(
              tables: tables,
              selected: _selected,
              onToggle: (id) => setState(
                () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Miejsc: $seats, gości: ${r.partySize}. System sprawdzi, czy stoliki są wolne w tym czasie.',
              style: text.bodySmall?.copyWith(
                color: seats < r.partySize ? AppColors.error : AppColors.textMuted,
                fontFeatures: _tabular,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Przenieś'),
        ),
      ],
    );
  }
}

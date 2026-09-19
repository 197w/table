import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../floor/floor_canvas.dart';
import 'reservation_dialogs.dart';

const _tabular = [FontFeature.tabularFigures()];

enum _Filter {
  all('Wszystkie'),
  upcoming('Nadchodzące'),
  seated('Przy stoliku'),
  done('Zakończone'),
  cancelled('Odwołane i nieobecni');

  const _Filter(this.label);
  final String label;

  bool matches(PanelReservation r) => switch (this) {
    all => true,
    upcoming => r.status == ReservationStatus.confirmed,
    seated => r.status == ReservationStatus.seated,
    done => r.status == ReservationStatus.completed,
    cancelled =>
      r.status == ReservationStatus.cancelled ||
          r.status == ReservationStatus.noShow,
  };
}

class ReservationsScreen extends ConsumerStatefulWidget {
  const ReservationsScreen({super.key});

  @override
  ConsumerState<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends ConsumerState<ReservationsScreen> {
  String? _selectedId;
  String? _zoneName;
  _Filter _filter = _Filter.all;

  Future<void> _pickDay(DateTime current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) ref.read(selectedDayProvider.notifier).set(picked);
  }

  Future<void> _create(String restaurantId, ReservationSource source) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => NewReservationDialog(
        restaurantId: restaurantId,
        source: source,
        day: ref.read(selectedDayProvider),
      ),
    );
    if (id != null && mounted) {
      setState(() => _selectedId = id);
      showMessage(
        context,
        source == ReservationSource.walkIn
            ? 'Gość z ulicy siedzi przy stoliku.'
            : 'Rezerwacja dodana.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();

    if (!restaurant.isPro) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Rezerwacje'),
          Expanded(child: ProGate(feature: 'Rezerwacje w aplikacji')),
        ],
      );
    }

    final day = ref.watch(selectedDayProvider);
    final query = (restaurantId: restaurant.id, day: day);
    final async = ref.watch(reservationsProvider(query));
    final isToday = day == dateOnly(DateTime.now());
    final items = async.value ?? const <PanelReservation>[];

    PanelReservation? selected;
    for (final r in items) {
      if (r.id == _selectedId) selected = r;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Rezerwacje',
          subtitle:
              '${Fmt.capitalize(Fmt.dayLong(day))}${isToday ? ' · dziś' : ''}',
          actions: [
            IconButton(
              tooltip: 'Poprzedni dzień',
              icon: const Glyph(AppIcons.caretLeft, size: 18),
              onPressed: () => ref.read(selectedDayProvider.notifier).shift(-1),
            ),
            OutlinedButton(
              onPressed: isToday
                  ? null
                  : () => ref.read(selectedDayProvider.notifier).today(),
              child: const Text('Dziś'),
            ),
            IconButton(
              tooltip: 'Następny dzień',
              icon: const Glyph(AppIcons.caretRight, size: 18),
              onPressed: () => ref.read(selectedDayProvider.notifier).shift(1),
            ),
            IconButton(
              tooltip: 'Wybierz dzień',
              icon: const Glyph(AppIcons.calendar, size: 18),
              onPressed: () => _pickDay(day),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Gość z ulicy',
              child: OutlinedButton(
                onPressed: () => _create(restaurant.id, ReservationSource.walkIn),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(44, 40),
                  padding: EdgeInsets.zero,
                ),
                child: const Glyph(AppIcons.doorOpen, size: 18),
              ),
            ),
            Tooltip(
              message: 'Nowa rezerwacja',
              child: FilledButton(
                onPressed: () => _create(restaurant.id, ReservationSource.phone),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(44, 40),
                  padding: EdgeInsets.zero,
                ),
                child: const Glyph(AppIcons.plus, size: 18),
              ),
            ),
          ],
          below: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedTabs<_Filter>(
              options: [for (final f in _Filter.values) (f, f.label)],
              selected: _filter,
              onChanged: (f) => setState(() => _filter = f),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
            child: async.when(
              skipLoadingOnReload: true,
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(
                error: e,
                onRetry: () => ref.invalidate(reservationsProvider(query)),
              ),
              data: (all) {
                final visible = all.where(_filter.matches).toList();
                final tables =
                    ref.watch(tablesProvider(restaurant.id)).value ?? const <DiningTable>[];
                final zones =
                    ref.watch(zonesProvider(restaurant.id)).value ?? const <FloorZone>[];
                final elements =
                    ref.watch(elementsProvider(restaurant.id)).value ?? const <FloorElement>[];
                final side = SizedBox(
                  width: 440,
                  child: selected != null
                      ? ReservationDetail(
                          key: ValueKey(selected.id),
                          reservation: selected,
                          restaurantId: restaurant.id,
                          onChanged: () => ref.invalidate(reservationsProvider(query)),
                          onBack: () => setState(() => _selectedId = null),
                        )
                      : Card(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _Counts(items: all),
                              Divider(height: 1, color: AppColors.ring),
                              Expanded(
                                child: visible.isEmpty
                              ? MessageView(
                                  icon: AppIcons.calendarDots,
                                  title: all.isEmpty ? 'Brak rezerwacji' : 'Nic w tym filtrze',
                                  message: all.isEmpty
                                      ? 'Rezerwacje z aplikacji pojawią się tu same. Telefoniczne dodasz przyciskiem z plusem u góry.'
                                      : 'Wybierz inny filtr, żeby zobaczyć pozostałe rezerwacje.',
                                )
                              : Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                                  child: _ReservationList(
                                    items: visible,
                                    selectedId: _selectedId,
                                    onSelect: (id) => setState(() => _selectedId = id),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                );

                if (tables.isEmpty) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(
                        child: MessageView(
                          icon: AppIcons.squaresFour,
                          title: 'Sala jest pusta',
                          message:
                              'Rozstaw stoliki w zakładce „Plan sali”, a tutaj zobaczysz je razem z rezerwacjami.',
                        ),
                      ),
                      const SizedBox(width: 20),
                      side,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _PlanPanel(
                        zones: zones,
                        tables: tables,
                        elements: elements,
                        reservations: all,
                        day: day,
                        zoneName: _zoneName,
                        selected: selected,
                        onZone: (z) => setState(() => _zoneName = z),
                        onSelectReservation: (id) => setState(() => _selectedId = id),
                      ),
                    ),
                    const SizedBox(width: 20),
                    side,
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Liczba rezerwacji i gości w dniu, jako ikona i liczba nad listą.
class _Counts extends StatelessWidget {
  const _Counts({required this.items});

  final List<PanelReservation> items;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final booked = items.where(
      (r) =>
          !r.isBlock &&
          r.status != ReservationStatus.cancelled &&
          r.status != ReservationStatus.noShow,
    );
    final guests = booked.fold(0, (sum, r) => sum + r.partySize);

    Widget count(AppIconData icon, int value, String tooltip) => Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: text.titleSmall?.copyWith(fontFeatures: _tabular),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          count(AppIcons.calendarCheck, booked.length, 'Rezerwacje w tym dniu'),
          const SizedBox(width: 20),
          count(AppIcons.users, guests, 'Goście w tym dniu'),
        ],
      ),
    );
  }
}

class _ReservationList extends StatelessWidget {
  const _ReservationList({
    required this.items,
    required this.selectedId,
    required this.onSelect,
  });

  final List<PanelReservation> items;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = <Widget>[];
    int? lastHour;
    for (final r in items) {
      final hour = r.startsAt.hour;
      if (hour != lastHour) {
        rows.add(
          Padding(
            padding: EdgeInsets.fromLTRB(4, rows.isEmpty ? 0 : 14, 0, 8),
            child: Text(
              '${hour.toString().padLeft(2, '0')}:00',
              style: text.labelMedium?.copyWith(
                color: AppColors.textMuted,
                fontFeatures: _tabular,
              ),
            ),
          ),
        );
        lastHour = hour;
      }
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ReservationRow(
            reservation: r,
            selected: r.id == selectedId,
            onTap: () => onSelect(r.id),
          ),
        ),
      );
    }
    return ListView(padding: EdgeInsets.zero, children: rows);
  }
}

class _ReservationRow extends StatelessWidget {
  const _ReservationRow({
    required this.reservation,
    required this.selected,
    required this.onTap,
  });

  final PanelReservation reservation;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final text = Theme.of(context).textTheme;
    final inactive =
        r.status == ReservationStatus.cancelled ||
        r.status == ReservationStatus.noShow;

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? AppColors.accent : AppColors.ring,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: AppColors.ring,
        splashColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Fmt.time(r.startsAt),
                      style: text.titleMedium?.copyWith(fontFeatures: _tabular),
                    ),
                    Text(
                      Fmt.time(r.endsAt),
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            r.guestName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: inactive
                                  ? AppColors.textMuted
                                  : AppColors.text,
                              decoration: inactive
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SourceIcon(source: r.source),
                        if (r.occasion != null) ...[
                          const SizedBox(width: 8),
                          Tag(
                            r.occasion!.label.toUpperCase(),
                            color: AppColors.accent,
                          ),
                        ],
                        if (r.diet != null) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Alergie lub dieta',
                            child: Glyph(
                              AppIcons.warning,
                              size: 16,
                              color: AppColors.warning,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (!r.isBlock) Fmt.people(r.partySize),
                        if (r.tableLabels.isNotEmpty)
                          'stolik ${r.tableLabels.join(' + ')}'
                        else
                          'bez stolika',
                        if (r.message != null) '„${r.message}”',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusPill(status: r.status),
            ],
          ),
        ),
      ),
    );
  }
}

class SourceIcon extends StatelessWidget {
  const SourceIcon({super.key, required this.source});

  final ReservationSource source;

  @override
  Widget build(BuildContext context) {
    final icon = switch (source) {
      ReservationSource.app => AppIcons.deviceMobile,
      ReservationSource.phone => AppIcons.phone,
      ReservationSource.walkIn => AppIcons.doorOpen,
      ReservationSource.block => AppIcons.prohibit,
    };
    return Tooltip(
      message: source.label,
      child: Glyph(icon, size: 15, color: AppColors.textMuted),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final ReservationStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (status) {
      ReservationStatus.confirmed => (AppColors.text, AppColors.surfaceRaised),
      ReservationStatus.seated => (AppColors.accent, AppColors.accentTint),
      ReservationStatus.completed => (AppColors.textMuted, AppColors.surfaceRaised),
      ReservationStatus.cancelled => (AppColors.textMuted, AppColors.surfaceRaised),
      ReservationStatus.noShow => (AppColors.error, AppColors.error.withValues(alpha: 0.12)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Szczegóły rezerwacji
// ---------------------------------------------------------------

class ReservationDetail extends ConsumerStatefulWidget {
  const ReservationDetail({
    super.key,
    required this.reservation,
    required this.restaurantId,
    required this.onChanged,
    required this.onBack,
  });

  final PanelReservation reservation;
  final String restaurantId;
  final VoidCallback onChanged;

  /// Powrót do listy rezerwacji w prawej kolumnie.
  final VoidCallback onBack;

  @override
  ConsumerState<ReservationDetail> createState() => _ReservationDetailState();
}

class _ReservationDetailState extends ConsumerState<ReservationDetail> {
  late final _note = TextEditingController(
    text: widget.reservation.staffNote ?? '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      widget.onChanged();
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(ReservationStatus status, String done) {
    return _run(
      () => ref.read(repositoryProvider).setStatus(widget.reservation.id, status),
      done,
    );
  }

  Future<void> _cancel() async {
    final ok = await confirm(
      context,
      title: 'Odwołać rezerwację?',
      message: widget.reservation.fromApp
          ? 'Stolik wróci do puli. Gość zobaczy w aplikacji, że rezerwacja została odwołana.'
          : 'Stolik wróci do puli. Zadzwoń do gościa, żeby dać mu znać.',
      action: 'Odwołaj',
      destructive: true,
    );
    if (ok) await _setStatus(ReservationStatus.cancelled, 'Rezerwacja odwołana.');
  }

  Future<void> _move() async {
    final moved = await showDialog<bool>(
      context: context,
      builder: (_) => MoveReservationDialog(
        reservation: widget.reservation,
        restaurantId: widget.restaurantId,
      ),
    );
    if (moved == true) {
      widget.onChanged();
      if (mounted) showMessage(context, 'Rezerwacja przeniesiona.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reservation;
    final text = Theme.of(context).textTheme;
    final noteChanged = _note.text.trim() != (r.staffNote ?? '');

    return Card(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: 'Wróć do listy',
                icon: const Glyph(AppIcons.caretLeft, size: 18),
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 4),
              Expanded(child: Text(r.guestName, style: text.titleLarge)),
              const SizedBox(width: 8),
              StatusPill(status: r.status),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              SourceIcon(source: r.source),
              const SizedBox(width: 6),
              Text(
                r.fromApp
                    ? (r.guestVisits == 0
                          ? 'Z aplikacji · pierwsza wizyta'
                          : 'Z aplikacji · ${r.guestVisits + 1}. wizyta')
                    : r.source.label,
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          if (r.guestNoShows > 0) ...[
            const SizedBox(height: 12),
            _Callout(
              icon: AppIcons.warning,
              color: AppColors.warning,
              text:
                  'Ten gość nie przyszedł wcześniej ${r.guestNoShows} ${r.guestNoShows == 1 ? 'raz' : 'razy'}.',
            ),
          ],
          if (r.guestPhone != null) ...[
            const SizedBox(height: 12),
            _PhoneRow(phone: r.guestPhone!),
          ],
          const SizedBox(height: 16),
          _InfoRow(
            label: 'Godzina',
            value: '${Fmt.time(r.startsAt)}–${Fmt.time(r.endsAt)}',
          ),
          if (!r.isBlock) _InfoRow(label: 'Liczba osób', value: Fmt.people(r.partySize)),
          _InfoRow(
            label: 'Stolik',
            value: r.tableLabels.isEmpty ? 'bez stolika' : r.tableLabels.join(' + '),
            trailing: r.status.isActive
                ? TextButton(
                    onPressed: _busy ? null : _move,
                    child: const Text('Zmień'),
                  )
                : null,
          ),
          if (r.occasion != null) _InfoRow(label: 'Okazja', value: r.occasion!.label),
          _InfoRow(
            label: 'Utworzona',
            value: Fmt.dateTime(r.createdAt),
          ),
          if (r.seatedAt != null)
            _InfoRow(label: 'Przyszedł', value: Fmt.time(r.seatedAt!)),
          if (r.message != null) ...[
            const SizedBox(height: 14),
            Text('Wiadomość od gościa', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 4),
            Text(r.message!, style: text.bodyMedium),
          ],
          if (r.diet != null) ...[
            const SizedBox(height: 14),
            _Callout(
              icon: AppIcons.warning,
              color: AppColors.warning,
              title: 'Alergie i dieta',
              text: r.diet!,
            ),
          ],
          const SizedBox(height: 18),
          Text('Notatka obsługi', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 6),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 5,
            maxLength: 500,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Widzi ją tylko personel, na przykład „stolik przy oknie”.',
            ),
          ),
          if (noteChanged)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => ref.read(repositoryProvider).setStaffNote(r.id, _note.text),
                        'Notatka zapisana.',
                      ),
                child: const Text('Zapisz notatkę'),
              ),
            ),
          const SizedBox(height: 12),
          ..._actions(r),
        ],
      ),
    );
  }

  List<Widget> _actions(PanelReservation r) {
    const gap = SizedBox(height: 8);
    switch (r.status) {
      case ReservationStatus.confirmed:
        return [
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _setStatus(ReservationStatus.seated, 'Gość jest przy stoliku.'),
            icon: const Glyph(AppIcons.userCheck, size: 18),
            label: Text(r.isBlock ? 'Rozpocznij blokadę' : 'Gość przyszedł'),
          ),
          gap,
          if (!r.isBlock) ...[
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _setStatus(ReservationStatus.noShow, 'Oznaczono jako nieobecność.'),
              icon: const Glyph(AppIcons.userMinus, size: 18),
              label: const Text('Nie przyszedł'),
            ),
            gap,
          ],
          TextButton(
            onPressed: _busy ? null : _cancel,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(r.isBlock ? 'Usuń blokadę' : 'Odwołaj rezerwację'),
          ),
        ];
      case ReservationStatus.seated:
        return [
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _setStatus(ReservationStatus.completed, 'Wizyta zakończona, stolik wolny.'),
            icon: const Glyph(AppIcons.checkCircle, size: 18),
            label: const Text('Zakończ wizytę'),
          ),
          gap,
          TextButton(
            onPressed: _busy
                ? null
                : () => _setStatus(ReservationStatus.confirmed, 'Cofnięto przyjście gościa.'),
            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
            child: const Text('Cofnij przyjście'),
          ),
        ];
      case ReservationStatus.cancelled:
      case ReservationStatus.noShow:
        return [
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _setStatus(ReservationStatus.confirmed, 'Rezerwacja przywrócona.'),
            icon: const Glyph(AppIcons.undo, size: 18),
            label: const Text('Przywróć rezerwację'),
          ),
        ];
      case ReservationStatus.completed:
        return const [];
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(
              value,
              style: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                fontFeatures: _tabular,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Glyph(AppIcons.phone, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              Fmt.phone(phone),
              style: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: _tabular,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Kopiuj numer',
            icon: const Glyph(AppIcons.copy, size: 16),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: phone));
              showMessage(context, 'Skopiowano numer.');
            },
          ),
        ],
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    required this.icon,
    required this.color,
    required this.text,
    this.title,
  });

  final AppIconData icon;
  final Color color;
  final String? title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Glyph(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(title!, style: theme.labelLarge?.copyWith(color: color)),
                Text(text, style: theme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// Plan sali obok listy rezerwacji
// ---------------------------------------------------------------

class _PlanPanel extends StatelessWidget {
  const _PlanPanel({
    required this.zones,
    required this.tables,
    required this.elements,
    required this.reservations,
    required this.day,
    required this.zoneName,
    required this.selected,
    required this.onZone,
    required this.onSelectReservation,
  });

  final List<FloorZone> zones;
  final List<DiningTable> tables;
  final List<FloorElement> elements;
  final List<PanelReservation> reservations;
  final DateTime day;
  final String? zoneName;
  final PanelReservation? selected;
  final ValueChanged<String> onZone;
  final ValueChanged<String> onSelectReservation;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final isToday = day == dateOnly(now);
    // Bez wybranej rezerwacji plan pokazuje bieżącą chwilę, a w innym dniu wieczór.
    final at = selected?.startsAt ??
        (isToday ? now : DateTime(day.year, day.month, day.day, 18));

    final list = [...zones];
    for (final t in tables) {
      if (!list.any((z) => z.name == t.zone)) {
        list.add(
          FloorZone(id: null, name: t.zone, widthCm: 1000, heightCm: 700, position: list.length),
        );
      }
    }
    if (list.isEmpty) return const SizedBox.shrink();
    final zone = list.firstWhere((z) => z.name == zoneName, orElse: () => list.first);
    final inZone = tables.where((t) => t.zone == zone.name).toList();
    final seatedCountsNow = selected == null && isToday;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                if (list.length > 1)
                  SegmentedTabs<String>(
                    options: [for (final z in list) (z.name, Fmt.capitalize(z.name))],
                    selected: zone.name,
                    onChanged: onZone,
                  )
                else
                  Text(Fmt.capitalize(zone.name), style: text.titleMedium),
                const Spacer(),
                Glyph(AppIcons.clock, size: 15, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  selected == null
                      ? (isToday ? 'zajętość teraz' : 'zajętość o ${Fmt.time(at)}')
                      : 'zajętość o ${Fmt.time(at)}, godzina wybranej rezerwacji',
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: FloorCanvas(
                zone: zone,
                tables: inZone,
                elements: elements.where((e) => e.zone == zone.name).toList(),
                // Kratka pomaga przy rozstawianiu, więc jest tylko w zakładce „Plan sali”.
                showGrid: false,
                selectedId: null,
                lookOf: (t) => liveTableLook(
                  t,
                  reservations,
                  at,
                  seatedCountsNow: seatedCountsNow,
                  highlighted: selected?.tableIds.contains(t.id) ?? false,
                ),
                onTapTable: (t) {
                  final state = tableState(
                    t,
                    reservations,
                    at,
                    seatedCountsNow: seatedCountsNow,
                  );
                  final r = state.current ?? state.next;
                  if (r != null) onSelectReservation(r.id);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

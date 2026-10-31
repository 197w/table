import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../fleet/vehicle_days.dart';
import 'timesheet.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Kolory pracowników w kalendarzu. Czytelne w jasnym i ciemnym motywie.
const staffColors = [
  Color(0xFF16A37F),
  Color(0xFF3B82F6),
  Color(0xFFE08A1E),
  Color(0xFFD9467A),
  Color(0xFF8B5CF6),
  Color(0xFF0EA5B7),
  Color(0xFFB45309),
  Color(0xFF64748B),
];

const _weekdayShort = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'];

DateTime _weekStart(DateTime d) {
  final day = dateOnly(d);
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';

String _initials(String name) =>
    name.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();

/// Pracownicy w układzie jak „People” w UniFi (31.10.2026, wzór od użytkownika): po lewej panel z zakładkami
/// (Zespół, Grafik, Stanowiska), wyszukiwaniem, „Dodaj pracownika” i filtrami (stanowisko, stan, konto
/// w aplikacji), po prawej tabela pracowników, grafik albo tabela stanowisk.
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

/// Zakładki w panelu po lewej.
enum _View { team, schedule, positions }

/// Stan pracownika w filtrach.
enum _Status {
  onShift('Na zmianie'),
  active('Aktywni'),
  inactive('Nieaktywni');

  const _Status(this.label);
  final String label;

  bool matches(StaffMember m, Map<String, DateTime> working) => switch (this) {
    _Status.onShift => working.containsKey(m.id),
    _Status.active => m.active,
    _Status.inactive => !m.active,
  };
}

/// Szerokość panelu z zakładkami i filtrami.
const _panelWidth = 312.0;

class _StaffScreenState extends ConsumerState<StaffScreen> {
  /// Okres grafiku względem bieżącego (tydzień, 2 tygodnie albo miesiąc, jak ustawił lokal).
  int _offset = 0;
  bool _saving = false;
  _View _view = _View.team;
  bool _panelOpen = true;
  final _search = TextEditingController();

  /// Filtry: zaznaczone stanowiska ('' = bez stanowiska), stany i konto w aplikacji (true = połączone).
  /// Pusta grupa nie filtruje. Na start tylko aktywni, jak wcześniej bez „Pokaż nieaktywnych”.
  final _positionFilter = <String>{};
  final _statusFilter = <_Status>{_Status.active};
  final _accountFilter = <bool>{};

  /// Zwinięte grupy filtrów.
  final _closed = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _addMember(String restaurantId, {required bool withLogin}) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _MemberDialog(restaurantId: restaurantId),
    );
    if (id == null || !mounted) return;
    ref.invalidate(staffProvider(restaurantId));
    if (!withLogin) return;
    // Nowy pracownik od razu ma czterocyfrowy kod (nadaje go baza). Pokazujemy go do przekazania.
    try {
      ref.invalidate(staffCodesProvider(restaurantId));
      final codes = await ref.read(staffCodesProvider(restaurantId).future);
      final members = await ref.read(staffProvider(restaurantId).future);
      if (!mounted || codes[id] == null) return;
      final name = members.where((m) => m.id == id).firstOrNull?.name ?? 'Pracownik';
      await showDialog<void>(
        context: context,
        builder: (_) => CodeDialog(name: name, code: codes[id]!),
      );
    } catch (e) {
      if (mounted) showMessage(context, 'Pracownik dodany. Kod zobaczysz w jego szczegółach.');
    }
  }

  Future<void> _openMember(String restaurantId, StaffMember member) {
    return showDialog<void>(
      context: context,
      builder: (_) => _MemberDetailsDialog(restaurantId: restaurantId, member: member),
    );
  }

  /// Dzień pracownika w trybie edycji: decyzja trafia do niezapisanych zmian.
  Future<void> _hours(
    String restaurantId,
    StaffMember member,
    DateTime day,
    PlannedShift? existing,
    ScheduleChange? staged,
    List<StaffPosition> positions,
  ) async {
    final result = await showDialog<_HoursResult>(
      context: context,
      builder: (_) => _HoursDialog(
        member: member,
        day: day,
        existing: existing,
        shown: staged == null ? existing : staged.apply(existing),
        staged: staged != null,
        positions: positions,
      ),
    );
    if (result == null || !mounted) return;
    final draft = ref.read(scheduleDraftProvider(restaurantId).notifier);
    if (result.undo) {
      draft.undo(scheduleKey(member.id, day));
    } else if (result.change case final change?) {
      draft.put(change);
    }
  }

  Future<void> _cancelEdit(String restaurantId, ScheduleDraft draft) async {
    if (draft.changes.isNotEmpty) {
      final ok = await confirm(
        context,
        title: 'Odrzucić zmiany w grafiku?',
        message: 'Niezapisane zmiany: ${draft.changes.length}. Pracownicy ich nie zobaczą.',
        action: 'Odrzuć zmiany',
        destructive: true,
      );
      if (!ok) return;
    }
    ref.read(scheduleDraftProvider(restaurantId).notifier).close();
  }

  Future<void> _saveSchedule(String restaurantId, ScheduleDraft draft) async {
    setState(() => _saving = true);
    try {
      final n = await ref.read(repositoryProvider).saveSchedule(restaurantId, draft.changes.values.toList());
      ref.read(scheduleDraftProvider(restaurantId).notifier).close();
      ref.invalidate(scheduleRangeProvider);
      if (mounted) {
        showMessage(
          context,
          'Grafik zapisany (zmiany: $n). Pracownicy widzą go już w aplikacji Table for employees.',
          tone: ToastTone.success,
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Pracownik pasuje do wyszukiwania (imię albo co najmniej 3 cyfry telefonu) i do zaznaczonych filtrów.
  bool _matches(StaffMember m, Map<String, DateTime> working) {
    final query = _search.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
      final byPhone = digits.length >= 3 && (m.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '').contains(digits);
      if (!m.name.toLowerCase().contains(query) && !byPhone) return false;
    }
    if (_positionFilter.isNotEmpty &&
        !(m.positionIds.isEmpty ? _positionFilter.contains('') : m.positionIds.any(_positionFilter.contains))) {
      return false;
    }
    if (_statusFilter.isNotEmpty && !_statusFilter.any((s) => s.matches(m, working))) return false;
    if (_accountFilter.isNotEmpty && !_accountFilter.contains(m.userId != null)) return false;
    return true;
  }

  void _toggle<T>(Set<T> set, T value, bool on) {
    setState(() {
      if (on) {
        set.add(value);
      } else {
        set.remove(value);
      }
    });
  }

  void _toggleSection(String key) => _toggle(_closed, key, !_closed.contains(key));

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    // Uprawnienia pracownika zalogowanego w tej zakładce. Każda część ma własne.
    final permissions = ref.watch(memberPermissionsProvider);
    final canStaff = permissions.contains('staff');
    final canLogins = permissions.contains('staff_logins');
    final canPlan = permissions.contains('schedule');
    final canPositions = permissions.contains('positions');
    // Czas pracy jest w Management → „Godziny pracy”.
    final views = [
      if (canStaff || canLogins) (_View.team, 'Zespół'),
      if (canPlan) (_View.schedule, 'Grafik'),
      if (canPositions) (_View.positions, 'Stanowiska'),
    ];
    if (views.isEmpty) {
      return const MessageView(
        icon: AppIcons.lock,
        title: 'Brak dostępu',
        message: 'Twoje stanowisko nie ma uprawnień do żadnej części zakładki „Pracownicy”.',
      );
    }
    final view = views.any((v) => v.$1 == _view) ? _view : views.first.$1;

    final staffAsync = ref.watch(staffProvider(restaurant.id));
    final all = staffAsync.value ?? const <StaffMember>[];
    final positions = ref.watch(positionsProvider(restaurant.id)).value ?? const <StaffPosition>[];
    final thisWeek = _weekStart(DateTime.now());
    final shifts = ref.watch(
      shiftsProvider((
        restaurantId: restaurant.id,
        from: thisWeek,
        to: DateTime(thisWeek.year, thisWeek.month, thisWeek.day + 7),
      )),
    ).value ?? const <StaffShift>[];
    final working = {for (final s in shifts) if (s.isOpen) s.memberId: s.startedAt};
    final me = ref.watch(panelMemberProvider)?.memberId;
    final members = [for (final m in all) if (_matches(m, working)) m];
    final addMember = canStaff ? () => _addMember(restaurant.id, withLogin: canLogins) : null;

    // Lista pracowników albo pusty lokal, ładowanie i błąd (Zespół i Grafik).
    Widget withStaff(Widget Function() build) => staffAsync.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(staffProvider(restaurant.id))),
      data: (all) => all.isEmpty
          ? MessageView(
              icon: AppIcons.users,
              title: 'Brak pracowników',
              message: canStaff ? 'Dodaj pracownika.' : 'Kierownik jeszcze nie dodał pracowników.',
              actionLabel: canStaff ? 'Dodaj pracownika' : null,
              onAction: addMember,
            )
          : build(),
    );

    final content = switch (view) {
      _View.team => withStaff(
        () => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 32, 16),
          child: _TeamTable(
            members: members,
            positions: positions,
            codes: canLogins
                ? ref.watch(staffCodesProvider(restaurant.id)).value ?? const <String, String>{}
                : const <String, String>{},
            showCodes: canLogins,
            working: working,
            shifts: shifts,
            me: me,
            onOpen: canStaff || canLogins ? (m) => _openMember(restaurant.id, m) : null,
          ),
        ),
      ),
      _View.schedule => withStaff(() => _schedule(restaurant.id, members, positions, canStaff, canPlan, me)),
      _View.positions => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 32, 16),
        child: _PositionsTable(
          restaurantId: restaurant.id,
          positions: positions,
          members: all,
          query: _search.text.trim().toLowerCase(),
        ),
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_panelOpen)
          _panel(
            views: views,
            view: view,
            all: all,
            positions: positions,
            working: working,
            onAdd: switch (view) {
              _View.team => addMember,
              _View.positions => () => _editPosition(context, ref, restaurant.id),
              _View.schedule => null,
            },
          )
        else
          // Zwinięty panel: wąski pasek ze strzałką, która go rozwija.
          Container(
            width: 48,
            padding: const EdgeInsets.only(top: 16),
            alignment: Alignment.topCenter,
            decoration: BoxDecoration(border: Border(right: BorderSide(color: AppColors.ring))),
            child: IconButton(
              tooltip: 'Pokaż panel',
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _panelOpen = true),
              icon: Glyph(AppIcons.caretRight, size: 16, color: AppColors.textMuted),
            ),
          ),
        Expanded(child: TabContent(tab: view, child: content)),
      ],
    );
  }

  /// Panel po lewej: zakładki, wyszukiwanie, „Dodaj…” i filtry pracowników (w Stanowiskach opis zamiast filtrów).
  Widget _panel({
    required List<(_View, String)> views,
    required _View view,
    required List<StaffMember> all,
    required List<StaffPosition> positions,
    required Map<String, DateTime> working,
    required VoidCallback? onAdd,
  }) {
    final text = Theme.of(context).textTheme;
    int count(bool Function(StaffMember m) test) => all.where(test).length;
    final noPosition = count((m) => m.positionIds.isEmpty);
    _FilterOption option<T>(Set<T> set, T value, String label, int n, {Color? dot}) => (
      label: label,
      count: n,
      checked: set.contains(value),
      onChanged: (on) => _toggle(set, value, on),
      dot: dot,
    );

    return Container(
      width: _panelWidth,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: AppColors.ring))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: views.length > 1
                      ? SegmentedTabs<_View>(
                          options: views,
                          selected: view,
                          expand: true,
                          onChanged: (v) => setState(() {
                            _view = v;
                            _search.clear();
                          }),
                        )
                      : Text(views.first.$2, style: text.titleSmall),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Zwiń panel',
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _panelOpen = false),
                  icon: Glyph(AppIcons.caretLeft, size: 16, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: view == _View.positions ? 'Szukaj stanowiska' : 'Szukaj',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Glyph(AppIcons.search, size: 16, color: AppColors.textMuted),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ),
          ),
          if (onAdd != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: OutlinedButton(
                onPressed: onAdd,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: BorderSide(color: AppColors.accent.withValues(alpha: 0.7)),
                  minimumSize: const Size.fromHeight(40),
                ),
                child: Text(view == _View.positions ? 'Dodaj stanowisko' : 'Dodaj pracownika'),
              ),
            ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (view == _View.positions)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'ALL, Kelner, Kucharz i Dostawca dodał system i nie da się ich usunąć, bo korzystają z nich '
                      'pakiety Table. Własne stanowiska dodajesz tutaj. Pracownik otworzy tylko te zakładki '
                      'i przyciski, do których jego stanowisko ma uprawnienia.',
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  )
                else ...[
                  _FilterSection(
                    title: 'Stanowisko',
                    first: true,
                    open: !_closed.contains('positions'),
                    onToggle: () => _toggleSection('positions'),
                    options: [
                      for (final p in positions)
                        option(_positionFilter, p.id, p.name, count((m) => m.positionIds.contains(p.id))),
                      if (noPosition > 0) option(_positionFilter, '', 'Bez stanowiska', noPosition),
                    ],
                  ),
                  _FilterSection(
                    title: 'Stan',
                    open: !_closed.contains('status'),
                    onToggle: () => _toggleSection('status'),
                    options: [
                      for (final s in _Status.values)
                        option(
                          _statusFilter,
                          s,
                          s.label,
                          count((m) => s.matches(m, working)),
                          dot: s == _Status.onShift ? AppColors.accent : null,
                        ),
                    ],
                  ),
                  _FilterSection(
                    title: 'Konto w aplikacji',
                    open: !_closed.contains('account'),
                    onToggle: () => _toggleSection('account'),
                    options: [
                      option(_accountFilter, true, 'Połączone', count((m) => m.userId != null)),
                      option(_accountFilter, false, 'Niepołączone', count((m) => m.userId == null)),
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

  /// Grafik: okres i edycja u góry, pod nimi tydzień pod tygodniem dla pracowników z filtrów.
  Widget _schedule(
    String restaurantId,
    List<StaffMember> members,
    List<StaffPosition> positions,
    bool canStaff,
    bool canPlan,
    String? me,
  ) {
    final text = Theme.of(context).textTheme;
    // Okres z „Ustawień lokalu” i tryb edycji.
    final periodKind = ref.watch(profileProvider(restaurantId)).value?.schedulePeriod ?? 'week';
    final period = schedulePeriod(periodKind, _offset);
    final unit = switch (periodKind) {
      'month' => 'miesiąc',
      'two_weeks' => '2 tygodnie',
      _ => 'tydzień',
    };
    final draft = ref.watch(scheduleDraftProvider(restaurantId));
    if (draft.editing && draft.editor != me) {
      // Zalogował się ktoś inny niż osoba, która edytowała: jej niezapisane zmiany znikają.
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(scheduleDraftProvider(restaurantId).notifier).close());
    }
    final editing = canPlan && draft.editing && draft.editor == me;

    // Cały okres lokalu, tydzień pod tygodniem (miesiąc: od poniedziałku do niedzieli).
    final weeks = periodWeeks(period);
    final gridEnd = DateTime(weeks.last.year, weeks.last.month, weeks.last.day + 7);
    final query = (restaurantId: restaurantId, from: weeks.first, to: gridEnd);
    final saved = ref.watch(scheduleRangeProvider(query)).value ?? const <PlannedShift>[];
    // W trybie edycji grafik pokazuje dni po niezapisanych zmianach.
    final changes = editing ? draft.changes : const <String, ScheduleChange>{};
    final savedByKey = {for (final p in saved) scheduleKey(p.memberId, p.day): p};
    final planned = [
      for (final p in saved)
        if (!changes.containsKey(scheduleKey(p.memberId, p.day))) p,
      for (final c in changes.values) ?c.apply(savedByKey[c.key]),
    ];
    bool inPeriod(DateTime d) => !d.isBefore(period.from) && !d.isAfter(period.to);
    final waiting = planned.where((p) => p.status == PlannedShiftStatus.pending && inPeriod(p.day)).length;
    // Uwagi pracowników na tygodnie (z aplikacji Table for employees).
    final notes = {
      for (final n in ref.watch(weekNotesProvider(query)).value ?? const <WeekNote>[])
        '${n.memberId}@${dateOnly(n.weekStart)}': n.note,
    };
    final positionNames = {for (final p in positions) p.id: p.name};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Okres i edycja grafiku nad tabelą; pracownicy widzą zmiany dopiero po „Zapisz”.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 32, 16),
          child: Row(
            children: [
              StepSwitcher(
                label: periodKind == 'month' ? Fmt.monthYear(period.from) : weekLabel(period.from, period.to),
                labelWidth: periodKind == 'week' ? 132 : 170,
                previousTooltip: periodKind == 'month' ? 'Poprzedni miesiąc' : 'Poprzedni okres',
                nextTooltip: periodKind == 'month' ? 'Następny miesiąc' : 'Następny okres',
                onPrevious: () => setState(() => _offset--),
                onNext: () => setState(() => _offset++),
                resetTooltip: 'Wróć do bieżącego okresu',
                onReset: _offset == 0 ? null : () => setState(() => _offset = 0),
              ),
              const Spacer(),
              if (canPlan) ...[
                if (editing) ...[
                  TextButton(
                    onPressed: _saving ? null : () => _cancelEdit(restaurantId, draft),
                    style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                    child: const Text('Anuluj'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saving || draft.changes.isEmpty ? null : () => _saveSchedule(restaurantId, draft),
                    icon: const Glyph(AppIcons.check, size: 18),
                    label: Text(draft.changes.isEmpty ? 'Zapisz' : 'Zapisz (${draft.changes.length})'),
                  ),
                ] else
                  FilledButton.icon(
                    onPressed: () => ref.read(scheduleDraftProvider(restaurantId).notifier).start(me ?? ''),
                    icon: const Glyph(AppIcons.pencil, size: 18),
                    label: const Text('Edytuj'),
                  ),
              ],
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 32, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (editing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _Banner(
                      icon: AppIcons.pencil,
                      color: AppColors.accent,
                      text: draft.changes.isEmpty
                          ? 'Edycja grafiku. Kliknij dzień, żeby przyjąć, zmienić albo odrzucić zgłoszenie, wpisać godziny '
                              'albo dać wolne. Pracownicy zobaczą zmiany po „Zapisz”.'
                          : 'Niezapisane zmiany: ${draft.changes.length} (zaznaczone kropką). '
                              'Pracownicy zobaczą je po „Zapisz”.',
                    ),
                  )
                else if (waiting > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _Banner(
                      icon: AppIcons.clock,
                      text: waiting == 1
                          ? 'Jedno zgłoszenie czeka na decyzję.${canPlan ? ' Kliknij „Edytuj”, żeby je przyjąć, zmienić albo odrzucić.' : ''}'
                          : 'Zgłoszenia czekające na decyzję: $waiting.${canPlan ? ' Kliknij „Edytuj”, żeby je przyjąć, zmienić albo odrzucić.' : ''}',
                    ),
                  ),
                if (members.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      'Nikogo nie znaleziono. Zmień wyszukiwanie albo filtry po lewej.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  )
                else
                  for (final (i, week) in weeks.indexed) ...[
                    if (weeks.length > 1)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 20, bottom: 8, left: 4),
                        child: Text(
                          'Tydzień ${weekLabel(week, DateTime(week.year, week.month, week.day + 6))}',
                          style: text.titleSmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                      ),
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: _WeekGrid(
                        week: week,
                        members: members,
                        planned: planned,
                        inPeriod: inPeriod,
                        changed: changes.keys.toSet(),
                        positionNames: positionNames,
                        notes: {
                          for (final m in members) m.id: ?notes['${m.id}@$week'],
                        },
                        onOpenMember: canStaff ? (m) => _openMember(restaurantId, m) : null,
                        onHours: editing
                            ? (m, day, _) => _hours(
                                restaurantId,
                                m,
                                day,
                                savedByKey[scheduleKey(m.id, day)],
                                changes[scheduleKey(m.id, day)],
                                [
                                  for (final id in m.positionIds)
                                    for (final p in positions)
                                      if (p.id == id) p,
                                ],
                              )
                            : null,
                      ),
                    ),
                  ],
                const SizedBox(height: 8),
                const _Legend(),
                const SizedBox(height: 8),
                Text(
                  'Pracownicy zgłaszają w aplikacji Table for employees, od której do której mogą pracować '
                  '(okres grafiku: $unit, zmiana i termin zgłaszania w „Ustawieniach lokalu”). Dzień bez zgłoszenia '
                  'to „Niedostępny”: takiej osobie nie da się wpisać zmiany, ale można wysłać propozycję, którą przyjmie '
                  'albo odrzuci w aplikacji. Kliknij „Edytuj”, żeby przyjąć zgłoszenie (także ze zmienionymi godzinami '
                  'i stanowiskiem na ten dzień), odrzucić je, wysłać propozycję albo dać wolne. Zmiany trafiają do '
                  'pracowników dopiero po „Zapisz”.',
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.color = _pending});

  final AppIconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Glyph(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Kolor zgłoszenia, które czeka na decyzję przełożonego.
const _pending = Color(0xFFE08A1E);

/// Kolor wolnego dnia.
const _off = Color(0xFF3B82F6);

/// Kolor propozycji przełożonego, na którą czeka odpowiedź pracownika.
const _proposed = Color(0xFF8B5CF6);

Color _statusColor(PlannedShiftStatus s) => switch (s) {
  PlannedShiftStatus.accepted => AppColors.accent,
  PlannedShiftStatus.pending => _pending,
  PlannedShiftStatus.rejected => AppColors.error,
  PlannedShiftStatus.off => _off,
  PlannedShiftStatus.proposed => _proposed,
  PlannedShiftStatus.unavailable => AppColors.textMuted,
};

AppIconData _statusIcon(PlannedShiftStatus s) => switch (s) {
  PlannedShiftStatus.accepted => AppIcons.checkCircle,
  PlannedShiftStatus.pending => AppIcons.clock,
  PlannedShiftStatus.rejected => AppIcons.prohibit,
  PlannedShiftStatus.off => AppIcons.sun,
  PlannedShiftStatus.proposed => AppIcons.send,
  PlannedShiftStatus.unavailable => AppIcons.userMinus,
};

/// Minuty między „HH:MM” a „HH:MM” (koniec może być 24:00). Koniec wcześniej niż początek: następnego dnia
/// (np. 18:00–02:00 to 8 godzin).
int _minutesBetween(String starts, String ends) {
  int m(String hm) {
    final p = hm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  if (starts.isEmpty || ends.isEmpty) return 0;
  final d = m(ends) - m(starts);
  if (d == 0) return 0;
  return d > 0 ? d : d + 24 * 60;
}

/// Czas jako „37:30 h”.
String _hoursLabel(int minutes) => '${minutes ~/ 60}:${_two(minutes % 60)} h';

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted);
    return Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        for (final s in PlannedShiftStatus.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Glyph(_statusIcon(s), size: 14, color: _statusColor(s)),
              const SizedBox(width: 6),
              Text(s.label, style: text),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Panel po lewej i tabela zespołu
// ---------------------------------------------------------------

/// Pole wyboru w grupie filtrów: napis, liczba osób, zaznaczenie i kropka koloru (np. „Na zmianie”).
typedef _FilterOption = ({String label, int count, bool checked, ValueChanged<bool> onChanged, Color? dot});

/// Grupa filtrów w panelu po lewej: nagłówek ze strzałką (zwija grupę) i pola wyboru z liczbą osób.
class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.title,
    required this.open,
    required this.onToggle,
    required this.options,
    this.first = false,
  });

  final String title;
  final bool open;
  final VoidCallback onToggle;
  final List<_FilterOption> options;

  /// Pierwsza grupa nie ma kreski nad sobą.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!first) Divider(height: 1, color: AppColors.ring),
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(child: Text(title, style: text.labelLarge)),
                Glyph(open ? AppIcons.caretUp : AppIcons.caretDown, size: 14, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
        if (open) ...[
          for (final o in options) _FilterRow(option: o),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Jedno pole wyboru filtra. Bez nikogo w tej grupie przygaszone i nieklikalne (chyba że zaznaczone).
class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.option});

  final _FilterOption option;

  @override
  Widget build(BuildContext context) {
    final o = option;
    final enabled = o.count > 0 || o.checked;
    return InkWell(
      onTap: enabled ? () => o.onChanged(!o.checked) : null,
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: o.checked,
                onChanged: enabled ? (v) => o.onChanged(v ?? false) : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                activeColor: AppColors.accentFill,
                checkColor: AppColors.onAccent,
                side: WidgetStateBorderSide.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? BorderSide.none
                      : BorderSide(color: enabled ? AppColors.ringStrong : AppColors.ring, width: 1.5),
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (o.dot != null) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: enabled ? o.dot : AppColors.textDisabled, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
            ],
            Expanded(
              child: Text(
                '${o.label} (${o.count})',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: enabled ? AppColors.text : AppColors.textDisabled,
                  fontFeatures: _tabular,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nagłówek kolumny tabeli: z [width] stała szerokość, bez niej część wolnego miejsca według [flex].
Widget _head(BuildContext context, String label, int flex, {TextAlign align = TextAlign.left, double? width}) {
  final child = Text(
    label,
    textAlign: align,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.text, fontWeight: FontWeight.w600),
  );
  return width == null ? Expanded(flex: flex, child: child) : SizedBox(width: width, child: child);
}

/// Stałe szerokości wąskich kolumn tabeli zespołu; imię i stanowisko dzielą resztę.
const _phoneWidth = 136.0;
const _nowWidth = 96.0;
const _weekWidth = 88.0;
const _codeWidth = 60.0;

/// Zespół jako tabela jak „People” w UniFi: imię z odznakami (ALL, Ty, Nieaktywny), telefon, stanowisko, stan
/// teraz, godziny w tym tygodniu i kod. Kliknięcie wiersza otwiera szczegóły pracownika.
class _TeamTable extends StatelessWidget {
  const _TeamTable({
    required this.members,
    required this.positions,
    required this.codes,
    required this.showCodes,
    required this.working,
    required this.shifts,
    required this.me,
    required this.onOpen,
  });

  final List<StaffMember> members;
  final List<StaffPosition> positions;
  final Map<String, String> codes;

  /// Kody pracowników widać tylko z uprawnieniem „Kody pracowników”.
  final bool showCodes;

  /// Kto jest teraz w pracy i od kiedy.
  final Map<String, DateTime> working;

  /// Zmiany z bieżącego tygodnia, do godzin w tabeli.
  final List<StaffShift> shifts;

  /// Zalogowany pracownik (odznaka „Ty”).
  final String? me;
  final ValueChanged<StaffMember>? onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final byId = {for (final p in positions) p.id: p};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _head(context, 'Imię i nazwisko', 3),
                _head(context, 'Telefon', 0, width: _phoneWidth),
                _head(context, 'Stanowisko', 2),
                _head(context, 'Teraz', 0, width: _nowWidth),
                _head(context, 'Ten tydzień', 0, align: TextAlign.right, width: _weekWidth),
                if (showCodes) _head(context, 'Kod', 0, align: TextAlign.right, width: _codeWidth),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.ring),
        Expanded(
          child: members.isEmpty
              ? Center(
                  child: Text(
                    'Nikogo nie znaleziono. Zmień wyszukiwanie albo filtry po lewej.',
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                )
              : ListView.separated(
                  itemCount: members.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.ring),
                  itemBuilder: (context, i) {
                    final m = members[i];
                    return _TeamRow(
                      member: m,
                      position: byId[m.positionId]?.name ?? m.position,
                      extraPositions: m.positionIds.where((id) => id != m.positionId).length,
                      isAll: m.positionIds.any((id) => byId[id]?.isAll ?? false),
                      isMe: m.id == me,
                      code: codes[m.id],
                      showCode: showCodes,
                      workingSince: working[m.id],
                      week: shifts.where((s) => s.memberId == m.id).fold(Duration.zero, (sum, s) => sum + s.duration),
                      onTap: onOpen == null ? null : () => onOpen!(m),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.member,
    required this.position,
    required this.extraPositions,
    required this.isAll,
    required this.isMe,
    required this.code,
    required this.showCode,
    required this.workingSince,
    required this.week,
    required this.onTap,
  });

  final StaffMember member;
  final String? position;
  final int extraPositions;
  final bool isAll;
  final bool isMe;
  final String? code;
  final bool showCode;
  final DateTime? workingSince;
  final Duration week;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final m = member;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                // W wąskiej kolumnie (najmniejsze okno) odznaki ustępują miejsca imieniu.
                child: LayoutBuilder(
                  builder: (context, box) {
                    final badges = box.maxWidth >= 260;
                    return Row(
                      children: [
                        _Avatar(
                          name: m.name,
                          color: staffColors[m.color % staffColors.length],
                          size: 30,
                          dimmed: !m.active,
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            m.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                              color: m.active ? AppColors.text : AppColors.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (badges) ...[
                          if (isAll) ...[const SizedBox(width: 8), const _Badge('ALL')],
                          if (isMe) ...[const SizedBox(width: 6), const _Badge('Ty', accent: true)],
                          if (!m.active) ...[const SizedBox(width: 6), const _Badge('Nieaktywny')],
                        ],
                        const SizedBox(width: 12),
                      ],
                    );
                  },
                ),
              ),
              SizedBox(
                width: _phoneWidth,
                child: Text(
                  m.phone == null ? '—' : Fmt.phone(m.phone),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: position == null
                        ? Text('—', style: muted)
                        : _PositionChip(name: position!, extra: extraPositions),
                  ),
                ),
              ),
              // Na zmianie: zielona kropka i godzina początku, jak „Na zmianie” w filtrach.
              SizedBox(
                width: _nowWidth,
                child: workingSince == null
                    ? Text('—', style: muted)
                    : Tooltip(
                        message: 'Na zmianie od ${_hm(workingSince!)}',
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'od ${_hm(workingSince!)}',
                              style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                            ),
                          ],
                        ),
                      ),
              ),
              SizedBox(
                width: _weekWidth,
                child: Text(
                  '${hoursText(week)} h',
                  textAlign: TextAlign.right,
                  style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                ),
              ),
              if (showCode)
                SizedBox(
                  width: _codeWidth,
                  child: Text(
                    code ?? '…',
                    textAlign: TextAlign.right,
                    style: text.labelLarge?.copyWith(fontFeatures: _tabular, letterSpacing: 2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mała odznaka przy imieniu, np. „ALL” albo „Ty”.
class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.accent = false});

  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent ? AppColors.accentTint : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accent ? AppColors.accent : AppColors.textMuted,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Stanowisko w tabeli jako szary znaczek z ikoną; dodatkowe stanowiska jako „+1”.
class _PositionChip extends StatelessWidget {
  const _PositionChip({required this.name, this.extra = 0});

  final String name;
  final int extra;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(AppIcons.identification, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              extra > 0 ? '$name +$extra' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.color, this.size = 40, this.dimmed = false});

  final String name;
  final Color color;
  final double size;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = dimmed ? AppColors.textMuted : color;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w600,
          color: c,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Szczegóły pracownika: dane, login do stanowiska i statystyki
// ---------------------------------------------------------------

class _MemberDetailsDialog extends ConsumerStatefulWidget {
  const _MemberDetailsDialog({required this.restaurantId, required this.member});

  final String restaurantId;
  final StaffMember member;

  @override
  ConsumerState<_MemberDetailsDialog> createState() => _MemberDetailsDialogState();
}

class _MemberDetailsDialogState extends ConsumerState<_MemberDetailsDialog> {
  /// Miesiąc statystyk (pierwszy dzień), od 1. do ostatniego dnia.
  DateTime _month = monthStart(DateTime.now());

  Future<void> _edit(StaffMember member) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _MemberDialog(restaurantId: widget.restaurantId, member: member),
    );
    if (result == null) return;
    ref.invalidate(staffProvider(widget.restaurantId));
    // Usunięty pracownik: zamykamy też szczegóły.
    if (result == _MemberDialog.deleted && mounted) Navigator.pop(context);
  }

  Future<void> _changeCode(StaffMember member) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CodeEditDialog(member: member),
    );
    if (saved == true) ref.invalidate(staffCodesProvider(widget.restaurantId));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final members = ref.watch(staffProvider(widget.restaurantId)).value;
    final member = members?.where((m) => m.id == widget.member.id).firstOrNull ?? widget.member;
    final permissions = ref.watch(memberPermissionsProvider);
    final canLogins = permissions.contains('staff_logins');
    final canStats = permissions.contains('staff');
    final codes = canLogins ? ref.watch(staffCodesProvider(widget.restaurantId)).value : null;
    final code = codes?[member.id];
    final positions = ref.watch(positionsProvider(widget.restaurantId)).value ?? const <StaffPosition>[];
    final position = positions.where((p) => p.id == member.positionId).firstOrNull;
    final statsAsync = canStats
        ? ref.watch(memberStatsProvider((memberId: member.id, month: _month)))
        : const AsyncValue<MemberStats>.loading();
    final stats = statsAsync.value;
    final color = staffColors[member.color % staffColors.length];

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _Avatar(name: member.name, color: color, size: 56, dimmed: !member.active),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(member.name, style: text.headlineSmall),
                        const SizedBox(height: 2),
                        Text(
                          [
                            ?(position?.name ?? member.position),
                            ?member.phone,
                            if (!member.active) 'nieaktywny',
                          ].join(' · '),
                          style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                      ],
                    ),
                  ),
                  if (canStats)
                  OutlinedButton.icon(
                    onPressed: () => _edit(member),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                    icon: const Glyph(AppIcons.pencil, size: 16),
                    label: const Text('Edytuj'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Zamknij',
                    onPressed: () => Navigator.pop(context),
                    icon: const Glyph(AppIcons.close, size: 18),
                  ),
                ],
              ),
              if (position != null && position.permissions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in position.permissions) Tag(p.label.toUpperCase(), color: AppColors.textMuted),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              // Kod do głównego stanowiska: widać go stale (uprawnienie „Kody pracowników”).
              if (canLogins)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Glyph(AppIcons.password, size: 22, color: AppColors.accent),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: 'Kod pracownika: ', style: TextStyle(color: AppColors.textMuted)),
                                TextSpan(
                                  text: code ?? '…',
                                  style: const TextStyle(fontSize: 26, letterSpacing: 4, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            style: text.titleMedium?.copyWith(fontFeatures: _tabular),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tym kodem pracownik loguje się na głównym stanowisku. Widzi go też w aplikacji.',
                            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: () => _changeCode(member),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                      child: const Text('Zmień kod'),
                    ),
                  ],
                ),
              ),
              if (canStats) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(child: Text('Statystyki', style: text.titleLarge)),
                  MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
                ],
              ),
              const SizedBox(height: 14),
              if (statsAsync.hasError)
                Text(errorText(statsAsync.error!), style: text.bodyMedium?.copyWith(color: AppColors.error))
              else if (stats == null)
                const SizedBox(height: 160, child: LoadingView())
              else ...[
                LayoutBuilder(
                  builder: (context, box) {
                    const gap = 12.0;
                    final width = (box.maxWidth - gap * 2) / 3;
                    final tiles = [
                      ('Czas pracy', '${hoursText(Duration(seconds: stats.seconds))} h',
                          '${stats.shifts} zmian${stats.openSince == null ? '' : ' · w pracy od ${_hm(stats.openSince!)}'}'),
                      // Zarobek w miesiącu: przepracowane godziny × stawka.
                      (
                        'Zarobek brutto',
                        stats.earningsGrosze == null ? '—' : Fmt.price(stats.earningsGrosze!),
                        stats.rateGrosze == null
                            ? 'ustaw stawkę w „Edytuj”'
                            : 'netto ${Fmt.price(Payroll.monthlyNet(stats.contract, stats.earningsGrosze!))} · '
                                  '${Fmt.price(stats.rateGrosze!)}/h',
                      ),
                      ('Sprzedaż', Fmt.price(stats.revenueGrosze), '${stats.ordersClosed} zamkniętych rachunków'),
                      ('Średni rachunek', stats.ordersClosed == 0 ? '—' : Fmt.price(stats.averageOrder), 'na zamknięty rachunek'),
                      ('Otwarte stoliki', '${stats.ordersOpened}', 'rachunki otwarte przez pracownika'),
                      ('Nabite pozycje', '${stats.items}', 'dania i napoje'),
                    ];
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final (label, value, hint) in tiles)
                          SizedBox(width: width, child: _StatTile(label: label, value: value, hint: hint)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Najczęściej nabijane', style: text.titleSmall),
                          const SizedBox(height: 6),
                          if (stats.topItems.isEmpty)
                            Text('Brak zamówień w tym okresie.',
                                style: text.bodySmall?.copyWith(color: AppColors.textMuted))
                          else
                            for (final (name, quantity) in stats.topItems)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                    Text('$quantity×', style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Grafik', style: text.titleSmall),
                          const SizedBox(height: 6),
                          Text(
                            stats.planned == 0
                                ? 'Brak przyjętych godzin od dziś.'
                                : 'Przyjęte dni od dziś: ${stats.planned}.',
                            style: text.bodyMedium,
                          ),
                          if (stats.lastShift != null)
                            Text(
                              'Ostatnia zmiana: ${Fmt.dayShort(stats.lastShift!)}, ${_hm(stats.lastShift!)}',
                              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.hint});

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ring),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(value, style: text.headlineSmall?.copyWith(fontFeatures: _tabular)),
          const SizedBox(height: 2),
          Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Kod nowego pracownika, do przekazania mu od razu.
class CodeDialog extends StatelessWidget {
  const CodeDialog({super.key, required this.name, required this.code});

  final String name;
  final String code;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Kod dla: $name'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                code,
                style: text.displaySmall?.copyWith(
                  fontFeatures: _tabular,
                  letterSpacing: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Przekaż go pracownikowi. Tym kodem loguje się na głównym stanowisku. '
              'Kod widać też w szczegółach pracownika i w jego aplikacji.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Gotowe')),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Grafik: dyspozycyjność i propozycje godzin
// ---------------------------------------------------------------

class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.week,
    required this.members,
    required this.planned,
    required this.inPeriod,
    required this.changed,
    required this.positionNames,
    required this.onOpenMember,
    required this.onHours,
    this.notes = const {},
  });

  final DateTime week;
  final List<StaffMember> members;
  final List<PlannedShift> planned;

  /// Uwagi pracowników na ten tydzień według numeru pracownika.
  final Map<String, String> notes;

  /// Dni spoza okresu (np. koniec poprzedniego miesiąca) są wyszarzone i nieklikalne.
  final bool Function(DateTime day) inPeriod;

  /// Dni z niezapisaną zmianą (klucze [scheduleKey]).
  final Set<String> changed;

  /// Aktualne nazwy stanowisk po identyfikatorze. Po zmianie nazwy stanowiska
  /// lista pokazuje nową, a nie tę zapisaną przy pracowniku.
  final Map<String, String> positionNames;
  final ValueChanged<StaffMember>? onOpenMember;

  /// Kliknięcie dnia. Null poza trybem edycji: grafik tylko do odczytu.
  final void Function(StaffMember member, DateTime day, PlannedShift? existing)? onHours;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final days = [for (var i = 0; i < 7; i++) DateTime(week.year, week.month, week.day + i)];
    final today = dateOnly(DateTime.now());
    final byId = {for (final m in members) m.id: m};

    // Przyjęte zmiany w dniu (tylko pracownicy z listy).
    List<PlannedShift> acceptedOn(DateTime day) => [
      for (final p in planned)
        if (dateOnly(p.day) == day && p.status == PlannedShiftStatus.accepted && byId.containsKey(p.memberId)) p,
    ];
    // Godziny pracownika w tym tygodniu (przyjęte, w okresie).
    int weekMinutes(String memberId) => [
      for (final p in planned)
        if (p.memberId == memberId &&
            p.status == PlannedShiftStatus.accepted &&
            !dateOnly(p.day).isBefore(days.first) &&
            !dateOnly(p.day).isAfter(days.last) &&
            inPeriod(dateOnly(p.day)))
          _minutesBetween(p.starts, p.ends),
    ].fold(0, (a, b) => a + b);
    // Ile osób na jakim stanowisku w dniu: stanowisko z grafiku albo główne pracownika.
    Map<String, int> positionsOn(DateTime day) {
      final counts = <String, int>{};
      for (final p in acceptedOn(day)) {
        final name = positionNames[p.positionId ?? byId[p.memberId]?.positionId] ?? byId[p.memberId]?.position ?? 'Bez stanowiska';
        counts[name] = (counts[name] ?? 0) + 1;
      }
      return counts;
    }

    Widget footerLabel(String label) => SizedBox(
      width: 220,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(label, style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
      ),
    );

    Widget headerCell(int i) {
      final isToday = days[i] == today;
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.ring)),
            color: isToday ? AppColors.accentTint : null,
          ),
          foregroundDecoration: inPeriod(days[i])
              ? null
              : BoxDecoration(color: AppColors.surface.withValues(alpha: 0.6)),
          child: Column(
            children: [
              Text(_weekdayShort[i], style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
              Text(
                '${days[i].day}.${days[i].month.toString().padLeft(2, '0')}',
                style: text.titleSmall?.copyWith(
                  fontFeatures: _tabular,
                  color: isToday ? AppColors.accent : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 220,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Pracownik', style: text.labelMedium?.copyWith(color: AppColors.textMuted)),
              ),
            ),
            for (var i = 0; i < 7; i++) headerCell(i),
            SizedBox(
              width: 76,
              child: Text(
                'Tydzień',
                textAlign: TextAlign.center,
                style: text.labelMedium?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
        for (final m in members) ...[
          Divider(height: 1, color: AppColors.ring),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 220,
                  child: InkWell(
                    onTap: onOpenMember == null ? null : () => onOpenMember!(m),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: staffColors[m.color % staffColors.length],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  m.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.labelLarge?.copyWith(
                                    color: m.active ? AppColors.text : AppColors.textMuted,
                                  ),
                                ),
                                if (m.positionIds.isNotEmpty || m.position != null || !m.active)
                                  Text(
                                    [
                                      if (m.positionIds.isEmpty) ?m.position,
                                      for (final id in m.positionIds) ?positionNames[id],
                                      if (!m.active) 'nieaktywny',
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                                  ),
                              ],
                            ),
                          ),
                          // Uwaga pracownika na ten tydzień.
                          if (notes[m.id] case final note?)
                            Tooltip(
                              message: 'Uwaga na tydzień: $note',
                              child: const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Glyph(AppIcons.chatText, size: 16, color: _pending),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                for (final day in days)
                  Expanded(
                    child: _DayCell(
                      member: m,
                      entry: planned.where((p) => p.memberId == m.id && dateOnly(p.day) == day).firstOrNull,
                      isToday: day == today,
                      outside: !inPeriod(day),
                      changed: changed.contains(scheduleKey(m.id, day)),
                      positionName: () {
                        final e = planned.where((p) => p.memberId == m.id && dateOnly(p.day) == day).firstOrNull;
                        // Stanowisko pokazujemy tylko u osób z kilkoma stanowiskami.
                        return e?.positionId == null || m.positionIds.length < 2 ? null : positionNames[e!.positionId];
                      }(),
                      onTap: onHours == null || !inPeriod(day) ? null : (existing) => onHours!(m, day, existing),
                    ),
                  ),
                SizedBox(
                  width: 76,
                  child: Center(
                    child: Text(
                      weekMinutes(m.id) == 0 ? '—' : _hoursLabel(weekMinutes(m.id)),
                      style: text.labelLarge?.copyWith(
                        fontFeatures: _tabular,
                        color: weekMinutes(m.id) == 0 ? AppColors.textDisabled : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Divider(height: 1, color: AppColors.ring),
        Row(
          children: [
            footerLabel('Przyjętych osób'),
            for (final day in days)
              Expanded(
                child: Text(
                  inPeriod(day) ? '${acceptedOn(day).length}' : '',
                  textAlign: TextAlign.center,
                  style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                ),
              ),
            const SizedBox(width: 76),
          ],
        ),
        // Łączne godziny pracy w dniu i ile osób na jakim stanowisku.
        Row(
          children: [
            footerLabel('Godziny pracy'),
            for (final day in days)
              Expanded(
                child: Text(
                  inPeriod(day)
                      ? (() {
                          final minutes = acceptedOn(day).fold(0, (a, p) => a + _minutesBetween(p.starts, p.ends));
                          return minutes == 0 ? '—' : _hoursLabel(minutes);
                        })()
                      : '',
                  textAlign: TextAlign.center,
                  style: text.labelLarge?.copyWith(fontFeatures: _tabular, color: AppColors.textMuted),
                ),
              ),
            SizedBox(
              width: 76,
              child: Text(
                () {
                  final minutes = [for (final day in days) if (inPeriod(day)) ...acceptedOn(day)]
                      .fold(0, (a, p) => a + _minutesBetween(p.starts, p.ends));
                  return minutes == 0 ? '' : _hoursLabel(minutes);
                }(),
                textAlign: TextAlign.center,
                style: text.labelLarge?.copyWith(fontFeatures: _tabular),
              ),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            footerLabel('Na stanowiskach'),
            for (final day in days)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                  child: Column(
                    children: [
                      if (inPeriod(day))
                        for (final e in positionsOn(day).entries)
                          Text(
                            '${e.key} ${e.value}',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                          ),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 76),
          ],
        ),
      ],
    );
  }
}

/// Dzień pracownika w grafiku: zgłoszenie (pomarańczowe), przyjęte (w kolorze pracownika),
/// odrzucone (przekreślone) albo wolne (niebieskie).
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.member,
    required this.entry,
    required this.isToday,
    required this.outside,
    required this.changed,
    required this.onTap,
    this.positionName,
  });

  final StaffMember member;
  final PlannedShift? entry;
  final bool isToday;

  /// Stanowisko na ten dzień (u osób z kilkoma stanowiskami).
  final String? positionName;

  /// Dzień spoza okresu grafiku.
  final bool outside;

  /// Dzień ma niezapisaną zmianę.
  final bool changed;

  /// Null: grafik tylko do odczytu (poza trybem edycji).
  final ValueChanged<PlannedShift?>? onTap;

  @override
  Widget build(BuildContext context) {
    final color = staffColors[member.color % staffColors.length];
    final text = Theme.of(context).textTheme;
    final e = entry;
    final cell = Container(
      constraints: const BoxConstraints(minHeight: 64),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.ring)),
        color: isToday ? AppColors.accentTint.withValues(alpha: 0.18) : null,
      ),
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(e),
        hoverColor: AppColors.ring,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: e == null
              // Bez zgłoszenia pracownik jest niedostępny: można mu tylko wysłać propozycję.
              ? Center(
                  child: changed
                      ? Glyph(AppIcons.trash, size: 14, color: AppColors.textDisabled)
                      : outside
                      ? const SizedBox.shrink()
                      : Text('Niedostępny', style: text.labelSmall?.copyWith(color: AppColors.textDisabled)),
                )
              : Tooltip(
                  message: [
                    e.status.label,
                    ?positionName,
                    if (e.changed || (e.off && e.requestedStarts != null))
                      'Zgłoszone: ${e.requestedStarts}–${e.requestedEnds}',
                    if (e.note != null) 'Pracownik: ${e.note}',
                    if (e.answer != null) 'Odpowiedź: ${e.answer}',
                  ].join('\n'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: switch (e.status) {
                        PlannedShiftStatus.accepted => color.withValues(alpha: 0.9),
                        PlannedShiftStatus.pending => _pending.withValues(alpha: 0.16),
                        PlannedShiftStatus.rejected || PlannedShiftStatus.unavailable => Colors.transparent,
                        PlannedShiftStatus.off => _off.withValues(alpha: 0.14),
                        PlannedShiftStatus.proposed => _proposed.withValues(alpha: 0.14),
                      },
                      borderRadius: BorderRadius.circular(8),
                      border: switch (e.status) {
                        PlannedShiftStatus.accepted => null,
                        PlannedShiftStatus.pending => Border.all(color: _pending),
                        PlannedShiftStatus.rejected || PlannedShiftStatus.unavailable => Border.all(color: AppColors.ring),
                        PlannedShiftStatus.off => Border.all(color: _off.withValues(alpha: 0.6)),
                        PlannedShiftStatus.proposed => Border.all(color: _proposed.withValues(alpha: 0.7)),
                      },
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                        Glyph(
                          _statusIcon(e.status),
                          size: 13,
                          color: e.status == PlannedShiftStatus.accepted ? Colors.white : _statusColor(e.status),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            e.off
                                ? 'Wolne'
                                : e.status == PlannedShiftStatus.unavailable
                                ? 'Niedostępny'
                                : '${e.starts}–${e.ends}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelMedium?.copyWith(
                              fontFeatures: _tabular,
                              fontWeight: FontWeight.w600,
                              color: switch (e.status) {
                                PlannedShiftStatus.accepted => Colors.white,
                                PlannedShiftStatus.pending || PlannedShiftStatus.off || PlannedShiftStatus.proposed =>
                                  AppColors.text,
                                PlannedShiftStatus.rejected || PlannedShiftStatus.unavailable => AppColors.textMuted,
                              },
                              decoration: e.status == PlannedShiftStatus.rejected ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                          ],
                        ),
                        if (positionName != null)
                          Text(
                            positionName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelSmall?.copyWith(
                              color: e.status == PlannedShiftStatus.accepted ? Colors.white70 : AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
    if (outside) return Opacity(opacity: 0.35, child: cell);
    if (!changed) return cell;
    // Niezapisana zmiana: kropka w rogu dnia.
    return Stack(
      children: [
        Positioned.fill(child: cell),
        Positioned(
          top: 5,
          right: 5,
          child: IgnorePointer(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Wynik okna dnia: zmiana do zapisania albo cofnięcie niezapisanej zmiany.
typedef _HoursResult = ({ScheduleChange? change, bool undo});

/// Decyzja o zgłoszeniu pracownika (przyjmij, przyjmij ze zmienionymi godzinami, odrzuć, wolne)
/// albo godziny wpisane przez przełożonego na pusty dzień, albo wolne. Nic nie zapisuje: zmiana czeka
/// w trybie edycji na „Zapisz”.
class _HoursDialog extends StatefulWidget {
  const _HoursDialog({
    required this.member,
    required this.day,
    required this.existing,
    required this.shown,
    required this.staged,
    this.positions = const [],
  });

  final StaffMember member;
  final DateTime day;

  /// Stanowiska pracownika (do wyboru na ten dzień).
  final List<StaffPosition> positions;

  /// Wpis zapisany w bazie.
  final PlannedShift? existing;

  /// Jak dzień wygląda teraz, z niezapisaną zmianą.
  final PlannedShift? shown;

  /// Dzień ma niezapisaną zmianę, którą można cofnąć.
  final bool staged;

  @override
  State<_HoursDialog> createState() => _HoursDialogState();
}

class _HoursDialogState extends State<_HoursDialog> {
  // Wolny dzień nie ma godzin: podpowiadamy zgłoszone przez pracownika albo 10–18.
  late TimeOfDay _starts = _parse(_initial(widget.shown?.starts, widget.existing?.requestedStarts, '10:00'));
  late TimeOfDay _ends = _parse(_initial(widget.shown?.ends, widget.existing?.requestedEnds, '18:00'));
  late final _answer = TextEditingController(text: widget.shown?.answer ?? '');
  late String? _positionId = widget.shown?.positionId ?? widget.member.positionId;

  /// Pracownik niedostępny (bez zgłoszenia, zgłosił, że nie może, albo czeka propozycja): tylko propozycja.
  bool get _onlyProposal {
    final e = widget.existing;
    return e == null || e.status == PlannedShiftStatus.unavailable || e.status == PlannedShiftStatus.proposed;
  }

  static TimeOfDay _parse(String hm) {
    final p = hm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static String _fmt(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  static String _initial(String? hours, String? requested, String fallback) =>
      (hours?.isNotEmpty ?? false) ? hours! : (requested ?? fallback);

  void _done(ScheduleAction action, {String? starts, String? ends}) => Navigator.pop<_HoursResult>(context, (
    change: ScheduleChange(
      action,
      memberId: widget.member.id,
      day: widget.day,
      id: widget.existing?.id,
      starts: starts,
      ends: ends,
      answer: _answer.text,
      positionId: action == ScheduleAction.accept || action == ScheduleAction.add || action == ScheduleAction.propose
          ? _positionId
          : null,
    ),
    undo: false,
  ));

  /// Koniec wcześniej niż początek to godziny przez północ (do następnego dnia); równe nie mają sensu.
  bool get _validTimes => _ends.hour * 60 + _ends.minute != _starts.hour * 60 + _starts.minute;

  bool get _overnight => _ends.hour * 60 + _ends.minute < _starts.hour * 60 + _starts.minute;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final picked = await pickTime(
      context,
      initial: start ? _starts : _ends,
      allowEndOfDay: !start,
      title: start ? 'Od' : 'Do',
    );
    if (picked != null) setState(() => start ? _starts = picked : _ends = picked);
  }

  void _accept() {
    if (!_validTimes) {
      showMessage(context, 'Początek i koniec nie mogą być takie same.');
      return;
    }
    _done(
      _onlyProposal ? ScheduleAction.propose : ScheduleAction.accept,
      starts: _fmt(_starts),
      ends: _fmt(_ends),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final existing = widget.existing;
    final shown = widget.shown;
    final changedHours = existing?.requestedStarts != null &&
        (existing!.requestedStarts != _fmt(_starts) || existing.requestedEnds != _fmt(_ends));
    Widget timeButton(TimeOfDay t, bool start) => OutlinedButton(
      onPressed: () => _pick(start),
      style: OutlinedButton.styleFrom(minimumSize: const Size(96, 44)),
      child: Text(_fmt(t), style: const TextStyle(fontFeatures: _tabular, fontSize: 16)),
    );

    return AlertDialog(
      title: Text(widget.member.name),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              Fmt.capitalize(Fmt.dayLong(widget.day)),
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            if (shown != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusColor(shown.status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Glyph(_statusIcon(shown.status), size: 18, color: _statusColor(shown.status)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            switch (shown.status) {
                              PlannedShiftStatus.unavailable => 'Pracownik zgłosił, że nie może pracować',
                              PlannedShiftStatus.proposed =>
                                'Propozycja ${shown.starts}–${shown.ends}: czeka na odpowiedź pracownika',
                              _ when shown.requestedStarts == null => shown.off
                                  ? 'Wolne (dał przełożony)'
                                  : '${shown.status.label}: ${shown.starts}–${shown.ends} (wpisane przez przełożonego)',
                              _ => 'Pracownik zgłosił ${shown.requestedStarts}–${shown.requestedEnds}',
                            },
                            style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                          ),
                          if (shown.requestedStarts != null)
                            Text(
                              shown.status == PlannedShiftStatus.accepted
                                  ? 'Przyjęte: ${shown.starts}–${shown.ends}'
                                  : shown.status.label,
                              style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                            ),
                          if (shown.note != null)
                            Text('„${shown.note}”', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                          if (widget.staged)
                            Text(
                              'Niezapisana zmiana. Pracownik zobaczy ją po „Zapisz”.',
                              style: text.bodySmall?.copyWith(color: AppColors.accent),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                widget.staged
                    ? 'Wpis zostanie usunięty po „Zapisz”.'
                    : 'Pracownik jest niedostępny: nie zgłosił dyspozycyjności na ten dzień. Możesz wysłać mu propozycję '
                        'godzin (przyjmie ją albo odrzuci w aplikacji) albo dać wolne.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            const SizedBox(height: 16),
            Text(
              _onlyProposal
                  ? 'Proponowane godziny'
                  : shown?.off ?? false
                  ? 'Godziny, jeśli jednak ma pracować'
                  : 'Godziny do przyjęcia (możesz je zmienić)',
              style: text.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                timeButton(_starts, true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('–', style: text.titleMedium),
                ),
                timeButton(_ends, false),
                if (_overnight) ...[
                  const SizedBox(width: 10),
                  Text('następnego dnia', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                ],
                if (changedHours) ...[
                  const SizedBox(width: 12),
                  const Flexible(child: Tag('ZMIENIONE', color: _pending)),
                ],
              ],
            ),
            // Dostawca: auto na ten dzień (zapisuje się od razu).
            if (widget.positions.any((p) => p.permissions.contains(StaffPermission.deliveries))) ...[
              const SizedBox(height: 12),
              VehicleDayPicker(memberId: widget.member.id, day: widget.day),
            ],
            // Stanowisko na ten dzień: u osób z kilkoma stanowiskami do wyboru.
            if (widget.positions.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: widget.positions.any((p) => p.id == _positionId) ? _positionId : widget.positions.first.id,
                decoration: const InputDecoration(labelText: 'Stanowisko tego dnia'),
                icon: const Glyph(AppIcons.caretDown, size: 16),
                items: [for (final p in widget.positions) DropdownMenuItem(value: p.id, child: Text(p.name))],
                onChanged: (v) => setState(() => _positionId = v),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _answer,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Wiadomość dla pracownika (opcjonalnie)',
                hintText: 'Na przykład: potrzebuję Cię od 12',
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.staged)
          TextButton(
            onPressed: () => Navigator.pop<_HoursResult>(context, (change: null, undo: true)),
            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
            child: const Text('Cofnij zmianę'),
          ),
        if (existing != null && shown != null)
          TextButton(
            onPressed: () => _done(ScheduleAction.delete),
            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
            child: const Text('Usuń'),
          ),
        if (existing != null &&
            !existing.off &&
            !_onlyProposal &&
            shown?.status != PlannedShiftStatus.rejected)
          TextButton(
            onPressed: () => _done(ScheduleAction.reject),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Odrzuć'),
          ),
        if (shown == null || !shown.off)
          TextButton.icon(
            onPressed: () => _done(ScheduleAction.off),
            style: TextButton.styleFrom(foregroundColor: _off),
            icon: const Glyph(AppIcons.sun, size: 16, color: _off),
            label: const Text('Wolne'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Zamknij'),
        ),
        FilledButton(
          onPressed: _accept,
          child: Text(
            _onlyProposal
                ? (existing?.status == PlannedShiftStatus.proposed ? 'Zmień propozycję' : 'Wyślij propozycję')
                : existing!.off
                ? 'Dodaj godziny'
                : (changedHours ? 'Przyjmij zmienione' : 'Przyjmij'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Dane pracownika
// ---------------------------------------------------------------

/// Dodanie albo edycja pracownika. Zwraca numer pracownika po zapisie
/// albo [deleted] po usunięciu.
class _MemberDialog extends ConsumerStatefulWidget {
  const _MemberDialog({required this.restaurantId, this.member});

  static const deleted = 'usunięty';

  final String restaurantId;
  final StaffMember? member;

  @override
  ConsumerState<_MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends ConsumerState<_MemberDialog> {
  late final _firstName = TextEditingController(text: widget.member?.firstName ?? '');
  late final _lastName = TextEditingController(text: widget.member?.lastName ?? '');
  late final _phone = TextEditingController(text: widget.member?.phone ?? '');
  late String? _positionId = widget.member?.positionId;

  /// Dodatkowe stanowiska (np. kelner, który bywa też barmanem).
  late final Set<String> _extraPositions = {...?widget.member?.extraPositionIds};
  late int _color = widget.member?.color ?? 0;
  late bool _active = widget.member?.active ?? true;
  /// Stawka brutto i netto za godzinę: wpisanie jednej liczy drugą według rodzaju umowy.
  final _gross = TextEditingController();
  final _net = TextEditingController();
  Contract _contract = Contract.zlecenie;

  /// Stawka z bazy, żeby nie zapisywać jej bez zmiany. Null: jeszcze się wczytuje albo jej nie ma.
  StaffRate? _savedRate;
  bool _rateLoaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final id = widget.member?.id;
    if (id == null) {
      _rateLoaded = true;
      return;
    }
    ref.read(staffRatesProvider(widget.restaurantId).future).then((rates) {
      if (!mounted) return;
      setState(() {
        _savedRate = rates[id];
        _rateLoaded = true;
        if (_savedRate case final rate?) {
          _contract = rate.contract;
          _gross.text = groszeToText(rate.grossGrosze);
          _net.text = groszeToText(rate.netGrosze);
        }
      });
    }).catchError((_) {
      if (mounted) setState(() => _rateLoaded = true);
    });
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _gross.dispose();
    _net.dispose();
    super.dispose();
  }

  /// Brutto wpisane: netto liczy się samo.
  void _grossChanged(String text) {
    final gross = parseGrosze(text);
    _net.text = text.trim().isEmpty || gross == null ? '' : groszeToText(Payroll.hourlyNet(_contract, gross));
  }

  /// Netto wpisane: brutto liczy się samo.
  void _netChanged(String text) {
    final net = parseGrosze(text);
    _gross.text = text.trim().isEmpty || net == null ? '' : groszeToText(Payroll.hourlyGross(_contract, net));
  }

  /// Zmiana umowy przelicza netto z brutto.
  void _contractChanged(Contract contract) {
    setState(() => _contract = contract);
    _grossChanged(_gross.text);
  }

  Future<void> _save(List<StaffPosition> positions) async {
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    StaffPosition? position;
    for (final p in positions) {
      if (p.id == _positionId) position = p;
    }
    final String? problem;
    if (_firstName.text.trim().isEmpty || _lastName.text.trim().isEmpty) {
      problem = 'Wpisz imię i nazwisko pracownika.';
    } else if (digits.length < 9 || digits.length > 15) {
      problem = 'Wpisz numer telefonu, co najmniej 9 cyfr.';
    } else if (position == null) {
      problem = 'Wybierz stanowisko.';
    } else if (_gross.text.trim().isNotEmpty && (parseGrosze(_gross.text) == null || parseGrosze(_gross.text)! > 100000)) {
      problem = 'Wpisz stawkę za godzinę, na przykład 30 albo 32,50.';
    } else {
      problem = null;
    }
    if (problem != null) {
      showMessage(context, problem);
      return;
    }

    setState(() => _busy = true);
    try {
      final id = await ref.read(repositoryProvider).saveStaffMember(
        restaurantId: widget.restaurantId,
        id: widget.member?.id,
        firstName: _firstName.text,
        lastName: _lastName.text,
        position: position!,
        phone: _phone.text,
        color: _color,
        active: _active,
      );
      final extras = [for (final p in positions) if (_extraPositions.contains(p.id) && p.id != position.id) p.id];
      if (widget.member != null || extras.isNotEmpty) {
        final before = {...?widget.member?.extraPositionIds};
        if (before.length != extras.length || !before.containsAll(extras)) {
          await ref.read(repositoryProvider).setMemberPositions(id, extras);
        }
      }
      final rate = _gross.text.trim().isEmpty ? null : parseGrosze(_gross.text);
      if (_rateLoaded && (rate != _savedRate?.grossGrosze || (rate != null && _contract != _savedRate?.contract))) {
        await ref.read(repositoryProvider).setStaffRate(id, rate, _contract);
        ref.invalidate(staffRatesProvider(widget.restaurantId));
        ref.invalidate(memberStatsProvider);
        ref.invalidate(teamStatsProvider);
      }
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Usunąć ${widget.member!.name}?',
      message: 'Razem z pracownikiem znikną jego login, grafik i wpisy w kalendarzu. '
          'Jeśli tylko odchodzi, możesz go oznaczyć jako nieaktywnego.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deleteStaffMember(widget.member!.id);
      if (mounted) Navigator.pop(context, _MemberDialog.deleted);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final canAssignAll = ref.watch(memberPermissionsProvider).contains('positions');
    final positions = [
      for (final p in ref.watch(positionsProvider(widget.restaurantId)).value ?? const <StaffPosition>[])
        // „ALL” (wszystkie uprawnienia) nadaje tylko osoba z uprawnieniem „Stanowiska”.
        if (!p.isAll || canAssignAll || p.id == widget.member?.positionId) p,
    ];
    final selected = positions.any((p) => p.id == _positionId) ? _positionId : null;

    return AlertDialog(
      title: Text(widget.member == null ? 'Nowy pracownik' : 'Pracownik'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _firstName,
                    autofocus: widget.member == null,
                    maxLength: 40,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Imię', counterText: ''),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _lastName,
                    maxLength: 60,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Nazwisko', counterText: ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                LengthLimitingTextInputFormatter(20),
              ],
              style: const TextStyle(fontFeatures: _tabular),
              decoration: const InputDecoration(
                labelText: 'Numer telefonu',
                helperText: 'Tym numerem pracownik loguje się w aplikacji Table for employees.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Stanowisko'),
              items: [
                for (final p in positions)
                  DropdownMenuItem(
                    value: p.id,
                    child: Row(
                      children: [
                        Text(p.name),
                        if (p.isSystem) ...[
                          const SizedBox(width: 8),
                          Glyph(AppIcons.lock, size: 12, color: AppColors.textDisabled),
                        ],
                      ],
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _positionId = v),
            ),
            if (positions.length > 1) ...[
              const SizedBox(height: 10),
              Text(
                'Dodatkowe stanowiska (uprawnienia z wszystkich, w grafiku wybór na dany dzień)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in positions)
                    if (p.id != _positionId)
                      FilterChip(
                        label: Text(p.name),
                        selected: _extraPositions.contains(p.id),
                        onSelected: (on) => setState(() => on ? _extraPositions.add(p.id) : _extraPositions.remove(p.id)),
                      ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<Contract>(
              initialValue: _contract,
              decoration: const InputDecoration(labelText: 'Umowa'),
              icon: const Glyph(AppIcons.caretDown, size: 16),
              items: [for (final c in Contract.values) DropdownMenuItem(value: c, child: Text(c.label))],
              onChanged: _rateLoaded ? (c) => _contractChanged(c!) : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _gross,
                    enabled: _rateLoaded,
                    onChanged: _grossChanged,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                    style: const TextStyle(fontFeatures: _tabular),
                    decoration: const InputDecoration(labelText: 'Stawka brutto', suffixText: 'zł/h'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _net,
                    enabled: _rateLoaded,
                    onChanged: _netChanged,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                    style: const TextStyle(fontFeatures: _tabular),
                    decoration: const InputDecoration(labelText: 'Stawka netto', suffixText: 'zł/h'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Kolor w grafiku', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < staffColors.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _color = i),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: staffColors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: i == _color ? AppColors.text : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (widget.member != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Text('Aktywny (może się logować)', style: text.bodyMedium)),
                  Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
                ],
              ),
            ] else ...[
            ],
          ],
        ),
      ),
      actions: [
        if (widget.member != null)
          TextButton(
            onPressed: _busy ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Usuń'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _save(positions),
          child: Text(widget.member == null ? 'Dodaj' : 'Zapisz'),
        ),
      ],
    );
  }
}

/// Nowe albo zmienione własne stanowisko (okno z nazwą i uprawnieniami).
Future<void> _editPosition(BuildContext context, WidgetRef ref, String restaurantId, [StaffPosition? position]) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _PositionEditor(restaurantId: restaurantId, position: position),
  );
  if (saved == true) {
    ref
      ..invalidate(positionsProvider(restaurantId))
      ..invalidate(staffProvider(restaurantId));
  }
}

Future<void> _deletePosition(BuildContext context, WidgetRef ref, String restaurantId, StaffPosition position) async {
  final ok = await confirm(
    context,
    title: 'Usunąć stanowisko „${position.name}”?',
    message: 'Stanowiska przypisanego do pracowników nie da się usunąć. Najpierw zmień im stanowisko.',
    action: 'Usuń',
    destructive: true,
  );
  if (!ok) return;
  try {
    await ref.read(repositoryProvider).deletePosition(position.id);
    ref.invalidate(positionsProvider(restaurantId));
  } catch (e) {
    if (!context.mounted) return;
    final raw = e.toString().toLowerCase();
    showMessage(
      context,
      raw.contains('foreign key') || raw.contains('violates')
          ? 'To stanowisko ma przypisanych pracowników. Najpierw zmień im stanowisko.'
          : errorText(e),
      tone: ToastTone.error,
    );
  }
}

/// Stanowiska jak „Roles” w UniFi: nazwa (systemowe z kłódką), uprawnienia i liczba pracowników.
/// Kliknięcie własnego stanowiska otwiera jego zmianę; systemowych nie da się zmienić ani usunąć.
class _PositionsTable extends ConsumerWidget {
  const _PositionsTable({
    required this.restaurantId,
    required this.positions,
    required this.members,
    required this.query,
  });

  final String restaurantId;
  final List<StaffPosition> positions;
  final List<StaffMember> members;

  /// Wyszukiwanie z panelu po lewej (małymi literami).
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final list = [
      for (final p in positions)
        if (query.isEmpty || p.name.toLowerCase().contains(query)) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _head(context, 'Nazwa', 3),
                _head(context, 'Uprawnienia', 6),
                _head(context, 'Pracownicy', 1, align: TextAlign.right),
                const SizedBox(width: 96),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.ring),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    positions.isEmpty ? 'Brak stanowisk' : 'Nie znaleziono stanowiska',
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                )
              : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.ring),
                  itemBuilder: (context, i) {
                    final p = list[i];
                    final summary = p.isAll
                        ? 'Wszystkie uprawnienia, także te dodane w przyszłości'
                        : p.permissions.isEmpty
                        ? 'Bez uprawnień'
                        : p.permissions.map((x) => x.label).join(' · ');
                    final people = members.where((m) => m.positionIds.contains(p.id)).length;
                    return InkWell(
                      onTap: p.isSystem ? null : () => _editPosition(context, ref, restaurantId, p),
                      child: SizedBox(
                        height: 52,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        p.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    if (p.isSystem) ...[
                                      const SizedBox(width: 8),
                                      Tooltip(
                                        message: 'Dodane przez system, nie da się go zmienić ani usunąć',
                                        child: Glyph(AppIcons.lock, size: 13, color: AppColors.textMuted),
                                      ),
                                    ],
                                    const SizedBox(width: 12),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 6,
                                child: Tooltip(
                                  message: summary,
                                  waitDuration: const Duration(milliseconds: 400),
                                  child: Text(
                                    summary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '$people',
                                  textAlign: TextAlign.right,
                                  style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                                ),
                              ),
                              SizedBox(
                                width: 96,
                                child: p.isSystem
                                    ? null
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            tooltip: 'Zmień',
                                            visualDensity: VisualDensity.compact,
                                            icon: const Glyph(AppIcons.pencil, size: 16),
                                            onPressed: () => _editPosition(context, ref, restaurantId, p),
                                          ),
                                          IconButton(
                                            tooltip: 'Usuń',
                                            visualDensity: VisualDensity.compact,
                                            icon: Glyph(AppIcons.trash, size: 16, color: AppColors.error),
                                            onPressed: () => _deletePosition(context, ref, restaurantId, p),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Nazwa i uprawnienia własnego stanowiska.
class _PositionEditor extends ConsumerStatefulWidget {
  const _PositionEditor({required this.restaurantId, this.position});

  final String restaurantId;
  final StaffPosition? position;

  @override
  ConsumerState<_PositionEditor> createState() => _PositionEditorState();
}

class _PositionEditorState extends ConsumerState<_PositionEditor> {
  late final _name = TextEditingController(text: widget.position?.name ?? '');
  late final Set<StaffPermission> _permissions = {...?widget.position?.permissions};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showMessage(context, 'Wpisz nazwę stanowiska.');
      return;
    }
    const reserved = ['kelner', 'kucharz', 'dostawca'];
    if (reserved.contains(name.toLowerCase())) {
      showMessage(context, 'Stanowisko „$name” jest już dodane przez system.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).savePosition(
        restaurantId: widget.restaurantId,
        id: widget.position?.id,
        name: name,
        permissions: [
          for (final p in StaffPermission.values)
            if (_permissions.contains(p)) p,
        ],
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().toLowerCase();
      showMessage(
        context,
        raw.contains('duplicate') || raw.contains('unique')
            ? 'Stanowisko o tej nazwie już istnieje.'
            : errorText(e),
        tone: ToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(widget.position == null ? 'Nowe stanowisko' : 'Stanowisko'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                autofocus: widget.position == null,
                maxLength: 40,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nazwa',
                  hintText: 'Barman, Kierownik zmiany, Hostessa',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 14),
              Text('Uprawnienia', style: text.titleSmall),
              Text(
                'Pracownik widzi i otwiera tylko te zakładki i przyciski, do których ma uprawnienia.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
              for (final p in StaffPermission.values) ...[
                if (p == StaffPermission.values.first || p.group != StaffPermission.values[p.index - 1].group)
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 2),
                    child: Text(
                      p.group.toUpperCase(),
                      style: text.labelSmall?.copyWith(
                        color: AppColors.textDisabled,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                CheckboxListTile(
                  value: _permissions.contains(p),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _permissions.add(p);
                    } else {
                      _permissions.remove(p);
                    }
                  }),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  activeColor: AppColors.accentFill,
                  checkColor: AppColors.onAccent,
                  title: Text(p.label, style: text.bodyMedium),
                  subtitle: Text(
                    p.description,
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Zapisz')),
      ],
    );
  }
}

/// Nowy kod pracownika: wpisany (4 cyfry) albo wylosowany. Kod musi być unikalny w lokalu.
class _CodeEditDialog extends ConsumerStatefulWidget {
  const _CodeEditDialog({required this.member});

  final StaffMember member;

  @override
  ConsumerState<_CodeEditDialog> createState() => _CodeEditDialogState();
}

class _CodeEditDialogState extends ConsumerState<_CodeEditDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _save({required bool random}) async {
    final typed = _code.text.trim();
    if (!random && !RegExp(r'^[0-9]{4}$').hasMatch(typed)) {
      setState(() => _problem = 'Kod to dokładnie 4 cyfry.');
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final code = await ref
          .read(repositoryProvider)
          .setStaffCode(widget.member.id, code: random ? null : typed);
      if (!mounted) return;
      Navigator.pop(context, true);
      showMessage(context, '${widget.member.name}: nowy kod $code.');
    } catch (e) {
      if (mounted) setState(() => _problem = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Kod: ${widget.member.name}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Wpisz nowy czterocyfrowy kod albo wylosuj go. Stary kod przestanie działać.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              style: text.headlineSmall?.copyWith(fontFeatures: _tabular, letterSpacing: 8),
              decoration: InputDecoration(labelText: 'Kod', hintText: '0000', errorText: _problem, errorMaxLines: 3),
              onSubmitted: (_) => _save(random: false),
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
        OutlinedButton(
          onPressed: _busy ? null : () => _save(random: true),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Wylosuj'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _save(random: false),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: const Text('Zapisz kod'),
        ),
      ],
    );
  }
}

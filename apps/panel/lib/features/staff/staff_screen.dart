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

/// Pracownicy w układzie jak „People” w UniFi (31.10.2026, wzór od użytkownika): po lewej panel z zakładkami Zespół
/// i Stanowiska, wyszukiwaniem, wyborem lokalu (tylko ALL), „Dodaj pracownika” i filtrami, obok niego okno dodawania
/// pracownika albo stanowiska, po prawej tabela. Grafik jest osobną podzakładką ([ScheduleScreen]) z tym samym panelem.
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

/// Zakładki w panelu po lewej (jak „People” i „Roles” w UniFi).
enum _View { team, positions }

/// Stan pracownika w filtrach.
enum _Status {
  onShift('Na zmianie'),
  active('Aktywni'),
  inactive('Nieaktywni'),
  dismissed('Zwolnieni');

  const _Status(this.label);
  final String label;

  bool matches(StaffMember m, Map<String, DateTime> working) => switch (this) {
    _Status.onShift => working.containsKey(m.id),
    _Status.active => m.active,
    _Status.inactive => !m.active && !m.dismissed,
    _Status.dismissed => m.dismissed,
  };
}

/// Szerokość panelu po lewej, zwiniętego paska i okna dodawania obok panelu.
const _panelWidth = 288.0;
const _collapsedWidth = 20.0;
const _sheetWidth = 368.0;

/// Panel po lewej wspólny dla Pracowników i Grafiku: zaznaczone filtry ('' = bez stanowiska), zwinięte grupy
/// i czy panel jest rozwinięty. Zostaje przy przejściu między zakładkami. Na start tylko aktywni.
class _PanelState {
  const _PanelState({
    this.positions = const {},
    this.statuses = const {_Status.active},
    this.closed = const {},
    this.open = true,
  });

  final Set<String> positions;
  final Set<_Status> statuses;
  final Set<String> closed;
  final bool open;

  _PanelState copyWith({Set<String>? positions, Set<_Status>? statuses, Set<String>? closed, bool? open}) =>
      _PanelState(
        positions: positions ?? this.positions,
        statuses: statuses ?? this.statuses,
        closed: closed ?? this.closed,
        open: open ?? this.open,
      );
}

class _PanelNotifier extends Notifier<_PanelState> {
  @override
  _PanelState build() => const _PanelState();

  void togglePosition(String id) => state = state.copyWith(positions: _flip(state.positions, id));
  void toggleStatus(_Status s) => state = state.copyWith(statuses: _flip(state.statuses, s));
  void toggleSection(String key) => state = state.copyWith(closed: _flip(state.closed, key));
  void setOpen(bool open) => state = state.copyWith(open: open);
}

final _panelProvider = NotifierProvider<_PanelNotifier, _PanelState>(_PanelNotifier.new);

Set<T> _flip<T>(Set<T> set, T value) => set.contains(value) ? ({...set}..remove(value)) : {...set, value};

/// Pracownik pasuje do wyszukiwania (imię albo co najmniej 3 cyfry telefonu) i do zaznaczonych filtrów.
/// Pusta grupa filtrów nie filtruje.
bool _matches(StaffMember m, _PanelState f, String query, Map<String, DateTime> working) {
  if (query.isNotEmpty) {
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    final byPhone = digits.length >= 3 && (m.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '').contains(digits);
    if (!m.name.toLowerCase().contains(query) && !byPhone) return false;
  }
  if (f.positions.isNotEmpty &&
      !(m.positionIds.isEmpty ? f.positions.contains('') : m.positionIds.any(f.positions.contains))) {
    return false;
  }
  return f.statuses.isEmpty || f.statuses.any((s) => s.matches(m, working));
}

/// Zmiany z bieżącego tygodnia i kto jest teraz na zmianie (od kiedy).
({List<StaffShift> shifts, Map<String, DateTime> working}) _thisWeek(WidgetRef ref, String restaurantId) {
  final monday = _weekStart(DateTime.now());
  final shifts = ref.watch(
    shiftsProvider((
      restaurantId: restaurantId,
      from: monday,
      to: DateTime(monday.year, monday.month, monday.day + 7),
    )),
  ).value ?? const <StaffShift>[];
  return (shifts: shifts, working: {for (final s in shifts) if (s.isOpen) s.memberId: s.startedAt});
}

/// Zalogowany ma stanowisko ALL albo pełny dostęp właściciela: tylko on widzi wybór lokalu w panelu.
bool _hasAll(ActingMember? member, List<StaffMember> staff, List<StaffPosition> positions) {
  if (member == null) return false;
  if (member.isAccount) return true;
  final all = {for (final p in positions) if (p.isAll) p.id};
  return staff.any((m) => m.id == member.memberId && m.positionIds.any(all.contains));
}

/// Grupy filtrów w panelu: stanowisko i stan, z liczbą osób przy każdej pozycji.
List<Widget> _filterSections(
  _PanelState f,
  _PanelNotifier notifier,
  List<StaffMember> all,
  List<StaffPosition> positions,
  Map<String, DateTime> working,
) {
  int count(bool Function(StaffMember m) test) => all.where(test).length;
  final noPosition = count((m) => m.positionIds.isEmpty);
  return [
    _FilterSection(
      title: 'Stanowisko',
      first: true,
      open: !f.closed.contains('positions'),
      onToggle: () => notifier.toggleSection('positions'),
      options: [
        for (final p in positions)
          (
            label: p.name,
            count: count((m) => m.positionIds.contains(p.id)),
            checked: f.positions.contains(p.id),
            onChanged: (_) => notifier.togglePosition(p.id),
            dot: null,
          ),
        if (noPosition > 0)
          (
            label: 'Bez stanowiska',
            count: noPosition,
            checked: f.positions.contains(''),
            onChanged: (_) => notifier.togglePosition(''),
            dot: null,
          ),
      ],
    ),
    _FilterSection(
      title: 'Stan',
      open: !f.closed.contains('status'),
      onToggle: () => notifier.toggleSection('status'),
      options: [
        for (final s in _Status.values)
          (
            label: s.label,
            count: count((m) => s.matches(m, working)),
            checked: f.statuses.contains(s),
            onChanged: (_) => notifier.toggleStatus(s),
            dot: s == _Status.onShift ? AppColors.accent : null,
          ),
      ],
    ),
  ];
}

/// Szczegóły pracownika (dane, kod, statystyki).
Future<void> _showMember(BuildContext context, String restaurantId, StaffMember member) {
  return showDialog<void>(
    context: context,
    builder: (_) => _MemberDetailsDialog(restaurantId: restaurantId, member: member),
  );
}

/// Lista pracowników albo pusty lokal, ładowanie i błąd (Zespół i Grafik).
Widget _staffOrEmpty(
  AsyncValue<List<StaffMember>> async, {
  required VoidCallback onRetry,
  required bool canStaff,
  required Widget Function() build,
}) {
  return async.when(
    skipLoadingOnReload: true,
    loading: () => const LoadingView(),
    error: (e, _) => ErrorView(error: e, onRetry: onRetry),
    data: (all) => all.isEmpty
        ? MessageView(
            icon: AppIcons.users,
            title: 'Brak pracowników',
            message: canStaff
                ? 'Dodaj pracownika przyciskiem w panelu po lewej.'
                : 'Kierownik jeszcze nie dodał pracowników.',
          )
        : build(),
  );
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  _View _view = _View.team;
  final _search = TextEditingController();

  /// Zaznaczeni pracownicy (pola wyboru w tabeli).
  final _selected = <String>{};

  /// Otwarte okno dodawania pracownika.
  bool _addingMember = false;

  /// Otwarte okno stanowiska: (position: null) to nowe stanowisko.
  ({StaffPosition? position})? _role;

  /// Stanowisko dodane z okna pracownika: okno pracownika je zaznacza.
  String? _newRoleId;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Po dodaniu pracownika: okno się zamyka, a nowy kod (nadaje go baza) pokazujemy do przekazania.
  Future<void> _memberAdded(String restaurantId, String id, {required bool withLogin}) async {
    setState(() {
      _addingMember = false;
      _role = null;
      _newRoleId = null;
    });
    ref.invalidate(staffProvider(restaurantId));
    if (!withLogin) return;
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

  /// „Aktywny”, „Nieaktywny” albo „Zwolnij” dla zaznaczonych (0075). Siebie nie da się wyłączyć ani zwolnić.
  Future<void> _setStatus(String restaurantId, List<StaffMember> members, String status) async {
    final me = ref.read(panelMemberProvider)?.memberId;
    if (status != 'active' && members.any((m) => m.id == me)) {
      showMessage(context, 'Nie możesz wyłączyć ani zwolnić siebie. Odznacz swój wiersz.');
      return;
    }
    final one = members.length == 1 ? members.single.name : null;
    final many = '${members.length} pracowników';
    if (status != 'active') {
      final dismiss = status == 'dismissed';
      final ok = await confirm(
        context,
        title: dismiss
            ? 'Zwolnić ${one ?? many}?'
            : one != null
            ? 'Ustawić $one jako nieaktywnego?'
            : 'Ustawić $many jako nieaktywnych?',
        message: dismiss
            ? 'Zakończą trwającą zmianę, znikną z przyszłego grafiku i nie zalogują się w panelu ani w aplikacji. '
                  'Przepracowane godziny i historia zostają. Później możesz ich znowu ustawić jako aktywnych.'
            : 'Nie zalogują się w panelu ani w aplikacji, dopóki znowu nie ustawisz ich jako aktywnych. '
                  'Grafik i godziny pracy zostają.',
        action: dismiss ? 'Zwolnij' : 'Nieaktywny',
        destructive: dismiss,
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      final n = await ref.read(repositoryProvider).setStaffStatus([for (final m in members) m.id], status);
      ref.invalidate(staffProvider(restaurantId));
      if (!mounted) return;
      setState(_selected.clear);
      showMessage(
        context,
        switch (status) {
          'dismissed' => 'Zwolnieni: $n',
          'inactive' => 'Nieaktywni: $n',
          _ => 'Aktywni: $n',
        },
        tone: ToastTone.success,
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openRole(StaffPosition? position) => setState(() => _role = (position: position));

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    // Uprawnienia pracownika zalogowanego w tej zakładce. Każda część ma własne.
    final permissions = ref.watch(memberPermissionsProvider);
    final canStaff = permissions.contains('staff');
    final canLogins = permissions.contains('staff_logins');
    final canPositions = permissions.contains('positions');
    // Grafik jest osobną podzakładką, czas pracy w Management → „Godziny pracy”.
    final views = [
      if (canStaff || canLogins) (_View.team, 'Zespół', AppIcons.list),
      if (canPositions) (_View.positions, 'Stanowiska', AppIcons.userGear),
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
    final week = _thisWeek(ref, restaurant.id);
    final filters = ref.watch(_panelProvider);
    final query = _search.text.trim().toLowerCase();
    final members = [for (final m in all) if (_matches(m, filters, query, week.working)) m];
    final chosen = [for (final m in members) if (_selected.contains(m.id)) m];

    final panel = _StaffPanel(
      header: views.length > 1
          ? SegmentedTabs<_View>(
              options: [for (final v in views) (v.$1, v.$2)],
              icons: [for (final v in views) v.$3],
              selected: view,
              expand: true,
              onChanged: (v) => setState(() {
                _view = v;
                _search.clear();
                _selected.clear();
                _addingMember = false;
                _role = null;
              }),
            )
          : _PanelTitle(icon: views.first.$3, title: views.first.$2),
      search: _search,
      searchHint: view == _View.positions ? 'Szukaj stanowiska' : 'Szukaj',
      onSearch: () => setState(() {}),
      restaurantPicker: _hasAll(ref.watch(panelMemberProvider), all, positions),
      actions: [
        if (view == _View.team && canStaff)
          _PanelAction(
            label: 'Dodaj pracownika',
            active: _addingMember,
            onTap: () => setState(() {
              _addingMember = true;
              _role = null;
              _newRoleId = null;
            }),
          ),
        if (view == _View.positions)
          _PanelAction(
            label: 'Dodaj stanowisko',
            active: _role != null && _role!.position == null,
            onTap: () => _openRole(null),
          ),
      ],
      children: view == _View.positions
          ? [
              Text(
                'ALL, Kelner, Kucharz i Dostawca dodał system i nie da się ich zmienić ani usunąć, bo korzystają '
                'z nich pakiety Table. Własne stanowiska dodajesz tutaj. Pracownik otworzy tylko te zakładki '
                'i przyciski, do których jego stanowisko ma uprawnienia.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ]
          : _filterSections(filters, ref.read(_panelProvider.notifier), all, positions, week.working),
    );

    final content = switch (view) {
      _View.team => _staffOrEmpty(
        staffAsync,
        onRetry: () => ref.invalidate(staffProvider(restaurant.id)),
        canStaff: canStaff,
        build: () => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 32, 16),
          child: _TeamTable(
            members: members,
            positions: positions,
            codes: canLogins
                ? ref.watch(staffCodesProvider(restaurant.id)).value ?? const <String, String>{}
                : const <String, String>{},
            showCodes: canLogins,
            working: week.working,
            shifts: week.shifts,
            me: ref.watch(panelMemberProvider)?.memberId,
            onOpen: canStaff || canLogins ? (m) => _showMember(context, restaurant.id, m) : null,
            selectable: canStaff,
            selected: _selected,
            onSelect: (id, on) => setState(() => on ? _selected.add(id) : _selected.remove(id)),
            onSelectAll: (on) => setState(() {
              for (final m in members) {
                on ? _selected.add(m.id) : _selected.remove(m.id);
              }
            }),
            bar: chosen.isEmpty
                ? null
                : _SelectionBar(
                    count: chosen.length,
                    busy: _busy,
                    onClear: () => setState(_selected.clear),
                    onActive: chosen.any((m) => !m.active)
                        ? () => _setStatus(restaurant.id, chosen, 'active')
                        : null,
                    onInactive: chosen.any((m) => m.active)
                        ? () => _setStatus(restaurant.id, chosen, 'inactive')
                        : null,
                    onDismiss: chosen.any((m) => !m.dismissed)
                        ? () => _setStatus(restaurant.id, chosen, 'dismissed')
                        : null,
                  ),
          ),
        ),
      ),
      _View.positions => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 32, 16),
        child: _PositionsTable(
          restaurantId: restaurant.id,
          positions: positions,
          members: all,
          query: query,
          selectedId: _role?.position?.id,
          onEdit: _openRole,
        ),
      ),
    };

    // Okno dodawania obok panelu. Nowe stanowisko z okna pracownika otwiera się na nim, a po zapisie
    // okno pracownika wraca z tym stanowiskiem zaznaczonym (IndexedStack zachowuje wpisane dane).
    final sheets = [
      if (_addingMember)
        _MemberSheet(
          key: const ValueKey('nowy pracownik'),
          restaurantId: restaurant.id,
          positions: positions,
          selectPositionId: _newRoleId,
          onNewRole: canPositions ? () => _openRole(null) : null,
          onClose: () => setState(() {
            _addingMember = false;
            _role = null;
          }),
          onSaved: (id) => _memberAdded(restaurant.id, id, withLogin: canLogins),
        ),
      if (_role case final role?)
        _RoleSheet(
          key: ValueKey('stanowisko ${role.position?.id}'),
          restaurantId: restaurant.id,
          position: role.position,
          onClose: () => setState(() => _role = null),
          onSaved: (id) => setState(() {
            if (_addingMember && role.position == null) _newRoleId = id;
            _role = null;
          }),
        ),
    ];

    return _StaffLayout(
      panel: panel,
      sheet: sheets.isEmpty
          ? null
          : SizedBox(
              key: ValueKey(_addingMember ? 'okno pracownika' : 'okno stanowiska'),
              width: _sheetWidth,
              child: IndexedStack(index: sheets.length - 1, sizing: StackFit.expand, children: sheets),
            ),
      content: TabContent(tab: view, child: content),
    );
  }
}

/// Grafik jako osobna podzakładka Pracowników (31.10.2026): ten sam panel po lewej co w Pracownikach, w nim wybór
/// okresu i „Edytuj”, a po prawej grafik dla pracowników z filtrów. Uprawnienie „Grafik”.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  /// Okres grafiku względem bieżącego (tydzień, 2 tygodnie albo miesiąc, jak ustawił lokal).
  int _offset = 0;
  bool _saving = false;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final restaurantId = restaurant.id;
    final text = Theme.of(context).textTheme;
    final permissions = ref.watch(memberPermissionsProvider);
    final canStaff = permissions.contains('staff');
    final canPlan = permissions.contains('schedule');
    final me = ref.watch(panelMemberProvider)?.memberId;

    final staffAsync = ref.watch(staffProvider(restaurantId));
    final all = staffAsync.value ?? const <StaffMember>[];
    final positions = ref.watch(positionsProvider(restaurantId)).value ?? const <StaffPosition>[];
    final week = _thisWeek(ref, restaurantId);
    final filters = ref.watch(_panelProvider);
    final query = _search.text.trim().toLowerCase();
    final members = [for (final m in all) if (_matches(m, filters, query, week.working)) m];

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
    final range = (restaurantId: restaurantId, from: weeks.first, to: gridEnd);
    final saved = ref.watch(scheduleRangeProvider(range)).value ?? const <PlannedShift>[];
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
      for (final n in ref.watch(weekNotesProvider(range)).value ?? const <WeekNote>[])
        '${n.memberId}@${dateOnly(n.weekStart)}': n.note,
    };
    final positionNames = {for (final p in positions) p.id: p.name};

    final panel = _StaffPanel(
      header: const _PanelTitle(icon: AppIcons.calendarDots, title: 'Grafik'),
      search: _search,
      searchHint: 'Szukaj',
      onSearch: () => setState(() {}),
      restaurantPicker: _hasAll(ref.watch(panelMemberProvider), all, positions),
      // Okres i edycja w panelu; pracownicy widzą zmiany dopiero po „Zapisz”.
      actions: [
        StepSwitcher(
          label: periodKind == 'month' ? Fmt.monthYear(period.from) : weekLabel(period.from, period.to),
          expand: true,
          previousTooltip: periodKind == 'month' ? 'Poprzedni miesiąc' : 'Poprzedni okres',
          nextTooltip: periodKind == 'month' ? 'Następny miesiąc' : 'Następny okres',
          onPrevious: () => setState(() => _offset--),
          onNext: () => setState(() => _offset++),
          resetTooltip: 'Wróć do bieżącego okresu',
          onReset: _offset == 0 ? null : () => setState(() => _offset = 0),
        ),
        if (canPlan)
          if (editing)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _cancelEdit(restaurantId, draft),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                    child: const Text('Anuluj'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving || draft.changes.isEmpty ? null : () => _saveSchedule(restaurantId, draft),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                    child: Text(draft.changes.isEmpty ? 'Zapisz' : 'Zapisz (${draft.changes.length})'),
                  ),
                ),
              ],
            )
          else
            FilledButton.icon(
              onPressed: () => ref.read(scheduleDraftProvider(restaurantId).notifier).start(me ?? ''),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(40)),
              icon: const Glyph(AppIcons.pencil, size: 18),
              label: const Text('Edytuj'),
            ),
      ],
      children: _filterSections(filters, ref.read(_panelProvider.notifier), all, positions, week.working),
    );

    final content = _staffOrEmpty(
      staffAsync,
      onRetry: () => ref.invalidate(staffProvider(restaurantId)),
      canStaff: canStaff,
      build: () => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 32, 32),
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
                      ? 'Jedno zgłoszenie czeka na decyzję.${canPlan ? ' Kliknij „Edytuj” w panelu, żeby je przyjąć, zmienić albo odrzucić.' : ''}'
                      : 'Zgłoszenia czekające na decyzję: $waiting.${canPlan ? ' Kliknij „Edytuj” w panelu, żeby je przyjąć, zmienić albo odrzucić.' : ''}',
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
                    onOpenMember: canStaff ? (m) => _showMember(context, restaurantId, m) : null,
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
              'albo odrzuci w aplikacji. Kliknij „Edytuj” w panelu, żeby przyjąć zgłoszenie (także ze zmienionymi '
              'godzinami i stanowiskiem na ten dzień), odrzucić je, wysłać propozycję albo dać wolne. Zmiany trafiają '
              'do pracowników dopiero po „Zapisz”.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );

    return _StaffLayout(panel: panel, content: content);
  }
}

// ---------------------------------------------------------------
// Układ jak w UniFi: panel po lewej, okno obok, treść
// ---------------------------------------------------------------

/// Panel po lewej (albo wąski pasek, gdy zwinięty), obok niego okno dodawania (gdy otwarte), po prawej treść.
/// Przycisk zwijania stoi na kresce między panelem a resztą, jak w UniFi.
class _StaffLayout extends ConsumerWidget {
  const _StaffLayout({required this.panel, required this.content, this.sheet});

  final Widget panel;
  final Widget content;
  final Widget? sheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(_panelProvider.select((s) => s.open));
    final edge = open ? _panelWidth : _collapsedWidth;
    return Stack(
      children: [
        Positioned.fill(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (open)
                panel
              else
                Container(
                  width: _collapsedWidth,
                  decoration: BoxDecoration(border: Border(right: BorderSide(color: AppColors.ring))),
                ),
              // Okno dodawania wysuwa się zza panelu.
              AnimatedSwitcher(
                duration: PanelMotion.tab,
                transitionBuilder: (child, animation) => SizeTransition(
                  axis: Axis.horizontal,
                  alignment: Alignment.centerLeft,
                  sizeFactor: CurvedAnimation(parent: animation, curve: AppMotion.easeOut),
                  child: child,
                ),
                child: sheet ?? const SizedBox.shrink(key: ValueKey('bez okna')),
              ),
              Expanded(child: content),
            ],
          ),
        ),
        Positioned(
          left: edge - 14,
          top: 22,
          child: _EdgeButton(open: open, onTap: () => ref.read(_panelProvider.notifier).setOpen(!open)),
        ),
      ],
    );
  }
}

/// Okrągły przycisk na kresce panelu: zwija go albo rozwija.
class _EdgeButton extends StatelessWidget {
  const _EdgeButton({required this.open, required this.onTap});

  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: open ? 'Zwiń panel' : 'Pokaż panel',
      child: Material(
        color: AppColors.surface,
        shape: CircleBorder(side: BorderSide(color: AppColors.ringStrong)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: Glyph(open ? AppIcons.caretLeft : AppIcons.caretRight, size: 14, color: AppColors.textMuted),
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel po lewej: zakładki albo tytuł, wyszukiwanie, wybór lokalu (tylko ALL), przyciski i filtry.
class _StaffPanel extends StatelessWidget {
  const _StaffPanel({
    required this.header,
    required this.search,
    required this.searchHint,
    required this.onSearch,
    required this.restaurantPicker,
    this.actions = const [],
    this.children = const [],
  });

  final Widget header;
  final TextEditingController search;
  final String searchHint;
  final VoidCallback onSearch;
  final bool restaurantPicker;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _panelWidth,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: AppColors.ring))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: SizedBox(height: 40, child: header),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: search,
              onChanged: (_) => onSearch(),
              decoration: InputDecoration(
                hintText: searchHint,
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
          if (restaurantPicker)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _RestaurantPicker(),
            ),
          for (final a in actions)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: a,
            ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tytuł panelu, gdy nie ma zakładek do wyboru (Grafik albo tylko jedna część Pracowników).
class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.icon, required this.title});

  final AppIconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Glyph(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

/// Przycisk z obrysem w kolorze akcentu („Dodaj pracownika”), podświetlony, gdy jego okno jest otwarte.
class _PanelAction extends StatelessWidget {
  const _PanelAction({required this.label, required this.onTap, this.active = false});

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        backgroundColor: active ? AppColors.accentTint : null,
        side: BorderSide(color: AppColors.accent.withValues(alpha: 0.7)),
        minimumSize: const Size.fromHeight(40),
      ),
      child: Text(label),
    );
  }
}

/// Wybór lokalu pod wyszukiwaniem, jak wybór firmy w UniFi. Widzi go tylko osoba ze stanowiskiem ALL albo
/// z pełnym dostępem właściciela; zmienia lokal całego panelu (jak lokal w prawym górnym rogu).
class _RestaurantPicker extends ConsumerWidget {
  const _RestaurantPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final current = ref.watch(currentRestaurantProvider);
    final list = ref.watch(restaurantsProvider).value ?? const <PanelRestaurant>[];
    if (current == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Zmień lokal',
      position: PopupMenuPosition.under,
      color: AppColors.surface,
      constraints: const BoxConstraints(minWidth: _panelWidth - 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.ring),
      ),
      onSelected: (id) => ref.read(selectedRestaurantIdProvider.notifier).select(id),
      itemBuilder: (context) => [
        for (final r in list)
          PopupMenuItem(
            value: r.id,
            child: Row(
              children: [
                RestaurantLogo(name: r.name, logoUrl: r.logoUrl, size: 24, radius: 6),
                const SizedBox(width: 10),
                Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (r.id == current.id) ...[
                  const SizedBox(width: 8),
                  Glyph(AppIcons.check, size: 16, color: AppColors.accent),
                ],
              ],
            ),
          ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.ring),
        ),
        child: Row(
          children: [
            RestaurantLogo(name: current.name, logoUrl: current.logoUrl, size: 24, radius: 6),
            const SizedBox(width: 10),
            Expanded(
              child: Text(current.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelLarge),
            ),
            Glyph(AppIcons.caretDown, size: 14, color: AppColors.textMuted),
          ],
        ),
      ),
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
// Filtry i tabela zespołu
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
            _Check(value: o.checked, onChanged: enabled ? (v) => o.onChanged(v ?? false) : null),
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

/// Małe pole wyboru (filtry, uprawnienia, wiersze tabeli). Przy [tristate] null znaczy „część zaznaczona”.
class _Check extends StatelessWidget {
  const _Check({required this.value, required this.onChanged, this.tristate = false});

  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return SizedBox(
      width: 18,
      height: 18,
      child: Checkbox(
        value: value,
        tristate: tristate,
        onChanged: onChanged,
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
const _checkWidth = 36.0;
const _phoneWidth = 136.0;
const _nowWidth = 96.0;
const _weekWidth = 88.0;
const _codeWidth = 60.0;

/// Zespół jako tabela jak „People” w UniFi: pole wyboru, imię z odznakami (ALL, Ty, Nieaktywny, Zwolniony),
/// telefon, stanowisko, stan teraz, godziny w tym tygodniu i kod. Kliknięcie wiersza otwiera szczegóły pracownika.
/// Nad tabelą pasek działań dla zaznaczonych ([bar]).
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
    required this.selectable,
    required this.selected,
    required this.onSelect,
    required this.onSelectAll,
    this.bar,
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

  /// Pola wyboru tylko z uprawnieniem „Pracownicy” (działania na zaznaczonych).
  final bool selectable;
  final Set<String> selected;
  final void Function(String id, bool on) onSelect;
  final ValueChanged<bool> onSelectAll;
  final Widget? bar;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final byId = {for (final p in positions) p.id: p};
    final chosen = members.where((m) => selected.contains(m.id)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: AppMotion.easeOut,
          alignment: Alignment.topCenter,
          child: bar == null ? const SizedBox(width: double.infinity) : Padding(padding: const EdgeInsets.only(bottom: 8), child: bar),
        ),
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (selectable)
                  SizedBox(
                    width: _checkWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _Check(
                        tristate: true,
                        value: chosen == 0 ? false : (chosen == members.length ? true : null),
                        onChanged: members.isEmpty ? null : (_) => onSelectAll(chosen < members.length),
                      ),
                    ),
                  ),
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
                    final on = selected.contains(m.id);
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
                      selected: on,
                      leading: selectable
                          ? SizedBox(
                              width: _checkWidth,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _Check(value: on, onChanged: (v) => onSelect(m.id, v ?? false)),
                              ),
                            )
                          : null,
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
    this.selected = false,
    this.leading,
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
  final bool selected;

  /// Pole wyboru przed imieniem.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final m = member;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    return Material(
      color: selected ? AppColors.accentFill.withValues(alpha: 0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ?leading,
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
                            if (m.dismissed)
                              ...[const SizedBox(width: 6), const _Badge('Zwolniony')]
                            else if (!m.active)
                              ...[const SizedBox(width: 6), const _Badge('Nieaktywny')],
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
      ),
    );
  }
}

/// Pasek nad tabelą, gdy ktoś jest zaznaczony: liczba i działania „Aktywny”, „Nieaktywny”, „Zwolnij”
/// (przycisk tylko wtedy, gdy zmienia coś u któregoś z zaznaczonych).
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.busy,
    required this.onClear,
    this.onActive,
    this.onInactive,
    this.onDismiss,
  });

  final int count;
  final bool busy;
  final VoidCallback onClear;
  final VoidCallback? onActive;
  final VoidCallback? onInactive;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget action(String label, AppIconData icon, VoidCallback onTap, {Color? color}) => Padding(
      padding: const EdgeInsets.only(left: 8),
      child: OutlinedButton.icon(
        onPressed: busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: color == null ? null : BorderSide(color: color.withValues(alpha: 0.6)),
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        icon: Glyph(icon, size: 16, color: color),
        label: Text(label),
      ),
    );
    return Container(
      height: 52,
      padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ring),
      ),
      child: Row(
        children: [
          Text('Zaznaczono: $count', style: text.labelLarge?.copyWith(fontFeatures: _tabular)),
          const Spacer(),
          if (onActive case final f?) action('Aktywny', AppIcons.userCheck, f),
          if (onInactive case final f?) action('Nieaktywny', AppIcons.userMinus, f),
          if (onDismiss case final f?) action('Zwolnij', AppIcons.prohibit, f, color: AppColors.error),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Odznacz wszystkich',
            onPressed: onClear,
            icon: Glyph(AppIcons.close, size: 16, color: AppColors.textMuted),
          ),
        ],
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

/// Edycja pracownika (ze szczegółów; nowego dodaje okno obok panelu). Zwraca numer pracownika po zapisie
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
    final position = positions.where((p) => p.id == _positionId).firstOrNull;
    final problem = _memberProblem(
      firstName: _firstName.text,
      lastName: _lastName.text,
      phone: _phone.text,
      position: position,
      gross: _gross.text,
    );
    if (problem != null) {
      showMessage(context, problem);
      return;
    }

    setState(() => _busy = true);
    try {
      final id = await _persistMember(
        ref,
        restaurantId: widget.restaurantId,
        member: widget.member,
        firstName: _firstName.text,
        lastName: _lastName.text,
        phone: _phone.text,
        position: position!,
        extras: _extraPositions,
        positions: positions,
        color: _color,
        active: _active,
        gross: _gross.text,
        contract: _contract,
        savedRate: _savedRate,
        rateLoaded: _rateLoaded,
      );
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

/// Usunięcie własnego stanowiska po potwierdzeniu. True, gdy się udało.
Future<bool> _deletePosition(BuildContext context, WidgetRef ref, String restaurantId, StaffPosition position) async {
  final ok = await confirm(
    context,
    title: 'Usunąć stanowisko „${position.name}”?',
    message: 'Stanowiska przypisanego do pracowników nie da się usunąć. Najpierw zmień im stanowisko.',
    action: 'Usuń',
    destructive: true,
  );
  if (!ok) return false;
  try {
    await ref.read(repositoryProvider).deletePosition(position.id);
    ref.invalidate(positionsProvider(restaurantId));
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    final raw = e.toString().toLowerCase();
    showMessage(
      context,
      raw.contains('foreign key') || raw.contains('violates')
          ? 'To stanowisko ma przypisanych pracowników. Najpierw zmień im stanowisko.'
          : errorText(e),
      tone: ToastTone.error,
    );
    return false;
  }
}

/// Uprawnienia stanowiska w jednej linii (karty stanowisk i tabela).
String _permissionSummary(StaffPosition p, {String separator = ' · '}) => p.isAll
    ? 'Wszystkie uprawnienia, także te dodane w przyszłości'
    : p.permissions.isEmpty
    ? 'Bez uprawnień'
    : p.permissions.map((x) => x.label).join(separator);

/// Stanowiska jak „Roles” w UniFi: nazwa (systemowe z kłódką), uprawnienia i liczba pracowników.
/// Kliknięcie własnego stanowiska otwiera je w oknie obok panelu; systemowych nie da się zmienić ani usunąć.
class _PositionsTable extends ConsumerWidget {
  const _PositionsTable({
    required this.restaurantId,
    required this.positions,
    required this.members,
    required this.query,
    required this.onEdit,
    this.selectedId,
  });

  final String restaurantId;
  final List<StaffPosition> positions;
  final List<StaffMember> members;

  /// Wyszukiwanie z panelu po lewej (małymi literami).
  final String query;
  final ValueChanged<StaffPosition> onEdit;

  /// Stanowisko otwarte w oknie obok panelu.
  final String? selectedId;

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
                _head(context, 'Pracownicy', 0, align: TextAlign.right, width: 88),
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
                    final summary = _permissionSummary(p);
                    final people = members.where((m) => m.positionIds.contains(p.id)).length;
                    return Material(
                      color: p.id == selectedId ? AppColors.accentFill.withValues(alpha: 0.08) : Colors.transparent,
                      child: InkWell(
                        onTap: p.isSystem ? null : () => onEdit(p),
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
                                SizedBox(
                                  width: 88,
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
                                              onPressed: () => onEdit(p),
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
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Okna obok panelu: nowy pracownik i stanowisko (jak „Add New Person” w UniFi)
// ---------------------------------------------------------------

/// Ramka okna obok panelu: tytuł z „Zamknij”, przewijana treść i przycisk na dole.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.onClose, required this.children, required this.footer});

  final String title;
  final VoidCallback onClose;
  final List<Widget> children;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.ring)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 10, 4),
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zamknij',
                    onPressed: onClose,
                    icon: Glyph(AppIcons.close, size: 18, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              children: children,
            ),
          ),
          Divider(height: 1, color: AppColors.ring),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: footer,
          ),
        ],
      ),
    );
  }
}

/// Pole w oknie: mały napis nad nim, jak w UniFi.
class _SheetField extends StatelessWidget {
  const _SheetField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// Nagłówek części okna, np. „Stanowisko” albo „Dodatkowe stanowiska (opcjonalnie)”.
class _SheetHeading extends StatelessWidget {
  const _SheetHeading(this.title, {this.optional = false, this.trailing});

  final String title;
  final bool optional;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Text(title, style: text.titleSmall),
        if (optional) ...[
          const SizedBox(width: 6),
          Text('(opcjonalnie)', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        ],
        const Spacer(),
        if (trailing != null)
          Text(trailing!, style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular)),
      ],
    );
  }
}

InputDecoration _sheetInput({String? hint, String? suffix}) => InputDecoration(
  isDense: true,
  hintText: hint,
  suffixText: suffix,
  counterText: '',
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
);

/// Karty po dwie w rzędzie (stanowiska w oknie pracownika, jak role w UniFi).
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final c in children) SizedBox(width: width, height: 108, child: c)],
        );
      },
    );
  }
}

/// Karta wyboru: ikona, nazwa i opis w dwóch liniach. Wybrana ma obrys i tło w kolorze akcentu.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  final AppIconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: selected ? AppColors.accentTint : AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? AppColors.accent : Colors.transparent, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Glyph(selected ? icon.duotone : icon, size: 20, color: AppColors.accent),
              const Spacer(),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelLarge),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: AppColors.textMuted, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Szary przycisk na całą szerokość z plusem, jak „Add site” w UniFi.
class _AddRow extends StatelessWidget {
  const _AddRow({required this.label, this.enabled = true});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.text : AppColors.textDisabled;
    return Container(
      height: 40,
      decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Glyph(AppIcons.plus, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Co trzeba poprawić przed zapisem pracownika; null, gdy wszystko w porządku.
String? _memberProblem({
  required String firstName,
  required String lastName,
  required String phone,
  required StaffPosition? position,
  required String gross,
}) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (firstName.trim().isEmpty || lastName.trim().isEmpty) return 'Wpisz imię i nazwisko pracownika.';
  if (digits.length < 9 || digits.length > 15) return 'Wpisz numer telefonu, co najmniej 9 cyfr.';
  if (position == null) return 'Wybierz stanowisko.';
  if (gross.trim().isNotEmpty && (parseGrosze(gross) == null || parseGrosze(gross)! > 100000)) {
    return 'Wpisz stawkę za godzinę, na przykład 30 albo 32,50.';
  }
  return null;
}

/// Zapis pracownika (okno pracownika i okno dodawania): dane, dodatkowe stanowiska i stawka. Zwraca jego numer.
/// Stawka zapisuje się tylko wtedy, gdy się zmieniła względem [savedRate].
Future<String> _persistMember(
  WidgetRef ref, {
  required String restaurantId,
  StaffMember? member,
  required String firstName,
  required String lastName,
  required String phone,
  required StaffPosition position,
  required Set<String> extras,
  required List<StaffPosition> positions,
  required int color,
  required bool active,
  required String gross,
  required Contract contract,
  StaffRate? savedRate,
  bool rateLoaded = true,
}) async {
  final repository = ref.read(repositoryProvider);
  final id = await repository.saveStaffMember(
    restaurantId: restaurantId,
    id: member?.id,
    firstName: firstName,
    lastName: lastName,
    position: position,
    phone: phone,
    color: color,
    active: active,
  );
  final extraIds = [for (final p in positions) if (extras.contains(p.id) && p.id != position.id) p.id];
  if (member != null || extraIds.isNotEmpty) {
    final before = {...?member?.extraPositionIds};
    if (before.length != extraIds.length || !before.containsAll(extraIds)) {
      await repository.setMemberPositions(id, extraIds);
    }
  }
  final rate = gross.trim().isEmpty ? null : parseGrosze(gross);
  if (rateLoaded && (rate != savedRate?.grossGrosze || (rate != null && contract != savedRate?.contract))) {
    await repository.setStaffRate(id, rate, contract);
    ref.invalidate(staffRatesProvider(restaurantId));
    ref.invalidate(memberStatsProvider);
    ref.invalidate(teamStatsProvider);
  }
  return id;
}

/// Nowy pracownik w oknie obok panelu (jak „Add New Person” w UniFi): imię i nazwisko, telefon, stanowisko jako
/// karty z „Nowe stanowisko”, dodatkowe stanowiska, umowa i stawka, kolor w grafiku.
class _MemberSheet extends ConsumerStatefulWidget {
  const _MemberSheet({
    super.key,
    required this.restaurantId,
    required this.positions,
    required this.onClose,
    required this.onSaved,
    this.onNewRole,
    this.selectPositionId,
  });

  final String restaurantId;
  final List<StaffPosition> positions;
  final VoidCallback onClose;
  final ValueChanged<String> onSaved;

  /// „Nowe stanowisko” (tylko z uprawnieniem „Stanowiska”).
  final VoidCallback? onNewRole;

  /// Stanowisko dodane przed chwilą z tego okna: zaznacza się samo.
  final String? selectPositionId;

  @override
  ConsumerState<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends ConsumerState<_MemberSheet> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _gross = TextEditingController();
  final _net = TextEditingController();
  String? _positionId;
  final _extraPositions = <String>{};
  int _color = 0;
  Contract _contract = Contract.zlecenie;
  bool _busy = false;

  @override
  void didUpdateWidget(_MemberSheet old) {
    super.didUpdateWidget(old);
    final added = widget.selectPositionId;
    if (added != null && added != old.selectPositionId) {
      _positionId = added;
      _extraPositions.remove(added);
    }
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

  Future<void> _save(List<StaffPosition> positions) async {
    final position = positions.where((p) => p.id == _positionId).firstOrNull;
    final problem = _memberProblem(
      firstName: _firstName.text,
      lastName: _lastName.text,
      phone: _phone.text,
      position: position,
      gross: _gross.text,
    );
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await _persistMember(
        ref,
        restaurantId: widget.restaurantId,
        firstName: _firstName.text,
        lastName: _lastName.text,
        phone: _phone.text,
        position: position!,
        extras: _extraPositions,
        positions: positions,
        color: _color,
        active: true,
        gross: _gross.text,
        contract: _contract,
      );
      if (mounted) widget.onSaved(id);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // „ALL” (wszystkie uprawnienia) nadaje tylko osoba z uprawnieniem „Stanowiska”.
    final canAssignAll = ref.watch(memberPermissionsProvider).contains('positions');
    final positions = [for (final p in widget.positions) if (!p.isAll || canAssignAll) p];
    final extrasLeft = [for (final p in positions) if (p.id != _positionId && !_extraPositions.contains(p.id)) p];
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))];

    return _SheetFrame(
      title: 'Nowy pracownik',
      onClose: widget.onClose,
      footer: FilledButton(
        onPressed: _busy ? null : () => _save(positions),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        child: const Text('Dodaj pracownika'),
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _SheetField(
                label: 'Imię',
                child: TextField(
                  controller: _firstName,
                  autofocus: true,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  decoration: _sheetInput(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SheetField(
                label: 'Nazwisko',
                child: TextField(
                  controller: _lastName,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: _sheetInput(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SheetField(
          label: 'Numer telefonu',
          child: TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
              LengthLimitingTextInputFormatter(20),
            ],
            style: const TextStyle(fontFeatures: _tabular),
            decoration: _sheetInput(hint: '+48 600 100 200'),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tym numerem pracownik loguje się w aplikacji Table for employees.',
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 24),
        const _SheetHeading('Stanowisko'),
        const SizedBox(height: 10),
        _CardGrid(
          children: [
            for (final p in positions)
              _ChoiceCard(
                icon: p.isAll ? AppIcons.userGear : AppIcons.identification,
                title: p.name,
                subtitle: _permissionSummary(p, separator: ', '),
                selected: p.id == _positionId,
                onTap: () => setState(() {
                  _positionId = p.id;
                  _extraPositions.remove(p.id);
                }),
              ),
            if (widget.onNewRole case final newRole?)
              _ChoiceCard(
                icon: AppIcons.plus,
                title: 'Nowe stanowisko',
                subtitle: 'Własne uprawnienia dla zespołu',
                onTap: newRole,
              ),
          ],
        ),
        const SizedBox(height: 24),
        const _SheetHeading('Dodatkowe stanowiska', optional: true),
        const SizedBox(height: 4),
        Text(
          'Uprawnienia są sumą wszystkich stanowisk, a w grafiku wybiera się stanowisko na dany dzień.',
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 10),
        if (_extraPositions.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in positions)
                if (_extraPositions.contains(p.id))
                  InputChip(
                    label: Text(p.name),
                    deleteIcon: const Glyph(AppIcons.close, size: 14),
                    onDeleted: () => setState(() => _extraPositions.remove(p.id)),
                  ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        PopupMenuButton<String>(
          enabled: extrasLeft.isNotEmpty,
          tooltip: 'Dodaj stanowisko',
          position: PopupMenuPosition.under,
          color: AppColors.surface,
          onSelected: (id) => setState(() => _extraPositions.add(id)),
          itemBuilder: (_) => [for (final p in extrasLeft) PopupMenuItem(value: p.id, child: Text(p.name))],
          child: _AddRow(label: 'Dodaj stanowisko', enabled: extrasLeft.isNotEmpty),
        ),
        const SizedBox(height: 24),
        const _SheetHeading('Umowa i stawka', optional: true),
        const SizedBox(height: 10),
        DropdownButtonFormField<Contract>(
          initialValue: _contract,
          decoration: _sheetInput(),
          icon: const Glyph(AppIcons.caretDown, size: 16),
          items: [for (final c in Contract.values) DropdownMenuItem(value: c, child: Text(c.label))],
          onChanged: (c) {
            setState(() => _contract = c!);
            _grossChanged(_gross.text);
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _SheetField(
                label: 'Stawka brutto',
                child: TextField(
                  controller: _gross,
                  onChanged: _grossChanged,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: decimal,
                  style: const TextStyle(fontFeatures: _tabular),
                  decoration: _sheetInput(suffix: 'zł/h'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SheetField(
                label: 'Stawka netto',
                child: TextField(
                  controller: _net,
                  onChanged: _netChanged,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: decimal,
                  style: const TextStyle(fontFeatures: _tabular),
                  decoration: _sheetInput(suffix: 'zł/h'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _SheetHeading('Kolor w grafiku'),
        const SizedBox(height: 10),
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
                      border: Border.all(color: i == _color ? AppColors.text : Colors.transparent, width: 2.5),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Nowe albo zmienione własne stanowisko w oknie obok panelu (ten sam wygląd co nowy pracownik): nazwa
/// i uprawnienia w grupach z „Zaznacz wszystkie”. Systemowych stanowisk tu nie ma (są zablokowane).
class _RoleSheet extends ConsumerStatefulWidget {
  const _RoleSheet({
    super.key,
    required this.restaurantId,
    required this.onClose,
    required this.onSaved,
    this.position,
  });

  final String restaurantId;
  final StaffPosition? position;
  final VoidCallback onClose;

  /// Po zapisie: numer stanowiska (nowy przy dodaniu).
  final ValueChanged<String> onSaved;

  @override
  ConsumerState<_RoleSheet> createState() => _RoleSheetState();
}

class _RoleSheetState extends ConsumerState<_RoleSheet> {
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
    const reserved = ['kelner', 'kucharz', 'dostawca', 'all'];
    if (reserved.contains(name.toLowerCase())) {
      showMessage(context, 'Stanowisko „$name” jest już dodane przez system.');
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await ref.read(repositoryProvider).savePosition(
        restaurantId: widget.restaurantId,
        id: widget.position?.id,
        name: name,
        permissions: [
          for (final p in StaffPermission.values)
            if (_permissions.contains(p)) p,
        ],
      );
      ref
        ..invalidate(positionsProvider(widget.restaurantId))
        ..invalidate(staffProvider(widget.restaurantId));
      if (mounted) widget.onSaved(id);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().toLowerCase();
      showMessage(
        context,
        raw.contains('duplicate') || raw.contains('unique') ? 'Stanowisko o tej nazwie już istnieje.' : errorText(e),
        tone: ToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (await _deletePosition(context, ref, widget.restaurantId, widget.position!)) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final groups = <String, List<StaffPermission>>{};
    for (final p in StaffPermission.values) {
      groups.putIfAbsent(p.group, () => []).add(p);
    }
    return _SheetFrame(
      title: widget.position == null ? 'Nowe stanowisko' : widget.position!.name,
      onClose: widget.onClose,
      footer: Row(
        children: [
          if (widget.position != null) ...[
            TextButton(
              onPressed: _busy ? null : _delete,
              style: TextButton.styleFrom(foregroundColor: AppColors.error, minimumSize: const Size(0, 44)),
              child: const Text('Usuń'),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              child: Text(widget.position == null ? 'Dodaj stanowisko' : 'Zapisz'),
            ),
          ),
        ],
      ),
      children: [
        _SheetField(
          label: 'Nazwa',
          child: TextField(
            controller: _name,
            autofocus: widget.position == null,
            maxLength: 40,
            textCapitalization: TextCapitalization.sentences,
            decoration: _sheetInput(hint: 'Barman, Kierownik zmiany, Hostessa'),
          ),
        ),
        const SizedBox(height: 24),
        _SheetHeading('Uprawnienia', trailing: '${_permissions.length} z ${StaffPermission.values.length}'),
        const SizedBox(height: 4),
        Text(
          'Pracownik widzi i otwiera tylko te zakładki i przyciski, do których ma uprawnienia.',
          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        for (final MapEntry(key: group, value: list) in groups.entries) ...[
          _PermissionGroup(
            title: group,
            permissions: list,
            selected: _permissions,
            onChanged: (p, on) => setState(() => on ? _permissions.add(p) : _permissions.remove(p)),
            onAll: (on) => setState(() => on ? _permissions.addAll(list) : _permissions.removeAll(list)),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Grupa uprawnień w oknie stanowiska (np. Sala, Zamówienia): karta z nazwą, „Zaznacz wszystkie”
/// i polami wyboru z opisem.
class _PermissionGroup extends StatelessWidget {
  const _PermissionGroup({
    required this.title,
    required this.permissions,
    required this.selected,
    required this.onChanged,
    required this.onAll,
  });

  final String title;
  final List<StaffPermission> permissions;
  final Set<StaffPermission> selected;
  final void Function(StaffPermission p, bool on) onChanged;
  final ValueChanged<bool> onAll;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final all = permissions.every(selected.contains);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 8),
      decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: text.labelLarge)),
              TextButton(
                onPressed: () => onAll(!all),
                style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 8)),
                child: Text(all ? 'Odznacz' : 'Zaznacz wszystkie'),
              ),
            ],
          ),
          for (final p in permissions)
            InkWell(
              onTap: () => onChanged(p, !selected.contains(p)),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: _Check(value: selected.contains(p), onChanged: (v) => onChanged(p, v ?? false)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.label, style: text.bodyMedium),
                          Text(p.description, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
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

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../reservations/reservations_screen.dart' show StatusPill;
import 'floor_canvas.dart';

const _tabular = [FontFeature.tabularFigures()];

enum _Mode { live, edit }

class FloorScreen extends ConsumerStatefulWidget {
  const FloorScreen({super.key});

  @override
  ConsumerState<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends ConsumerState<FloorScreen> {
  _Mode _mode = _Mode.live;
  String? _zoneName;
  String? _selectedKey;

  // Podgląd na żywo: godzina, dla której pokazujemy zajętość.
  DateTime _now = DateTime.now();
  int? _minuteOfDay;
  Timer? _clock;

  // Edycja: kopia robocza układu.
  List<FloorZone> _zones = [];
  List<DiningTable> _tables = [];
  final List<String> _deletedTables = [];
  final List<String> _deletedZones = [];
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  DateTime get _viewTime {
    final m = _minuteOfDay;
    if (m == null) return _now;
    final d = dateOnly(_now);
    return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
  }

  void _startEditing(List<FloorZone> zones, List<DiningTable> tables) {
    final all = [...zones];
    for (final t in tables) {
      if (!all.any((z) => z.name == t.zone)) {
        all.add(FloorZone(id: null, name: t.zone, widthCm: 1000, heightCm: 700, position: all.length));
      }
    }
    setState(() {
      _zones = all;
      _tables = [...tables];
      _deletedTables.clear();
      _deletedZones.clear();
      _dirty = false;
      _mode = _Mode.edit;
      _selectedKey = null;
    });
  }

  Future<void> _stopEditing() async {
    if (_dirty) {
      final ok = await confirm(
        context,
        title: 'Odrzucić zmiany?',
        message: 'Niezapisane zmiany w układzie sali zostaną utracone.',
        action: 'Odrzuć',
        destructive: true,
      );
      if (!ok) return;
    }
    setState(() {
      _mode = _Mode.live;
      _dirty = false;
      _selectedKey = null;
    });
  }

  void _update(DiningTable table, DiningTable Function(DiningTable) change) {
    final key = FloorCanvas.keyOf(table);
    setState(() {
      _tables = [
        for (final t in _tables)
          if (FloorCanvas.keyOf(t) == key) change(t) else t,
      ];
      _selectedKey = FloorCanvas.keyOf(change(table));
      _dirty = true;
    });
  }

  void _addTable(FloorZone zone) {
    var n = _tables.length + 1;
    String label() => 'S$n';
    while (_tables.any((t) => t.label == label())) {
      n++;
    }
    final table = DiningTable(
      id: null,
      draftKey: 'nowy-${DateTime.now().microsecondsSinceEpoch}',
      label: label(),
      seats: 4,
      widthCm: 120,
      heightCm: 80,
      zone: zone.name,
      priority: 0,
      active: true,
      xCm: zone.widthCm ~/ 2,
      yCm: zone.heightCm ~/ 2,
      rotation: 0,
      shape: TableShape.rect,
    );
    setState(() {
      _tables = [..._tables, table];
      _selectedKey = FloorCanvas.keyOf(table);
      _dirty = true;
    });
  }

  Future<void> _deleteTable(DiningTable table) async {
    final ok = await confirm(
      context,
      title: 'Usunąć stolik ${table.label}?',
      message:
          'Jeśli stolik ma przyszłe rezerwacje, zapis się nie uda. Wtedy wyłącz stolik zamiast go usuwać.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    setState(() {
      final key = FloorCanvas.keyOf(table);
      _tables = _tables.where((t) => FloorCanvas.keyOf(t) != key).toList();
      if (table.id != null) _deletedTables.add(table.id!);
      _selectedKey = null;
      _dirty = true;
    });
  }

  Future<void> _addZone() async {
    final name = await _askText(context, title: 'Nowa strefa', label: 'Nazwa, na przykład „ogródek”');
    if (name == null) return;
    if (_zones.any((z) => z.name.toLowerCase() == name.toLowerCase())) {
      if (mounted) showMessage(context, 'Strefa o tej nazwie już istnieje.');
      return;
    }
    setState(() {
      _zones = [
        ..._zones,
        FloorZone(id: null, name: name, widthCm: 800, heightCm: 500, position: _zones.length),
      ];
      _zoneName = name;
      _dirty = true;
    });
  }

  void _updateZone(FloorZone zone, FloorZone updated) {
    setState(() {
      _zones = [for (final z in _zones) if (z == zone) updated else z];
      if (updated.name != zone.name) {
        _tables = [
          for (final t in _tables) t.zone == zone.name ? t.copyWith(zone: updated.name) : t,
        ];
        _zoneName = updated.name;
      }
      _dirty = true;
    });
  }

  Future<void> _deleteZone(FloorZone zone) async {
    if (_tables.any((t) => t.zone == zone.name)) {
      showMessage(context, 'Najpierw usuń albo przenieś stoliki z tej strefy.');
      return;
    }
    final ok = await confirm(
      context,
      title: 'Usunąć strefę „${zone.name}”?',
      message: 'Strefa jest pusta.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    setState(() {
      _zones = _zones.where((z) => z != zone).toList();
      if (zone.id != null) _deletedZones.add(zone.id!);
      _zoneName = null;
      _dirty = true;
    });
  }

  Future<void> _save(String restaurantId) async {
    final labels = <String>{};
    for (final t in _tables) {
      if (!labels.add(t.label.trim().toLowerCase())) {
        showMessage(context, 'Numer stolika ${t.label} się powtarza. Każdy stolik potrzebuje innego numeru.');
        return;
      }
    }
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider).saveFloor(
        restaurantId: restaurantId,
        zones: _zones,
        deletedZoneIds: _deletedZones,
        tables: _tables,
        deletedTableIds: _deletedTables,
      );
      ref
        ..invalidate(zonesProvider(restaurantId))
        ..invalidate(tablesProvider(restaurantId));
      if (!mounted) return;
      setState(() {
        _mode = _Mode.live;
        _dirty = false;
        _selectedKey = null;
      });
      showMessage(context, 'Układ sali zapisany.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
      // Część zmian mogła się zapisać, więc odświeżamy dane z bazy.
      ref
        ..invalidate(zonesProvider(restaurantId))
        ..invalidate(tablesProvider(restaurantId));
    } finally {
      if (mounted) setState(() => _saving = false);
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
          PageHeader(title: 'Plan sali'),
          Expanded(child: ProGate(feature: 'Plan sali')),
        ],
      );
    }

    final zonesAsync = ref.watch(zonesProvider(restaurant.id));
    final tablesAsync = ref.watch(tablesProvider(restaurant.id));
    final today = dateOnly(_now);
    final reservations =
        ref.watch(reservationsProvider((restaurantId: restaurant.id, day: today))).value ??
        const <PanelReservation>[];

    if (zonesAsync.hasError || tablesAsync.hasError) {
      return ErrorView(
        error: zonesAsync.error ?? tablesAsync.error!,
        onRetry: () => ref
          ..invalidate(zonesProvider(restaurant.id))
          ..invalidate(tablesProvider(restaurant.id)),
      );
    }
    if (!zonesAsync.hasValue || !tablesAsync.hasValue) return const LoadingView();

    final editing = _mode == _Mode.edit;
    final zones = editing ? _zones : zonesAsync.value!;
    final tables = editing ? _tables : tablesAsync.value!;

    // Stoliki ze strefą, której nie ma w tabeli stref, pokazujemy w strefie o domyślnych wymiarach.
    final zoneList = [...zones];
    for (final t in tables) {
      if (!zoneList.any((z) => z.name == t.zone)) {
        zoneList.add(FloorZone(id: null, name: t.zone, widthCm: 1000, heightCm: 700, position: zoneList.length));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Plan sali',
          subtitle: editing
              ? 'Przeciągnij stolik, żeby go przesunąć. Pozycja przyciąga się co 10 cm.'
              : 'Zajętość stolików ${_minuteOfDay == null ? 'teraz' : 'dziś o ${Fmt.time(_viewTime)}'}. Odświeża się sama.',
          actions: [
            if (!editing && restaurant.canManage)
              OutlinedButton.icon(
                onPressed: () => _startEditing(zonesAsync.value!, tablesAsync.value!),
                icon: const Glyph(AppIcons.pencil, size: 16),
                label: const Text('Edytuj układ'),
              ),
            if (editing) ...[
              TextButton(
                onPressed: _saving ? null : _stopEditing,
                style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                child: const Text('Anuluj'),
              ),
              FilledButton(
                onPressed: _saving || !_dirty ? null : () => _save(restaurant.id),
                child: const Text('Zapisz układ'),
              ),
            ],
          ],
          below: Row(
            children: [
              if (zoneList.isNotEmpty)
                SegmentedTabs<String>(
                  options: [for (final z in zoneList) (z.name, Fmt.capitalize(z.name))],
                  selected: _currentZone(zoneList).name,
                  onChanged: (n) => setState(() {
                    _zoneName = n;
                    _selectedKey = null;
                  }),
                ),
              if (editing) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _addZone,
                  icon: const Glyph(AppIcons.plus, size: 16),
                  label: const Text('Strefa'),
                ),
              ],
              const Spacer(),
              if (!editing) _TimeControl(
                minuteOfDay: _minuteOfDay,
                onChanged: (m) => setState(() => _minuteOfDay = m),
              ),
              if (editing && zoneList.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => _addTable(_currentZone(zoneList)),
                  icon: const Glyph(AppIcons.plus, size: 16),
                  label: const Text('Dodaj stolik'),
                ),
            ],
          ),
        ),
        Expanded(
          child: zoneList.isEmpty
              ? MessageView(
                  icon: AppIcons.squaresFour,
                  title: 'Sala jest pusta',
                  message: restaurant.canManage
                      ? 'Dodaj strefę, na przykład „sala”, a potem rozstaw w niej stoliki.'
                      : 'Kierownik lokalu jeszcze nie narysował sali.',
                  actionLabel: restaurant.canManage ? 'Edytuj układ' : null,
                  onAction: restaurant.canManage
                      ? () => _startEditing(zonesAsync.value!, tablesAsync.value!)
                      : null,
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _canvas(zoneList, tables, reservations, editing)),
                      const SizedBox(width: 20),
                      SizedBox(
                        width: 340,
                        child: editing
                            ? _inspector(_currentZone(zoneList), tables)
                            : _livePanel(tables, reservations),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  FloorZone _currentZone(List<FloorZone> zones) =>
      zones.firstWhere((z) => z.name == _zoneName, orElse: () => zones.first);

  Widget _canvas(
    List<FloorZone> zones,
    List<DiningTable> tables,
    List<PanelReservation> reservations,
    bool editing,
  ) {
    final zone = _currentZone(zones);
    final inZone = tables.where((t) => t.zone == zone.name).toList();
    final overlapping = <String>{};
    if (editing) {
      for (var i = 0; i < inZone.length; i++) {
        for (var j = i + 1; j < inZone.length; j++) {
          if (tablesOverlap(inZone[i], inZone[j])) {
            overlapping
              ..add(FloorCanvas.keyOf(inZone[i]))
              ..add(FloorCanvas.keyOf(inZone[j]));
          }
        }
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FloorCanvas(
          zone: zone,
          tables: inZone,
          selectedId: _selectedKey,
          onTapTable: (t) => setState(() => _selectedKey = FloorCanvas.keyOf(t)),
          onTapEmpty: () => setState(() => _selectedKey = null),
          lookOf: (t) => editing
              ? _editLook(t, overlapping.contains(FloorCanvas.keyOf(t)))
              : _liveLook(t, reservations),
          onDragTable: editing
              ? (t, d) => _update(t, (x) => x.copyWith(
                    xCm: (x.xCm + d.dx).round().clamp(0, zone.widthCm),
                    yCm: (x.yCm + d.dy).round().clamp(0, zone.heightCm),
                  ))
              : null,
          onDragEnd: editing
              ? (t) => _update(t, (x) => x.copyWith(
                    xCm: ((x.xCm / 10).round() * 10).clamp(0, zone.widthCm),
                    yCm: ((x.yCm / 10).round() * 10).clamp(0, zone.heightCm),
                  ))
              : null,
        ),
      ),
    );
  }

  TableLook _editLook(DiningTable t, bool overlaps) {
    return TableLook(
      fill: overlaps ? AppColors.error.withValues(alpha: 0.12) : AppColors.surfaceRaised,
      stroke: overlaps ? AppColors.error : AppColors.ringStrong,
      caption: '${t.seats} os.',
      captionColor: overlaps ? AppColors.error : null,
      dimmed: !t.active,
    );
  }

  /// Rezerwacja, która w danej chwili zajmuje stolik, i najbliższa kolejna.
  (PanelReservation?, PanelReservation?) _stateOf(DiningTable t, List<PanelReservation> all) {
    final at = _viewTime;
    PanelReservation? current;
    PanelReservation? next;
    for (final r in all) {
      if (!r.status.isActive || !r.tableIds.contains(t.id)) continue;
      final seatedEarly = r.status == ReservationStatus.seated && _minuteOfDay == null;
      if ((!r.startsAt.isAfter(at) || seatedEarly) && r.endsAt.isAfter(at)) {
        current = r;
      } else if (r.startsAt.isAfter(at) && (next == null || r.startsAt.isBefore(next.startsAt))) {
        next = r;
      }
    }
    return (current, next);
  }

  TableLook _liveLook(DiningTable t, List<PanelReservation> reservations) {
    if (!t.active) {
      return TableLook(
        fill: AppColors.surface,
        stroke: AppColors.ring,
        caption: 'wyłączony',
        dimmed: true,
      );
    }
    final (current, next) = _stateOf(t, reservations);
    if (current != null) {
      final seated = current.status == ReservationStatus.seated;
      return TableLook(
        fill: seated ? AppColors.accentTint : AppColors.warning.withValues(alpha: 0.14),
        stroke: seated ? AppColors.accent : AppColors.warning,
        strokeWidth: 2,
        caption: '${seated ? 'do' : 'od'} ${Fmt.time(seated ? current.endsAt : current.startsAt)} · ${_surname(current.guestName)}',
        captionColor: seated ? AppColors.accent : AppColors.warning,
      );
    }
    final soon = next != null && next.startsAt.difference(_viewTime).inMinutes <= 90;
    return TableLook(
      fill: AppColors.surface,
      stroke: soon ? AppColors.warning : AppColors.ringStrong,
      caption: next == null ? '${t.seats} os. · wolny' : 'wolny do ${Fmt.time(next.startsAt)}',
    );
  }

  String _surname(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.length > 1 ? parts.last : parts.first;
  }

  Widget _livePanel(List<DiningTable> tables, List<PanelReservation> reservations) {
    final text = Theme.of(context).textTheme;
    DiningTable? table;
    for (final t in tables) {
      if (FloorCanvas.keyOf(t) == _selectedKey) table = t;
    }

    if (table == null) {
      final active = tables.where((t) => t.active).toList();
      var busy = 0;
      var seats = 0;
      for (final t in active) {
        seats += t.seats;
        if (_stateOf(t, reservations).$1 != null) busy++;
      }
      return PanelCard(
        title: 'Sala ${_minuteOfDay == null ? 'teraz' : 'o ${Fmt.time(_viewTime)}'}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: StatTile(label: 'Zajęte stoliki', value: '$busy', accent: busy > 0)),
                const SizedBox(width: 10),
                Expanded(child: StatTile(label: 'Wolne', value: '${active.length - busy}')),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Miejsc przy wszystkich stolikach: $seats.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
            ),
            const SizedBox(height: 18),
            const _Legend(),
            const SizedBox(height: 18),
            Text(
              'Kliknij stolik, żeby zobaczyć jego rezerwacje na dziś.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    final forTable = reservations.where((r) => r.tableIds.contains(table!.id)).toList();
    return PanelCard(
      title: 'Stolik ${table.label}',
      trailing: IconButton(
        tooltip: 'Zamknij',
        icon: const Glyph(AppIcons.close, size: 16),
        onPressed: () => setState(() => _selectedKey = null),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${table.seats} miejsc · ${table.widthCm}×${table.heightCm} cm · ${table.zone}'
            '${table.joinGroup == null ? '' : ' · łączenie: ${table.joinGroup}'}',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
          ),
          const SizedBox(height: 16),
          Text('Dziś', style: text.titleSmall),
          const SizedBox(height: 8),
          if (forTable.isEmpty)
            Text('Brak rezerwacji na ten stolik.', style: text.bodyMedium?.copyWith(color: AppColors.textMuted))
          else
            for (final r in forTable)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        '${Fmt.time(r.startsAt)}–${Fmt.time(r.endsAt)}',
                        style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.guestName, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelLarge),
                          Text(
                            [Fmt.people(r.partySize), if (r.occasion != null) r.occasion!.label].join(' · '),
                            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(status: r.status),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _inspector(FloorZone zone, List<DiningTable> tables) {
    DiningTable? table;
    for (final t in tables) {
      if (FloorCanvas.keyOf(t) == _selectedKey) table = t;
    }
    if (table == null) {
      return _ZoneInspector(
        key: ValueKey('strefa-${zone.name}'),
        zone: zone,
        tableCount: tables.where((t) => t.zone == zone.name).length,
        onChanged: (updated) => _updateZone(zone, updated),
        onDelete: () => _deleteZone(zone),
      );
    }
    return _TableInspector(
      key: ValueKey('stolik-${FloorCanvas.keyOf(table)}'),
      table: table,
      zones: _zones.map((z) => z.name).toList(),
      onChanged: (change) => _update(table!, change),
      onDelete: () => _deleteTable(table!),
      onClose: () => setState(() => _selectedKey = null),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget item(Color fill, Color stroke, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 12,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: stroke, width: 1.5),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: text.bodySmall),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        item(AppColors.accentTint, AppColors.accent, 'Goście przy stoliku'),
        item(AppColors.warning.withValues(alpha: 0.14), AppColors.warning, 'Zarezerwowany na tę godzinę'),
        item(AppColors.surface, AppColors.warning, 'Wolny, rezerwacja w ciągu 90 minut'),
        item(AppColors.surface, AppColors.ringStrong, 'Wolny'),
      ],
    );
  }
}

class _TimeControl extends StatelessWidget {
  const _TimeControl({required this.minuteOfDay, required this.onChanged});

  final int? minuteOfDay;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final value = (minuteOfDay ?? (DateTime.now().hour * 60 + DateTime.now().minute)).clamp(600, 1425);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedTabs<bool>(
          options: const [(true, 'Teraz'), (false, 'Inna godzina')],
          selected: minuteOfDay == null,
          onChanged: (now) => onChanged(now ? null : value),
        ),
        if (minuteOfDay != null) ...[
          SizedBox(
            width: 240,
            child: Slider(
              value: value.toDouble(),
              min: 600,
              max: 1425,
              divisions: (1425 - 600) ~/ 15,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          Text(
            '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}',
            style: text.titleSmall?.copyWith(fontFeatures: _tabular),
          ),
        ],
      ],
    );
  }
}

class _ZoneInspector extends StatefulWidget {
  const _ZoneInspector({
    super.key,
    required this.zone,
    required this.tableCount,
    required this.onChanged,
    required this.onDelete,
  });

  final FloorZone zone;
  final int tableCount;
  final ValueChanged<FloorZone> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ZoneInspector> createState() => _ZoneInspectorState();
}

class _ZoneInspectorState extends State<_ZoneInspector> {
  late final _name = TextEditingController(text: widget.zone.name);
  late final _width = TextEditingController(text: '${widget.zone.widthCm}');
  late final _height = TextEditingController(text: '${widget.zone.heightCm}');

  @override
  void dispose() {
    _name.dispose();
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _apply() {
    final w = parseInt(_width.text);
    final h = parseInt(_height.text);
    final name = _name.text.trim();
    if (name.isEmpty || w == null || h == null || w < 200 || h < 200 || w > 10000 || h > 10000) {
      showMessage(context, 'Podaj nazwę i wymiary strefy od 200 do 10 000 cm.');
      return;
    }
    widget.onChanged(widget.zone.copyWith(name: name, widthCm: w, heightCm: h));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PanelCard(
      title: 'Strefa',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nazwa strefy'),
            onSubmitted: (_) => _apply(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _NumberField(controller: _width, label: 'Szerokość', suffix: 'cm', onSubmitted: _apply)),
              const SizedBox(width: 10),
              Expanded(child: _NumberField(controller: _height, label: 'Głębokość', suffix: 'cm', onSubmitted: _apply)),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _apply, child: const Text('Zastosuj')),
          const SizedBox(height: 18),
          Text(
            'Stolików w strefie: ${widget.tableCount}. Kliknij stolik na planie, żeby zmienić jego wymiary, liczbę miejsc i obrót.',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: widget.onDelete,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Usuń strefę'),
          ),
        ],
      ),
    );
  }
}

class _TableInspector extends StatefulWidget {
  const _TableInspector({
    super.key,
    required this.table,
    required this.zones,
    required this.onChanged,
    required this.onDelete,
    required this.onClose,
  });

  final DiningTable table;
  final List<String> zones;
  final ValueChanged<DiningTable Function(DiningTable)> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  State<_TableInspector> createState() => _TableInspectorState();
}

class _TableInspectorState extends State<_TableInspector> {
  late final _label = TextEditingController(text: widget.table.label);
  late final _width = TextEditingController(text: '${widget.table.widthCm}');
  late final _height = TextEditingController(text: '${widget.table.heightCm}');
  late final _group = TextEditingController(text: widget.table.joinGroup ?? '');

  @override
  void didUpdateWidget(covariant _TableInspector old) {
    super.didUpdateWidget(old);
    // Po przeciągnięciu albo obrocie wymiary się nie zmieniają, ale po zamianie
    // szerokości z głębokością pola muszą pokazać nowe wartości.
    if (old.table.widthCm != widget.table.widthCm) _width.text = '${widget.table.widthCm}';
    if (old.table.heightCm != widget.table.heightCm) _height.text = '${widget.table.heightCm}';
  }

  @override
  void dispose() {
    _label.dispose();
    _width.dispose();
    _height.dispose();
    _group.dispose();
    super.dispose();
  }

  void _applySize() {
    final w = parseInt(_width.text);
    final h = parseInt(_height.text);
    if (w == null || h == null || w < 30 || h < 30 || w > 1000 || h > 1000) {
      showMessage(context, 'Wymiary blatu od 30 do 1000 cm.');
      return;
    }
    widget.onChanged((t) => t.copyWith(
      widthCm: w,
      heightCm: widget.table.shape == TableShape.round ? w : h,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.table;
    final text = Theme.of(context).textTheme;

    return Card(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(child: Text('Stolik', style: text.titleMedium)),
              IconButton(
                tooltip: 'Zamknij',
                icon: const Glyph(AppIcons.close, size: 16),
                onPressed: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _label,
                  maxLength: 8,
                  decoration: const InputDecoration(labelText: 'Numer', counterText: ''),
                  onChanged: (v) {
                    if (v.trim().isNotEmpty) widget.onChanged((x) => x.copyWith(label: v.trim()));
                  },
                ),
              ),
              const SizedBox(width: 10),
              _Stepper(
                label: 'Miejsca',
                value: t.seats,
                min: 1,
                max: 30,
                onChanged: (v) => widget.onChanged((x) => x.copyWith(seats: v)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SegmentedTabs<TableShape>(
            options: [for (final s in TableShape.values) (s, s.label)],
            selected: t.shape,
            onChanged: (s) {
              widget.onChanged(
                (x) => x.copyWith(
                  shape: s,
                  heightCm: s == TableShape.round ? x.widthCm : x.heightCm,
                ),
              );
              if (s == TableShape.round) _height.text = _width.text;
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: _width,
                  label: t.shape == TableShape.round ? 'Średnica' : 'Szerokość',
                  suffix: 'cm',
                  onSubmitted: _applySize,
                ),
              ),
              if (t.shape == TableShape.rect) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _NumberField(controller: _height, label: 'Głębokość', suffix: 'cm', onSubmitted: _applySize),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _applySize, child: const Text('Zastosuj wymiary')),
          ),
          const SizedBox(height: 6),
          if (t.shape == TableShape.rect)
            Row(
              children: [
                Text('Obrót', style: text.bodyMedium),
                const Spacer(),
                IconButton(
                  tooltip: 'Obróć o 15° w lewo',
                  icon: const Glyph(AppIcons.undo, size: 16),
                  onPressed: () => widget.onChanged((x) => x.copyWith(rotation: (x.rotation - 15) % 360)),
                ),
                SizedBox(
                  width: 44,
                  child: Text('${t.rotation}°', textAlign: TextAlign.center, style: text.labelLarge?.copyWith(fontFeatures: _tabular)),
                ),
                IconButton(
                  tooltip: 'Obróć o 15° w prawo',
                  icon: const Glyph(AppIcons.refresh, size: 16),
                  onPressed: () => widget.onChanged((x) => x.copyWith(rotation: (x.rotation + 15) % 360)),
                ),
              ],
            ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: widget.zones.contains(t.zone) ? t.zone : null,
            decoration: const InputDecoration(labelText: 'Strefa'),
            items: [for (final z in widget.zones) DropdownMenuItem(value: z, child: Text(Fmt.capitalize(z)))],
            onChanged: (z) {
              if (z != null) widget.onChanged((x) => x.copyWith(zone: z));
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _group,
            maxLength: 20,
            decoration: const InputDecoration(
              labelText: 'Grupa łączenia (opcjonalnie)',
              helperText: 'Stoliki z tą samą grupą system może zestawić dla większej rezerwacji.',
              helperMaxLines: 2,
              counterText: '',
            ),
            onChanged: (v) => widget.onChanged(
              (x) => v.trim().isEmpty ? x.copyWith(clearJoinGroup: true) : x.copyWith(joinGroup: v.trim()),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pierwszeństwo przy doborze', style: text.bodyMedium),
                    Text(
                      'Wyższe wybierane wcześniej przy tej samej liczbie miejsc',
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              _Stepper(
                value: t.priority,
                min: 0,
                max: 9,
                onChanged: (v) => widget.onChanged((x) => x.copyWith(priority: v)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Przyjmuje rezerwacje', style: text.bodyMedium),
                    Text(
                      'Wyłączony stolik zostaje na planie, ale system go nie dobiera',
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Switch(
                value: t.active,
                onChanged: (v) => widget.onChanged((x) => x.copyWith(active: v)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextButton(
            onPressed: widget.onDelete,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Usuń stolik'),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
      style: const TextStyle(fontFeatures: _tabular),
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.label,
  });

  final String? label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Text(label!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Mniej',
              icon: const Glyph(AppIcons.minus, size: 14),
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 28,
              child: Text('$value', textAlign: TextAlign.center, style: text.titleSmall?.copyWith(fontFeatures: _tabular)),
            ),
            IconButton(
              tooltip: 'Więcej',
              icon: const Glyph(AppIcons.plus, size: 14),
              onPressed: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

Future<String?> _askText(BuildContext context, {required String title, required String label}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: () {
            final v = controller.text.trim();
            if (v.isNotEmpty) Navigator.pop(context, v);
          },
          child: const Text('Dodaj'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

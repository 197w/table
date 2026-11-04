import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/notes_view.dart';
import '../../shared/panel_widgets.dart';
import '../../shared/side_panel.dart';
import 'vehicle_days.dart';

/// Wpisywane litery od razu zamieniają się na wielkie (rejestracja, VIN), jak przy włączonym Caps Locku.
class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

AppIconData vehicleIcon(VehicleKind kind) => switch (kind) {
  VehicleKind.car => AppIcons.car,
  VehicleKind.scooter => AppIcons.moped,
  VehicleKind.bike => AppIcons.bicycle,
  VehicleKind.other => AppIcons.van,
};

Color _kindColor(VehicleKind kind) => switch (kind) {
  VehicleKind.car => TileColors.blue,
  VehicleKind.scooter => TileColors.green,
  VehicleKind.bike => TileColors.amber,
  VehicleKind.other => TileColors.violet,
};

const _tabular = [FontFeature.tabularFigures()];

/// Stałe szerokości wąskich kolumn tabeli pojazdów; pojazd i notatka dzielą resztę.
const _plateWidth = 132.0;
const _vinWidth = 200.0;
const _courierWidth = 180.0;
const _checksWidth = 48.0;

/// Flota (`/flota`, uprawnienie `fleet`) w układzie jak Pracownicy (4.11.2026, prośba użytkownika: lista zamiast
/// kafli): po lewej zwijany panel z wyszukiwaniem (nazwa, rejestracja, VIN, dzisiejszy dostawca), „Dodaj pojazd”
/// i filtrami z liczbą pojazdów (rodzaj, stan, dziś), po prawej tabela: pojazd, rejestracja, VIN, kto nim jeździ
/// dziś, ostatnia notatka i przebieg ze zdjęciami. Kliknięty wiersz otwiera okno pojazdu (zmiana i notatki,
/// tylko z uprawnieniem „Flota”).
class FleetScreen extends ConsumerStatefulWidget {
  const FleetScreen({super.key});

  @override
  ConsumerState<FleetScreen> createState() => _FleetScreenState();
}

class _FleetScreenState extends ConsumerState<FleetScreen> {
  final _search = TextEditingController();
  final _kinds = <VehicleKind>{};
  final _states = <String>{};
  final _today = <String>{};
  final _closed = <String>{};
  bool _panelOpen = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _edit(String restaurantId, [Vehicle? vehicle]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _VehicleDialog(restaurantId: restaurantId, vehicle: vehicle),
    );
    if (saved == true) ref.invalidate(vehiclesProvider(restaurantId));
    ref.invalidate(vehicleNotesProvider(restaurantId));
  }

  void _toggle<T>(Set<T> set, T value) => setState(() => set.contains(value) ? set.remove(value) : set.add(value));

  static String _state(Vehicle v) => v.active ? 'active' : 'inactive';

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final canEdit = ref.watch(memberPermissionsProvider).contains('fleet');
    final async = ref.watch(vehiclesProvider(restaurant.id));
    final staff = ref.watch(staffProvider(restaurant.id)).value ?? const <StaffMember>[];
    final names = {for (final m in staff) m.id: m.name};
    // Kto jeździ autem dziś (Grafik, Dostawy albo wybór dostawcy przy kontroli auta).
    final today = {
      for (final d in ref.watch(todayVehicleDaysProvider(restaurant.id)).value ?? const <VehicleDay>[])
        d.vehicleId: names[d.memberId],
    };
    final notes = ref.watch(vehicleNotesProvider(restaurant.id)).value ?? const <String, List<Note>>{};
    final all = async.value ?? const <Vehicle>[];
    String todayKey(Vehicle v) => today[v.id] == null ? 'free' : 'driven';

    final query = _search.text.trim().toLowerCase();
    final vehicles = [
      for (final v in all)
        if ((_kinds.isEmpty || _kinds.contains(v.kind)) &&
            (_states.isEmpty || _states.contains(_state(v))) &&
            (_today.isEmpty || _today.contains(todayKey(v))) &&
            (query.isEmpty ||
                [v.name, ?v.plate, ?v.vin, ?today[v.id]].any((t) => t.toLowerCase().contains(query)) ||
                (v.plate ?? '').replaceAll(' ', '').toLowerCase().contains(query.replaceAll(' ', ''))))
          v,
    ];

    final panel = SidePanel(
      header: const PanelTitle(icon: AppIcons.car, title: 'Flota'),
      search: _search,
      searchHint: 'Szukaj pojazdu',
      onSearch: () => setState(() {}),
      actions: [if (canEdit) PanelAction(label: 'Dodaj pojazd', onTap: () => _edit(restaurant.id))],
      children: [
        FilterSection(
          title: 'Rodzaj',
          first: true,
          open: !_closed.contains('kind'),
          onToggle: () => _toggle(_closed, 'kind'),
          options: [
            for (final k in VehicleKind.values)
              (
                label: k.label,
                count: all.where((v) => v.kind == k).length,
                checked: _kinds.contains(k),
                onChanged: (_) => _toggle(_kinds, k),
                dot: _kindColor(k),
              ),
          ],
        ),
        FilterSection(
          title: 'Stan',
          open: !_closed.contains('state'),
          onToggle: () => _toggle(_closed, 'state'),
          options: [
            for (final (key, label) in const [('active', 'W użyciu'), ('inactive', 'Nieużywane')])
              (
                label: label,
                count: all.where((v) => _state(v) == key).length,
                checked: _states.contains(key),
                onChanged: (_) => _toggle(_states, key),
                dot: null,
              ),
          ],
        ),
        FilterSection(
          title: 'Dziś',
          open: !_closed.contains('today'),
          onToggle: () => _toggle(_closed, 'today'),
          options: [
            for (final (key, label) in const [('driven', 'Z dostawcą'), ('free', 'Bez dostawcy')])
              (
                label: label,
                count: all.where((v) => todayKey(v) == key).length,
                checked: _today.contains(key),
                onChanged: (_) => _toggle(_today, key),
                dot: key == 'driven' ? AppColors.accent : null,
              ),
          ],
        ),
      ],
    );

    final content = async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(vehiclesProvider(restaurant.id))),
      data: (_) => all.isEmpty
          ? MessageView(
              icon: AppIcons.car,
              title: 'Brak pojazdów',
              message: 'Dodaj auto, skuter albo rower. Dostawcę wybiera się na dany dzień w Grafiku albo Dostawach.',
              actionLabel: canEdit ? 'Dodaj pojazd' : null,
              onAction: canEdit ? () => _edit(restaurant.id) : null,
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 32, 16),
              child: _VehicleTable(
                vehicles: vehicles,
                today: today,
                notes: notes,
                onOpen: canEdit ? (v) => _edit(restaurant.id, v) : null,
                onChecks: (v) => showDialog<void>(
                  context: context,
                  builder: (_) => VehicleChecksDialog(restaurantId: restaurant.id, vehicle: v),
                ),
              ),
            ),
    );

    return SidePanelLayout(
      open: _panelOpen,
      onToggle: () => setState(() => _panelOpen = !_panelOpen),
      panel: panel,
      content: content,
    );
  }
}

/// Pojazdy jako tabela jak Zespół w Pracownikach.
class _VehicleTable extends StatelessWidget {
  const _VehicleTable({
    required this.vehicles,
    required this.today,
    required this.notes,
    required this.onOpen,
    required this.onChecks,
  });

  final List<Vehicle> vehicles;

  /// Kto jeździ danym pojazdem dziś.
  final Map<String, String?> today;

  /// Notatki od najnowszej.
  final Map<String, List<Note>> notes;
  final ValueChanged<Vehicle>? onOpen;
  final ValueChanged<Vehicle> onChecks;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                tableHead(context, 'Pojazd', 3),
                tableHead(context, 'Rejestracja', 0, width: _plateWidth),
                tableHead(context, 'VIN', 0, width: _vinWidth),
                tableHead(context, 'Dziś', 0, width: _courierWidth),
                tableHead(context, 'Notatka', 3),
                const SizedBox(width: _checksWidth),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.ring),
        Expanded(
          child: vehicles.isEmpty
              ? Center(
                  child: Text(
                    'Nic nie znaleziono. Zmień wyszukiwanie albo filtry po lewej.',
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                )
              : ListView.separated(
                  itemCount: vehicles.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.ring),
                  itemBuilder: (context, i) {
                    final v = vehicles[i];
                    return _VehicleRow(
                      vehicle: v,
                      courier: today[v.id],
                      notes: notes[v.id] ?? const [],
                      onTap: onOpen == null ? null : () => onOpen!(v),
                      onChecks: () => onChecks(v),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _VehicleRow extends StatelessWidget {
  const _VehicleRow({
    required this.vehicle,
    required this.courier,
    required this.notes,
    required this.onTap,
    required this.onChecks,
  });

  final Vehicle vehicle;
  final String? courier;
  final List<Note> notes;
  final VoidCallback? onTap;
  final VoidCallback onChecks;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final v = vehicle;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final note = notes.firstOrNull;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
                      Tooltip(
                        message: v.kind.label,
                        child: Glyph(
                          vehicleIcon(v.kind),
                          size: 18,
                          color: v.active ? _kindColor(v.kind) : AppColors.textDisabled,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          v.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            color: v.active ? AppColors.text : AppColors.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (!v.active) ...[const SizedBox(width: 8), const RowBadge('Nieużywany')],
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
                SizedBox(
                  width: _plateWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: v.plate == null
                        ? Text('—', style: muted)
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceRaised,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.ringStrong),
                            ),
                            child: Text(
                              v.plate!,
                              style: text.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                                fontFeatures: _tabular,
                              ),
                            ),
                          ),
                  ),
                ),
                SizedBox(
                  width: _vinWidth,
                  child: Text(
                    v.vin ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted?.copyWith(letterSpacing: 0.5),
                  ),
                ),
                // Dostawca na dziś: zielona kropka jak „Na zmianie” w Pracownikach.
                SizedBox(
                  width: _courierWidth,
                  child: courier == null
                      ? Text('—', style: muted)
                      : Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                courier!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                ),
                Expanded(
                  flex: 3,
                  child: note == null
                      ? Text('—', style: muted)
                      : Tooltip(
                          message: note.body,
                          waitDuration: const Duration(milliseconds: 600),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  note.body,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodyMedium,
                                ),
                              ),
                              if (notes.length > 1) ...[
                                const SizedBox(width: 8),
                                Text('+${notes.length - 1}', style: muted),
                              ],
                            ],
                          ),
                        ),
                ),
                SizedBox(
                  width: _checksWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Przebieg i zdjęcia',
                      onPressed: onChecks,
                      icon: const Glyph(AppIcons.camera, size: 18),
                    ),
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

/// Nowy pojazd albo zmiana istniejącego: rodzaj, nazwa, rejestracja i czy jest używany. Dostawcę ma się na dany
/// dzień (Grafik, Dostawy), nie na stałe.
/// Istniejący pojazd ma obok notatki (dopisują się od razu, bez „Zapisz”).
class _VehicleDialog extends ConsumerStatefulWidget {
  const _VehicleDialog({required this.restaurantId, this.vehicle});

  final String restaurantId;
  final Vehicle? vehicle;

  @override
  ConsumerState<_VehicleDialog> createState() => _VehicleDialogState();
}

class _VehicleDialogState extends ConsumerState<_VehicleDialog> {
  late VehicleKind _kind = widget.vehicle?.kind ?? VehicleKind.car;
  late final _name = TextEditingController(text: widget.vehicle?.name ?? '');
  late final _plate = TextEditingController(text: widget.vehicle?.plate ?? '');
  late final _vin = TextEditingController(text: widget.vehicle?.vin ?? '');
  late bool _active = widget.vehicle?.active ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    _vin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showMessage(context, 'Wpisz nazwę pojazdu, na przykład „Fiat Panda”.', tone: ToastTone.warning);
      return;
    }
    final vin = _vin.text.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (_kind != VehicleKind.bike && vin.isNotEmpty && !RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(vin)) {
      showMessage(context, 'VIN ma 17 znaków: litery i cyfry, bez I, O i Q.', tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .saveVehicle(
            restaurantId: widget.restaurantId,
            id: widget.vehicle?.id,
            kind: _kind,
            name: _name.text.trim(),
            plate: _kind == VehicleKind.bike || _plate.text.trim().isEmpty ? null : _plate.text.trim(),
            vin: _kind == VehicleKind.bike || vin.isEmpty ? null : vin,
            active: _active,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final v = widget.vehicle;
    if (v == null) return;
    final ok = await confirm(
      context,
      title: 'Usunąć pojazd?',
      message: '${v.name}${v.plate == null ? '' : ' (${v.plate})'} zniknie z floty.',
      action: 'Usuń',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).deleteVehicle(v.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    final form = SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconTabs<VehicleKind>(
              options: [for (final k in VehicleKind.values) (k, vehicleIcon(k), k.label)],
              selected: _kind,
              onChanged: (k) => setState(() => _kind = k),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: widget.vehicle == null,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Nazwa', hintText: 'Na przykład Fiat Panda', counterText: ''),
          ),
          if (_kind != VehicleKind.bike) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _plate,
              maxLength: 15,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [UpperCaseFormatter()],
              decoration: const InputDecoration(labelText: 'Rejestracja', hintText: 'BI 12345', counterText: ''),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _vin,
              maxLength: 17,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')), UpperCaseFormatter()],
              style: const TextStyle(letterSpacing: 1, fontFeatures: [FontFeature.tabularFigures()]),
              decoration: const InputDecoration(labelText: 'VIN', hintText: '17 znaków, z dowodu rejestracyjnego'),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('Pojazd w użyciu', style: Theme.of(context).textTheme.titleSmall)),
              Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
            ],
          ),
        ],
      ),
    );

    return AlertDialog(
      title: Text(vehicle == null ? 'Nowy pojazd' : 'Pojazd'),
      content: vehicle == null
          ? form
          : SizedBox(
              height: 470,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(child: form),
                  const SizedBox(width: 24),
                  VerticalDivider(width: 1, color: AppColors.ring),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 340,
                    child: _VehicleNotes(restaurantId: widget.restaurantId, vehicleId: vehicle.id),
                  ),
                ],
              ),
            ),
      actions: [
        if (widget.vehicle != null)
          TextButton(
            onPressed: _busy ? null : _delete,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Usuń'),
          ),
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

/// Notatki o pojeździe w oknie pojazdu, od najnowszej.
class _VehicleNotes extends ConsumerWidget {
  const _VehicleNotes({required this.restaurantId, required this.vehicleId});

  final String restaurantId;
  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(vehicleNotesProvider(restaurantId)).whenData((all) => all[vehicleId] ?? const <Note>[]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Notatki', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        Expanded(
          child: NotesView(
            notes: notes,
            hint: 'Na przykład przegląd w marcu',
            onAdd: (body) async {
              await ref
                  .read(repositoryProvider)
                  .addVehicleNote(vehicleId, body, memberId: ref.read(panelMemberProvider)?.dbMemberId);
              ref.invalidate(vehicleNotesProvider(restaurantId));
            },
            onDelete: (note) async {
              await ref.read(repositoryProvider).deleteVehicleNote(note.id);
              ref.invalidate(vehicleNotesProvider(restaurantId));
            },
          ),
        ),
      ],
    );
  }
}

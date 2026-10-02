import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

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

/// Flota: pojazdy dostawców (auto, skuter, rower), rejestracja i kto nim jeździ.
/// Zmiany tylko z uprawnieniem „Flota”.
class FleetScreen extends ConsumerWidget {
  const FleetScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, String restaurantId, [Vehicle? vehicle]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _VehicleDialog(restaurantId: restaurantId, vehicle: vehicle),
    );
    if (saved == true) ref.invalidate(vehiclesProvider(restaurantId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final canEdit = ref.watch(memberPermissionsProvider).contains('fleet');
    final async = ref.watch(vehiclesProvider(restaurant.id));
    final staff = ref.watch(staffProvider(restaurant.id)).value ?? const <StaffMember>[];
    final names = {for (final m in staff) m.id: m.name};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          actions: [
            if (canEdit)
              FilledButton.icon(
                onPressed: () => _edit(context, ref, restaurant.id),
                icon: const Glyph(AppIcons.plus, size: 18),
                label: const Text('Dodaj pojazd'),
              ),
          ],
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(vehiclesProvider(restaurant.id))),
            data: (vehicles) => vehicles.isEmpty
                ? MessageView(
                    icon: AppIcons.car,
                    title: 'Brak pojazdów',
                    message: 'Dodaj auto, skuter albo rower i przypisz go dostawcy.',
                    actionLabel: canEdit ? 'Dodaj pojazd' : null,
                    onAction: canEdit ? () => _edit(context, ref, restaurant.id) : null,
                  )
                : LayoutBuilder(
                    builder: (context, box) {
                      const gap = 16.0;
                      final columns = ((box.maxWidth - 64 + gap) / (320 + gap)).floor().clamp(1, 6);
                      final width = (box.maxWidth - 64 - gap * (columns - 1)) / columns;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                        child: Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final v in vehicles)
                              SizedBox(
                                width: width,
                                child: _VehicleCard(
                                  vehicle: v,
                                  courier: v.memberId == null ? null : names[v.memberId],
                                  onTap: canEdit ? () => _edit(context, ref, restaurant.id, v) : null,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({required this.vehicle, required this.courier, required this.onTap});

  final Vehicle vehicle;
  final String? courier;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final v = vehicle;
    return PanelPress(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Opacity(
            opacity: v.active ? 1 : 0.55,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconBadge(vehicleIcon(v.kind), color: _kindColor(v.kind), size: 40),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                            Text(
                              v.active ? v.kind.label : '${v.kind.label} · nieużywany',
                              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      if (v.plate != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceRaised,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.ringStrong),
                          ),
                          child: Text(
                            v.plate!,
                            style: text.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Glyph(AppIcons.users, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          courier ?? 'Bez dostawcy',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: courier == null ? AppColors.textMuted : AppColors.text),
                        ),
                      ),
                    ],
                  ),
                  if (v.vin != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'VIN ${v.vin}',
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        letterSpacing: 0.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (v.note != null) ...[
                    const SizedBox(height: 8),
                    Text(v.note!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nowy pojazd albo zmiana istniejącego: rodzaj, nazwa, rejestracja, dostawca, uwagi i czy jest używany.
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
  late final _note = TextEditingController(text: widget.vehicle?.note ?? '');
  late String? _memberId = widget.vehicle?.memberId;
  late bool _active = widget.vehicle?.active ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    _vin.dispose();
    _note.dispose();
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
      await ref.read(repositoryProvider).saveVehicle(
        restaurantId: widget.restaurantId,
        id: widget.vehicle?.id,
        kind: _kind,
        name: _name.text.trim(),
        plate: _kind == VehicleKind.bike || _plate.text.trim().isEmpty ? null : _plate.text.trim(),
        vin: _kind == VehicleKind.bike || vin.isEmpty ? null : vin,
        memberId: _memberId,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
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
    final staff = [
      for (final m in ref.watch(staffProvider(widget.restaurantId)).value ?? const <StaffMember>[])
        if (m.active || m.id == _memberId) m,
    ]..sort((a, b) => a.name.compareTo(b.name));

    return AlertDialog(
      title: Text(widget.vehicle == null ? 'Nowy pojazd' : 'Pojazd'),
      content: SizedBox(
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
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: staff.any((m) => m.id == _memberId) ? _memberId : null,
              decoration: const InputDecoration(labelText: 'Dostawca'),
              icon: const Glyph(AppIcons.caretDown, size: 16),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Bez dostawcy')),
                for (final m in staff) DropdownMenuItem<String?>(value: m.id, child: Text(m.name)),
              ],
              onChanged: (v) => setState(() => _memberId = v),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Uwagi', hintText: 'Na przykład przegląd w marcu', counterText: ''),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Pojazd w użyciu', style: Theme.of(context).textTheme.titleSmall)),
                Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
              ],
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

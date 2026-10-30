import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

String _km(int km) {
  final s = km.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return '$b km';
}

/// Auto dostawcy na wybrany dzień (okno dnia w Grafiku). Zapisuje się od razu, poza szkicem grafiku.
class VehicleDayPicker extends ConsumerWidget {
  const VehicleDayPicker({super.key, required this.memberId, required this.day});

  final String memberId;
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const SizedBox.shrink();
    final vehicles = [
      for (final v in ref.watch(vehiclesProvider(restaurant.id)).value ?? const <Vehicle>[])
        if (v.active) v,
    ];
    if (vehicles.isEmpty) return const SizedBox.shrink();
    final query = (restaurantId: restaurant.id, day: dateOnly(day));
    final days = ref.watch(vehicleDaysOnProvider(query)).value ?? const <VehicleDay>[];
    final mine = days.where((d) => d.memberId == memberId).firstOrNull?.vehicleId;
    final taken = {
      for (final d in days)
        if (d.memberId != memberId) d.vehicleId,
    };

    return DropdownButtonFormField<String?>(
      key: ValueKey('auto-$memberId-$mine'),
      initialValue: vehicles.any((v) => v.id == mine) ? mine : null,
      decoration: const InputDecoration(
        labelText: 'Auto tego dnia',
        helperText: 'Zapisuje się od razu. Dostawca zrobi zdjęcia i wpisze przebieg przed pierwszym kursem.',
        helperMaxLines: 2,
      ),
      icon: const Glyph(AppIcons.caretDown, size: 16),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Bez auta')),
        for (final v in vehicles)
          DropdownMenuItem<String?>(
            value: v.id,
            child: Text([v.name, ?v.plate, if (taken.contains(v.id)) '(zajęte)'].join(' · ')),
          ),
      ],
      onChanged: (v) async {
        try {
          await ref
              .read(repositoryProvider)
              .setVehicleDay(restaurant.id, day, memberId, v, editorId: ref.read(panelMemberProvider)?.dbMemberId);
          ref
            ..invalidate(vehicleDaysOnProvider(query))
            ..invalidate(todayVehicleDaysProvider(restaurant.id));
        } catch (e) {
          if (context.mounted) showError(context, e);
        }
      },
    );
  }
}

/// Flota → „Przebieg i zdjęcia”: kontrole auta z ostatnich 30 dni, dzień po dniu (kierowca, przebieg na początku
/// i na końcu zmiany, przejechane kilometry i cztery zdjęcia dookoła; kliknięcie powiększa zdjęcie).
class VehicleChecksDialog extends ConsumerWidget {
  const VehicleChecksDialog({super.key, required this.restaurantId, required this.vehicle});

  final String restaurantId;
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(vehicleChecksProvider((restaurantId: restaurantId, vehicleId: vehicle.id)));
    return AlertDialog(
      title: Text('${vehicle.name}${vehicle.plate == null ? '' : ' · ${vehicle.plate}'}'),
      content: SizedBox(
        width: 760,
        height: 600,
        child: async.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(vehicleChecksProvider((restaurantId: restaurantId, vehicleId: vehicle.id))),
          ),
          data: (checks) {
            if (checks.isEmpty) {
              return MessageView(
                icon: AppIcons.camera.duotone,
                title: 'Brak kontroli',
                message: 'Dostawca robi zdjęcia i wpisuje przebieg w Table for employees na początku i końcu zmiany.',
              );
            }
            final byDay = <DateTime, List<VehicleCheck>>{};
            for (final c in checks) {
              byDay.putIfAbsent(c.day, () => []).add(c);
            }
            return ListView(
              children: [
                for (final entry in byDay.entries) ...[
                  _DayHeader(day: entry.key, checks: entry.value),
                  for (final c in entry.value.reversed) _CheckRow(check: c),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Zamknij', style: text.labelLarge),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.checks});

  final DateTime day;
  final List<VehicleCheck> checks;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final start = checks.where((c) => c.start && c.odometerKm != null).map((c) => c.odometerKm!);
    final end = checks.where((c) => !c.start && c.odometerKm != null).map((c) => c.odometerKm!);
    final driven = start.isEmpty || end.isEmpty
        ? null
        : end.reduce((a, b) => a > b ? a : b) - start.reduce((a, b) => a < b ? a : b);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
      child: Row(
        children: [
          Text(Fmt.capitalize(Fmt.dayLong(day)), style: text.titleSmall),
          const Spacer(),
          if (driven != null)
            Text(
              'Przejechane: ${_km(driven)}',
              style: text.labelLarge?.copyWith(color: AppColors.accent, fontFeatures: _tabular),
            ),
        ],
      ),
    );
  }
}

class _CheckRow extends ConsumerWidget {
  const _CheckRow({required this.check});

  final VehicleCheck check;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final c = check;
    final urls = ref.watch(_photoUrlsProvider(c.photos.join('|'))).value ?? const <String, String>{};
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusChip(
                  label: c.start ? 'Początek zmiany' : 'Koniec zmiany',
                  icon: c.start ? AppIcons.signIn : AppIcons.doorOpen,
                  color: c.start ? TileColors.blue : TileColors.violet,
                ),
                const SizedBox(height: 6),
                Text([?c.memberName, Fmt.time(c.createdAt)].join(' · '), style: text.bodyMedium),
                Text(
                  c.odometerKm == null ? 'bez przebiegu' : _km(c.odometerKm!),
                  style: text.titleMedium?.copyWith(fontFeatures: _tabular),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, path) in c.photos.indexed)
                  _Thumb(url: urls[path], label: i < _sides.length ? _sides[i] : 'Zdjęcie'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _sides = ['Przód', 'Tył', 'Lewy bok', 'Prawy bok'];

/// Podpisane adresy zdjęć jednej kontroli (klucz: ścieżki połączone „|”).
final _photoUrlsProvider = FutureProvider.autoDispose.family<Map<String, String>, String>((ref, joined) {
  final paths = [
    for (final p in joined.split('|'))
      if (p.isNotEmpty) p,
  ];
  return ref.watch(repositoryProvider).vehiclePhotoUrls(paths);
});

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.label});

  final String? url;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final image = url;
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: image == null
            ? null
            : () => showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      InteractiveViewer(child: Image.network(image, fit: BoxFit.contain)),
                      Positioned(left: 12, top: 12, child: PanelPill(label)),
                    ],
                  ),
                ),
              ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 120,
            height: 90,
            child: image == null
                ? ColoredBox(
                    color: AppColors.surface,
                    child: Center(
                      child: Text(label, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                    ),
                  )
                : Image.network(image, fit: BoxFit.cover, cacheWidth: 240),
          ),
        ),
      ),
    );
  }
}

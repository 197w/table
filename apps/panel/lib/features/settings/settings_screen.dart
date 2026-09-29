import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../kiosk/kiosk_screen.dart';

/// Ustawienia tego komputera i lokalu. Na razie: główne stanowisko.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Ustawienia',
          subtitle: 'Ten komputer: ${ref.watch(deviceNameProvider)}',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: _MainStationCard(restaurant: restaurant),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Główne stanowisko: jedno w lokalu. Żeby je przenieść, trzeba je wyłączyć na starym
/// komputerze i włączyć na nowym.
class _MainStationCard extends ConsumerStatefulWidget {
  const _MainStationCard({required this.restaurant});

  final PanelRestaurant restaurant;

  @override
  ConsumerState<_MainStationCard> createState() => _MainStationCardState();
}

class _MainStationCardState extends ConsumerState<_MainStationCard> {
  late final TextEditingController _name;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: ref.read(deviceNameProvider));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _set(bool enable, {bool force = false}) async {
    final device = ref.read(deviceIdProvider).value;
    if (device == null) return;
    final id = widget.restaurant.id;
    if (!enable) {
      final ok = await confirm(
        context,
        title: 'Wyłączyć główne stanowisko?',
        message:
            'Pracownicy nie zalogują się na zmianę ani nie nabiją zamówień, dopóki nie włączysz '
            'głównego stanowiska na tym albo innym komputerze.',
        action: 'Wyłącz',
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).setMainStation(
        restaurantId: id,
        deviceId: device,
        deviceName: _name.text.trim().isEmpty ? ref.read(deviceNameProvider) : _name.text.trim(),
        enable: enable,
        force: force,
      );
      if (!enable) {
        // Bez głównego stanowiska blokada tego komputera nie ma sensu.
        await ref.read(kioskModeProvider.notifier).set(false);
      }
      ref.invalidate(mainStationProvider(id));
      if (mounted) {
        showMessage(context, enable ? 'Ten komputer jest teraz głównym stanowiskiem.' : 'Główne stanowisko wyłączone.');
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
      ref.invalidate(mainStationProvider(id));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takeOver(MainStation station) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => RestaurantPasswordDialog(
        title: 'Przenieść główne stanowisko tutaj?',
        message:
            'Używaj tylko wtedy, gdy komputer „${station.label}” nie działa i nie da się na nim wyłączyć '
            'głównego stanowiska. Tamten komputer przestanie nim być.',
        action: 'Przenieś',
      ),
    );
    if (ok == true) await _set(true, force: true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final id = widget.restaurant.id;
    final stationAsync = ref.watch(mainStationProvider(id));
    final isMain = ref.watch(isMainStationProvider(id));
    final station = stationAsync.value;
    final elsewhere = station != null && isMain == false;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Glyph(AppIcons.storefront, size: 22, color: AppColors.accent),
                const SizedBox(width: 12),
                Expanded(child: Text('Główne stanowisko', style: text.titleLarge)),
                if (isMain == null)
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Switch(
                    value: isMain,
                    // Stanowisko na innym komputerze trzeba najpierw wyłączyć tam.
                    onChanged: _busy || elsewhere ? null : (v) => _set(v),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Na głównym stanowisku pracownicy wchodzą na zmianę (kodem QR z aplikacji Table for employees '
              'albo loginem i hasłem) i nabijają zamówienia. W lokalu jest tylko jedno główne stanowisko. '
              'Żeby je przenieść, wyłącz je na starym komputerze i włącz na nowym.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 18),
            if (stationAsync.hasError)
              Text(errorText(stationAsync.error!), style: text.bodyMedium?.copyWith(color: AppColors.error))
            else if (isMain == true)
              _Status(
                icon: AppIcons.checkCircle,
                color: AppColors.accent,
                title: 'Ten komputer jest głównym stanowiskiem',
                detail: [
                  '„${station!.label}”',
                  if (station.setAt != null) 'od ${Fmt.dayShort(station.setAt!)}',
                ].join(' · '),
              )
            else if (elsewhere)
              _Status(
                icon: AppIcons.lock,
                color: AppColors.textMuted,
                title: 'Główne stanowisko jest na innym komputerze: „${station.label}”',
                detail: 'Wyłącz je tam w Ustawieniach, a potem włącz tutaj.',
                action: widget.restaurant.canManage
                    ? TextButton(
                        onPressed: _busy ? null : () => _takeOver(station),
                        child: const Text('Tamten komputer nie działa?'),
                      )
                    : null,
              )
            else if (isMain == false) ...[
              _Status(
                icon: AppIcons.circle,
                color: AppColors.textMuted,
                title: 'Główne stanowisko nie jest ustawione',
                detail: 'Pracownicy nie zalogują się, dopóki go nie włączysz.',
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: TextField(
                  controller: _name,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'Nazwa tego komputera',
                    helperText: 'Widać ją na innych komputerach, np. „Kasa przy barze”.',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    this.action,
  });

  final AppIconData icon;
  final Color color;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Glyph(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(detail, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                if (action != null) ...[const SizedBox(height: 6), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

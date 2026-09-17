import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app.dart';
import '../../core/formatters.dart';
import '../../core/maps.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets.dart';
import '../../shared/app_icons.dart';

const _tabular = [FontFeature.tabularFigures()];

class ReservationDetailScreen extends ConsumerWidget {
  const ReservationDetailScreen({super.key, required this.reservationId});

  final String reservationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reservationDetailProvider(reservationId));

    return Scaffold(
      appBar: AppBar(title: const Text('Szczegóły rezerwacji')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () =>
              ref.invalidate(reservationDetailProvider(reservationId)),
        ),
        data: (detail) => detail == null
            ? const MessageView(
                icon: AppIcons.calendarX,
                title: 'Nie znaleziono rezerwacji',
                message:
                    'Zaloguj się na konto, na które była zrobiona rezerwacja.',
              )
            : _Body(detail: detail),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.detail});

  final ReservationDetail detail;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _cancelling = false;

  Future<void> _navigate() async {
    final d = widget.detail;
    final platform = Theme.of(context).platform;
    final ok = await openNavigation(
      lat: d.lat,
      lng: d.lng,
      label: d.restaurantName,
      platform: platform,
    );
    if (!ok && mounted) {
      showMessage(
        context,
        'Nie udało się otworzyć map. Adres: ${d.address}, ${d.city}',
      );
    }
  }

  Future<void> _call() async {
    final phone = widget.detail.phone;
    final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!ok && mounted) {
      showMessage(context, 'Nie udało się otworzyć telefonu. Numer: $phone');
    }
  }

  /// Otwiera kalendarz telefonu z gotowym wydarzeniem. Gość zatwierdza je w kalendarzu.
  Future<void> _addToCalendar() async {
    final d = widget.detail;
    final description = [
      'Rezerwacja stolika w Table: ${Fmt.people(d.partySize)}.',
      if (d.occasion != null) 'Okazja: ${d.occasion!.label}.',
      'Telefon do lokalu: ${d.phone}',
    ].join('\n');

    var ok = false;
    try {
      ok = await Add2Calendar.addEvent2Cal(
        Event(
          title: 'Stolik w ${d.restaurantName}',
          description: description,
          location: '${d.address}, ${d.city}',
          startDate: d.startsAt.toLocal(),
          endDate: d.endsAt.toLocal(),
          iosParams: const IOSParams(reminder: Duration(hours: 2)),
        ),
      );
    } catch (_) {
      ok = false;
    }
    if (!ok && mounted) {
      showMessage(context, 'Nie udało się otworzyć kalendarza.');
    }
  }

  Future<void> _cancel() async {
    final d = widget.detail;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Odwołać rezerwację?'),
        content: Text(
          '${d.restaurantName}, ${Fmt.dateTime(d.startsAt)}. Stolik wróci do puli wolnych miejsc.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Zostaw'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Odwołaj'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancelling = true);
    try {
      await ref.read(repositoryProvider).cancelReservation(d.id);
      ref
        ..invalidate(myReservationsProvider)
        ..invalidate(reservationDetailProvider(d.id));
      if (mounted) showMessage(context, 'Rezerwacja odwołana.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.detail;
    final text = Theme.of(context).textTheme;
    final cancelled = d.status == ReservationStatus.cancelled;
    final timeRange = '${Fmt.time(d.startsAt)}–${Fmt.time(d.endsAt)}';
    final statusLabel = d.isUpcoming
        ? d.status.label
        : cancelled
        ? 'Odwołana'
        : 'Minęła';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Row(
          children: [
            RestaurantMark(name: d.restaurantName, size: 56, radius: 14),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.restaurantName, style: text.titleLarge),
                  const SizedBox(height: 6),
                  Tag(
                    statusLabel.toUpperCase(),
                    color: d.isUpcoming
                        ? AppColors.accent
                        : AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          Fmt.capitalize(Fmt.dayLong(d.startsAt)),
          style: text.headlineMedium?.copyWith(
            color: cancelled ? AppColors.textMuted : AppColors.text,
            decoration: cancelled ? TextDecoration.lineThrough : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$timeRange · ${Fmt.people(d.partySize)}',
          style: text.titleMedium?.copyWith(
            color: AppColors.textMuted,
            fontWeight: FontWeight.w500,
            fontFeatures: _tabular,
          ),
        ),
        if (d.isUpcoming && !cancelled) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _addToCalendar,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                side: BorderSide(color: AppColors.ringStrong),
              ),
              icon: const Glyph(AppIcons.calendarCheck, size: 18),
              label: const Text('Dodaj do kalendarza'),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _LocationCard(detail: d, onNavigate: _navigate, onCall: _call),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Column(
              children: [
                _InfoRow(
                  icon: AppIcons.calendar,
                  label: 'Data',
                  value: Fmt.capitalize(Fmt.dayShort(d.startsAt)),
                ),
                const Divider(height: 1),
                _InfoRow(
                  icon: AppIcons.clock,
                  label: 'Godzina',
                  value: timeRange,
                ),
                const Divider(height: 1),
                _InfoRow(
                  icon: AppIcons.users,
                  label: 'Liczba osób',
                  value: Fmt.people(d.partySize),
                ),
                if (d.occasion != null) ...[
                  const Divider(height: 1),
                  _InfoRow(
                    icon: AppIcons.confetti,
                    label: 'Okazja',
                    value: d.occasion!.label,
                  ),
                ],
                if (d.message != null) ...[
                  const Divider(height: 1),
                  _InfoBlock(
                    label: 'Wiadomość do restauracji',
                    value: d.message!,
                  ),
                ],
                if (d.diet != null) ...[
                  const Divider(height: 1),
                  _InfoBlock(label: 'Alergie i dieta', value: d.diet!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (d.canReview) ...[
          FilledButton(
            onPressed: () => context.push(
              AppRoutes.review(d.restaurantId, reservationId: d.id),
            ),
            child: const Text('Oceń wizytę'),
          ),
          const SizedBox(height: 10),
        ],
        OutlinedButton(
          onPressed: () => context.push(AppRoutes.restaurant(d.restaurantId)),
          child: const Text('Zobacz lokal'),
        ),
        if (d.canCancel) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: _cancelling ? null : _cancel,
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Odwołaj rezerwację'),
          ),
        ],
      ],
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.detail,
    required this.onNavigate,
    required this.onCall,
  });

  final ReservationDetail detail;
  final VoidCallback onNavigate;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Semantics(
              button: true,
              label: 'Otwórz nawigację do ${detail.address}, ${detail.city}',
              excludeSemantics: true,
              child: PressScale(
                onTap: onNavigate,
                child: Row(
                  children: [
                    // Ikona w rogu karty: promień 8 = promień karty 22 minus odstęp 14.
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Glyph(
                        AppIcons.mapPin,
                        size: 22,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.address,
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            detail.city,
                            style: text.bodySmall?.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const ArrowBadge(),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1),
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onNavigate,
                    // Mniejszy odstęp, żeby etykiety mieściły się w jednej linii w połowie szerokości karty.
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    icon: const Glyph(AppIcons.navigation, size: 18),
                    label: const Text('Nawiguj'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCall,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      side: BorderSide(color: AppColors.ringStrong),
                    ),
                    icon: const Glyph(AppIcons.phone, size: 18),
                    label: const Text('Zadzwoń'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final AppIconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Glyph(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Text(
            label,
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: _tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            Text(value, style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}

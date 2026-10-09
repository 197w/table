import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../ordering/order_screens.dart';
import 'booking_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Zakładka „Moje”: rezerwacje (najbliższa na dużej karcie, dalej nadchodzące, lista oczekujących i archiwum)
/// i zamówienia z dostawą albo na wynos.
class ReservationsScreen extends ConsumerWidget {
  const ReservationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Zakładka pokazuje prośbę o logowanie w miejscu, żeby gość nie tracił dolnego menu.
    if (ref.watch(sessionProvider) == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rezerwacje')),
        body: MessageView(
          icon: AppIcons.lock,
          title: 'Zaloguj się, żeby zobaczyć rezerwacje',
          message: 'Po zalogowaniu znajdziesz tu nadchodzące i minione wizyty oraz zamówienia.',
          actionLabel: 'Zaloguj się',
          onAction: () => context.push(AppRoutes.withNext(AppRoutes.login, AppRoutes.reservations)),
        ),
      );
    }

    final async = ref.watch(myReservationsProvider);
    final waitlist = ref.watch(myWaitlistProvider).value ?? const <GuestWaitlist>[];
    final reviewed = ref.watch(myReviewedReservationsProvider).value ?? const <String>{};
    final now = DateTime.now();

    // Rezerwacje i zamówienia z dostawą albo na wynos w jednej zakładce.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Moje'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Rezerwacje'),
              Tab(text: 'Zamówienia'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            async.when(
              skipLoadingOnReload: true,
              loading: () => const _Skeleton(),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myReservationsProvider)),
              data: (items) {
                if (items.isEmpty && waitlist.isEmpty) {
                  return MessageView(
                    icon: AppIcons.calendarCheck,
                    title: 'Nie masz jeszcze rezerwacji',
                    message: 'Znajdź lokal z oznaczeniem „Rezerwacja online” i wybierz godzinę.',
                    actionLabel: 'Odkrywaj lokale',
                    onAction: () => context.go(AppRoutes.discover),
                  );
                }

                final upcoming = items.where((r) => r.isUpcoming).toList()
                  ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
                final past = items.where((r) => !r.isUpcoming).toList();
                final next = upcoming.firstOrNull;

                return RefreshIndicator(
                  color: AppColors.accent,
                  backgroundColor: AppColors.surface,
                  onRefresh: () async {
                    ref
                      ..invalidate(myReviewedReservationsProvider)
                      ..invalidate(myWaitlistProvider)
                      ..invalidate(myReservationsProvider);
                    await ref.read(myReservationsProvider.future);
                  },
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: ListView(
                        padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
                        children: [
                          if (next != null) ...[
                            const SectionTitle('Najbliższa'),
                            _NextCard(reservation: next, now: now),
                          ],
                          if (waitlist.isNotEmpty) ...[
                            const SectionTitle('Lista oczekujących'),
                            for (final w in waitlist) _WaitlistCard(entry: w),
                          ],
                          if (upcoming.length > 1) ...[
                            const SectionTitle('Nadchodzące'),
                            for (final r in upcoming.skip(1))
                              _ReservationCard(reservation: r, now: now, reviewed: false),
                          ],
                          if (past.isNotEmpty) ...[
                            const SectionTitle('Archiwum'),
                            for (final r in past)
                              _ReservationCard(reservation: r, now: now, reviewed: reviewed.contains(r.id)),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const MyOrdersList(),
          ],
        ),
      ),
    );
  }
}

Future<void> _call(BuildContext context, String phone) async {
  final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
  if (!ok && context.mounted) showMessage(context, 'Nie udało się otworzyć telefonu. Numer: $phone');
}

Future<void> _cancel(BuildContext context, WidgetRef ref, Reservation reservation) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Odwołać rezerwację?'),
      content: Text(
        '${reservation.restaurantName}, ${Fmt.dateTime(reservation.startsAt)}. Stolik wróci do puli wolnych miejsc.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Zostaw')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Odwołaj'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await ref.read(repositoryProvider).cancelReservation(reservation.id);
    ref.invalidate(myReservationsProvider);
    if (context.mounted) showMessage(context, 'Rezerwacja odwołana.');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Opis rezerwacji dla czytnika ekranu: jedna wypowiedź.
String _semantics(Reservation r, DateTime now) {
  final status = reservationStatus(r.status, upcoming: r.isUpcoming);
  return [
    r.restaurantName,
    relativeVisit(r.startsAt, now),
    Fmt.people(r.partySize),
    status.label,
    if (r.occasion != null) 'okazja: ${r.occasion!.label}',
  ].join(', ');
}

/// Najbliższa wizyta na dużej karcie: kiedy (po ludzku), lokal, adres i szybkie działania.
class _NextCard extends ConsumerWidget {
  const _NextCard({required this.reservation, required this.now});

  final Reservation reservation;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = reservation;
    final text = Theme.of(context).textTheme;
    final status = reservationStatus(r.status, upcoming: true);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                label: '${_semantics(r, now)}. Szczegóły rezerwacji',
                excludeSemantics: true,
                child: PressScale(
                  onTap: () => context.push(AppRoutes.reservationDetail(r.id)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DateTile(date: r.startsAt, size: 64),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              relativeVisit(r.startsAt, now),
                              style: text.titleLarge?.copyWith(fontFeatures: _tabular),
                            ),
                            const SizedBox(height: 2),
                            Text(r.restaurantName, style: text.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              '${Fmt.people(r.partySize)} · ${r.restaurantAddress}',
                              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                StatusChip(label: status.label, icon: status.icon, color: status.color),
                                if (r.occasion != null)
                                  StatusChip(
                                    label: r.occasion!.label,
                                    icon: AppIcons.confetti,
                                    color: AppColors.textMuted,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Glyph(AppIcons.caretRight, size: 18, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
              if (r.canCancel) ...[
                const SizedBox(height: 16),
                // Przy dużej czcionce przyciski stają jeden pod drugim, żeby napisy nie łamały się w środku słowa.
                _ButtonPair(
                  first: OutlinedButton.icon(
                    onPressed: () => _cancel(context, ref, r),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error),
                    ),
                    icon: const Glyph(AppIcons.calendarX, size: 18),
                    label: const Text('Odwołaj'),
                  ),
                  second: OutlinedButton.icon(
                    onPressed: () => _call(context, r.restaurantPhone),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      side: BorderSide(color: AppColors.ringStrong),
                    ),
                    icon: const Glyph(AppIcons.phone, size: 18),
                    label: const Text('Zadzwoń'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Kolejna albo minione rezerwacja: kafelek z datą, lokal, godzina i liczba osób, stan z ikoną.
class _ReservationCard extends StatelessWidget {
  const _ReservationCard({required this.reservation, required this.now, required this.reviewed});

  final Reservation reservation;
  final DateTime now;
  final bool reviewed;

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final text = Theme.of(context).textTheme;
    final cancelled = r.status == ReservationStatus.cancelled;
    final status = reservationStatus(r.status, upcoming: r.isUpcoming);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                button: true,
                label: '${_semantics(r, now)}. Szczegóły rezerwacji',
                excludeSemantics: true,
                child: PressScale(
                  onTap: () => context.push(AppRoutes.reservationDetail(r.id)),
                  child: Row(
                    children: [
                      DateTile(date: r.startsAt, active: r.isUpcoming),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.restaurantName, style: text.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              '${Fmt.time(r.startsAt)} · ${Fmt.people(r.partySize)}',
                              style: text.bodyMedium?.copyWith(
                                // Odwołana: przekreślona, ale czytelna (kontrast tekstu co najmniej 4,5:1).
                                color: AppColors.textMuted,
                                decoration: cancelled ? TextDecoration.lineThrough : null,
                                fontFeatures: _tabular,
                              ),
                            ),
                            const SizedBox(height: 6),
                            StatusChip(label: status.label, icon: status.icon, color: status.color),
                          ],
                        ),
                      ),
                      Glyph(AppIcons.caretRight, size: 18, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
              if (r.canReview && !reviewed) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => context.push(AppRoutes.review(r.restaurantId, reservationId: r.id)),
                    icon: const Glyph(AppIcons.star, size: 16),
                    label: const Text('Oceń wizytę'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Miejsce na liście oczekujących: czekam albo lokal zaproponował godzinę (wtedy „Zarezerwuj”).
class _WaitlistCard extends ConsumerWidget {
  const _WaitlistCard({required this.entry});

  final GuestWaitlist entry;

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(repositoryProvider).leaveWaitlist(entry.id);
      ref.invalidate(myWaitlistProvider);
      if (context.mounted) showMessage(context, 'Wypisano z listy oczekujących.');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final e = entry;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DateTile(date: e.day, active: e.offered),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.restaurantName, style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          '${Fmt.people(e.partySize)} · ${e.from}–${e.to}',
                          style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                        const SizedBox(height: 6),
                        e.offered
                            ? StatusChip(
                                label: 'Wolny stolik o ${e.offeredTime}',
                                icon: AppIcons.checkCircle,
                                color: AppColors.accent,
                              )
                            : StatusChip(
                                label: 'Czekasz na stolik',
                                icon: AppIcons.hourglass,
                                color: AppColors.warning,
                              ),
                      ],
                    ),
                  ),
                ],
              ),
              if (e.offered) ...[
                const SizedBox(height: 10),
                Text(
                  'Zarezerwuj, zanim zajmie go ktoś inny.',
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
              ],
              if (e.offeredNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('„${e.offeredNote}”', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (e.offered) ...[
                    Expanded(
                      child: FilledButton(
                        onPressed: () => context.push(AppRoutes.booking(e.restaurantId)),
                        child: const Text('Zarezerwuj'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: TextButton(
                      onPressed: () => _leave(context, ref),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('Wypisz się'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dwa przyciski obok siebie, a przy dużej czcionce systemu jeden pod drugim.
class _ButtonPair extends StatelessWidget {
  const _ButtonPair({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(16) > 20) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 8), second],
      );
    }
    return Row(
      children: [
        Expanded(child: first),
        const SizedBox(width: 10),
        Expanded(child: second),
      ],
    );
  }
}

/// Szkielet listy rezerwacji, zanim dane dojdą (bez animacji).
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(6)),
    );
    return ExcludeSemantics(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 52, 16, 0),
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppColors.ring),
              ),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 66,
                    decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(14)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [bar(150, 14), const SizedBox(height: 8), bar(100, 12)],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../ordering/order_screens.dart';

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
          message: 'Po zalogowaniu znajdziesz tu nadchodzące i minione wizyty.',
          actionLabel: 'Zaloguj się',
          onAction: () => context.push(
            AppRoutes.withNext(AppRoutes.login, AppRoutes.reservations),
          ),
        ),
      );
    }

    final async = ref.watch(myReservationsProvider);
    final waitlist = ref.watch(myWaitlistProvider).value ?? const <GuestWaitlist>[];
    final reviewed =
        ref.watch(myReviewedReservationsProvider).value ?? const <String>{};

    // Rezerwacje i zamówienia z dostawą albo na wynos w jednej zakładce.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Moje'),
        bottom: const TabBar(tabs: [Tab(text: 'Rezerwacje'), Tab(text: 'Zamówienia')]),
      ),
      body: TabBarView(
        children: [
          async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(myReservationsProvider),
        ),
        data: (items) {
          if (items.isEmpty && waitlist.isEmpty) {
            return MessageView(
              icon: AppIcons.calendarCheck,
              title: 'Nie masz jeszcze rezerwacji',
              message:
                  'Znajdź lokal z oznaczeniem „Rezerwacja w aplikacji” i wybierz godzinę.',
              actionLabel: 'Odkrywaj lokale',
              onAction: () => context.go(AppRoutes.discover),
            );
          }

          final upcoming = items.where((r) => r.isUpcoming).toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
          final past = items.where((r) => !r.isUpcoming).toList();

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
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (waitlist.isNotEmpty) ...[
                  const SectionTitle('Lista oczekujących'),
                  for (final w in waitlist) _WaitlistCard(entry: w),
                ],
                if (upcoming.isNotEmpty) ...[
                  const SectionTitle('Nadchodzące'),
                  for (final r in upcoming)
                    _ReservationCard(reservation: r, reviewed: false),
                ],
                if (past.isNotEmpty) ...[
                  const SectionTitle('Archiwum'),
                  for (final r in past)
                    _ReservationCard(
                      reservation: r,
                      reviewed: reviewed.contains(r.id),
                    ),
                ],
              ],
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

class _ReservationCard extends ConsumerWidget {
  const _ReservationCard({required this.reservation, required this.reviewed});

  final Reservation reservation;
  final bool reviewed;

  Future<void> _call(BuildContext context) async {
    final phone = reservation.restaurantPhone;
    final ok = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!ok && context.mounted) {
      showMessage(context, 'Nie udało się otworzyć telefonu. Numer: $phone');
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Odwołać rezerwację?'),
        content: Text(
          '${reservation.restaurantName}, ${Fmt.dateTime(reservation.startsAt)}. '
          'Stolik wróci do puli wolnych miejsc.',
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

    try {
      await ref.read(repositoryProvider).cancelReservation(reservation.id);
      ref.invalidate(myReservationsProvider);
      if (context.mounted) showMessage(context, 'Rezerwacja odwołana.');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = reservation;
    final text = Theme.of(context).textTheme;
    final cancelled = r.status == ReservationStatus.cancelled;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: PressScale(
        onTap: () => context.push(AppRoutes.reservationDetail(r.id)),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(r.restaurantName, style: text.titleMedium),
                    ),
                    Tag(
                      r.isUpcoming
                          ? r.status.label.toUpperCase()
                          : (cancelled ? 'ODWOŁANA' : 'MINIONA'),
                      color: r.isUpcoming
                          ? AppColors.accent
                          : AppColors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${Fmt.dateTime(r.startsAt)} · ${Fmt.people(r.partySize)}',
                  style: text.bodyMedium?.copyWith(
                    color: cancelled ? AppColors.textDisabled : AppColors.text,
                    decoration: cancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                Text(
                  r.restaurantAddress,
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                if (r.occasion != null) ...[
                  const SizedBox(height: 8),
                  Tag(r.occasion!.label.toUpperCase()),
                ],
                if (r.canCancel) ...[
                  const SizedBox(height: 14),
                  // Ten sam układ co „Nawiguj” i „Zadzwoń” w szczegółach rezerwacji.
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _cancel(context, ref),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            foregroundColor: AppColors.error,
                            side: BorderSide(color: AppColors.error),
                          ),
                          icon: const Glyph(AppIcons.calendarX, size: 18),
                          label: const Text('Odwołaj'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _call(context),
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
                if (r.canReview && !reviewed) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                        TextButton(
                          onPressed: () => context.push(
                            AppRoutes.review(
                              r.restaurantId,
                              reservationId: r.id,
                            ),
                          ),
                          child: const Text('Oceń wizytę'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
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
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Glyph(e.offered ? AppIcons.checkCircle : AppIcons.hourglass, size: 20, color: e.offered ? AppColors.accent : AppColors.warning),
                  const SizedBox(width: 10),
                  Expanded(child: Text(e.restaurantName, style: text.titleMedium)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${Fmt.capitalize(Fmt.dayLong(e.day))} · ${Fmt.people(e.partySize)} · ${e.from}–${e.to}',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              Text(
                e.offered ? 'Zwolnił się stolik o ${e.offeredTime}. Zarezerwuj, zanim zajmie go ktoś inny.' : 'Czekasz na wolny stolik.',
                style: text.bodyMedium?.copyWith(color: e.offered ? AppColors.accent : null),
              ),
              if (e.offeredNote != null)
                Text('„${e.offeredNote}”', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (e.offered)
                    Expanded(
                      child: FilledButton(
                        onPressed: () => context.push(AppRoutes.booking(e.restaurantId)),
                        child: const Text('Zarezerwuj'),
                      ),
                    ),
                  if (e.offered) const SizedBox(width: 8),
                  Expanded(
                    child: TextButton(
                      onPressed: () => _leave(context, ref),
                      style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
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

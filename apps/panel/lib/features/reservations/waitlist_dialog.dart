import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Goście na liście oczekujących w wybranym dniu. Odświeża się razem z rezerwacjami.
final waitlistProvider = FutureProvider.autoDispose.family<List<WaitlistEntry>, DayQuery>((ref, q) {
  ref.watch(reservationsLiveProvider(q.restaurantId).select((s) => s.version));
  return ref.watch(repositoryProvider).waitlist(q.restaurantId, q.day);
});

/// Przycisk „Lista oczekujących” z liczbą gości w wybranym dniu.
class WaitlistButton extends ConsumerWidget {
  const WaitlistButton({super.key, required this.restaurantId, required this.day});

  final String restaurantId;
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(waitlistProvider((restaurantId: restaurantId, day: day))).value?.length ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        PanelPress(
          child: GlowButton(
            icon: AppIcons.hourglass,
            tooltip: 'Lista oczekujących',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => WaitlistDialog(restaurantId: restaurantId, day: day),
            ),
          ),
        ),
        if (count > 0)
          Positioned(
            right: -4,
            top: -4,
            child: IgnorePointer(
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.warning, borderRadius: BorderRadius.circular(9)),
                child: Text(
                  '$count',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Lista oczekujących dnia: gość, liczba osób, godziny, notatka. Lokal proponuje godzinę (gość widzi ją
/// w aplikacji Table i rezerwuje) albo usuwa gościa z listy.
class WaitlistDialog extends ConsumerWidget {
  const WaitlistDialog({super.key, required this.restaurantId, required this.day});

  final String restaurantId;
  final DateTime day;

  Future<void> _offer(BuildContext context, WidgetRef ref, WaitlistEntry e) async {
    final parts = e.from.split(':');
    final time = await pickTime(
      context,
      initial: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      title: 'Wolny stolik o',
    );
    if (time == null) return;
    try {
      await ref.read(repositoryProvider).offerWaitlist(e.id, time.hour, time.minute);
      ref.invalidate(waitlistProvider((restaurantId: restaurantId, day: day)));
      if (context.mounted) {
        showMessage(context, '${e.guestName} zobaczy w aplikacji propozycję na ${time.format(context)}.', tone: ToastTone.success);
      }
    } catch (err) {
      if (context.mounted) showError(context, err);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, WaitlistEntry e) async {
    final ok = await confirm(
      context,
      title: 'Usunąć z listy?',
      message: '${e.guestName}, ${Fmt.people(e.partySize)}, ${e.from}–${e.to}.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).removeWaitlist(e.id);
      ref.invalidate(waitlistProvider((restaurantId: restaurantId, day: day)));
    } catch (err) {
      if (context.mounted) showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(waitlistProvider((restaurantId: restaurantId, day: day)));
    return AlertDialog(
      title: Text('Lista oczekujących · ${Fmt.dayShort(day)}'),
      content: SizedBox(
        width: 560,
        child: async.when(
          skipLoadingOnReload: true,
          loading: () => const SizedBox(height: 120, child: LoadingView()),
          error: (e, _) => Text(errorText(e), style: text.bodyMedium?.copyWith(color: AppColors.error)),
          data: (entries) => entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nikt nie czeka na stolik tego dnia.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, e) in entries.indexed) ...[
                        if (i > 0) Divider(height: 1, color: AppColors.ring),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.guestName, style: text.titleSmall),
                                    Text(
                                      [
                                        Fmt.people(e.partySize),
                                        '${e.from}–${e.to}',
                                        ?(e.guestPhone == null ? null : Fmt.phone(e.guestPhone)),
                                        if (e.guestVisits > 0) '${e.guestVisits} wizyt',
                                      ].join(' · '),
                                      style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                                    ),
                                    if (e.note != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text('„${e.note}”', style: text.bodySmall),
                                      ),
                                    if (e.offered)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Tag('PROPOZYCJA ${e.offeredTime ?? ''}', color: AppColors.accent),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () => _offer(context, ref, e),
                                child: Text(e.offered ? 'Zmień godzinę' : 'Zaproponuj godzinę'),
                              ),
                              IconButton(
                                tooltip: 'Usuń z listy',
                                onPressed: () => _remove(context, ref, e),
                                icon: Glyph(AppIcons.trash, size: 16, color: AppColors.error),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zamknij')),
      ],
    );
  }
}

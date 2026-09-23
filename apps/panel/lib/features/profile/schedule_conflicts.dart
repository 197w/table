import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';

/// Nadchodzące potwierdzone rezerwacje, które wypadają poza godzinami otwarcia:
/// w dniu zamknięcia albo poza godzinami danego dnia.
Future<List<PanelReservation>> findScheduleConflicts(
  WidgetRef ref,
  String restaurantId, {
  required List<OpeningHours> weekly,
  required List<OpeningException> exceptions,
}) async {
  final now = DateTime.now();
  final upcoming = await ref.read(repositoryProvider).reservations(
    restaurantId: restaurantId,
    from: now,
    to: now.add(const Duration(days: 61)),
  );

  int minutes(String hm) {
    final p = hm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  final byDay = {for (final e in exceptions) DateTime(e.day.year, e.day.month, e.day.day): e};

  bool fits(PanelReservation r) {
    final start = r.startsAt.toLocal();
    final end = r.endsAt.toLocal();
    final day = DateTime(start.year, start.month, start.day);
    final String? opens;
    final String? closes;
    final exception = byDay[day];
    if (exception != null) {
      if (exception.closed) return false;
      opens = exception.opens;
      closes = exception.closes;
    } else {
      OpeningHours? h;
      for (final x in weekly) {
        if (x.weekday == start.weekday) h = x;
      }
      if (h == null) return false;
      opens = h.opens;
      closes = h.closes;
    }
    if (opens == null || closes == null) return false;
    final startMin = start.hour * 60 + start.minute;
    // Wizyta kończąca się po północy liczy się jako koniec dnia.
    final endMin = end.day == start.day ? end.hour * 60 + end.minute : 24 * 60;
    return startMin >= minutes(opens) && endMin <= minutes(closes);
  }

  return [
    for (final r in upcoming)
      if (r.status == ReservationStatus.confirmed && r.startsAt.isAfter(now) && !fits(r)) r,
  ]..sort((a, b) => a.startsAt.compareTo(b.startsAt));
}

/// Pokazuje kolidujące rezerwacje i pyta, czy je odwołać. Powód trafia do notatki obsługi.
Future<void> resolveScheduleConflicts(
  BuildContext context,
  WidgetRef ref,
  String restaurantId,
  List<PanelReservation> conflicts, {
  required String reason,
}) async {
  if (conflicts.isEmpty || !context.mounted) return;
  final cancel = await showDialog<bool>(
    context: context,
    builder: (context) => _ConflictsDialog(conflicts: conflicts),
  );
  if (cancel != true || !context.mounted) return;
  try {
    final count = await ref.read(repositoryProvider).cancelReservations(
      restaurantId,
      [for (final r in conflicts) r.id],
      reason: reason,
    );
    if (context.mounted) {
      showMessage(context, 'Odwołano rezerwacje: $count. Goście zobaczą to w aplikacji.');
    }
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(e));
  }
}

class _ConflictsDialog extends StatelessWidget {
  const _ConflictsDialog({required this.conflicts});

  final List<PanelReservation> conflicts;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const shown = 8;
    return AlertDialog(
      title: const Text('Rezerwacje poza godzinami otwarcia'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Te rezerwacje wypadają w czasie, gdy lokal jest teraz zamknięty. '
              'Możesz je zostawić albo odwołać.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            for (final r in conflicts.take(shown))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        '${Fmt.dayShort(r.startsAt.toLocal())}, ${Fmt.time(r.startsAt.toLocal())}',
                        style: text.bodyMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.guestName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelLarge,
                      ),
                    ),
                    Text(
                      Fmt.people(r.partySize),
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            if (conflicts.length > shown)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'i ${conflicts.length - shown} więcej',
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Zostaw je'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          child: Text('Odwołaj ${conflicts.length == 1 ? 'ją' : 'je'}'),
        ),
      ],
    );
  }
}

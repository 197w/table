import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';

const _tabular = [FontFeature.tabularFigures()];
const _weekdays = ['PN', 'WT', 'ŚR', 'CZ', 'PT', 'SB', 'ND'];
const _months = ['sty', 'lut', 'mar', 'kwi', 'maj', 'cze', 'lip', 'sie', 'wrz', 'paź', 'lis', 'gru'];
const _weekdayNames = ['W poniedziałek', 'We wtorek', 'W środę', 'W czwartek', 'W piątek', 'W sobotę', 'W niedzielę'];

/// Kiedy jest wizyta, po ludzku: „Dziś, 19:00”, „Jutro, 19:00”, „W piątek, 19:00”, dalej pełna data.
String relativeVisit(DateTime start, DateTime now) {
  final l = start.toLocal();
  final days = DateTime(l.year, l.month, l.day).difference(DateTime(now.year, now.month, now.day)).inDays;
  final time = Fmt.time(l);
  return switch (days) {
    0 => 'Dziś, $time',
    1 => 'Jutro, $time',
    > 1 && < 7 => '${_weekdayNames[l.weekday - 1]}, $time',
    _ => Fmt.dateTime(l),
  };
}

/// Kafelek z datą jak kartka z kalendarza: dzień tygodnia, numer dnia i miesiąc.
class DateTile extends StatelessWidget {
  const DateTile({super.key, required this.date, this.active = true, this.size = 58});

  final DateTime date;

  /// Nadchodząca wizyta: w kolorze akcentu. Minione i odwołane: przygaszone.
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l = date.toLocal();
    final fg = active ? AppColors.accent : AppColors.textMuted;
    return ExcludeSemantics(
      child: Container(
        width: size,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.accentTint : AppColors.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? AppColors.accent.withValues(alpha: 0.4) : AppColors.ring),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _weekdays[l.weekday - 1],
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: fg,
              ),
            ),
            Text(
              '${l.day}',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: size * 0.38,
                height: 1.15,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.text : AppColors.textMuted,
                fontFeatures: _tabular,
              ),
            ),
            Text(
              _months[l.month - 1],
              style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stan rezerwacji albo zamówienia: ikona i słowo, nie sam kolor.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.icon, required this.color});

  final String label;
  final AppIconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ikona, kolor i napis stanu rezerwacji (nadchodząca, przy stoliku, minęła, odwołana, nieobecność).
({String label, AppIconData icon, Color color}) reservationStatus(ReservationStatus status, {required bool upcoming}) =>
    switch (status) {
      ReservationStatus.cancelled => (label: 'Odwołana', icon: AppIcons.calendarX, color: AppColors.error),
      ReservationStatus.noShow => (label: 'Nieobecność', icon: AppIcons.warning, color: AppColors.warning),
      ReservationStatus.seated => (label: 'Przy stoliku', icon: AppIcons.armchair, color: AppColors.accent),
      _ when upcoming => (label: 'Potwierdzona', icon: AppIcons.checkCircle, color: AppColors.accent),
      _ => (label: 'Minęła', icon: AppIcons.clockBack, color: AppColors.textMuted),
    };

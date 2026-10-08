import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Dzień w pasku dni („Dziś”, „Jutro”, „Pt” i numer dnia). Wyszarzony, gdy lokal jest zamknięty.
class DayTile extends StatelessWidget {
  const DayTile({
    super.key,
    required this.day,
    required this.index,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final DateTime day;
  final int index;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (index) {
      0 => 'Dziś',
      1 => 'Jutro',
      _ => Fmt.weekdayShort(day),
    };
    final number = !enabled ? AppColors.textDisabled : AppColors.text;
    final caption = !enabled
        ? AppColors.textDisabled
        : selected
        ? AppColors.text
        : AppColors.textMuted;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label:
          '${Fmt.capitalize(Fmt.dayLong(day))}${enabled ? '' : ', zamknięte'}',
      excludeSemantics: true,
      child: PressScale(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: 60,
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceRaised : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.ring,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: caption,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: number,
                  fontFeatures: _tabular,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Godziny do wyboru w trzech kolumnach (rezerwacja stolika).
class SlotGrid extends StatelessWidget {
  const SlotGrid({
    super.key,
    required this.slots,
    required this.selected,
    required this.onSelected,
  });

  final List<DateTime> slots;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        const columns = 3;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in slots)
              SizedBox(
                width: width,
                height: 48,
                child: SlotButton(
                  label: Fmt.time(s),
                  selected: s == selected,
                  onTap: () => onSelected(s),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Jedna godzina do wyboru, np. „18:30”.
class SlotButton extends StatelessWidget {
  const SlotButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Godzina $label',
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accentFill : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.accentFill : AppColors.ring,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.onAccent : AppColors.text,
              fontFeatures: _tabular,
            ),
          ),
        ),
      ),
    );
  }
}

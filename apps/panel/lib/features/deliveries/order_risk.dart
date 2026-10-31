// Analiza oszustw (0070) działa w tle: baza ocenia każde zamówienie z aplikacji Table, panel sprawdza IP
// (orderRisksProvider), a ryzyko widać przy zamówieniu w Dostawach i Odbiorze. Osobnej zakładki nie ma.
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

Color riskColor(RiskLevel level) => switch (level) {
  RiskLevel.high => TileColors.rose,
  RiskLevel.medium => TileColors.amber,
  RiskLevel.low => TileColors.green,
};

String riskLabel(RiskLevel level) => switch (level) {
  RiskLevel.high => 'Wysokie ryzyko',
  RiskLevel.medium => 'Średnie ryzyko',
  RiskLevel.low => 'Niskie ryzyko',
};

/// Znaczek ryzyka na karcie zamówienia z aplikacji w Dostawach i Odbiorze. Kliknięcie: szczegóły.
class RiskChip extends StatelessWidget {
  const RiskChip({super.key, required this.risk});

  final OrderRisk risk;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = riskColor(risk.level);
    return Tooltip(
      message: '${riskLabel(risk.level)}: ${risk.flags.map((f) => f.text).join(' ')}',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showRiskDialog(context, risk),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Glyph(AppIcons.shieldWarning, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                'Ryzyko ${risk.score}',
                style: text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600, fontFeatures: _tabular),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showRiskDialog(BuildContext context, OrderRisk risk) {
  final text = Theme.of(context).textTheme;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Zamówienie #${risk.number}: ryzyko ${risk.score}/100'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              StatusChip(label: riskLabel(risk.level), icon: AppIcons.shieldWarning, color: riskColor(risk.level)),
              const SizedBox(height: 8),
              Text(
                risk.level == RiskLevel.high
                    ? 'Sprawdź gościa przed przyjęciem, na przykład zadzwoń pod podany numer. Przy płatności gotówką '
                          'możesz poprosić o płatność kartą online albo odrzucić zamówienie.'
                    : risk.level == RiskLevel.medium
                    ? 'Coś odbiega od zwykłych zamówień. Zwykle wystarczy telefon do gościa.'
                    : 'Nic niepokojącego.',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              _RiskDetails(risk: risk),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Zamknij'))],
    ),
  );
}

/// Sygnały z punktami i adres IP.
class _RiskDetails extends StatelessWidget {
  const _RiskDetails({required this.risk});

  final OrderRisk risk;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (risk.flags.isEmpty) Text('Brak sygnałów.', style: muted),
        for (final f in risk.flags)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '+${f.points}',
                    style: text.labelLarge?.copyWith(color: riskColor(risk.level), fontFeatures: _tabular),
                  ),
                ),
                Expanded(child: Text(f.text, style: text.bodyMedium)),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          risk.clientIp == null
              ? 'Adres IP: nieznany (zamówienie spoza aplikacji albo starsza wersja).'
              : !risk.ipChecked
              ? 'Adres IP ${risk.clientIp}: czeka na sprawdzenie w ipinfo.io.'
              : 'Adres IP ${risk.clientIp}${risk.ipPlace == null ? '' : ' · ${risk.ipPlace}'}',
          style: muted,
        ),
      ],
    );
  }
}

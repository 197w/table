import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Ile dni wstecz pokazuje „Analiza oszustw”.
const fraudDays = 30;

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

/// Znaczek ryzyka na karcie zamówienia w Dostawach i Odbiorze (tylko średnie i wysokie). Kliknięcie: szczegóły.
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

enum _Filter { suspicious, all }

/// Management → Analiza oszustw (uprawnienie `fraud`): zamówienia z aplikacji Table z ostatnich 30 dni z oceną
/// ryzyka. Sygnały: wzorce zamówień gościa w całym Table (np. kilka zamówień po 10 makaronów), nieudane płatności,
/// odrzucone zamówienia, ten sam numer albo IP na kilku kontach, adres IP z ipinfo.io (kraj, VPN, odległość).
class FraudScreen extends ConsumerStatefulWidget {
  const FraudScreen({super.key});

  @override
  ConsumerState<FraudScreen> createState() => _FraudScreenState();
}

class _FraudScreenState extends ConsumerState<FraudScreen> {
  _Filter _filter = _Filter.suspicious;

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final query = (restaurantId: restaurant.id, days: fraudDays);
    final async = ref.watch(orderRisksProvider(query));
    final ipStatus = ref.watch(ipCheckStatusProvider);
    final all = async.value ?? const <OrderRisk>[];
    final suspicious = all.where((r) => r.level != RiskLevel.low).toList()..sort((a, b) => b.score.compareTo(a.score));
    final high = suspicious.where((r) => r.level == RiskLevel.high).length;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          below: Row(
            children: [
              SegmentedTabs<_Filter>(
                options: [
                  (_Filter.suspicious, 'Podejrzane (${suspicious.length})'),
                  (_Filter.all, 'Wszystkie (${all.length})'),
                ],
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
              const Spacer(),
              Text('Ostatnie $fraudDays dni', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
            ],
          ),
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(orderRisksProvider(query))),
            data: (_) {
              final visible = _filter == _Filter.suspicious ? suspicious : all;
              return ListView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Zamówienia z aplikacji',
                          value: '${all.length}',
                          hint: 'dostawy i odbiór z $fraudDays dni',
                          icon: AppIcons.receipt,
                          color: TileColors.blue,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: StatTile(
                          label: 'Podejrzane',
                          value: '${suspicious.length}',
                          hint: 'co najmniej 25 punktów',
                          icon: AppIcons.shieldWarning,
                          color: suspicious.isEmpty ? TileColors.green : TileColors.amber,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: StatTile(
                          label: 'Wysokie ryzyko',
                          value: '$high',
                          hint: 'co najmniej 50 punktów',
                          icon: AppIcons.warning,
                          color: high == 0 ? TileColors.green : TileColors.rose,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (ipStatus == 'no_token') ...[
                    const _Notice(
                      color: TileColors.amber,
                      text:
                          'Adresy IP czekają na sprawdzenie: w Supabase brakuje tokenu ipinfo.io (sekret IPINFO_TOKEN '
                          'funkcji fraud-ip). Pozostałe sygnały działają.',
                    ),
                    const SizedBox(height: 12),
                  ],
                  _Notice(
                    color: AppColors.textMuted,
                    text:
                        'Sprawdzamy: wzorce zamówień gościa w całym Table (konto i numer telefonu), nieudane płatności, '
                        'odrzucone zamówienia, ten sam numer albo adres IP na kilku kontach, kraj i odległość adresu IP '
                        'od lokalu oraz VPN i proxy. AVS i kod CVV sprawdzi operator płatności, gdy go podłączymy. '
                        'Limity sztuk w zamówieniu: Ustawienia lokalu → Dostawa i odbiór.',
                  ),
                  const SizedBox(height: 20),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: MessageView(
                        icon: AppIcons.checkCircle.duotone,
                        title: _filter == _Filter.suspicious ? 'Brak podejrzanych zamówień' : 'Brak zamówień z aplikacji',
                        message: 'Zamówienia z aplikacji Table z ostatnich $fraudDays dni pojawią się tutaj z oceną.',
                      ),
                    ),
                  for (final r in visible)
                    Padding(padding: const EdgeInsets.only(bottom: 10), child: _RiskTile(risk: r)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Glyph(AppIcons.info, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _RiskTile extends StatelessWidget {
  const _RiskTile({required this.risk});

  final OrderRisk risk;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = riskColor(risk.level);
    final opened = risk.openedAt.toLocal();
    final delivery = risk.kind == OrderKind.delivery;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: risk.level == RiskLevel.low ? AppColors.ring : color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Text(
              '${risk.score}',
              style: text.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w600, fontFeatures: _tabular),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('#${risk.number}', style: text.titleMedium?.copyWith(fontFeatures: _tabular)),
                    StatusChip(
                      label: delivery ? 'Dostawa' : 'Odbiór',
                      icon: delivery ? AppIcons.moped : AppIcons.shoppingBag,
                      color: delivery ? TileColors.violet : TileColors.blue,
                    ),
                    StatusChip(label: riskLabel(risk.level), icon: AppIcons.shieldWarning, color: color),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (risk.customerName.isNotEmpty) risk.customerName,
                    if (risk.customerPhone.isNotEmpty) Fmt.phone(risk.customerPhone),
                    risk.paymentChoice == 'cash' ? 'gotówka' : 'karta online',
                  ].join(' · '),
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
                const SizedBox(height: 8),
                _RiskDetails(risk: risk),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Fmt.price(risk.totalGrosze),
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontFeatures: _tabular),
              ),
              Text(
                '${Fmt.dayShort(opened)}, ${Fmt.time(opened)}',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

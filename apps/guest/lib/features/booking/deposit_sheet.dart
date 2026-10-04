import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/providers.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Płatność zadatku za rezerwację. Zwraca true po opłaceniu.
Future<bool> payDeposit(BuildContext context, {required String reservationId, required int amountGrosze}) async {
  final paid = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _DepositSheet(reservationId: reservationId, amountGrosze: amountGrosze),
  );
  return paid == true;
}

class _DepositSheet extends ConsumerStatefulWidget {
  const _DepositSheet({required this.reservationId, required this.amountGrosze});

  final String reservationId;
  final int amountGrosze;

  @override
  ConsumerState<_DepositSheet> createState() => _DepositSheetState();
}

class _DepositSheetState extends ConsumerState<_DepositSheet> {
  bool _busy = false;

  Future<void> _pay() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).payDepositTest(widget.reservationId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final test = ref.watch(paymentsTestModeProvider).value ?? true;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Glyph(AppIcons.creditCard, size: 24, color: AppColors.accent),
              const SizedBox(width: 10),
              Text('Zadatek za rezerwację', style: text.titleLarge),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                Text('Do zapłaty', style: text.titleMedium),
                const Spacer(),
                Text(Fmt.price(widget.amountGrosze), style: text.headlineSmall?.copyWith(fontFeatures: _tabular)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Zadatek odejmie się od rachunku w lokalu. Odwołanie rezerwacji go zwraca, nieobecność nie.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          if (test) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Tryb testowy: płatności kartą nie są jeszcze podłączone. Nic nie zostanie pobrane.',
                style: text.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || !test ? null : _pay,
            child: Text(_busy ? 'Płacę…' : 'Zapłać ${Fmt.price(widget.amountGrosze)}'),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
            child: const Text('Anuluj'),
          ),
        ],
      ),
    );
  }
}

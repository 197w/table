import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

class GiftCardsScreen extends ConsumerStatefulWidget {
  const GiftCardsScreen({super.key});

  @override
  ConsumerState<GiftCardsScreen> createState() => _GiftCardsScreenState();
}

class _GiftCardsScreenState extends ConsumerState<GiftCardsScreen> {
  final _code = TextEditingController();
  GiftCard? _found;
  bool _searching = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _search(String restaurantId) async {
    final code = _code.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (code.length != 12) {
      showMessage(context, 'Kod karty ma 12 znaków, na przykład ABCD-EFGH-JKLM.');
      return;
    }
    setState(() => _searching = true);
    try {
      final cards = await ref.read(repositoryProvider).giftCards(restaurantId, code: code);
      if (!mounted) return;
      setState(() => _found = cards.isEmpty ? null : cards.first);
      if (cards.isEmpty) showMessage(context, 'Nie ma karty o tym kodzie w tym lokalu.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    if (!restaurant.isPro) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Karty podarunkowe'),
          Expanded(child: ProGate(feature: 'Karty podarunkowe')),
        ],
      );
    }
    final async = ref.watch(giftCardsProvider(restaurant.id));
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeader(
          title: 'Karty podarunkowe',
          subtitle: 'Goście kupują karty w aplikacji Table. Tu sprawdzasz kod i pobierasz kwotę przy płatności.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Glyph(AppIcons.warning, size: 16, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Tryb testowy: karty są kupowane bez prawdziwej płatności. Nie przyjmuj ich jeszcze jako zapłaty.',
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(giftCardsProvider(restaurant.id)),
            ),
            data: (cards) {
              int sum(int Function(GiftCard) f) => cards.fold(0, (a, c) => a + f(c));
              final sold = sum((c) => c.initialGrosze);
              final open = sum((c) => c.isExpired || c.status != 'active' ? 0 : c.balanceGrosze);
              return ListView(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                children: [
                  Row(
                    children: [
                      Expanded(child: StatTile(label: 'Sprzedane karty', value: '${cards.length}', icon: AppIcons.envelope)),
                      const SizedBox(width: 12),
                      Expanded(child: StatTile(label: 'Wartość sprzedaży', value: Fmt.price(sold), icon: AppIcons.chartBar)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          label: 'Wykorzystano',
                          value: Fmt.price(sold - sum((c) => c.balanceGrosze)),
                          icon: AppIcons.checkCircle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          label: 'Do wykorzystania',
                          value: Fmt.price(open),
                          icon: AppIcons.timer,
                          accent: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: PanelCard(
                          title: 'Realizacja karty',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _code,
                                      textCapitalization: TextCapitalization.characters,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')),
                                        LengthLimitingTextInputFormatter(14),
                                      ],
                                      style: const TextStyle(fontFeatures: _tabular, letterSpacing: 1.5),
                                      decoration: const InputDecoration(
                                        labelText: 'Kod z karty gościa',
                                        hintText: 'ABCD-EFGH-JKLM',
                                      ),
                                      onSubmitted: (_) => _search(restaurant.id),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton(
                                    onPressed: _searching ? null : () => _search(restaurant.id),
                                    style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                                    child: const Text('Sprawdź'),
                                  ),
                                ],
                              ),
                              if (_found != null) ...[
                                const SizedBox(height: 18),
                                _RedeemPanel(
                                  key: ValueKey('${_found!.id}-${_found!.balanceGrosze}'),
                                  card: _found!,
                                  onRedeemed: (balance) {
                                    ref.invalidate(giftCardsProvider(restaurant.id));
                                    _search(restaurant.id);
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: PanelCard(
                          title: 'Sprzedane karty',
                          child: cards.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24),
                                  child: Text(
                                    'Nikt jeszcze nie kupił karty podarunkowej tego lokalu.',
                                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                                  ),
                                )
                              : Column(
                                  children: [
                                    for (final c in cards) ...[
                                      _CardRow(card: c, onTap: () {
                                        _code.text = c.code;
                                        setState(() => _found = c);
                                      }),
                                      if (c != cards.last) Divider(height: 1, color: AppColors.ring),
                                    ],
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.card, required this.onTap});

  final GiftCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = card;
    final (label, color) = c.status != 'active'
        ? ('UNIEWAŻNIONA', AppColors.error)
        : c.isExpired
        ? ('PO TERMINIE', AppColors.textMuted)
        : c.balanceGrosze == 0
        ? ('WYKORZYSTANA', AppColors.textMuted)
        : ('AKTYWNA', AppColors.accent);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.code, style: text.labelLarge?.copyWith(fontFeatures: _tabular, letterSpacing: 1)),
                  Text(
                    [
                      'kupiona ${Fmt.dayShort(c.createdAt)}',
                      if (c.recipientName != null) 'dla: ${c.recipientName}',
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(Fmt.price(c.balanceGrosze), style: text.titleSmall?.copyWith(fontFeatures: _tabular)),
                Text(
                  'z ${Fmt.price(c.initialGrosze)}',
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
              ],
            ),
            const SizedBox(width: 14),
            SizedBox(width: 112, child: Align(alignment: Alignment.centerRight, child: Tag(label, color: color))),
          ],
        ),
      ),
    );
  }
}

class _RedeemPanel extends ConsumerStatefulWidget {
  const _RedeemPanel({super.key, required this.card, required this.onRedeemed});

  final GiftCard card;
  final ValueChanged<int> onRedeemed;

  @override
  ConsumerState<_RedeemPanel> createState() => _RedeemPanelState();
}

class _RedeemPanelState extends ConsumerState<_RedeemPanel> {
  final _amount = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final grosze = parseGrosze(_amount.text);
    if (grosze == null || grosze <= 0) {
      showMessage(context, 'Wpisz kwotę rachunku, na przykład 84,50.');
      return;
    }
    final take = grosze > widget.card.balanceGrosze ? widget.card.balanceGrosze : grosze;
    final ok = await confirm(
      context,
      title: 'Pobrać ${Fmt.price(take)} z karty?',
      message: grosze > widget.card.balanceGrosze
          ? 'Na karcie jest mniej niż rachunek. Pobierzemy całe saldo, a resztę (${Fmt.price(grosze - take)}) gość dopłaci inaczej.'
          : 'Po pobraniu na karcie zostanie ${Fmt.price(widget.card.balanceGrosze - take)}.',
      action: 'Pobierz',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final balance = await ref.read(repositoryProvider).redeemGiftCard(widget.card.id, take);
      if (!mounted) return;
      showMessage(context, 'Pobrano ${Fmt.price(take)}. Na karcie zostało ${Fmt.price(balance)}.');
      widget.onRedeemed(balance);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    final text = Theme.of(context).textTheme;
    final usable = c.isUsable;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Saldo', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
          Text(
            Fmt.price(c.balanceGrosze),
            style: text.displaySmall?.copyWith(
              color: usable ? AppColors.accent : AppColors.textMuted,
              fontFeatures: _tabular,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              'z ${Fmt.price(c.initialGrosze)}',
              'ważna do ${Fmt.dayShort(c.expiresAt)}',
              if (c.recipientName != null) 'dla: ${c.recipientName}',
            ].join(' · '),
            style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
          ),
          if (c.message != null) ...[
            const SizedBox(height: 8),
            Text('„${c.message}”', style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),
          if (!usable)
            Text(
              c.status != 'active'
                  ? 'Ta karta jest unieważniona.'
                  : c.isExpired
                  ? 'Ta karta straciła ważność.'
                  : 'Na tej karcie nie ma już środków.',
              style: text.bodyMedium?.copyWith(color: AppColors.error),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                    style: const TextStyle(fontFeatures: _tabular),
                    decoration: const InputDecoration(labelText: 'Kwota rachunku', suffixText: 'zł'),
                    onSubmitted: (_) => _redeem(),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _busy ? null : _redeem,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                  child: const Text('Pobierz z karty'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

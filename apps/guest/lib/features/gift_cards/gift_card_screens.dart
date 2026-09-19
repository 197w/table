import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

const _tabular = [FontFeature.tabularFigures()];
const _amounts = [100, 150, 200, 300, 500];

// ---------------------------------------------------------------
// Zakup karty
// ---------------------------------------------------------------

class GiftCardPurchaseScreen extends ConsumerStatefulWidget {
  const GiftCardPurchaseScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  ConsumerState<GiftCardPurchaseScreen> createState() => _GiftCardPurchaseScreenState();
}

class _GiftCardPurchaseScreenState extends ConsumerState<GiftCardPurchaseScreen> {
  int? _amount = 150;
  final _custom = TextEditingController();
  final _recipient = TextEditingController();
  final _message = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _custom.dispose();
    _recipient.dispose();
    _message.dispose();
    super.dispose();
  }

  int? get _zloty => _amount ?? int.tryParse(_custom.text.trim());

  Future<void> _buy() async {
    final zl = _zloty;
    if (zl == null || zl < 20 || zl > 2000) {
      showMessage(context, 'Wybierz kwotę od 20 do 2000 zł.');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final id = await ref.read(repositoryProvider).purchaseGiftCard(
        restaurantId: widget.restaurantId,
        amountGrosze: zl * 100,
        recipientName: _recipient.text,
        message: _message.text,
      );
      ref.invalidate(myGiftCardsProvider);
      if (!mounted) return;
      context.pushReplacement(AppRoutes.giftCard(id));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final restaurant = ref.watch(restaurantProvider(widget.restaurantId)).value;
    final zl = _zloty;

    return Scaffold(
      appBar: AppBar(title: const Text('Karta podarunkowa')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (restaurant != null)
            Row(
              children: [
                RestaurantLogo(name: restaurant.name, logoUrl: restaurant.logoUrl, size: 44, radius: 12),
                const SizedBox(width: 12),
                Expanded(child: Text(restaurant.name, style: text.titleLarge)),
              ],
            ),
          const SizedBox(height: 20),
          Text('Kwota', style: text.titleMedium),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in _amounts)
                ChoiceChip(
                  label: Text(
                    '$a zł',
                    style: TextStyle(
                      fontFeatures: _tabular,
                      color: _amount == a ? AppColors.onAccent : AppColors.text,
                    ),
                  ),
                  selected: _amount == a,
                  onSelected: (_) => setState(() {
                    _amount = a;
                    _custom.clear();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _custom,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            onChanged: (_) => setState(() => _amount = null),
            decoration: const InputDecoration(
              labelText: 'Inna kwota',
              hintText: 'od 20 do 2000',
              suffixText: 'zł',
            ),
          ),
          const SizedBox(height: 20),
          Text('Dla kogo', style: text.titleMedium),
          const SizedBox(height: 10),
          TextField(
            controller: _recipient,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Imię obdarowanego (opcjonalnie)', counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            maxLength: 300,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Życzenia (opcjonalnie)', alignLabelWithHint: true),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Glyph(AppIcons.warning, size: 18, color: AppColors.warning),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Wersja testowa: karta powstaje bez płatności i nie ma wartości w restauracji. '
                    'Płatność BLIK-iem, kartą, Apple Pay i Google Pay włączymy przed premierą.',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Karta jest ważna 12 miesięcy. Można ją wykorzystać w częściach, reszta zostaje na karcie.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _busy ? null : _buy,
          child: Text(zl == null ? 'Wybierz kwotę' : 'Kup kartę za $zl zł (test)'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Moje karty
// ---------------------------------------------------------------

class GiftCardsScreen extends ConsumerWidget {
  const GiftCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myGiftCardsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Karty podarunkowe')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myGiftCardsProvider)),
        data: (cards) => cards.isEmpty
            ? MessageView(
                icon: AppIcons.envelope,
                title: 'Nie masz jeszcze kart',
                message: 'Kartę podarunkową kupisz na stronie restauracji, która je sprzedaje.',
                actionLabel: 'Odkrywaj lokale',
                onAction: () => context.go(AppRoutes.discover),
              )
            : RefreshIndicator(
                color: AppColors.accent,
                backgroundColor: AppColors.surface,
                onRefresh: () => ref.refresh(myGiftCardsProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: cards.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => PressScale(
                    onTap: () => context.push(AppRoutes.giftCard(cards[i].id)),
                    child: _GiftCardFace(card: cards[i], compact: true),
                  ),
                ),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Szczegóły karty
// ---------------------------------------------------------------

class GiftCardDetailScreen extends ConsumerWidget {
  const GiftCardDetailScreen({super.key, required this.cardId});

  final String cardId;

  void _walletSoon(BuildContext context, String wallet) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('$wallet wkrótce'),
        content: Text(
          'Dodawanie kart do $wallet włączymy razem z płatnościami przed premierą. '
          'Na razie pokaż obsłudze kod QR z tego ekranu.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Rozumiem')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(myGiftCardsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Karta podarunkowa')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myGiftCardsProvider)),
        data: (cards) {
          final card = cards.where((c) => c.id == cardId).firstOrNull;
          if (card == null) {
            return const MessageView(
              icon: AppIcons.envelope,
              title: 'Nie znaleziono karty',
              message: 'Ta karta nie należy do Twojego konta.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _GiftCardFace(card: card),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: QrImageView(
                          data: card.code,
                          size: 180,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF161616)),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Color(0xFF161616),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SelectableText(
                        card.code,
                        style: text.titleLarge?.copyWith(letterSpacing: 2, fontFeatures: _tabular),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pokaż kod obsłudze przy płatności.',
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: card.code));
                          showMessage(context, 'Skopiowano kod karty.');
                        },
                        icon: const Glyph(AppIcons.copy, size: 16),
                        label: const Text('Kopiuj kod'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _WalletButton(
                label: 'Dodaj do Apple Wallet',
                onTap: () => _walletSoon(context, 'Apple Wallet'),
              ),
              const SizedBox(height: 10),
              _WalletButton(
                label: 'Dodaj do Google Wallet',
                onTap: () => _walletSoon(context, 'Google Wallet'),
              ),
              if (card.message != null) ...[
                const SizedBox(height: 20),
                Text('Życzenia', style: text.titleSmall),
                const SizedBox(height: 4),
                Text('„${card.message}”', style: text.bodyLarge?.copyWith(fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 20),
              Text(
                'Kupiona ${Fmt.dayLong(card.createdAt)}. Ważna do ${Fmt.dayLong(card.expiresAt)}.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WalletButton extends StatelessWidget {
  const _WalletButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Glyph(AppIcons.plus, size: 18),
      label: Text(label),
    );
  }
}

/// Karta w stylu portfela: logo, nazwa lokalu i saldo.
class _GiftCardFace extends StatelessWidget {
  const _GiftCardFace({required this.card, this.compact = false});

  final GuestGiftCard card;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final usable = card.isUsable;
    final state = card.status != 'active'
        ? 'UNIEWAŻNIONA'
        : card.isExpired
        ? 'PO TERMINIE'
        : card.balanceGrosze == 0
        ? 'WYKORZYSTANA'
        : null;

    return AspectRatio(
      aspectRatio: compact ? 2.1 : 1.6,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: usable
                ? const [Color(0xFF1F3D34), Color(0xFF0F2520)]
                : const [Color(0xFF3A3D3C), Color(0xFF262827)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RestaurantLogo(name: card.restaurantName, logoUrl: card.logoUrl, size: 36, radius: 10),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    card.restaurantName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(color: Colors.white),
                  ),
                ),
                if (card.testMode)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'TEST',
                      style: text.labelSmall?.copyWith(color: Colors.white),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Text(
              'Saldo',
              style: text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
            ),
            Text(
              Fmt.price(card.balanceGrosze),
              style: (compact ? text.headlineMedium : text.displaySmall)?.copyWith(
                color: usable ? const Color(0xFF00F8B9) : Colors.white70,
                fontFeatures: _tabular,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              state ??
                  [
                    'z ${Fmt.price(card.initialGrosze)}',
                    if (card.recipientName != null) 'dla: ${card.recipientName}',
                  ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.7), fontFeatures: _tabular),
            ),
          ],
        ),
      ),
    );
  }
}

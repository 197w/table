import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

const _tabular = [FontFeature.tabularFigures()];

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

// ---------------------------------------------------------------
// Menu z koszykiem
// ---------------------------------------------------------------

/// Zamawianie z dostawą albo na wynos: menu lokalu z przyciskiem „Dodaj” i koszykiem na dole.
class OrderMenuScreen extends ConsumerWidget {
  const OrderMenuScreen({super.key, required this.restaurantId});

  final String restaurantId;

  Future<void> _add(BuildContext context, WidgetRef ref, MenuItem item) async {
    final line = item.variants.isEmpty && item.addons.isEmpty
        ? CartLine(menuItemId: item.id, name: item.name, unitPriceGrosze: item.priceGrosze, quantity: 1)
        : await showModalBottomSheet<CartLine>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (_) => _OptionsSheet(item: item),
          );
    if (line == null) return;
    HapticFeedback.selectionClick();
    ref.read(cartProvider(restaurantId).notifier).add(line);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(restaurantProvider(restaurantId));
    final cart = ref.watch(cartProvider(restaurantId));
    final count = cart.fold(0, (s, l) => s + l.quantity);
    final total = cart.fold(0, (s, l) => s + l.totalGrosze);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(async.value == null ? 'Zamów' : 'Zamów · ${async.value!.name}')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(restaurantProvider(restaurantId))),
        data: (r) {
          if (!r.canOrder) {
            return const MessageView(
              icon: AppIcons.shoppingBag,
              title: 'Lokal nie przyjmuje zamówień',
              message: 'Ten lokal nie ma jeszcze dostawy ani odbioru osobistego w aplikacji.',
            );
          }
          final sections = [for (final s in r.menu) if (s.items.isNotEmpty) s];
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, (count > 0 ? 110 : 32) + MediaQuery.paddingOf(context).bottom),
            children: [
              _OrderInfo(restaurant: r),
              const SizedBox(height: 12),
              for (final s in sections) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text(s.name, style: text.titleLarge),
                ),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, item) in s.items.indexed) ...[
                        if (i > 0) Divider(height: 1, color: AppColors.ring),
                        _DishRow(
                          item: item,
                          inCart: cart.where((l) => l.menuItemId == item.id).fold(0, (s, l) => s + l.quantity),
                          onAdd: item.available ? () => _add(context, ref, item) : null,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: count == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: PressScale(
                  onTap: () => context.push(AppRoutes.checkout(restaurantId)),
                  child: Container(
                    height: 60,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: AppColors.accentFill,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.onAccent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: text.titleSmall?.copyWith(color: AppColors.onAccent, fontFeatures: _tabular),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('Koszyk', style: text.titleMedium?.copyWith(color: AppColors.onAccent)),
                        const Spacer(),
                        Text(
                          Fmt.price(total),
                          style: text.titleMedium?.copyWith(color: AppColors.onAccent, fontFeatures: _tabular),
                        ),
                        const SizedBox(width: 6),
                        Glyph(AppIcons.caretRight, size: 18, color: AppColors.onAccent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Dostawa, odbiór, opłata i minimalne zamówienie w jednym miejscu nad menu.
class _OrderInfo extends StatelessWidget {
  const _OrderInfo({required this.restaurant});

  final RestaurantDetail restaurant;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = restaurant;
    final lines = [
      if (r.deliveryEnabled)
        'Dostawa ${r.deliveryFeeGrosze == 0 ? 'gratis' : Fmt.price(r.deliveryFeeGrosze)}'
            '${r.deliveryMinGrosze > 0 ? ' · min. ${Fmt.price(r.deliveryMinGrosze)}' : ''}',
      if (r.pickupEnabled) 'Odbiór osobisty: ${r.address}',
      if (r.deliveryArea != null) r.deliveryArea!,
      r.takeawayCash ? 'Płatność kartą online albo gotówką' : 'Płatność kartą online',
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Glyph(AppIcons.moped, size: 22, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final l in lines) Text(l, style: text.bodyMedium?.copyWith(fontFeatures: _tabular))],
            ),
          ),
        ],
      ),
    );
  }
}

class _DishRow extends StatelessWidget {
  const _DishRow({required this.item, required this.inCart, required this.onAdd});

  final MenuItem item;
  final int inCart;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onAdd,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: text.titleMedium?.copyWith(color: item.available ? null : AppColors.textMuted),
                  ),
                  if (item.description != null)
                    Text(
                      item.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    !item.available
                        ? 'Chwilowo niedostępne'
                        : item.priceVaries
                        ? 'od ${Fmt.price(item.priceGrosze)}'
                        : Fmt.price(item.priceGrosze),
                    style: text.titleSmall?.copyWith(
                      color: item.available ? AppColors.accent : AppColors.error,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
            ),
            if (item.photoUrl != null) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  item.photoUrl!,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  cacheWidth: 192,
                  errorBuilder: (_, _, _) => const SizedBox(width: 64, height: 64),
                ),
              ),
            ],
            const SizedBox(width: 8),
            if (onAdd != null)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                child: inCart == 0
                    ? IconButton.filledTonal(
                        key: const ValueKey('add'),
                        tooltip: 'Dodaj',
                        onPressed: onAdd,
                        icon: const Glyph(AppIcons.plus, size: 18),
                      )
                    : Container(
                        key: ValueKey('count-$inCart'),
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.accentFill, shape: BoxShape.circle),
                        child: Text(
                          '$inCart',
                          style: text.titleSmall?.copyWith(color: AppColors.onAccent, fontFeatures: _tabular),
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Wybór wariantu (jeden) i dodatków (kilka) przed dodaniem do koszyka.
class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({required this.item});

  final MenuItem item;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late MenuOption? _variant = widget.item.variants.firstOrNull;
  final _addons = <MenuOption>{};
  int _quantity = 1;

  int get _unit => (_variant?.priceGrosze ?? widget.item.priceGrosze) + _addons.fold(0, (s, a) => s + a.priceGrosze);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = widget.item;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(item.name, style: text.titleLarge),
          if (item.variants.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Wybierz', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in item.variants)
                  ChoiceChip(
                    selected: _variant == v,
                    onSelected: (_) => setState(() => _variant = v),
                    label: Text('${v.name} · ${Fmt.price(v.priceGrosze)}'),
                  ),
              ],
            ),
          ],
          if (item.addons.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text('Dodatki', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in item.addons)
                  FilterChip(
                    selected: _addons.contains(a),
                    onSelected: (v) => setState(() => v ? _addons.add(a) : _addons.remove(a)),
                    label: Text('${a.name} +${Fmt.price(a.priceGrosze)}'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              IconButton.outlined(
                onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                icon: const Glyph(AppIcons.minus, size: 18),
              ),
              SizedBox(
                width: 44,
                child: Text('$_quantity', textAlign: TextAlign.center, style: text.titleLarge?.copyWith(fontFeatures: _tabular)),
              ),
              IconButton.outlined(
                onPressed: _quantity < 20 ? () => setState(() => _quantity++) : null,
                icon: const Glyph(AppIcons.plus, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    CartLine(
                      menuItemId: item.id,
                      name: item.name,
                      unitPriceGrosze: _unit,
                      quantity: _quantity,
                      variant: _variant?.name,
                      addons: [for (final a in item.addons) if (_addons.contains(a)) a.name],
                    ),
                  ),
                  child: Text('Dodaj · ${Fmt.price(_unit * _quantity)}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// Koszyk i zamówienie
// ---------------------------------------------------------------

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  OrderKind? _kind;
  PaymentChoice _payment = PaymentChoice.card;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  bool _prefilled = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _street.dispose();
    _city.dispose();
    _note.dispose();
    super.dispose();
  }

  void _prefill(Profile? profile, RestaurantDetail r) {
    if (_prefilled) return;
    _prefilled = true;
    _name.text = profile?.firstName ?? profile?.fullName ?? '';
    _phone.text = profile?.phone == null ? '' : Fmt.phone(profile!.phone);
    _city.text = r.city;
  }

  Future<void> _submit(RestaurantDetail r, List<CartLine> cart) async {
    final kind = _kind!;
    final subtotal = cart.fold(0, (s, l) => s + l.totalGrosze);
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      showMessage(context, 'Podaj imię i numer telefonu, żeby lokal i dostawca mogli się z Tobą skontaktować.',
          tone: ToastTone.warning);
      return;
    }
    if (kind == OrderKind.delivery && _street.text.trim().isEmpty) {
      showMessage(context, 'Podaj ulicę i numer domu.', tone: ToastTone.warning);
      return;
    }
    if (kind == OrderKind.delivery && subtotal < r.deliveryMinGrosze) {
      showMessage(context, 'Minimalne zamówienie z dostawą to ${Fmt.price(r.deliveryMinGrosze)}.', tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(repositoryProvider);
    try {
      final id = await repo.placeOrder(
        restaurantId: r.id,
        kind: kind,
        lines: cart,
        payment: _payment,
        name: _name.text,
        phone: _phone.text,
        address: kind == OrderKind.delivery ? '${_street.text.trim()}, ${_city.text.trim()}' : null,
        note: _note.text,
      );
      if (_payment == PaymentChoice.card) {
        if (!mounted) return;
        final paid = await showModalBottomSheet<bool>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => _CardPaymentSheet(orderId: id, totalGrosze: subtotal + (kind == OrderKind.delivery ? r.deliveryFeeGrosze : 0)),
        );
        if (paid != true) {
          // Bez płatności zamówienie nie trafia do lokalu. Odwołujemy je, żeby nie wisiało.
          await repo.cancelOrder(id);
          if (mounted) showMessage(context, 'Płatność przerwana. Zamówienie nie zostało wysłane.', tone: ToastTone.warning);
          return;
        }
      }
      ref.read(cartProvider(r.id).notifier).clear();
      ref.invalidate(myOrdersProvider);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      context.go(AppRoutes.orderDetail(id));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(restaurantProvider(widget.restaurantId));
    final cart = ref.watch(cartProvider(widget.restaurantId));
    final profile = ref.watch(profileProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Koszyk')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(restaurantProvider(widget.restaurantId))),
        data: (r) {
          if (cart.isEmpty) {
            return MessageView(
              icon: AppIcons.shoppingBag,
              title: 'Koszyk jest pusty',
              message: 'Dodaj dania z menu lokalu.',
              actionLabel: 'Wróć do menu',
              onAction: () => context.pop(),
            );
          }
          _prefill(profile, r);
          final kind = _kind ??= r.deliveryEnabled ? OrderKind.delivery : OrderKind.pickup;
          if (!r.takeawayCash) _payment = PaymentChoice.card;
          final subtotal = cart.fold(0, (s, l) => s + l.totalGrosze);
          final fee = kind == OrderKind.delivery ? r.deliveryFeeGrosze : 0;
          final belowMin = kind == OrderKind.delivery && subtotal < r.deliveryMinGrosze;

          return ListView(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 32 + MediaQuery.paddingOf(context).bottom),
            children: [
              Text(r.name, style: text.titleLarge),
              const SizedBox(height: 12),
              if (r.deliveryEnabled && r.pickupEnabled)
                SegmentedButton<OrderKind>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: OrderKind.delivery, label: Text('Dostawa')),
                    ButtonSegment(value: OrderKind.pickup, label: Text('Odbiór osobisty')),
                  ],
                  selected: {kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                )
              else
                Text(kind.label, style: text.titleMedium),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Column(
                    children: [
                      for (final l in cart)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l.name, style: text.titleSmall),
                                    if (l.details != null)
                                      Text(l.details!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                                    Text(Fmt.price(l.totalGrosze), style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: l.quantity == 1 ? 'Usuń' : 'Mniej',
                                onPressed: () => ref.read(cartProvider(r.id).notifier).setQuantity(l.key, l.quantity - 1),
                                icon: Glyph(l.quantity == 1 ? AppIcons.trash : AppIcons.minus, size: 18),
                              ),
                              Text('${l.quantity}', style: text.titleMedium?.copyWith(fontFeatures: _tabular)),
                              IconButton(
                                tooltip: 'Więcej',
                                onPressed: l.quantity >= 99
                                    ? null
                                    : () => ref.read(cartProvider(r.id).notifier).setQuantity(l.key, l.quantity + 1),
                                icon: const Glyph(AppIcons.plus, size: 18),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(kind == OrderKind.delivery ? 'Dokąd dowieźć' : 'Kto odbiera', style: text.titleMedium),
              const SizedBox(height: 10),
              TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Imię')),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefon'),
              ),
              if (kind == OrderKind.delivery) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _street,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Ulica, numer domu i mieszkania'),
                ),
                const SizedBox(height: 10),
                TextField(controller: _city, decoration: const InputDecoration(labelText: 'Miasto')),
              ] else ...[
                const SizedBox(height: 8),
                Text('Odbiór: ${r.address}, ${r.city}', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                maxLength: 300,
                decoration: InputDecoration(
                  labelText: 'Uwagi (opcjonalnie)',
                  hintText: kind == OrderKind.delivery ? 'Na przykład: domofon 12, drugie piętro' : 'Na przykład: bez cebuli',
                ),
              ),
              const SizedBox(height: 8),
              Text('Płatność', style: text.titleMedium),
              const SizedBox(height: 10),
              _PaymentOption(
                icon: AppIcons.creditCard,
                title: 'Karta online',
                subtitle: 'Płacisz teraz w aplikacji',
                selected: _payment == PaymentChoice.card,
                onTap: () => setState(() => _payment = PaymentChoice.card),
              ),
              if (r.takeawayCash) ...[
                const SizedBox(height: 8),
                _PaymentOption(
                  icon: AppIcons.money,
                  title: 'Gotówka',
                  subtitle: kind == OrderKind.delivery ? 'Płacisz dostawcy przy drzwiach' : 'Płacisz przy odbiorze w lokalu',
                  selected: _payment == PaymentChoice.cash,
                  onTap: () => setState(() => _payment = PaymentChoice.cash),
                ),
              ],
              const SizedBox(height: 20),
              _SumRow(label: 'Dania', value: subtotal),
              if (kind == OrderKind.delivery) _SumRow(label: 'Dostawa', value: fee),
              const SizedBox(height: 4),
              _SumRow(label: 'Razem', value: subtotal + fee, strong: true),
              if (belowMin)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Do minimalnego zamówienia z dostawą brakuje ${Fmt.price(r.deliveryMinGrosze - subtotal)}.',
                    style: text.bodyMedium?.copyWith(color: AppColors.error),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || belowMin ? null : () => _submit(r, cart),
                child: Text(
                  _payment == PaymentChoice.card
                      ? 'Zamawiam i płacę ${Fmt.price(subtotal + fee)}'
                      : 'Zamawiam · ${Fmt.price(subtotal + fee)}',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PaymentOption extends StatelessWidget {
  const _PaymentOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final AppIconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentTint : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.accent : AppColors.ring, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Glyph(icon, size: 22, color: selected ? AppColors.accent : AppColors.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall),
                  Text(subtitle, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ),
            Glyph(selected ? AppIcons.checkCircle : AppIcons.circle, size: 20, color: selected ? AppColors.accent : AppColors.ring),
          ],
        ),
      ),
    );
  }
}

class _SumRow extends StatelessWidget {
  const _SumRow({required this.label, required this.value, this.strong = false});

  final String label;
  final int value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = (strong ? text.titleLarge : text.bodyLarge)?.copyWith(fontFeatures: _tabular);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: strong ? text.titleMedium : text.bodyLarge?.copyWith(color: AppColors.textMuted)),
          const Spacer(),
          Text(Fmt.price(value), style: style),
        ],
      ),
    );
  }
}

/// Płatność kartą online. Bez operatora płatności działa tryb testowy: nic nie jest pobierane.
class _CardPaymentSheet extends ConsumerStatefulWidget {
  const _CardPaymentSheet({required this.orderId, required this.totalGrosze});

  final String orderId;
  final int totalGrosze;

  @override
  ConsumerState<_CardPaymentSheet> createState() => _CardPaymentSheetState();
}

class _CardPaymentSheetState extends ConsumerState<_CardPaymentSheet> {
  bool _busy = false;

  Future<void> _pay() async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).payOrderTest(widget.orderId);
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
              Text('Płatność kartą', style: text.titleLarge),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Text('Do zapłaty', style: text.titleMedium),
                const Spacer(),
                Text(Fmt.price(widget.totalGrosze), style: text.headlineSmall?.copyWith(fontFeatures: _tabular)),
              ],
            ),
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
                'Tryb testowy: płatności kartą nie są jeszcze podłączone. Nic nie zostanie pobrane, '
                'a zamówienie trafi do lokalu jako opłacone.',
                style: text.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy || !test ? null : _pay,
            child: Text(_busy ? 'Płacę…' : 'Zapłać ${Fmt.price(widget.totalGrosze)}'),
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

// ---------------------------------------------------------------
// Śledzenie zamówienia
// ---------------------------------------------------------------

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  Future<void> _cancel(BuildContext context, WidgetRef ref, GuestOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Odwołać zamówienie #${order.number}?'),
        content: Text(order.paid ? 'Pieniądze wrócą na kartę.' : 'Lokal jeszcze go nie przyjął.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Zostaw')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Odwołaj'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(repositoryProvider).cancelOrder(order.id);
      ref
        ..invalidate(guestOrderProvider(order.id))
        ..invalidate(myOrdersProvider);
      if (context.mounted) showMessage(context, 'Zamówienie odwołane.');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(guestOrderProvider(orderId));
    return Scaffold(
      appBar: AppBar(title: Text(async.value == null ? 'Zamówienie' : 'Zamówienie #${async.value!.number}')),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(guestOrderProvider(orderId))),
        data: (o) {
          if (o == null) {
            return const MessageView(icon: AppIcons.receipt, title: 'Nie ma takiego zamówienia', message: 'Mogło należeć do innego konta.');
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(guestOrderProvider(orderId)),
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 32 + MediaQuery.paddingOf(context).bottom),
              children: [
                Text(o.restaurantName, style: text.titleLarge),
                Text(
                  '${o.kind.label} · ${Fmt.dateTime(o.openedAt)}',
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 16),
                _StageCard(order: o),
                const SizedBox(height: 16),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final i in o.items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 30,
                                  child: Text('${i.quantity}×',
                                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular)),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(i.name, style: text.bodyMedium),
                                      if (i.details != null)
                                        Text(i.details!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                                    ],
                                  ),
                                ),
                                Text(Fmt.price(i.totalGrosze), style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
                              ],
                            ),
                          ),
                        if (o.feeGrosze > 0) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(child: Text('Dostawa', style: text.bodyMedium?.copyWith(color: AppColors.textMuted))),
                              Text(Fmt.price(o.feeGrosze), style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
                            ],
                          ),
                        ],
                        Divider(height: 20, color: AppColors.ring),
                        Row(
                          children: [
                            Expanded(child: Text('Razem', style: text.titleMedium)),
                            Text(Fmt.price(o.totalGrosze), style: text.titleLarge?.copyWith(fontFeatures: _tabular)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          o.payment == PaymentChoice.cash
                              ? 'Gotówka ${o.kind == OrderKind.delivery ? 'u dostawcy' : 'przy odbiorze'}'
                              : 'Karta online · ${o.paid ? 'opłacone' : 'nieopłacone'}${o.testPayment ? ' (test)' : ''}',
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  o.kind == OrderKind.delivery ? 'Dostawa: ${o.address ?? ''}' : 'Odbiór: ${o.restaurantAddress}',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: o.restaurantPhone)),
                  icon: const Glyph(AppIcons.phone, size: 18),
                  label: const Text('Zadzwoń do lokalu'),
                ),
                if (o.canCancel) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _cancel(context, ref, o),
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text('Odwołaj zamówienie'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Postęp zamówienia: kroki od złożenia do dostarczenia, na żywo.
class _StageCard extends StatelessWidget {
  const _StageCard({required this.order});

  final GuestOrder order;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final o = order;
    if (o.stage == OrderStage.rejected || o.stage == OrderStage.cancelled) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Glyph(AppIcons.prohibit, size: 26, color: AppColors.error),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(o.stage == OrderStage.rejected ? 'Lokal odrzucił zamówienie' : 'Zamówienie odwołane',
                        style: text.titleMedium),
                    if (o.rejectReason != null)
                      Text(o.rejectReason!, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final delivery = o.kind == OrderKind.delivery;
    final steps = [
      ('Złożone', 'Czekamy, aż lokal potwierdzi'),
      ('Przygotowujemy', o.promisedAt == null ? 'Kuchnia robi Twoje zamówienie' : 'Gotowe ok. ${_hm(o.promisedAt!)}'),
      if (delivery) ('W drodze', 'Dostawca jedzie do Ciebie') else ('Gotowe do odbioru', 'Zapraszamy do lokalu'),
      (delivery ? 'Dostarczone' : 'Odebrane', 'Smacznego!'),
    ];
    final current = switch (o.stage) {
      OrderStage.awaitingPayment || OrderStage.placed => 0,
      OrderStage.accepted => 1,
      OrderStage.ready => delivery ? 1 : 2,
      OrderStage.onTheWay => 2,
      _ => 3,
    };
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        child: Column(
          children: [
            for (final (i, (title, hint)) in steps.indexed)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= current ? AppColors.accentFill : Colors.transparent,
                          border: Border.all(color: i <= current ? AppColors.accentFill : AppColors.ringStrong, width: 2),
                        ),
                        child: i < current || (i == current && i == steps.length - 1)
                            ? Glyph(AppIcons.check, size: 13, color: AppColors.onAccent)
                            : null,
                      ),
                      if (i < steps.length - 1)
                        Container(width: 2, height: 30, color: i < current ? AppColors.accentFill : AppColors.ring),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: text.titleSmall?.copyWith(color: i <= current ? AppColors.text : AppColors.textMuted),
                          ),
                          if (i == current)
                            Text(hint, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Lista moich zamówień w zakładce Rezerwacje.
class MyOrdersList extends ConsumerWidget {
  const MyOrdersList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final async = ref.watch(myOrdersProvider);
    return async.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myOrdersProvider)),
      data: (orders) {
        final visible = orders.where((o) => o.stage != OrderStage.awaitingPayment).toList();
        if (visible.isEmpty) {
          return MessageView(
            icon: AppIcons.shoppingBag,
            title: 'Nie masz jeszcze zamówień',
            message: 'Zamów z dostawą albo na wynos w lokalu z przyciskiem „Zamów”.',
            actionLabel: 'Odkrywaj lokale',
            onAction: () => context.go(AppRoutes.discover),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myOrdersProvider);
            await ref.read(myOrdersProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              for (final o in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PressScale(
                    onTap: () => context.push(AppRoutes.orderDetail(o.id)),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Glyph(
                              o.kind == OrderKind.delivery ? AppIcons.moped : AppIcons.shoppingBag,
                              size: 24,
                              color: o.stage.finished ? AppColors.textMuted : AppColors.accent,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${o.restaurantName} · #${o.number}', style: text.titleSmall),
                                  Text(
                                    '${Fmt.dateTime(o.openedAt)} · ${Fmt.price(o.totalGrosze)}',
                                    style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                                  ),
                                ],
                              ),
                            ),
                            Tag(
                              o.stage.label.toUpperCase(),
                              color: o.stage.finished
                                  ? (o.stage == OrderStage.delivered ? AppColors.textMuted : AppColors.error)
                                  : AppColors.accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

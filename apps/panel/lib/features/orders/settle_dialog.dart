import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import 'discount_code_field.dart';
import 'person_badge.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Formy płatności przy stoliku (karty podarunkowe zostały tylko w historii).
const _methods = [PaymentMethod.cash, PaymentMethod.card, PaymentMethod.other];

enum _Mode {
  whole('Całość'),
  equal('Równo'),
  items('Po pozycjach');

  const _Mode(this.label);
  final String label;
}

/// VAT zawarty w kwocie brutto przy danej stawce.
int _vatOf(int gross, int rate) => (gross * rate / (100 + rate)).round();

/// Zamknięcie rachunku: rabat (kod wpisany przy rachunku albo z rezerwacji), napiwek i płatność całości, równy podział na osoby
/// albo płatność za wybrane pozycje (reszta zostaje na stoliku). Zwraca true, gdy rachunek jest zamknięty.
class SettleDialog extends ConsumerStatefulWidget {
  const SettleDialog({super.key, required this.restaurantId, required this.orderId, required this.title});

  final String restaurantId;
  final String orderId;
  final String title;

  @override
  ConsumerState<SettleDialog> createState() => _SettleDialogState();
}

class _SettleDialogState extends ConsumerState<SettleDialog> {
  var _mode = _Mode.whole;
  var _method = PaymentMethod.cash;
  final _tip = TextEditingController();
  final _received = TextEditingController();
  int _people = 2;
  final _personMethods = <int, PaymentMethod>{};
  final _personTips = <int, TextEditingController>{};
  final _picked = <String, int>{};
  bool _busy = false;

  @override
  void dispose() {
    _tip.dispose();
    _received.dispose();
    for (final c in _personTips.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _money(TextEditingController c) => c.text.trim().isEmpty ? 0 : (parseGrosze(c.text) ?? 0);

  TextEditingController _personTip(int i) => _personTips.putIfAbsent(i, TextEditingController.new);

  PanelOrder? _order() {
    for (final o in ref.watch(openOrdersProvider(widget.restaurantId)).value ?? const <PanelOrder>[]) {
      if (o.id == widget.orderId) return o;
    }
    return null;
  }

  Future<void> _run(Future<void> Function() action, {required bool closes, required String message}) async {
    setState(() => _busy = true);
    try {
      await action();
      ref
        ..invalidate(openOrdersProvider(widget.restaurantId))
        ..invalidate(orderDueProvider(widget.orderId));
      if (!mounted) return;
      showMessage(context, message, tone: ToastTone.success);
      if (closes) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _picked.clear();
          _tip.clear();
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _memberId => ref.read(panelMemberProvider)?.dbMemberId;

  Future<void> _payWhole(OrderDue due) {
    final tip = _money(_tip);
    return _run(
      () => ref.read(repositoryProvider).settleOrder(
        widget.orderId,
        [PaymentPart(_method, due.dueGrosze, tipGrosze: tip)],
        memberId: _memberId,
      ),
      closes: true,
      message: 'Rachunek zamknięty: ${Fmt.price(due.dueGrosze)}, ${_method.label.toLowerCase()}'
          '${tip > 0 ? ', napiwek ${Fmt.price(tip)}' : ''}.',
    );
  }

  Future<void> _payEqual(OrderDue due) {
    final parts = splitEqually(due.dueGrosze, _people);
    return _run(
      () => ref.read(repositoryProvider).settleOrder(
        widget.orderId,
        [
          for (final (i, amount) in parts.indexed)
            PaymentPart(_personMethods[i] ?? PaymentMethod.cash, amount, tipGrosze: _money(_personTip(i))),
        ],
        memberId: _memberId,
      ),
      closes: true,
      message: 'Rachunek zamknięty: ${Fmt.price(due.dueGrosze)} na $_people osoby.',
    );
  }

  Future<void> _payItems(PanelOrder order, OrderDue due) {
    final part = _partTotal(order);
    final (_, partDue) = due.forPart(part);
    final all = order.active.every((i) => (_picked[i.id] ?? 0) == i.quantity);
    final tip = _money(_tip);
    return _run(
      () => ref.read(repositoryProvider).payItems(
        widget.orderId,
        Map.of(_picked),
        [PaymentPart(_method, all ? due.dueGrosze : partDue, tipGrosze: tip)],
        memberId: _memberId,
      ),
      closes: all,
      message: all
          ? 'Rachunek zamknięty: ${Fmt.price(due.dueGrosze)}.'
          : 'Opłacono część: ${Fmt.price(partDue)}, ${_method.label.toLowerCase()}. Reszta zostaje na stoliku.',
    );
  }

  int _partTotal(PanelOrder order) => order.active.fold(
    0,
    (s, i) => s + (_picked[i.id] ?? 0) * (i.quantity == 0 ? 0 : i.totalGrosze ~/ i.quantity),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final order = _order();
    final dueAsync = ref.watch(orderDueProvider(widget.orderId));
    final due = dueAsync.value;

    if (order == null) {
      return AlertDialog(
        title: Text(widget.title),
        content: const SizedBox(width: 560, height: 120, child: LoadingView()),
      );
    }

    final vat = order.byVat.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    final part = _partTotal(order);
    final (partDiscount, partDue) = due?.forPart(part) ?? (0, part);
    final tip = _money(_tip);
    final payDue = _mode == _Mode.items ? partDue : (due?.dueGrosze ?? order.totalGrosze);
    final received = parseGrosze(_received.text);
    final change = received == null ? null : received - payDue - tip;

    Widget money(String label, int value, {TextStyle? style, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: (style ?? text.bodyMedium)?.copyWith(color: color))),
          Text(Fmt.price(value), style: (style ?? text.bodyMedium)?.copyWith(color: color, fontFeatures: _tabular)),
        ],
      ),
    );

    Widget methodPicker(PaymentMethod value, ValueChanged<PaymentMethod> onChanged) => SegmentedTabs<PaymentMethod>(
      options: [for (final m in _methods) (m, m.label)],
      selected: value,
      onChanged: onChanged,
    );

    Widget tipField(TextEditingController c, int base, {bool quick = true}) => Row(
      children: [
        SizedBox(
          width: 140,
          child: TextField(
            controller: c,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
            textAlign: TextAlign.right,
            style: const TextStyle(fontFeatures: _tabular),
            decoration: const InputDecoration(labelText: 'Napiwek', suffixText: 'zł', isDense: true),
          ),
        ),
        if (quick && base > 0) ...[
          const SizedBox(width: 8),
          for (final pct in const [5, 10, 15])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: OutlinedButton(
                onPressed: () => setState(() => c.text = groszeToText((base * pct / 100).round())),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text('$pct%'),
              ),
            ),
        ],
      ],
    );

    final itemsList = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in order.active)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 34,
                  child: Text('${i.quantity}×', style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular)),
                ),
                Expanded(child: Text([i.name, ?i.details].join(' · '), style: text.bodyMedium)),
                Text(Fmt.price(i.totalGrosze), style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
              ],
            ),
          ),
      ],
    );

    // Podział z nabijania: osoby z pozycjami i ich kwoty.
    final guests = {for (final i in order.active) ?i.guestNo}.toList()..sort();
    final shared = order.active.where((i) => i.guestNo == null).toList();
    int sumOf(Iterable<OrderItem> items) => items.fold(0, (s, i) => s + i.totalGrosze);
    void pickGuest(int? guest) => setState(() {
      _picked
        ..clear()
        ..addAll({for (final i in order.active) if (i.guestNo == guest) i.id: i.quantity});
    });

    // Wybór pozycji do zapłaty: ile sztuk każdej pozycji płaci ta osoba.
    final itemPicker = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (guests.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final g in guests)
                ActionChip(
                  avatar: PersonBadge(g, size: 18),
                  label: Text(
                    'Osoba $g · ${Fmt.price(sumOf(order.active.where((i) => i.guestNo == g)))}',
                    style: const TextStyle(fontFeatures: _tabular),
                  ),
                  onPressed: () => pickGuest(g),
                ),
              if (shared.isNotEmpty)
                ActionChip(
                  label: Text('Wspólne · ${Fmt.price(sumOf(shared))}', style: const TextStyle(fontFeatures: _tabular)),
                  onPressed: () => pickGuest(null),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        for (final i in order.active)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                if (i.guestNo case final g?) ...[PersonBadge(g, size: 18), const SizedBox(width: 6)],
                Expanded(child: Text([i.name, ?i.details].join(' · '), style: text.bodyMedium)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: (_picked[i.id] ?? 0) == 0 ? null : () => setState(() => _picked[i.id] = _picked[i.id]! - 1),
                  icon: const Glyph(AppIcons.minus, size: 16),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${_picked[i.id] ?? 0}/${i.quantity}',
                    textAlign: TextAlign.center,
                    style: text.titleSmall?.copyWith(
                      fontFeatures: _tabular,
                      color: (_picked[i.id] ?? 0) > 0 ? AppColors.accent : AppColors.textMuted,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: (_picked[i.id] ?? 0) >= i.quantity
                      ? null
                      : () => setState(() => _picked[i.id] = (_picked[i.id] ?? 0) + 1),
                  icon: const Glyph(AppIcons.plus, size: 16),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    Fmt.price((_picked[i.id] ?? 0) * (i.totalGrosze ~/ i.quantity)),
                    textAlign: TextAlign.right,
                    style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    final equalParts = splitEqually(due?.dueGrosze ?? order.totalGrosze, _people);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedTabs<_Mode>(
                  options: [for (final m in _Mode.values) (m, m.label)],
                  selected: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
              ),
              const SizedBox(height: 14),
              if (_mode == _Mode.items) itemPicker else itemsList,
              const SizedBox(height: 8),
              Divider(height: 1, color: AppColors.ring),
              const SizedBox(height: 12),
              DiscountCodeField(restaurantId: widget.restaurantId, orderId: widget.orderId, due: due),
              const SizedBox(height: 12),
              money('Suma', order.totalGrosze, color: AppColors.textMuted),
              if (due != null && due.discountGrosze > 0)
                money('Rabat ${due.label ?? ''}', -due.discountGrosze, color: AppColors.accent),
              if (due != null && due.depositGrosze > 0)
                money('Zadatek z rezerwacji', -due.depositGrosze, color: AppColors.accent),
              money('Do zapłaty', due?.dueGrosze ?? order.totalGrosze, style: text.titleLarge),
              for (final e in vat)
                Row(
                  children: [
                    Text('w tym VAT ${e.key}%', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                    const Spacer(),
                    Text(
                      Fmt.price(_vatOf(e.value, e.key)),
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                    ),
                  ],
                ),
              const SizedBox(height: 18),
              switch (_mode) {
                _Mode.whole || _Mode.items => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_mode == _Mode.items) ...[
                      money('Wybrane pozycje', part),
                      if (partDiscount > 0) money('Rabat', -partDiscount, color: AppColors.accent),
                      money('Płaci teraz', partDue, style: text.titleMedium),
                      const SizedBox(height: 14),
                    ],
                    Align(alignment: Alignment.centerLeft, child: methodPicker(_method, (m) => setState(() => _method = m))),
                    const SizedBox(height: 12),
                    tipField(_tip, payDue),
                    if (_method == PaymentMethod.cash) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: TextField(
                              controller: _received,
                              onChanged: (_) => setState(() {}),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontFeatures: _tabular),
                              decoration: const InputDecoration(labelText: 'Otrzymano', suffixText: 'zł', isDense: true),
                            ),
                          ),
                          const SizedBox(width: 16),
                          if (change != null)
                            Text(
                              change >= 0 ? 'Reszta ${Fmt.price(change)}' : 'Brakuje ${Fmt.price(-change)}',
                              style: text.titleMedium?.copyWith(
                                color: change >= 0 ? AppColors.accent : AppColors.error,
                                fontFeatures: _tabular,
                              ),
                            ),
                          // Gość zostawia resztę: idzie do napiwku pracownika, który przyjmuje płatność.
                          if (change != null && change > 0) ...[
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () => setState(() => _tip.text = groszeToText(received! - payDue)),
                              icon: const Glyph(AppIcons.handCoins, size: 16),
                              label: const Text('Bez reszty'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
                _Mode.equal => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('Osób', style: text.titleSmall),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: _people <= 2 ? null : () => setState(() => _people--),
                          icon: const Glyph(AppIcons.minus, size: 16),
                        ),
                        SizedBox(
                          width: 36,
                          child: Text('$_people', textAlign: TextAlign.center, style: text.titleMedium?.copyWith(fontFeatures: _tabular)),
                        ),
                        IconButton(
                          onPressed: _people >= 20 ? null : () => setState(() => _people++),
                          icon: const Glyph(AppIcons.plus, size: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final (i, amount) in equalParts.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                'Osoba ${i + 1} · ${Fmt.price(amount)}',
                                style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                              ),
                            ),
                            const SizedBox(width: 8),
                            methodPicker(
                              _personMethods[i] ?? PaymentMethod.cash,
                              (m) => setState(() => _personMethods[i] = m),
                            ),
                            const SizedBox(width: 8),
                            Expanded(child: tipField(_personTip(i), amount, quick: false)),
                          ],
                        ),
                      ),
                  ],
                ),
              },
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Wróć'),
        ),
        FilledButton(
          onPressed: _busy || due == null
              ? null
              : switch (_mode) {
                  _Mode.whole => () => _payWhole(due),
                  _Mode.equal => () => _payEqual(due),
                  _Mode.items => part == 0 ? null : () => _payItems(order, due),
                },
          child: Text(switch (_mode) {
            _Mode.items => 'Zapłać za wybrane',
            _ => 'Zamknij rachunek',
          }),
        ),
      ],
    );
  }
}

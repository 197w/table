import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];
const _amber = Color(0xFFD99A15);

/// Wybór w oknie „Nowe zamówienie”: stolik (w lokalu) albo dostawa lub odbiór z danymi klienta.
typedef NewOrderChoice = ({DiningTable? table, OrderKind? kind, TakeawayCustomer? customer});

/// „Nowe zamówienie” w Zamówieniach: w lokalu (wybór stolika), na dostawę albo na odbiór osobisty.
/// Dostawę i odbiór przyjmuje się z danymi klienta, a dania dokłada potem z menu.
class NewOrderDialog extends StatefulWidget {
  const NewOrderDialog({
    super.key,
    required this.restaurantId,
    required this.city,
    required this.tables,
    required this.orders,
  });

  final String restaurantId;

  /// Miasto lokalu: podpowiedź w adresie dostawy.
  final String city;
  final List<DiningTable> tables;
  final List<PanelOrder> orders;

  @override
  State<NewOrderDialog> createState() => _NewOrderDialogState();
}

class _NewOrderDialogState extends State<NewOrderDialog> {
  OrderKind _kind = OrderKind.delivery;
  late TakeawayCustomer _customer = TakeawayCustomer(city: widget.city);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final missing = _customer.missing(_kind);
    final busy = {for (final o in widget.orders) ?o.tableId: o};
    final tables = [...widget.tables]
      ..sort((a, b) {
        // Wolne stoliki najpierw, potem po numerze.
        final free = (busy.containsKey(a.id) ? 1 : 0).compareTo(busy.containsKey(b.id) ? 1 : 0);
        return free != 0 ? free : compareTableLabels(a.label, b.label);
      });

    return AlertDialog(
      title: const Text('Nowe zamówienie'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedTabs<OrderKind>(
                  options: const [
                    (OrderKind.dineIn, 'W lokalu'),
                    (OrderKind.delivery, 'Na dostawę'),
                    (OrderKind.pickup, 'Na odbiór'),
                  ],
                  selected: _kind,
                  onChanged: (k) => setState(() => _kind = k),
                ),
              ),
              const SizedBox(height: 18),
              if (_kind == OrderKind.dineIn) ...[
                Text('Wybierz stolik', style: text.titleSmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in tables)
                      _TableChoice(
                        table: t,
                        order: busy[t.id],
                        onTap: () => Navigator.pop<NewOrderChoice>(context, (table: t, kind: null, customer: null)),
                      ),
                  ],
                ),
              ] else
                TakeawayForm(
                  key: ValueKey(_kind),
                  restaurantId: widget.restaurantId,
                  kind: _kind,
                  initial: _customer,
                  onChanged: (c) => setState(() => _customer = c),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        if (_kind != OrderKind.dineIn)
          Tooltip(
            message: missing.isEmpty ? '' : 'Brakuje: ${missing.join(', ')}',
            child: FilledButton.icon(
              onPressed: missing.isEmpty
                  ? () => Navigator.pop<NewOrderChoice>(context, (table: null, kind: _kind, customer: _customer))
                  : null,
              icon: const Glyph(AppIcons.forkKnife, size: 18),
              label: const Text('Dalej: wybierz dania'),
            ),
          ),
      ],
    );
  }
}

/// Zmiana danych klienta zamówienia na wynos. Zwraca nowe dane.
class TakeawayEditDialog extends StatefulWidget {
  const TakeawayEditDialog({super.key, required this.restaurantId, required this.order});

  final String restaurantId;
  final TakeawayOrder order;

  @override
  State<TakeawayEditDialog> createState() => _TakeawayEditDialogState();
}

class _TakeawayEditDialogState extends State<TakeawayEditDialog> {
  late TakeawayCustomer _customer = widget.order.customer;

  @override
  Widget build(BuildContext context) {
    final missing = _customer.missing(widget.order.kind);
    return AlertDialog(
      title: Text('Dane klienta · ${widget.order.label}'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: TakeawayForm(
            restaurantId: widget.restaurantId,
            kind: widget.order.kind,
            initial: _customer,
            onChanged: (c) => setState(() => _customer = c),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: missing.isEmpty ? () => Navigator.pop(context, _customer) : null,
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

/// Numery stolików rosną jak liczby: 2 przed 10.
int compareTableLabels(String a, String b) {
  final na = int.tryParse(a);
  final nb = int.tryParse(b);
  if (na != null && nb != null) return na.compareTo(nb);
  if (na != null) return -1;
  if (nb != null) return 1;
  return a.toLowerCase().compareTo(b.toLowerCase());
}

class _TableChoice extends StatelessWidget {
  const _TableChoice({required this.table, required this.order, required this.onTap});

  final DiningTable table;
  final PanelOrder? order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final open = order != null;
    return PanelPress(
      child: Material(
        color: open ? AppColors.accentTint : AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: open ? AppColors.accent.withValues(alpha: 0.6) : AppColors.ringStrong),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 108, minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${table.isSeat ? 'Miejsce' : 'Stolik'} ${table.label}', style: text.labelLarge),
                  Text(
                    open ? 'otwarty · ${Fmt.price(order!.totalGrosze)}' : 'wolny · ${table.seats} os.',
                    style: text.bodySmall?.copyWith(
                      color: open ? AppColors.accent : AppColors.textMuted,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dane klienta zamówienia na dostawę albo odbiór: telefon (z liczbą i kwotą wcześniejszych zamówień),
/// imię i nazwisko albo nazwa lokalu, NIP, adres, komentarze i płatność. Każda zmiana idzie do [onChanged].
class TakeawayForm extends ConsumerStatefulWidget {
  const TakeawayForm({
    super.key,
    required this.restaurantId,
    required this.kind,
    required this.initial,
    required this.onChanged,
  });

  final String restaurantId;
  final OrderKind kind;
  final TakeawayCustomer initial;
  final ValueChanged<TakeawayCustomer> onChanged;

  @override
  ConsumerState<TakeawayForm> createState() => _TakeawayFormState();
}

class _TakeawayFormState extends ConsumerState<TakeawayForm> {
  late final _phone = TextEditingController(text: widget.initial.phone);
  late final _name = TextEditingController(text: widget.initial.name);
  late final _company = TextEditingController(text: widget.initial.company);
  late final _nip = TextEditingController(text: widget.initial.nip);
  late final _street = TextEditingController(text: widget.initial.street);
  late final _house = TextEditingController(text: widget.initial.house);
  late final _city = TextEditingController(text: widget.initial.city);
  late final _note = TextEditingController(text: widget.initial.note);
  late final _staffNote = TextEditingController(text: widget.initial.staffNote);
  late bool? _paid = widget.initial.paid;

  /// Na którą godzinę. Null: jak najszybciej.
  late DateTime? _when = widget.initial.scheduledFor?.toLocal();
  Timer? _debounce;

  /// Telefon, dla którego szukamy wcześniejszych zamówień (po chwili od ostatniej cyfry).
  late String _lookupPhone = TakeawayCustomer.digits(widget.initial.phone);

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_phone, _name, _company, _nip, _street, _house, _city, _note, _staffNote]) {
      c.dispose();
    }
    super.dispose();
  }

  TakeawayCustomer get _value => TakeawayCustomer(
    name: _name.text,
    company: _company.text,
    nip: _nip.text,
    phone: _phone.text,
    street: _street.text,
    house: _house.text,
    city: _city.text,
    note: _note.text,
    staffNote: _staffNote.text,
    paid: _paid,
    scheduledFor: _when,
  );

  void _changed() {
    setState(() {});
    widget.onChanged(_value);
  }

  void _phoneChanged(String _) {
    _changed();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _lookupPhone = TakeawayCustomer.digits(_phone.text));
    });
  }

  /// „Na godzinę”: domyślnie za godzinę, zaokrąglone w górę do kwadransa.
  void _scheduleOn() {
    if (_when != null) return;
    final t = DateTime.now().add(const Duration(minutes: 60));
    final extra = (15 - t.minute % 15) % 15;
    _when = DateTime(t.year, t.month, t.day, t.hour, t.minute + extra);
    _changed();
  }

  Future<void> _pickTime() async {
    final when = _when;
    if (when == null) return;
    final picked = await pickTime(
      context,
      initial: TimeOfDay(hour: when.hour, minute: when.minute),
      minuteStep: 5,
      title: widget.kind == OrderKind.delivery ? 'Dostawa na godzinę' : 'Odbiór na godzinę',
    );
    if (picked == null || !mounted) return;
    _when = DateTime(when.year, when.month, when.day, picked.hour, picked.minute);
    _changed();
  }

  /// Uzupełnia puste pola danymi z ostatniego zamówienia klienta.
  void _fill(CustomerLookup c) {
    void put(TextEditingController ctrl, String? value) {
      if (ctrl.text.trim().isEmpty && value != null) ctrl.text = value;
    }

    put(_name, c.name);
    put(_company, c.company);
    put(_nip, c.nip);
    if (widget.kind == OrderKind.delivery) {
      var (street, house, city) = (c.street, c.house, c.city);
      // Zamówienie z aplikacji ma adres w jednym napisie: „Lipowa 14/3, Białystok”.
      if (street == null && c.address != null) {
        final m = RegExp(r'^(.*\S)\s+(\S+),\s*(.+)$').firstMatch(c.address!);
        if (m != null) {
          (street, house, city) = (m.group(1), m.group(2), m.group(3));
        } else {
          street = c.address;
        }
      }
      put(_street, street);
      put(_house, house);
      if (city != null) _city.text = city;
    }
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final delivery = widget.kind == OrderKind.delivery;
    final lookup = _lookupPhone.length >= 9
        ? ref.watch(customerLookupProvider((restaurantId: widget.restaurantId, phone: _lookupPhone)))
        : null;
    final missing = _value.missing(widget.kind);

    Widget field(
      TextEditingController c,
      String label, {
      bool required = false,
      String? hint,
      int maxLength = 80,
      TextInputType? keyboard,
      List<TextInputFormatter>? formatters,
      ValueChanged<String>? onChanged,
      int lines = 1,
    }) => TextField(
      controller: c,
      onChanged: onChanged ?? (_) => _changed(),
      keyboardType: keyboard,
      inputFormatters: [LengthLimitingTextInputFormatter(maxLength), ...?formatters],
      minLines: lines,
      maxLines: lines,
      decoration: InputDecoration(labelText: required ? '$label *' : label, hintText: hint, isDense: true),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 220,
              child: field(
                _phone,
                'Telefon',
                required: true,
                maxLength: 20,
                keyboard: TextInputType.phone,
                formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-]'))],
                onChanged: _phoneChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _LookupBox(
                lookup: lookup,
                onFill: (c) => _fill(c),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: field(_name, 'Imię i nazwisko', required: _company.text.trim().isEmpty)),
            const SizedBox(width: 12),
            Expanded(
              child: field(_company, 'Nazwa lokalu (zamiast imienia)', maxLength: 120),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 220,
            child: field(
              _nip,
              'NIP (opcjonalnie)',
              maxLength: 13,
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 \-]'))],
            ),
          ),
        ),
        if (delivery) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(flex: 4, child: field(_street, 'Ulica', required: true, maxLength: 120)),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: field(_house, 'Nr domu/lokalu', required: true, hint: 'np. 14/3', maxLength: 20)),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: field(_city, 'Miasto', required: true)),
            ],
          ),
        ],
        const SizedBox(height: 12),
        field(
          _note,
          'Komentarz do zamówienia',
          hint: delivery ? 'np. domofon 14, drugie piętro' : 'np. odbiór o 18:30',
          maxLength: 300,
          lines: 2,
        ),
        const SizedBox(height: 12),
        field(
          _staffNote,
          'Komentarz tylko dla pracowników',
          hint: 'Klient go nie widzi',
          maxLength: 300,
          lines: 2,
        ),
        const SizedBox(height: 16),
        Text('Na kiedy', style: text.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _PayChoice(
                icon: AppIcons.timer,
                label: 'Jak najszybciej',
                hint: 'Kuchnia zaczyna od razu po przyjęciu.',
                selected: _when == null,
                onTap: () {
                  _when = null;
                  _changed();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PayChoice(
                icon: AppIcons.calendarDots,
                label: _when == null ? 'Na godzinę' : 'Na ${dayTimeLabel(_when!)}',
                hint: delivery ? 'Dostawa u klienta o wybranej godzinie.' : 'Odbiór w lokalu o wybranej godzinie.',
                selected: _when != null,
                onTap: _scheduleOn,
              ),
            ),
          ],
        ),
        if (_when case final at?) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Builder(
                        builder: (_) {
                          final now = DateTime.now();
                          final day = DateTime(now.year, now.month, now.day + i);
                          final selected =
                              at.year == day.year && at.month == day.month && at.day == day.day;
                          return ChoiceChip(
                            label: Text(switch (i) {
                              0 => 'Dziś',
                              1 => 'Jutro',
                              _ => dayTimeLabel(day).split(' ').take(2).join(' '),
                            }),
                            selected: selected,
                            onSelected: (_) {
                              _when = DateTime(day.year, day.month, day.day, at.hour, at.minute);
                              _changed();
                            },
                          );
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Glyph(AppIcons.clock, size: 16),
                label: Text(
                  '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontFeatures: _tabular),
                ),
              ),
            ],
          ),
          if (!at.isAfter(DateTime.now()))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Ta godzina już minęła.',
                style: text.bodySmall?.copyWith(color: AppColors.error),
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text('Płatność *', style: text.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _PayChoice(
                icon: AppIcons.checkCircle,
                label: 'Opłacone',
                hint: 'np. przelew albo BLIK. ${delivery ? 'Dostawca' : 'Obsługa'} nic nie pobiera.',
                selected: _paid == true,
                onTap: () {
                  _paid = true;
                  _changed();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PayChoice(
                icon: AppIcons.money,
                label: 'Do opłacenia',
                hint: delivery ? 'Klient płaci dostawcy.' : 'Klient płaci przy odbiorze.',
                selected: _paid == false,
                onTap: () {
                  _paid = false;
                  _changed();
                },
              ),
            ),
          ],
        ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Brakuje: ${missing.join(', ')}.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// Wcześniejsze zamówienia klienta po numerze telefonu i „Uzupełnij dane”.
class _LookupBox extends StatelessWidget {
  const _LookupBox({required this.lookup, required this.onFill});

  final AsyncValue<CustomerLookup>? lookup;
  final ValueChanged<CustomerLookup> onFill;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final value = lookup?.value;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Glyph(AppIcons.clockBack, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: lookup == null
                ? Text('Po wpisaniu telefonu zobaczysz wcześniejsze zamówienia klienta.', style: muted)
                : value == null
                ? Text(lookup!.hasError ? 'Nie udało się sprawdzić klienta.' : 'Sprawdzam…', style: muted)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value.orders == 0
                            ? 'Nowy klient: brak wcześniejszych zamówień'
                            : 'Wcześniejsze zamówienia: ${value.orders}',
                        style: text.labelLarge?.copyWith(fontFeatures: _tabular),
                      ),
                      if (value.orders > 0)
                        Text(
                          'Łącznie ${Fmt.price(value.spentGrosze)}'
                          '${value.lastAt == null ? '' : ' · ostatnie ${Fmt.dayShort(value.lastAt!)}'}',
                          style: muted,
                        ),
                    ],
                  ),
          ),
          if (value != null && value.known)
            TextButton(onPressed: () => onFill(value), child: const Text('Uzupełnij dane')),
        ],
      ),
    );
  }
}

class _PayChoice extends StatelessWidget {
  const _PayChoice({
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PanelPress(
      child: Material(
        color: selected ? AppColors.accentTint : AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AppColors.accent : AppColors.ringStrong),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                Glyph(icon, size: 20, color: selected ? AppColors.accent : AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: text.labelLarge?.copyWith(color: selected ? AppColors.accent : null)),
                      Text(hint, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dane klienta w karcie zamówienia na wynos: imię albo firma, telefon z historią, adres, komentarze, płatność.
class TakeawayCustomerCard extends ConsumerWidget {
  const TakeawayCustomerCard({super.key, required this.restaurantId, required this.order, this.onEdit});

  final String restaurantId;
  final TakeawayOrder order;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final o = order;
    final lookup = ref.watch(customerLookupProvider((restaurantId: restaurantId, phone: o.customerPhone))).value;

    Widget line(AppIconData icon, String value, {Color? color, TextStyle? style}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Glyph(icon, size: 15, color: color ?? AppColors.textMuted),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: style ?? text.bodyMedium?.copyWith(color: color))),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  o.company ?? o.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
              ),
              if (onEdit != null)
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Glyph(AppIcons.pencil, size: 14),
                  label: const Text('Zmień dane'),
                ),
            ],
          ),
          if (o.company != null && o.personName != null) Text(o.personName!, style: text.bodyMedium),
          if (o.nip != null) Text('NIP ${o.nip}', style: muted),
          line(AppIcons.phone, o.customerPhone, style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
          if (lookup != null)
            Padding(
              padding: const EdgeInsets.only(left: 23, top: 2),
              child: Text(
                lookup.orders == 0
                    ? 'Nowy klient'
                    : 'Wcześniejsze zamówienia: ${lookup.orders} · łącznie ${Fmt.price(lookup.spentGrosze)}',
                style: muted,
              ),
            ),
          if (o.address != null) line(AppIcons.mapPin, o.address!),
          if (o.scheduledFor case final at?)
            line(
              AppIcons.calendarDots,
              '${o.kind == OrderKind.delivery ? 'Dostawa' : 'Odbiór'} na ${dayTimeLabel(at)}',
              color: const Color(0xFFD946EF),
            ),
          if (o.note != null) line(AppIcons.chatText, o.note!, color: _amber),
          if (o.staffNote != null) line(AppIcons.lock, 'Dla pracowników: ${o.staffNote}', color: AppColors.textMuted),
          line(
            o.prepaid ? AppIcons.checkCircle : AppIcons.money,
            o.prepaid ? 'Opłacone' : (o.kind == OrderKind.delivery ? 'Do opłacenia u dostawcy' : 'Do opłacenia przy odbiorze'),
            color: o.prepaid ? AppColors.accent : _amber,
          ),
        ],
      ),
    );
  }
}

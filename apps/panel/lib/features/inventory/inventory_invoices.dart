import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_select.dart';
import '../../shared/panel_widgets.dart';
import '../../shared/side_panel.dart';

const _tabular = [FontFeature.tabularFigures()];
const _paidColor = Color(0xFF2FB673);
const _dueColor = Color(0xFFE0A21B);

/// Data bez godziny jako „pt 20 lis”.
String _d(DateTime day) => Fmt.dayShort(DateTime(day.year, day.month, day.day));

/// Dzień z bazy (data UTC) jako dzień lokalny o północy, żeby porównywać go z dniami z wyboru daty.
DateTime _local(DateTime day) => DateTime(day.year, day.month, day.day);

enum _InvoiceFilter { all, unpaid, paid }

/// Napis przy terminie: „po terminie 3 dni”, „dziś”, „za 5 dni”, „zapłacona 20 lis”.
String invoiceDueText(InventoryInvoice i, DateTime today) {
  if (i.paidOn != null) return 'zapłacona ${_d(i.paidOn!)}';
  final days = i.daysToDue(today);
  if (days == null) return 'bez terminu';
  if (days < 0) return 'po terminie ${-days} ${-days == 1 ? 'dzień' : 'dni'}';
  if (days == 0) return 'termin dziś';
  return 'za $days ${days == 1 ? 'dzień' : 'dni'}';
}

/// Inwentaryzacja → Faktury (20.11.2026, prośba użytkownika): faktury zakupu od dostawców towaru z numerem, kwotą
/// brutto, terminem płatności i oznaczeniem „opłacona”, opcjonalnie z powiązaną dostawą. Uprawnienie „Edytowanie
/// składników”. Nowa faktura z przycisku „Faktura” nad listą (w zakładce Faktury), zmiana kliknięciem wiersza.
class InventoryInvoicesTab extends ConsumerStatefulWidget {
  const InventoryInvoicesTab({super.key, required this.restaurantId, required this.memberId, required this.onAdd});

  final String restaurantId;
  final String? memberId;
  final VoidCallback onAdd;

  @override
  ConsumerState<InventoryInvoicesTab> createState() => _InventoryInvoicesTabState();
}

class _InventoryInvoicesTabState extends ConsumerState<InventoryInvoicesTab> {
  _InvoiceFilter _filter = _InvoiceFilter.all;
  bool _busy = false;

  void _refresh() => ref.invalidate(inventoryInvoicesProvider(widget.restaurantId));

  Future<void> _run(Future<void> Function() action, [String? done]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
      if (done != null && mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(InventoryInvoice invoice) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => InvoiceDialog(restaurantId: widget.restaurantId, memberId: widget.memberId, invoice: invoice),
    );
    if (saved == true) _refresh();
  }

  Future<void> _delete(InventoryInvoice invoice) async {
    final ok = await confirm(
      context,
      title: 'Usunąć fakturę ${invoice.number}?',
      message: '${invoice.supplier}, ${Fmt.price(invoice.grossGrosze)}. Tego nie da się cofnąć.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    await _run(
      () => ref.read(repositoryProvider).deleteInventoryInvoice(invoice.id, memberId: widget.memberId),
      'Faktura usunięta.',
    );
  }

  Future<void> _togglePaid(InventoryInvoice invoice) => _run(
    () => ref
        .read(repositoryProvider)
        .setInventoryInvoicePaid(invoice.id, invoice.paid ? null : dateOnly(DateTime.now()), memberId: widget.memberId),
    invoice.paid ? 'Faktura ${invoice.number} oznaczona jako nieopłacona.' : 'Faktura ${invoice.number} opłacona.',
  );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inventoryInvoicesProvider(widget.restaurantId));
    final text = Theme.of(context).textTheme;
    return async.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: _refresh),
      data: (all) {
        if (all.isEmpty) {
          return MessageView(
            icon: AppIcons.receipt.duotone,
            title: 'Brak faktur',
            message:
                'Wpisz fakturę od dostawcy towaru: numer, kwotę brutto i termin płatności. Panel pokaże, które są do '
                'zapłaty i które po terminie.',
            actionLabel: 'Dodaj fakturę',
            onAction: widget.onAdd,
          );
        }
        final today = dateOnly(DateTime.now());
        final unpaid = all.where((i) => !i.paid).toList();
        final overdue = unpaid.where((i) => i.overdue(today)).toList();
        final shown = switch (_filter) {
          _InvoiceFilter.all => all,
          _InvoiceFilter.unpaid => unpaid,
          _InvoiceFilter.paid => all.where((i) => i.paid).toList(),
        };
        int sum(Iterable<InventoryInvoice> l) => l.fold(0, (s, i) => s + i.grossGrosze);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
              child: Row(
                children: [
                  SegmentedTabs<_InvoiceFilter>(
                    options: [
                      (_InvoiceFilter.all, 'Wszystkie (${all.length})'),
                      (_InvoiceFilter.unpaid, 'Do zapłaty (${unpaid.length})'),
                      (_InvoiceFilter.paid, 'Opłacone (${all.length - unpaid.length})'),
                    ],
                    selected: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                  const Spacer(),
                  if (overdue.isNotEmpty) ...[
                    PanelPill('Po terminie: ${Fmt.price(sum(overdue))}', dotColor: AppColors.error),
                    const SizedBox(width: 8),
                  ],
                  PanelPill('Do zapłaty: ${Fmt.price(sum(unpaid))}', dotColor: _dueColor),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 32, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 40,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            tableHead(context, 'Dostawca', 4),
                            tableHead(context, 'Numer faktury', 3),
                            tableHead(context, 'Wystawiona', 0, width: 96),
                            tableHead(context, 'Termin płatności', 3),
                            tableHead(context, 'Kwota brutto', 0, width: 120, align: TextAlign.right),
                            const SizedBox(width: 16),
                            tableHead(context, 'Stan', 0, width: 128),
                            const SizedBox(width: 148),
                          ],
                        ),
                      ),
                    ),
                    Divider(height: 1, color: AppColors.ring),
                    Expanded(
                      child: shown.isEmpty
                          ? Center(
                              child: Text(
                                'Nie ma faktur w tym filtrze.',
                                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                              ),
                            )
                          : ListView.separated(
                              itemCount: shown.length,
                              separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.ring),
                              itemBuilder: (_, i) => _InvoiceRow(
                                invoice: shown[i],
                                today: today,
                                busy: _busy,
                                onTap: () => _edit(shown[i]),
                                onTogglePaid: () => _togglePaid(shown[i]),
                                onDelete: () => _delete(shown[i]),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow({
    required this.invoice,
    required this.today,
    required this.busy,
    required this.onTap,
    required this.onTogglePaid,
    required this.onDelete,
  });

  final InventoryInvoice invoice;
  final DateTime today;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onTogglePaid;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final i = invoice;
    final late = i.overdue(today);
    final color = i.paid ? _paidColor : (late ? AppColors.error : _dueColor);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.surfaceRaised,
        splashColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(i.supplier, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                    if (i.docAt != null) Text('Dostawa z ${_d(i.docAt!.toLocal())}', style: muted),
                    if (i.note != null) Text(i.note!, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(i.number, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
              ),
              SizedBox(
                width: 96,
                child: Text(_d(i.issuedOn), style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i.dueOn == null ? '—' : _d(i.dueOn!),
                      style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                    ),
                    Text(invoiceDueText(i, today), style: muted?.copyWith(color: late ? AppColors.error : null)),
                  ],
                ),
              ),
              SizedBox(
                width: 120,
                child: Text(
                  Fmt.price(i.grossGrosze),
                  textAlign: TextAlign.right,
                  style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 128,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusChip(
                    label: i.paid ? 'Opłacona' : (late ? 'Po terminie' : 'Do zapłaty'),
                    icon: i.paid ? AppIcons.checkCircle : (late ? AppIcons.warning : AppIcons.hourglass),
                    color: color,
                  ),
                ),
              ),
              SizedBox(
                width: 148,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: busy ? null : onTogglePaid,
                      child: Text(i.paid ? 'Cofnij' : 'Opłać'),
                    ),
                    DeleteButton(tooltip: 'Usuń fakturę', compact: true, onPressed: busy ? null : onDelete),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nowa faktura albo zmiana istniejącej: dostawca (z podpowiedziami), numer, daty, kwota brutto, powiązana dostawa,
/// notatka i „opłacona”. Zwraca true po zapisie.
class InvoiceDialog extends ConsumerStatefulWidget {
  const InvoiceDialog({super.key, required this.restaurantId, required this.memberId, this.invoice});

  final String restaurantId;
  final String? memberId;
  final InventoryInvoice? invoice;

  @override
  ConsumerState<InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends ConsumerState<InvoiceDialog> {
  late final _supplier = TextEditingController(text: widget.invoice?.supplier ?? '');
  late final _number = TextEditingController(text: widget.invoice?.number ?? '');
  late final _gross = TextEditingController(
    text: widget.invoice == null ? '' : groszeToText(widget.invoice!.grossGrosze),
  );
  late final _note = TextEditingController(text: widget.invoice?.note ?? '');
  late DateTime _issued = _local(widget.invoice?.issuedOn ?? DateTime.now());
  late DateTime? _due = widget.invoice?.dueOn == null ? null : _local(widget.invoice!.dueOn!);
  late DateTime? _paidOn = widget.invoice?.paidOn == null ? null : _local(widget.invoice!.paidOn!);
  late String? _docId = widget.invoice?.docId;
  bool _busy = false;

  @override
  void dispose() {
    _supplier.dispose();
    _number.dispose();
    _gross.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
    context: context,
    initialDate: DateTime(initial.year, initial.month, initial.day),
    firstDate: DateTime.now().subtract(const Duration(days: 730)),
    lastDate: DateTime.now().add(const Duration(days: 730)),
  );

  Future<void> _save() async {
    final gross = parseGrosze(_gross.text);
    String? problem;
    if (_supplier.text.trim().isEmpty) {
      problem = 'Wpisz dostawcę.';
    } else if (_number.text.trim().isEmpty) {
      problem = 'Wpisz numer faktury.';
    } else if (gross == null || gross <= 0) {
      problem = 'Wpisz kwotę brutto, na przykład 1250,50.';
    } else if (_due != null && _due!.isBefore(_issued)) {
      problem = 'Termin płatności nie może być przed datą wystawienia.';
    }
    if (problem != null) {
      showMessage(context, problem, tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .saveInventoryInvoice(
            widget.restaurantId,
            id: widget.invoice?.id,
            supplier: _supplier.text.trim(),
            number: _number.text.trim(),
            issuedOn: _issued,
            dueOn: _due,
            grossGrosze: gross!,
            docId: _docId,
            note: _note.text.trim(),
            paidOn: _paidOn,
            memberId: widget.memberId,
          );
      if (!mounted) return;
      showMessage(context, widget.invoice == null ? 'Faktura dodana.' : 'Faktura zapisana.', tone: ToastTone.success);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> onPick, {VoidCallback? onClear}) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await _pick(value ?? _issued);
        if (picked != null) onPick(dateOnly(picked));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear != null && value != null
              ? IconButton(tooltip: 'Wyczyść', onPressed: onClear, icon: const Glyph(AppIcons.close, size: 14))
              : null,
        ),
        child: Text(value == null ? '—' : _d(value), style: const TextStyle(fontFeatures: _tabular)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Dostawcy z faktur i dostaw (podpowiedzi) oraz dostawy do powiązania.
    final invoices = ref.watch(inventoryInvoicesProvider(widget.restaurantId)).value ?? const <InventoryInvoice>[];
    final docs = [
      for (final d in ref.watch(inventoryDocsProvider(widget.restaurantId)).value ?? const <InventoryDoc>[])
        if (d.delivery) d,
    ];
    final typed = _supplier.text.trim().toLowerCase();
    final suppliers = <String>{
      for (final i in invoices) i.supplier,
      for (final d in docs) ?d.supplier,
    }.where((s) => s.toLowerCase() != typed && (typed.isEmpty || s.toLowerCase().contains(typed))).take(6).toList();

    return AlertDialog(
      title: Text(widget.invoice == null ? 'Nowa faktura' : 'Faktura ${widget.invoice!.number}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _supplier,
                maxLength: 120,
                autofocus: widget.invoice == null,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Dostawca', counterText: ''),
              ),
              if (suppliers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in suppliers)
                      ActionChip(label: Text(s), onPressed: () => setState(() => _supplier.text = s)),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _number,
                      maxLength: 60,
                      decoration: const InputDecoration(labelText: 'Numer faktury', counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _gross,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontFeatures: _tabular),
                      decoration: const InputDecoration(labelText: 'Kwota brutto', suffixText: 'zł'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _dateField('Data wystawienia', _issued, (d) => setState(() => _issued = d)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _dateField(
                      'Termin płatności',
                      _due,
                      (d) => setState(() => _due = d),
                      onClear: () => setState(() => _due = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final days in const [0, 7, 14, 30])
                    ChoiceChip(
                      label: Text(days == 0 ? 'Termin: w dniu wystawienia' : 'Termin: $days dni'),
                      selected: _due == DateTime(_issued.year, _issued.month, _issued.day + days),
                      onSelected: (_) => setState(() => _due = DateTime(_issued.year, _issued.month, _issued.day + days)),
                    ),
                ],
              ),
              if (docs.isNotEmpty) ...[
                const SizedBox(height: 12),
                PanelSelect<String?>(
                  key: ValueKey('dostawa-$_docId'),
                  initialValue: _docId,
                  decoration: const InputDecoration(labelText: 'Dostawa (opcjonalnie)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Bez powiązania z dostawą')),
                    for (final d in docs) DropdownMenuItem<String?>(value: d.id, child: Text(d.title)),
                  ],
                  onChanged: (v) => setState(() => _docId = v),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Notatka (opcjonalnie)', counterText: ''),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Switch(
                    value: _paidOn != null,
                    onChanged: (v) => setState(() => _paidOn = v ? dateOnly(DateTime.now()) : null),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _paidOn == null ? 'Nieopłacona' : 'Opłacona ${_d(_paidOn!)}',
                      style: text.titleSmall,
                    ),
                  ),
                  if (_paidOn != null)
                    TextButton(
                      onPressed: () async {
                        final picked = await _pick(_paidOn!);
                        if (picked != null) setState(() => _paidOn = dateOnly(picked));
                      },
                      child: const Text('Zmień dzień'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Anuluj')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(widget.invoice == null ? 'Dodaj fakturę' : 'Zapisz')),
      ],
    );
  }
}

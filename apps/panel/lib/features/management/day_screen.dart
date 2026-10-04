import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];
const _ok = Color(0xFF2FB673);
const _warn = Color(0xFFE0A21B);

String? _money(int? grosze) => grosze == null ? null : groszeToText(grosze);

/// Management → Podsumowanie dnia: sprzedaż według płatności, raporty z kasy fiskalnej i terminali,
/// policzona gotówka i petty cash (drobne wydatki i wpłaty z kasy). Różnice są od razu widoczne.
/// Uprawnienie „Podsumowanie dnia”.
class DaySummaryScreen extends ConsumerStatefulWidget {
  const DaySummaryScreen({super.key});

  @override
  ConsumerState<DaySummaryScreen> createState() => _DaySummaryScreenState();
}

class _DaySummaryScreenState extends ConsumerState<DaySummaryScreen> {
  DateTime _day = dateOnly(DateTime.now());

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _day = dateOnly(picked));
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final today = dateOnly(DateTime.now());
    final query = (restaurantId: restaurant.id, day: _day);
    final async = ref.watch(daySummaryProvider(query));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          actions: [
            StepSwitcher(
              label: '${Fmt.capitalize(Fmt.dayShort(_day))}${_day == today ? ' · dziś' : ''}',
              labelWidth: 150,
              previousTooltip: 'Poprzedni dzień',
              nextTooltip: 'Następny dzień',
              onPrevious: () => setState(() => _day = DateTime(_day.year, _day.month, _day.day - 1)),
              onNext: _day == today ? null : () => setState(() => _day = DateTime(_day.year, _day.month, _day.day + 1)),
              resetTooltip: 'Wróć do dziś',
              onReset: _day == today ? null : () => setState(() => _day = today),
              extras: [(AppIcons.calendar, 'Wybierz dzień', _pickDay)],
            ),
          ],
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(daySummaryProvider(query))),
            data: (s) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Obrót',
                          value: Fmt.price(s.revenueGrosze),
                          hint: [
                            '${s.orders} rachunków',
                            if (s.takeaway > 0) '${s.takeaway} na wynos',
                            if (s.discountsGrosze > 0) 'rabaty ${Fmt.price(s.discountsGrosze)}',
                          ].join(' · '),
                          icon: AppIcons.receipt,
                          color: TileColors.green,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: StatTile(
                          label: 'Gotówka',
                          value: Fmt.price(s.cashGrosze),
                          hint: s.tipsCashGrosze > 0 ? '+ napiwki ${Fmt.price(s.tipsCashGrosze)}' : null,
                          icon: AppIcons.money,
                          color: TileColors.amber,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: StatTile(
                          label: 'Karta (terminal)',
                          value: Fmt.price(s.cardGrosze),
                          hint: s.tipsCardGrosze > 0 ? '+ napiwki ${Fmt.price(s.tipsCardGrosze)}' : null,
                          icon: AppIcons.creditCard,
                          color: TileColors.blue,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: StatTile(
                          label: 'Karta online',
                          value: Fmt.price(s.cardOnlineGrosze),
                          hint: s.otherGrosze > 0 ? 'inne: ${Fmt.price(s.otherGrosze)}' : 'zamówienia w aplikacji',
                          icon: AppIcons.deviceMobile,
                          color: TileColors.violet,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _ReportCard(
                          key: ValueKey(_day),
                          restaurantId: restaurant.id,
                          day: _day,
                          summary: s,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: _PettyCard(restaurantId: restaurant.id, day: _day, summary: s),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Zgodność wpisanej kwoty z tym, co policzył panel: zielone „Zgadza się” albo żółta różnica.
class _Check extends StatelessWidget {
  const _Check({required this.expected, required this.actual, required this.label});

  final int expected;
  final int? actual;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final a = actual;
    final diff = a == null ? null : a - expected;
    final color = diff == null ? AppColors.textMuted : (diff == 0 ? _ok : _warn);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label ${Fmt.price(expected)}', style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular)),
        if (diff != null) ...[
          const SizedBox(width: 10),
          Glyph(diff == 0 ? AppIcons.checkCircle : AppIcons.warning, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            diff == 0 ? 'Zgadza się' : 'Różnica ${diff > 0 ? '+' : '−'}${Fmt.price(diff.abs())}',
            style: text.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600, fontFeatures: _tabular),
          ),
        ],
      ],
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, required this.label, this.onChanged});

  final TextEditingController controller;
  final String label;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: (_) => onChanged?.call(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
      textAlign: TextAlign.right,
      style: const TextStyle(fontFeatures: _tabular),
      decoration: InputDecoration(labelText: label, suffixText: 'zł', isDense: true),
    );
  }
}

/// Raporty z końca dnia: kasa fiskalna, terminale, policzona gotówka i notatka. Zapis jednym przyciskiem.
class _ReportCard extends ConsumerStatefulWidget {
  const _ReportCard({super.key, required this.restaurantId, required this.day, required this.summary});

  final String restaurantId;
  final DateTime day;
  final DaySummary summary;

  @override
  ConsumerState<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<_ReportCard> {
  late final DayReport? _report = widget.summary.report;
  late final _fiscal = TextEditingController(text: _money(_report?.fiscalGrosze) ?? '');
  late final _cash = TextEditingController(text: _money(_report?.cashCountedGrosze) ?? '');
  late final _note = TextEditingController(text: _report?.note ?? '');
  late final List<(TextEditingController, TextEditingController)> _terminals = [
    for (final t in _report?.terminals ?? const <TerminalReport>[])
      (TextEditingController(text: t.name), TextEditingController(text: groszeToText(t.grosze))),
    if ((_report?.terminals ?? const []).isEmpty) (TextEditingController(text: 'Terminal 1'), TextEditingController()),
  ];
  bool _busy = false;

  @override
  void dispose() {
    _fiscal.dispose();
    _cash.dispose();
    _note.dispose();
    for (final (a, b) in _terminals) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  int? _parse(TextEditingController c) => c.text.trim().isEmpty ? null : parseGrosze(c.text);

  int? get _terminalsSum {
    final values = [for (final (_, amount) in _terminals) _parse(amount)];
    if (values.every((v) => v == null)) return null;
    return values.fold<int>(0, (s, v) => s + (v ?? 0));
  }

  Future<void> _save() async {
    for (final c in [_fiscal, _cash, for (final (_, amount) in _terminals) amount]) {
      if (c.text.trim().isNotEmpty && parseGrosze(c.text) == null) {
        showMessage(context, 'Wpisz kwotę, na przykład 1250 albo 1250,50.', tone: ToastTone.warning);
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveDayReport(
        widget.restaurantId,
        widget.day,
        fiscalGrosze: _parse(_fiscal),
        terminals: [
          for (final (name, amount) in _terminals)
            if (_parse(amount) != null) TerminalReport(name.text.trim(), _parse(amount)!),
        ],
        cashCountedGrosze: _parse(_cash),
        note: _note.text,
        memberId: ref.read(panelMemberProvider)?.dbMemberId,
      );
      ref.invalidate(daySummaryProvider((restaurantId: widget.restaurantId, day: widget.day)));
      if (mounted) showMessage(context, 'Podsumowanie dnia zapisane.', tone: ToastTone.success);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = widget.summary;
    final saved = _report?.updatedAt;
    void refresh() => setState(() {});

    return PanelCard(
      title: 'Raporty na koniec dnia',
      icon: AppIcons.cashRegister,
      iconColor: TileColors.green,
      trailing: saved == null
          ? null
          : Text(
              'Zapisano ${Fmt.time(saved)}${_report?.updatedBy == null ? '' : ' · ${_report!.updatedBy}'}',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Kasa fiskalna', style: text.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(width: 240, child: _MoneyField(controller: _fiscal, label: 'Raport dobowy', onChanged: refresh)),
              const SizedBox(width: 16),
              Expanded(child: _Check(label: 'Obrót w panelu', expected: s.revenueGrosze, actual: _parse(_fiscal))),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Text('Terminale płatnicze', style: text.titleSmall)),
              TextButton.icon(
                onPressed: () => setState(
                  () => _terminals.add((
                    TextEditingController(text: 'Terminal ${_terminals.length + 1}'),
                    TextEditingController(),
                  )),
                ),
                icon: const Glyph(AppIcons.plus, size: 16),
                label: const Text('Dodaj terminal'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final (i, (name, amount)) in _terminals.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: name,
                      maxLength: 60,
                      decoration: const InputDecoration(labelText: 'Nazwa', isDense: true, counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(width: 200, child: _MoneyField(controller: amount, label: 'Kwota', onChanged: refresh)),
                  IconButton(
                    tooltip: 'Usuń terminal',
                    onPressed: _terminals.length == 1
                        ? null
                        : () => setState(() {
                            final removed = _terminals.removeAt(i);
                            removed.$1.dispose();
                            removed.$2.dispose();
                          }),
                    icon: Glyph(AppIcons.trash, size: 16, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          _Check(label: 'Karty w panelu', expected: s.expectedCardGrosze, actual: _terminalsSum),
          const SizedBox(height: 20),
          Text('Gotówka w kasie', style: text.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(width: 240, child: _MoneyField(controller: _cash, label: 'Policzona gotówka', onChanged: refresh)),
              const SizedBox(width: 16),
              Expanded(
                child: _Check(label: 'Powinno być', expected: s.expectedCashGrosze, actual: _parse(_cash)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sprzedaż gotówką ${Fmt.price(s.cashGrosze)}'
            '${s.tipsCashGrosze > 0 ? ' + napiwki ${Fmt.price(s.tipsCashGrosze)}' : ''}'
            '${s.pettyOutGrosze > 0 ? ' − wydatki ${Fmt.price(s.pettyOutGrosze)}' : ''}'
            '${s.pettyInGrosze > 0 ? ' + wpłaty ${Fmt.price(s.pettyInGrosze)}' : ''}',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            decoration: const InputDecoration(labelText: 'Notatka', counterText: ''),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Glyph(AppIcons.check, size: 18),
              label: const Text('Zapisz podsumowanie'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Petty cash: drobne wydatki z kasy (np. cytryny, taksówka) i wpłaty do kasy (np. drobne do wydawania).
class _PettyCard extends ConsumerStatefulWidget {
  const _PettyCard({required this.restaurantId, required this.day, required this.summary});

  final String restaurantId;
  final DateTime day;
  final DaySummary summary;

  @override
  ConsumerState<_PettyCard> createState() => _PettyCardState();
}

class _PettyCardState extends ConsumerState<_PettyCard> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  bool _out = true;
  bool _busy = false;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _refresh() => ref.invalidate(daySummaryProvider((restaurantId: widget.restaurantId, day: widget.day)));

  Future<void> _add() async {
    final amount = parseGrosze(_amount.text);
    if (_description.text.trim().isEmpty) {
      showMessage(context, 'Wpisz, na co poszły pieniądze.', tone: ToastTone.warning);
      return;
    }
    if (amount == null || amount <= 0) {
      showMessage(context, 'Wpisz kwotę, na przykład 12,50.', tone: ToastTone.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).addPetty(
        widget.restaurantId,
        widget.day,
        out: _out,
        description: _description.text.trim(),
        amountGrosze: amount,
        memberId: ref.read(panelMemberProvider)?.dbMemberId,
      );
      _description.clear();
      _amount.clear();
      _refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(PettyEntry e) async {
    final ok = await confirm(
      context,
      title: 'Usunąć wpis?',
      message: '${e.description}, ${Fmt.price(e.amountGrosze)}.',
      action: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(repositoryProvider).deletePetty(e.id);
      _refresh();
    } catch (err) {
      if (mounted) showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = widget.summary;
    final balance = s.pettyInGrosze - s.pettyOutGrosze;
    return PanelCard(
      title: 'Petty cash',
      icon: AppIcons.coins,
      iconColor: TileColors.amber,
      trailing: s.petty.isEmpty
          ? null
          : Text(
              '${balance < 0 ? '−' : '+'}${Fmt.price(balance.abs())}',
              style: text.titleSmall?.copyWith(color: balance < 0 ? _warn : _ok, fontFeatures: _tabular),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedTabs<bool>(
              options: const [(true, 'Wydatek'), (false, 'Wpłata')],
              selected: _out,
              onChanged: (v) => setState(() => _out = v),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _description,
                  maxLength: 200,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    labelText: _out ? 'Na co' : 'Skąd',
                    hintText: _out ? 'Na przykład cytryny' : 'Na przykład drobne',
                    isDense: true,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(width: 120, child: _MoneyField(controller: _amount, label: 'Kwota')),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Dodaj',
                onPressed: _busy ? null : _add,
                icon: const Glyph(AppIcons.plus, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (s.petty.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Brak wpisów',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            )
          else
            for (final e in s.petty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Glyph(e.out ? AppIcons.minus : AppIcons.plus, size: 14, color: e.out ? _warn : _ok),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.description, style: text.bodyMedium),
                          Text(
                            '${e.author ?? 'Pracownik'} · ${Fmt.time(e.createdAt)}',
                            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${e.out ? '−' : '+'}${Fmt.price(e.amountGrosze)}',
                      style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                    ),
                    IconButton(
                      tooltip: 'Usuń',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _delete(e),
                      icon: Glyph(AppIcons.trash, size: 15, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

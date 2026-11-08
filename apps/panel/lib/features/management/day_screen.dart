import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];
const _ok = Color(0xFF2FB673);
const _warn = Color(0xFFE0A21B);

String? _money(int? grosze) => grosze == null ? null : groszeToText(grosze);

/// „1 opakowanie”, „3 opakowania”, „5 opakowań”.
String _packs(int n) {
  final ones = n % 10;
  final tens = n % 100;
  if (n == 1) return '1 opakowanie';
  if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14)) return '$n opakowania';
  return '$n opakowań';
}

String _envelopeHint(EnvelopeCash e) => [
  'Raport ${Fmt.price(e.fiscal)}',
  if (e.online > 0) '− online ${Fmt.price(e.online)}',
  '− terminale ${Fmt.price(e.terminals)}',
  if (e.other > 0) '− przelewy i inne ${Fmt.price(e.other)}',
  if (e.kaucja > 0) '− kaucja ${Fmt.price(e.kaucja)}',
].join(' ');

/// Management → Podsumowanie dnia (8.11.2026, prośba użytkownika: prostszy wygląd w jednej kolumnie, jak lista
/// w Ustawieniach lokalu). Od góry: sprzedaż dnia, kasa fiskalna (raport dobowy brutto i netto), terminale,
/// gotówka do koperty, gotówka w kasie, platformy dostaw, notatka z „Zapisz” i petty cash. Różnice z panelem widać
/// od razu (zielone „Zgadza się” albo żółta różnica). Niezamknięte zamówienia na górze. Uprawnienie „Podsumowanie
/// dnia”.
class DaySummaryScreen extends ConsumerStatefulWidget {
  const DaySummaryScreen({super.key});

  @override
  ConsumerState<DaySummaryScreen> createState() => _DaySummaryScreenState();
}

class _DaySummaryScreenState extends ConsumerState<DaySummaryScreen> {
  // Dzień lokalu: przy zamknięciu dnia o 02:00 o 01:30 to jeszcze wczoraj.
  late DateTime _day = businessToday(ref.read(dayCloseProvider));

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
    final close = ref.watch(dayCloseProvider);
    final today = businessToday(close);
    final query = (restaurantId: restaurant.id, day: _day);
    final async = ref.watch(daySummaryProvider(query));
    // Rachunki otwarte w wybranym dniu lokalu albo wcześniej: do zamknięcia przed rozliczeniem.
    final unclosed = [
      for (final o in ref.watch(unclosedOrdersProvider(restaurant.id)).value ?? const <UnclosedOrder>[])
        if (businessDayOf(o.order.openedAt, close).compareTo(_day) <= 0) o,
    ];
    String hm(Duration d) => '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';

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
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (unclosed.isNotEmpty) ...[
                        _UnclosedBanner(orders: unclosed),
                        const SizedBox(height: 24),
                      ],
                      _DayReport(
                        key: ValueKey(_day),
                        restaurantId: restaurant.id,
                        day: _day,
                        summary: s,
                        dayNote: close > Duration.zero
                            ? 'Dzień lokalu od ${hm(close)} do ${hm(close)} następnego dnia: sprzedaż po północy '
                                  'liczy się do tego dnia (zamknięcie dnia w Ustawieniach lokalu).'
                            : null,
                      ),
                      const SizedBox(height: 32),
                      _PettySection(restaurantId: restaurant.id, day: _day, summary: s),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Niezamknięte zamówienia z wybranego dnia albo wcześniejszych: nie ma ich w obrocie, dopóki są otwarte.
class _UnclosedBanner extends ConsumerWidget {
  const _UnclosedBanner({required this.orders});

  final List<UnclosedOrder> orders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final sum = orders.fold(0, (s, o) => s + o.order.billGrosze);
    final canOpen = canOpenRoute(PanelRoutes.unclosed, ref.watch(memberPermissionsProvider));
    final n = orders.length;
    final word = n == 1
        ? 'niezamknięte zamówienie'
        : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14))
        ? 'niezamknięte zamówienia'
        : 'niezamkniętych zamówień';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(
        color: _warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _warn.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Glyph(AppIcons.warning, size: 22, color: _warn),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '$n $word na ${Fmt.price(sum)}. Nie ma ich w obrocie, dopóki ktoś ich nie zamknie.',
              style: text.titleSmall?.copyWith(fontFeatures: _tabular),
            ),
          ),
          if (canOpen)
            TextButton(onPressed: () => context.go(PanelRoutes.unclosed), child: const Text('Sprawdź')),
        ],
      ),
    );
  }
}

/// Kwota po prawej stronie wiersza (liczby tabelaryczne, większe przy ważnych kwotach).
class _Amount extends StatelessWidget {
  const _Amount(this.value, {this.big = false, this.color});

  final String value;
  final bool big;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Text(
      value,
      style: (big ? text.titleLarge : text.titleSmall)?.copyWith(
        fontWeight: FontWeight.w600,
        color: color,
        fontFeatures: _tabular,
      ),
    );
  }
}

/// Zgodność wpisanej kwoty z panelem: kwota z panelu i zielone „Zgadza się” albo żółta różnica.
class _Match extends StatelessWidget {
  const _Match({required this.expected, required this.actual});

  final int expected;
  final int? actual;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final a = actual;
    final diff = a == null ? null : a - expected;
    final color = diff == null ? AppColors.textMuted : (diff == 0 ? _ok : _warn);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Amount(Fmt.price(expected)),
        if (diff != null) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Glyph(diff == 0 ? AppIcons.checkCircle : AppIcons.warning, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  diff == 0 ? 'Zgadza się' : 'Różnica ${diff > 0 ? '+' : '−'}${Fmt.price(diff.abs())}',
                  style: text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600, fontFeatures: _tabular),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, this.onChanged, this.width = 180});

  final TextEditingController controller;
  final VoidCallback? onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged?.call(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
        textAlign: TextAlign.right,
        style: const TextStyle(fontFeatures: _tabular),
        decoration: const InputDecoration(hintText: '0,00', suffixText: 'zł', isDense: true),
      ),
    );
  }
}

/// Raport dnia w jednej kolumnie: sprzedaż, kasa fiskalna, terminale, koperta, gotówka w kasie, platformy
/// i notatka. Zapis jednym przyciskiem pod notatką.
class _DayReport extends ConsumerStatefulWidget {
  const _DayReport({
    super.key,
    required this.restaurantId,
    required this.day,
    required this.summary,
    required this.dayNote,
  });

  final String restaurantId;
  final DateTime day;
  final DaySummary summary;
  final String? dayNote;

  @override
  ConsumerState<_DayReport> createState() => _DayReportState();
}

class _DayReportState extends ConsumerState<_DayReport> {
  late final DayReport? _report = widget.summary.report;
  late final _fiscal = TextEditingController(text: _money(_report?.fiscalGrosze) ?? '');
  late final _fiscalNet = TextEditingController(text: _money(_report?.fiscalNetGrosze) ?? '');
  late final _cash = TextEditingController(text: _money(_report?.cashCountedGrosze) ?? '');
  late final _note = TextEditingController(text: _report?.note ?? '');

  /// Kwoty z platform dostaw według nazwy (lista platform z „Ustawienia lokalu” i te zapisane w raporcie).
  late final Map<String, TextEditingController> _platforms = {
    for (final p in _report?.platforms ?? const <TerminalReport>[]) p.name: TextEditingController(text: groszeToText(p.grosze)),
  };

  late final List<(TextEditingController, TextEditingController)> _terminals = [
    for (final t in _report?.terminals ?? const <TerminalReport>[])
      (TextEditingController(text: t.name), TextEditingController(text: groszeToText(t.grosze))),
    if ((_report?.terminals ?? const []).isEmpty) (TextEditingController(text: 'Terminal 1'), TextEditingController()),
  ];
  bool _busy = false;

  @override
  void dispose() {
    _fiscal.dispose();
    _fiscalNet.dispose();
    _cash.dispose();
    _note.dispose();
    for (final (a, b) in _terminals) {
      a.dispose();
      b.dispose();
    }
    for (final c in _platforms.values) {
      c.dispose();
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
    for (final c in [_fiscal, _fiscalNet, _cash, for (final (_, amount) in _terminals) amount, ..._platforms.values]) {
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
        fiscalNetGrosze: _parse(_fiscalNet),
        terminals: [
          for (final (name, amount) in _terminals)
            if (_parse(amount) != null) TerminalReport(name.text.trim(), _parse(amount)!),
        ],
        cashCountedGrosze: _parse(_cash),
        note: _note.text,
        memberId: ref.read(panelMemberProvider)?.dbMemberId,
        platforms: [
          for (final e in _platforms.entries)
            if (_parse(e.value) != null) TerminalReport(e.key, _parse(e.value)!),
        ],
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
    // Karty z terminali inne niż w panelu: różnica przechodzi na gotówkę. Mniej na terminalu = ktoś zapłacił
    // gotówką, choć w panelu jest karta, więc gotówki ma być więcej (i odwrotnie).
    final terminals = _terminalsSum;
    final cardDiff = terminals == null ? 0 : s.expectedCardGrosze - terminals;
    // Platformy z ustawień lokalu: pole na kwotę dla każdej (zapisane wcześniej zostają, nawet po usunięciu z listy).
    final platformNames = ref.watch(profileProvider(widget.restaurantId)).value?.delivery.deliveryPlatforms ?? const <String>[];
    for (final n in platformNames) {
      _platforms.putIfAbsent(n, TextEditingController.new);
    }
    final platformsSum = _platforms.values.fold<int>(0, (sum, c) => sum + (_parse(c) ?? 0));
    final expectedCash = s.expectedCashGrosze + cardDiff;
    final avg = averageBill(s, fiscalNetGrosze: _parse(_fiscalNet));
    final envelope = envelopeCash(s, fiscalGrosze: _parse(_fiscal), terminalsGrosze: terminals);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Sprzedaż',
          description: widget.dayNote ?? 'Rachunki zamknięte tego dnia.',
          children: [
            SettingsRow(
              title: 'Obrót',
              description: [
                '${s.orders} rachunków',
                if (s.takeaway > 0) '${s.takeaway} na wynos',
                if (s.discountsGrosze > 0) 'rabaty ${Fmt.price(s.discountsGrosze)}',
              ].join(' · '),
              trailing: _Amount(Fmt.price(s.revenueGrosze), big: true),
            ),
            SettingsRow(
              title: 'Zamówienia netto',
              description: s.cancelled > 0 ? 'Bez ${s.cancelled} anulowanych i pustych.' : 'Bez anulowanych i pustych.',
              trailing: _Amount('${s.ordersNet}'),
            ),
            SettingsRow(
              title: 'Średni rachunek',
              description: avg == null
                  ? 'Brak zamówień.'
                  : avg.fromReport
                  ? 'Netto z raportu dobowego / zamówienia netto.'
                  : 'Netto z panelu (szacunek) / zamówienia netto. Wpisz netto z raportu dobowego niżej.',
              trailing: _Amount(avg == null ? '—' : Fmt.price(avg.grosze)),
            ),
            SettingsRow(title: 'Gotówka', trailing: _Amount(Fmt.price(s.cashGrosze))),
            SettingsRow(title: 'Karta (terminal)', trailing: _Amount(Fmt.price(s.cardGrosze))),
            SettingsRow(
              title: 'Karta online',
              description: s.depositsGrosze > 0 ? 'Aplikacja Table i zadatki ${Fmt.price(s.depositsGrosze)}.' : 'Aplikacja Table.',
              trailing: _Amount(Fmt.price(s.cardOnlineGrosze)),
            ),
            if (s.otherGrosze > 0) SettingsRow(title: 'Przelewy i inne', trailing: _Amount(Fmt.price(s.otherGrosze))),
            SettingsRow(
              title: 'Kaucja',
              description: s.kaucjaCount > 0
                  ? '${_packs(s.kaucjaCount)} ze składników z kaucją.'
                  : 'Składniki z kaucją ustawia się w Inwentaryzacji → Składniki.',
              trailing: _Amount(Fmt.price(s.kaucjaGrosze)),
            ),
          ],
        ),
        const SizedBox(height: 32),
        SettingsSection(
          title: 'Kasa fiskalna',
          description: 'Kwoty z raportu dobowego wydrukowanego na koniec dnia.',
          children: [
            SettingsRow(
              title: 'Raport dobowy (brutto)',
              trailing: _MoneyField(controller: _fiscal, onChanged: refresh),
            ),
            SettingsRow(
              title: 'Netto z raportu',
              description: 'Do średniego rachunku.',
              trailing: _MoneyField(controller: _fiscalNet, onChanged: refresh),
            ),
            SettingsRow(
              title: 'Obrót w panelu',
              description: 'Zgodność raportu dobowego z rachunkami w panelu.',
              trailing: _Match(expected: s.revenueGrosze, actual: _parse(_fiscal)),
            ),
          ],
        ),
        const SizedBox(height: 32),
        SettingsSection(
          title: 'Terminale płatnicze',
          description: 'Kwoty z raportów terminali; suma liczy się sama.',
          children: [
            for (final (i, (name, amount)) in _terminals.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: name,
                        maxLength: 60,
                        decoration: const InputDecoration(hintText: 'Nazwa terminala', isDense: true, counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _MoneyField(controller: amount, onChanged: refresh),
                    DeleteButton(
                      tooltip: 'Usuń terminal',
                      onPressed: _terminals.length == 1
                          ? null
                          : () => setState(() {
                              final removed = _terminals.removeAt(i);
                              removed.$1.dispose();
                              removed.$2.dispose();
                            }),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _terminals.add((
                      TextEditingController(text: 'Terminal ${_terminals.length + 1}'),
                      TextEditingController(),
                    )),
                  ),
                  icon: const Glyph(AppIcons.plus, size: 16),
                  label: const Text('Dodaj terminal'),
                ),
              ),
            ),
            SettingsRow(
              title: 'Karty w panelu',
              description: 'Płatności kartą z napiwkami. Różnica przechodzi na gotówkę w kasie.',
              trailing: _Match(expected: s.expectedCardGrosze, actual: terminals),
            ),
          ],
        ),
        const SizedBox(height: 32),
        SettingsSection(
          title: 'Gotówka do koperty',
          children: [
            SettingsRow(
              title: envelope == null ? 'Wpisz raport dobowy' : 'Do koperty',
              description: envelope == null
                  ? 'Raport dobowy minus płatności online, terminale (bez napiwków kartą), przelewy i kaucja.'
                  : _envelopeHint(envelope),
              trailing: envelope == null
                  ? null
                  : _Amount(Fmt.price(envelope.total), big: true, color: envelope.total < 0 ? _warn : null),
            ),
          ],
        ),
        const SizedBox(height: 32),
        SettingsSection(
          title: 'Gotówka w kasie',
          children: [
            SettingsRow(
              title: 'Policzona gotówka',
              trailing: _MoneyField(controller: _cash, onChanged: refresh),
            ),
            SettingsRow(
              title: 'Powinno być',
              description: 'Gotówka z rachunków ${Fmt.price(s.cashGrosze + s.tipsCashGrosze)}'
                  '${s.pettyOutGrosze > 0 ? ' − wydatki ${Fmt.price(s.pettyOutGrosze)}' : ''}'
                  '${s.pettyInGrosze > 0 ? ' + wpłaty ${Fmt.price(s.pettyInGrosze)}' : ''}'
                  '${cardDiff > 0 ? ' + ${Fmt.price(cardDiff)} (na terminalach mniej niż kart w panelu)' : ''}'
                  '${cardDiff < 0 ? ' − ${Fmt.price(-cardDiff)} (na terminalach więcej niż kart w panelu)' : ''}',
              trailing: _Match(expected: expectedCash, actual: _parse(_cash)),
            ),
          ],
        ),
        if (_platforms.isNotEmpty) ...[
          const SizedBox(height: 32),
          SettingsSection(
            title: 'Platformy dostaw',
            description: 'Razem ${Fmt.price(platformsSum)}: osobno, poza kasą fiskalną i obrotem w panelu.',
            children: [
              for (final e in _platforms.entries)
                SettingsRow(title: e.key, trailing: _MoneyField(controller: e.value, onChanged: refresh)),
            ],
          ),
        ],
        const SizedBox(height: 32),
        SettingsSection(
          title: 'Notatka',
          footer: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (saved != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    'Zapisano ${Fmt.time(saved)}${_report?.updatedBy == null ? '' : ' · ${_report!.updatedBy}'}',
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Glyph(AppIcons.check, size: 18),
                label: const Text('Zapisz podsumowanie'),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: TextField(
                controller: _note,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                decoration: const InputDecoration(hintText: 'Coś do zapamiętania z tego dnia', counterText: ''),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Petty cash: drobne wydatki z kasy (np. cytryny, taksówka) i wpłaty do kasy (np. drobne do wydawania).
class _PettySection extends ConsumerStatefulWidget {
  const _PettySection({required this.restaurantId, required this.day, required this.summary});

  final String restaurantId;
  final DateTime day;
  final DaySummary summary;

  @override
  ConsumerState<_PettySection> createState() => _PettySectionState();
}

class _PettySectionState extends ConsumerState<_PettySection> {
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
    return SettingsSection(
      title: 'Petty cash',
      description: s.petty.isEmpty
          ? 'Drobne wydatki z kasy i wpłaty do kasy.'
          : 'Bilans dnia ${balance < 0 ? '−' : '+'}${Fmt.price(balance.abs())}: wliczony w „Powinno być”.',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              SegmentedTabs<bool>(
                options: const [(true, 'Wydatek'), (false, 'Wpłata')],
                selected: _out,
                onChanged: (v) => setState(() => _out = v),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _description,
                  maxLength: 200,
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: _out ? 'Na co, np. cytryny' : 'Skąd, np. drobne',
                    isDense: true,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _MoneyField(controller: _amount, width: 130),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: 'Dodaj',
                onPressed: _busy ? null : _add,
                icon: const Glyph(AppIcons.plus, size: 18),
              ),
            ],
          ),
        ),
        for (final e in s.petty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
            child: Row(
              children: [
                Glyph(e.out ? AppIcons.minus : AppIcons.plus, size: 14, color: e.out ? _warn : _ok),
                const SizedBox(width: 12),
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
                _Amount('${e.out ? '−' : '+'}${Fmt.price(e.amountGrosze)}'),
                DeleteButton(tooltip: 'Usuń', compact: true, onPressed: () => _delete(e), size: 15),
              ],
            ),
          ),
      ],
    );
  }
}

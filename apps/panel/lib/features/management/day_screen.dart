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

/// Kolory form płatności na pasku „Jak zapłacono” (gotówka, karta z terminala, karta online, inne).
const _cashColor = Color(0xFF2FB673);
const _terminalColor = Color(0xFF3B82F6);
const _onlineColor = Color(0xFF7C5CFF);
const _otherColor = Color(0xFFD99A15);

String? _money(int? grosze) => grosze == null ? null : groszeToText(grosze);

/// „1 opakowanie”, „3 opakowania”, „5 opakowań”.
String _packs(int n) {
  final ones = n % 10;
  final tens = n % 100;
  if (n == 1) return '1 opakowanie';
  if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14)) return '$n opakowania';
  return '$n opakowań';
}

/// „1 zamówienie”, „3 zamówienia”, „5 zamówień”.
String ordersWord(int n) {
  final ones = n % 10;
  final tens = n % 100;
  if (n == 1) return '1 zamówienie';
  if (ones >= 2 && ones <= 4 && (tens < 12 || tens > 14)) return '$n zamówienia';
  return '$n zamówień';
}

/// Management → Podsumowanie dnia. Przebudowane 20.11.2026 (prośba użytkownika: „strasznie nieczytelne”; wcześniej
/// jedna kolumna dziewięciu sekcji z długimi opisami formuł). Od góry: niezamknięte zamówienia, cztery liczby dnia
/// (obrót ze wszystkimi zamówieniami razem: w lokalu i na wynos, średni rachunek, gotówka do koperty, gotówka
/// w kasie), po lewej „Jak zapłacono” z paskiem i petty cash, po prawej rozliczenie krok po kroku (kasa fiskalna,
/// terminale, gotówka w kasie, platformy dostaw, koperta) z jedną kontrolą „Zgadza się” albo różnicą w każdym
/// bloku i notatka. Formuły są w podpowiedziach przy ikonie „i”. Zapis w stałym pasku na dole. Uprawnienie
/// „Podsumowanie dnia”.
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
            data: (s) => _DayReport(
              key: ValueKey(_day),
              restaurantId: restaurant.id,
              day: _day,
              summary: s,
              unclosed: unclosed,
              dayNote: close > Duration.zero
                  ? 'Dzień lokalu od ${hm(close)} do ${hm(close)} następnego dnia: sprzedaż po północy '
                        'liczy się do tego dnia (zamknięcie dnia w Ustawieniach lokalu).'
                  : null,
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

/// Kontrola kwoty wpisanej z kwotą z panelu: zielone „Zgadza się”, żółta różnica albo szare „Wpisz kwotę”.
class _DiffChip extends StatelessWidget {
  const _DiffChip({required this.expected, required this.actual, this.empty = 'Wpisz kwotę'});

  final int expected;
  final int? actual;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final a = actual;
    final diff = a == null ? null : a - expected;
    final color = diff == null ? AppColors.textMuted : (diff == 0 ? _ok : _warn);
    final label = diff == null ? empty : (diff == 0 ? 'Zgadza się' : 'Różnica ${diff > 0 ? '+' : '−'}${Fmt.price(diff.abs())}');
    final icon = diff == null ? AppIcons.hourglass : (diff == 0 ? AppIcons.checkCircle : AppIcons.warning);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600, fontFeatures: _tabular),
          ),
        ],
      ),
    );
  }
}

/// Ikona „i” z podpowiedzią: formuły i wyjaśnienia, które wcześniej wisiały jako długie szare opisy.
class _Info extends StatelessWidget {
  const _Info(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 150),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Glyph(AppIcons.info, size: 16, color: AppColors.textMuted),
      ),
    );
  }
}

/// Cztery liczby dnia obok siebie (przy wąskim oknie po dwie w rzędzie).
class _Tiles extends StatelessWidget {
  const _Tiles(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        Widget row(List<Widget> items) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, w) in items.indexed) ...[if (i > 0) const SizedBox(width: 14), Expanded(child: w)],
            ],
          ),
        );
        if (c.maxWidth >= 900) return row(children);
        return Column(
          children: [
            for (var i = 0; i < children.length; i += 2) ...[
              if (i > 0) const SizedBox(height: 14),
              row(children.sublist(i, (i + 2).clamp(0, children.length))),
            ],
          ],
        );
      },
    );
  }
}

/// Karta z tytułem nad zawartością (jak sekcje Ustawień, ale z własną treścią).
class _TitledCard extends StatelessWidget {
  const _TitledCard({required this.title, required this.child, this.description});

  final String title;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleMedium),
                    if (description != null) ...[
                      const SizedBox(height: 2),
                      Text(description!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: child),
      ],
    );
  }
}

/// „Jak zapłacono”: pasek z udziałami form płatności i wiersze z kwotą i procentem, pod spodem rabaty, kaucja
/// i anulowane.
class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({required this.summary, required this.dayNote});

  final DaySummary summary;
  final String? dayNote;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = summary;
    final parts = [
      ('Gotówka', s.cashGrosze, _cashColor),
      ('Karta (terminal)', s.cardGrosze, _terminalColor),
      ('Karta online', s.cardOnlineGrosze, _onlineColor),
      if (s.otherGrosze > 0) ('Przelewy i inne', s.otherGrosze, _otherColor),
    ];
    final total = parts.fold(0, (sum, p) => sum + p.$2);
    String share(int v) => total == 0 ? '' : '${(v * 100 / total).round()}%';
    Widget detail(String label, String value, {String? hint}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: label,
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                children: [
                  if (hint != null) TextSpan(text: '  $hint', style: text.bodySmall?.copyWith(color: AppColors.textDisabled)),
                ],
              ),
            ),
          ),
          Text(value, style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
        ],
      ),
    );
    return _TitledCard(
      title: 'Jak zapłacono',
      description: dayNote ?? 'Rachunki zamknięte tego dnia.',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (total == 0)
              Text('Brak płatności w tym dniu.', style: text.bodyMedium?.copyWith(color: AppColors.textMuted))
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    children: [
                      for (final p in parts)
                        if (p.$2 > 0)
                          Expanded(
                            flex: p.$2,
                            child: Container(
                              height: 10,
                              margin: const EdgeInsets.only(right: 2),
                              decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(3)),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final p in parts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(width: 9, height: 9, decoration: BoxDecoration(color: p.$3, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.$1, style: text.bodyMedium)),
                      Text(
                        Fmt.price(p.$2),
                        style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontFeatures: _tabular),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          share(p.$2),
                          textAlign: TextAlign.right,
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 6),
            Divider(height: 1, color: AppColors.ring),
            const SizedBox(height: 8),
            if (s.discountsGrosze > 0) detail('Rabaty', '−${Fmt.price(s.discountsGrosze)}'),
            if (s.depositsGrosze > 0) detail('Zadatki w karcie online', Fmt.price(s.depositsGrosze)),
            detail(
              'Kaucja',
              Fmt.price(s.kaucjaGrosze),
              hint: s.kaucjaCount > 0 ? _packs(s.kaucjaCount) : 'składniki z kaucją: Inwentaryzacja → Składniki',
            ),
            if (s.cancelled > 0) detail('Anulowane i puste', '${s.cancelled}'),
          ],
        ),
      ),
    );
  }
}

/// Jeden krok rozliczenia: ikona i tytuł, kontrola (chip) i informacja po prawej, pod spodem wiersze.
class _Block extends StatelessWidget {
  const _Block({required this.icon, required this.title, required this.children, this.chip, this.help});

  final AppIconData icon;
  final String title;
  final Widget? chip;
  final String? help;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Glyph(icon.duotone, size: 20, color: AppColors.textMuted),
              const SizedBox(width: 10),
              Text(title, style: text.titleSmall),
              if (help != null) _Info(help!),
              const Spacer(),
              ?chip,
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

/// Wiersz w bloku: napis (z opcjonalnym drobnym opisem) i wartość albo pole po prawej.
class _Line extends StatelessWidget {
  const _Line(this.label, this.trailing, {this.sub});

  final String label;
  final String? sub;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Wiersz z samą kwotą jest niższy niż wiersz z polem do wpisania.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: trailing is _Amount && !(trailing as _Amount).big ? 34 : 44),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: text.bodyMedium),
                if (sub != null) Text(sub!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// Pasek na dole: czy są niezapisane zmiany albo kiedy i kto zapisał, oraz „Zapisz podsumowanie”.
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.dirty, required this.busy, required this.saved, required this.by, required this.onSave});

  final bool dirty;
  final bool busy;
  final DateTime? saved;
  final String? by;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = dirty
        ? 'Niezapisane zmiany'
        : saved == null
        ? 'Jeszcze nie zapisano'
        : 'Zapisano ${Fmt.time(saved!)}${by == null ? '' : ' · $by'}';
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.ringStrong)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dirty ? _warn : (saved == null ? AppColors.textDisabled : _ok), shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(status, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
          const Spacer(),
          FilledButton.icon(
            onPressed: busy ? null : onSave,
            icon: const Glyph(AppIcons.check, size: 18),
            label: const Text('Zapisz podsumowanie'),
          ),
        ],
      ),
    );
  }
}

/// Raport dnia: liczby dnia, „Jak zapłacono” i petty cash po lewej, rozliczenie krok po kroku po prawej,
/// zapis jednym przyciskiem w pasku na dole.
class _DayReport extends ConsumerStatefulWidget {
  const _DayReport({
    super.key,
    required this.restaurantId,
    required this.day,
    required this.summary,
    required this.unclosed,
    required this.dayNote,
  });

  final String restaurantId;
  final DateTime day;
  final DaySummary summary;
  final List<UnclosedOrder> unclosed;
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

  /// Coś zmieniono od ostatniego zapisu.
  bool _dirty = false;
  DateTime? _savedAt;
  String? _savedBy;

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

  void _changed() => setState(() => _dirty = true);

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
      if (mounted) {
        setState(() {
          _dirty = false;
          _savedAt = DateTime.now();
          _savedBy = ref.read(panelMemberProvider)?.name;
        });
        showMessage(context, 'Podsumowanie dnia zapisane.', tone: ToastTone.success);
      }
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
    final countedCash = _parse(_cash);
    final cashDiff = countedCash == null ? null : countedCash - expectedCash;

    final cashHelp = [
      'Gotówka z rachunków ${Fmt.price(s.cashGrosze)}',
      '+ napiwki gotówką ${Fmt.price(s.tipsCashGrosze)}',
      if (s.pettyOutGrosze > 0) '− wydatki z kasy ${Fmt.price(s.pettyOutGrosze)}',
      if (s.pettyInGrosze > 0) '+ wpłaty do kasy ${Fmt.price(s.pettyInGrosze)}',
      if (cardDiff > 0) '+ ${Fmt.price(cardDiff)} (na terminalach mniej niż kart w panelu)',
      if (cardDiff < 0) '− ${Fmt.price(-cardDiff)} (na terminalach więcej niż kart w panelu)',
    ].join('\n');
    final envelopeHelp =
        'Raport dobowy minus płatności online, terminale (bez napiwków kartą), przelewy i inne oraz kaucja.';

    final tiles = _Tiles([
      StatTile(
        label: 'Obrót',
        value: Fmt.price(s.revenueGrosze),
        icon: AppIcons.receipt,
        color: TileColors.green,
        hint: [
          ordersWord(s.orders),
          if (s.takeaway > 0) 'w lokalu ${s.dineIn} · na wynos ${s.takeaway}',
        ].join(' · '),
      ),
      StatTile(
        label: 'Średni rachunek',
        value: avg == null ? '—' : Fmt.price(avg.grosze),
        icon: AppIcons.chartPie,
        color: TileColors.blue,
        hint: avg == null
            ? 'Brak zamówień'
            : (avg.fromReport ? 'netto z raportu dobowego' : 'szacunek z panelu, wpisz netto z raportu'),
      ),
      Tooltip(
        message: envelopeHelp,
        child: StatTile(
          label: 'Do koperty',
          value: envelope == null ? '—' : Fmt.price(envelope.total),
          icon: AppIcons.envelope,
          color: envelope != null && envelope.total < 0 ? TileColors.rose : TileColors.violet,
          hint: envelope == null ? 'wpisz raport dobowy' : 'gotówka do odłożenia',
        ),
      ),
      Tooltip(
        message: cashHelp,
        child: StatTile(
          label: 'Gotówka w kasie',
          value: Fmt.price(expectedCash),
          icon: AppIcons.money,
          color: cashDiff == null || cashDiff == 0 ? TileColors.amber : TileColors.rose,
          hint: cashDiff == null
              ? 'tyle powinno być, wpisz policzoną'
              : (cashDiff == 0 ? 'policzona, zgadza się' : 'policzona ${cashDiff > 0 ? '+' : '−'}${Fmt.price(cashDiff.abs())}'),
        ),
      ),
    ]);

    final left = <Widget>[
      _PaymentsCard(summary: s, dayNote: widget.dayNote),
      const SizedBox(height: 28),
      _PettySection(restaurantId: widget.restaurantId, day: widget.day, summary: s),
    ];

    Widget divider() => Divider(height: 1, color: AppColors.ring);
    final right = <Widget>[
      _TitledCard(
        title: 'Rozliczenie dnia',
        description: 'Wpisz kwoty z raportów i z kasy. Przy każdym kroku panel od razu pokazuje, czy się zgadza.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Block(
              icon: AppIcons.cashRegister,
              title: 'Kasa fiskalna',
              chip: _DiffChip(expected: s.revenueGrosze, actual: _parse(_fiscal), empty: 'Wpisz raport'),
              help: 'Raport dobowy wydrukowany na koniec dnia porównujemy z obrotem w panelu.',
              children: [
                _Line('Obrót w panelu', _Amount(Fmt.price(s.revenueGrosze))),
                _Line('Raport dobowy (brutto)', _MoneyField(controller: _fiscal, onChanged: _changed)),
                _Line(
                  'Netto z raportu',
                  _MoneyField(controller: _fiscalNet, onChanged: _changed),
                  sub: 'Do średniego rachunku.',
                ),
              ],
            ),
            divider(),
            _Block(
              icon: AppIcons.creditCard,
              title: 'Terminale płatnicze',
              chip: _DiffChip(expected: s.expectedCardGrosze, actual: terminals, empty: 'Wpisz terminale'),
              help: 'Płatności kartą z napiwkami. Różnica między terminalami a panelem przechodzi na gotówkę w kasie.',
              children: [
                for (final (i, (name, amount)) in _terminals.indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: name,
                            maxLength: 60,
                            onChanged: (_) => _changed(),
                            decoration: const InputDecoration(hintText: 'Nazwa terminala', isDense: true, counterText: ''),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _MoneyField(controller: amount, onChanged: _changed),
                        DeleteButton(
                          tooltip: 'Usuń terminal',
                          onPressed: _terminals.length == 1
                              ? null
                              : () => setState(() {
                                  final removed = _terminals.removeAt(i);
                                  removed.$1.dispose();
                                  removed.$2.dispose();
                                  _dirty = true;
                                }),
                        ),
                      ],
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _terminals.add((TextEditingController(text: 'Terminal ${_terminals.length + 1}'), TextEditingController()));
                      _dirty = true;
                    }),
                    icon: const Glyph(AppIcons.plus, size: 16),
                    label: const Text('Dodaj terminal'),
                  ),
                ),
                _Line('Karty w panelu', _Amount(Fmt.price(s.expectedCardGrosze))),
              ],
            ),
            divider(),
            _Block(
              icon: AppIcons.money,
              title: 'Gotówka w kasie',
              chip: _DiffChip(expected: expectedCash, actual: countedCash, empty: 'Wpisz gotówkę'),
              help: 'Jak liczone:\n$cashHelp',
              children: [
                _Line('Powinno być', _Amount(Fmt.price(expectedCash), big: true)),
                _Line('Policzona gotówka', _MoneyField(controller: _cash, onChanged: _changed)),
              ],
            ),
            if (_platforms.isNotEmpty) ...[
              divider(),
              _Block(
                icon: AppIcons.moped,
                title: 'Platformy dostaw',
                chip: Text(
                  'Razem ${Fmt.price(platformsSum)}',
                  style: text.labelMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
                help: 'Osobno, poza kasą fiskalną i obrotem w panelu.',
                children: [
                  for (final e in _platforms.entries) _Line(e.key, _MoneyField(controller: e.value, onChanged: _changed)),
                ],
              ),
            ],
            divider(),
            _Block(
              icon: AppIcons.envelope,
              title: 'Gotówka do koperty',
              help: envelopeHelp,
              children: [
                if (envelope == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      'Wpisz raport dobowy, a panel policzy, ile gotówki odłożyć do koperty.',
                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  )
                else ...[
                  _Line('Raport dobowy', _Amount(Fmt.price(envelope.fiscal))),
                  if (envelope.online > 0) _Line('− Płatności online', _Amount('−${Fmt.price(envelope.online)}')),
                  _Line('− Terminale (bez napiwków)', _Amount('−${Fmt.price(envelope.terminals)}')),
                  if (envelope.other > 0) _Line('− Przelewy i inne', _Amount('−${Fmt.price(envelope.other)}')),
                  if (envelope.kaucja > 0) _Line('− Kaucja', _Amount('−${Fmt.price(envelope.kaucja)}')),
                  const SizedBox(height: 4),
                  Divider(height: 1, color: AppColors.ring),
                  _Line(
                    'Do koperty',
                    _Amount(Fmt.price(envelope.total), big: true, color: envelope.total < 0 ? _warn : null),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 28),
      _TitledCard(
        title: 'Notatka',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: TextField(
            controller: _note,
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            onChanged: (_) => _changed(),
            decoration: const InputDecoration(hintText: 'Coś do zapamiętania z tego dnia', counterText: ''),
          ),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth >= 940;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.unclosed.isNotEmpty) ...[
                          _UnclosedBanner(orders: widget.unclosed),
                          const SizedBox(height: 20),
                        ],
                        tiles,
                        const SizedBox(height: 28),
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: left)),
                              const SizedBox(width: 24),
                              Expanded(flex: 6, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: right)),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [...left, const SizedBox(height: 28), ...right],
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        _SaveBar(dirty: _dirty, busy: _busy, saved: _savedAt ?? _report?.updatedAt, by: _savedAt != null ? _savedBy : _report?.updatedBy, onSave: _save),
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

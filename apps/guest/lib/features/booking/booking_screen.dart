import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'deposit_sheet.dart';

const _tabular = [FontFeature.tabularFigures()];

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  static const _days = 14;

  late DateTime _date = _today();
  int _party = 2;
  DateTime? _slot;
  Occasion? _occasion;
  final _message = TextEditingController();
  final _diet = TextEditingController();
  final _code = TextEditingController();
  bool _dietConsent = false;
  bool _busy = false;

  /// Sprawdzony kod rabatowy; null, gdy go nie ma albo nie działa.
  GuestDiscount? _discount;
  String? _codeError;
  bool _checking = false;

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _message.dispose();
    _diet.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _checkCode() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _checking = true;
      _codeError = null;
    });
    try {
      final discount = await ref.read(repositoryProvider).checkDiscount(widget.restaurantId, code, startsAt: _slot ?? _date);
      if (mounted) setState(() => _discount = discount);
    } catch (e) {
      if (mounted) {
        setState(() {
          _discount = null;
          _codeError = errorText(e);
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  SlotQuery get _query =>
      (restaurantId: widget.restaurantId, date: _date, partySize: _party);

  void _setDate(DateTime day) => setState(() {
    _date = day;
    _slot = null;
  });

  void _setParty(int value) => setState(() {
    _party = value;
    _slot = null;
  });

  Future<void> _book() async {
    final slot = _slot;
    if (slot == null) return;
    FocusScope.of(context).unfocus();
    if (_diet.text.trim().isNotEmpty && !_dietConsent) {
      showMessage(
        context,
        'Zaznacz zgodę, żeby przekazać restauracji informację o alergiach.',
      );
      return;
    }

    final deposit = ref.read(restaurantProvider(widget.restaurantId)).value?.depositFor(_party);
    setState(() => _busy = true);
    try {
      final id = await ref
          .read(repositoryProvider)
          .book(
            restaurantId: widget.restaurantId,
            startsAt: slot,
            partySize: _party,
            occasion: _occasion,
            message: _message.text,
            diet: _diet.text,
            dietConsent: _dietConsent,
            discountCode: _code.text,
          );
      // Lokal bierze zadatek: bez wpłaty rezerwacja się nie utrzymuje, więc anulowanie płatności ją odwołuje.
      if (deposit != null && mounted) {
        final paid = await payDeposit(context, reservationId: id, amountGrosze: deposit);
        if (!paid) {
          await ref.read(repositoryProvider).cancelReservation(id);
          ref.invalidate(myReservationsProvider);
          if (mounted) showMessage(context, 'Bez zadatku rezerwacja nie została zapisana.');
          ref.invalidate(slotsProvider(_query));
          return;
        }
      }
      ref.invalidate(myReservationsProvider);
      if (!mounted) return;
      showMessage(
        context,
        'Zarezerwowano: ${Fmt.dateTime(slot)}, ${Fmt.people(_party)}${deposit == null ? '' : ', zadatek ${Fmt.price(deposit)}'}.',
      );
      context.go(AppRoutes.reservations);
    } catch (e) {
      if (!mounted) return;
      showError(context, e);
      setState(() => _slot = null);
      ref.invalidate(slotsProvider(_query));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final restaurant = ref.watch(restaurantProvider(widget.restaurantId)).value;
    final slots = ref.watch(slotsProvider(_query));
    final hours = restaurant?.hoursFor(_date);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Rezerwacja stolika',
              style: text.labelMedium?.copyWith(color: AppColors.textMuted),
            ),
            Text(
              restaurant?.name ?? '',
              style: text.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                Glyph(AppIcons.calendar, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Text(
                  Fmt.monthYear(_date),
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _days,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final day = _today().add(Duration(days: i));
                final closed =
                    restaurant != null && restaurant.hoursFor(day) == null;
                return _DayTile(
                  day: day,
                  index: i,
                  selected: day == _date,
                  enabled: !closed,
                  onTap: () => _setDate(day),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Fmt.capitalize(Fmt.dayLong(_date)),
                  style: text.titleLarge,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Glyph(AppIcons.clock, size: 15, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      hours == null
                          ? 'Zamknięte'
                          : 'Otwarte ${hours.opens}–${hours.closes}',
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SectionTitle('Liczba osób'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Mniej osób',
                      onPressed: _party > 1
                          ? () => _setParty(_party - 1)
                          : null,
                      icon: const Glyph(AppIcons.minus),
                    ),
                    Expanded(
                      child: Text(
                        Fmt.people(_party),
                        textAlign: TextAlign.center,
                        style: text.titleMedium?.copyWith(
                          fontFeatures: _tabular,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Więcej osób',
                      onPressed: _party < (restaurant?.maxPartySize ?? 12)
                          ? () => _setParty(_party + 1)
                          : null,
                      icon: const Glyph(AppIcons.plus),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (restaurant?.depositFor(_party) case final deposit?)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Glyph(AppIcons.creditCard, size: 18, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Zadatek ${Fmt.price(deposit)} (${Fmt.price(restaurant!.depositPerPersonGrosze!)} za osobę). '
                        'Odejmie się od rachunku, odwołanie go zwraca.',
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SectionTitle('Godzina'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: slots.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: LoadingView(),
              ),
              error: (e, _) => Text(
                errorText(e),
                style: TextStyle(color: AppColors.textMuted),
              ),
              data: (items) => items.isEmpty
                  ? Text(
                      'Brak wolnych stolików tego dnia dla takiej liczby osób. Wybierz inny dzień.',
                      style: TextStyle(color: AppColors.textMuted),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SlotGrid(
                          slots: items,
                          selected: _slot,
                          onSelected: (s) => setState(() => _slot = s),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Glyph(
                              AppIcons.check,
                              size: 16,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Godziny z wolnym stolikiem na ${Fmt.peopleAccusative(_party)}.',
                                style: text.bodySmall?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          const SectionTitle('Okazja'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in Occasion.values)
                  ChoiceChip(
                    label: Text(o.label),
                    selected: o == _occasion,
                    onSelected: (_) =>
                        setState(() => _occasion = o == _occasion ? null : o),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _message,
              maxLength: 300,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(
                labelText: 'Wiadomość do restauracji',
                hintText:
                    'Na przykład: stolik przy oknie, przyjdziemy z wózkiem.',
                alignLabelWithHint: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text('Alergie lub dieta'),
                children: [
                  TextField(
                    controller: _diet,
                    maxLength: 300,
                    maxLines: 2,
                    // Przykład jako podpowiedź, bo pływająca etykieta wychodziła
                    // nad pole i rozwijana sekcja ją ucinała.
                    decoration: const InputDecoration(
                      hintText: 'Na przykład: bez orzechów, bez glutenu',
                    ),
                  ),
                  CheckboxListTile(
                    value: _dietConsent,
                    onChanged: (v) => setState(() => _dietConsent = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.accent,
                    checkColor: AppColors.onAccentStrong,
                    title: Text(
                      'Zgadzam się przekazać restauracji informację o alergiach. Usuniemy ją 30 dni po wizycie.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                initiallyExpanded: _code.text.isNotEmpty,
                title: Text(_discount == null ? 'Kod rabatowy' : 'Kod rabatowy: ${_discount!.code}'),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _code,
                          maxLength: 20,
                          textCapitalization: TextCapitalization.characters,
                          onChanged: (_) => setState(() {
                            _discount = null;
                            _codeError = null;
                          }),
                          onSubmitted: (_) => _checkCode(),
                          decoration: InputDecoration(
                            hintText: 'Na przykład JESIEN10',
                            counterText: '',
                            errorText: _codeError,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: OutlinedButton(
                          onPressed: _checking || _code.text.trim().isEmpty ? null : _checkCode,
                          child: const Text('Sprawdź'),
                        ),
                      ),
                    ],
                  ),
                  if (_discount != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: Row(
                        children: [
                          Glyph(AppIcons.check, size: 16, color: AppColors.accent),
                          const SizedBox(width: 6),
                          Text(_discount!.label, style: text.bodyMedium?.copyWith(color: AppColors.accent)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
      // Dolny pasek Scaffolda zostaje pod klawiaturą, więc podnosimy go o jej wysokość.
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _SummaryBar(
          slot: _slot,
          party: _party,
          busy: _busy,
          deposit: restaurant?.depositFor(_party),
          onBook: _book,
        ),
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.index,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final DateTime day;
  final int index;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (index) {
      0 => 'Dziś',
      1 => 'Jutro',
      _ => Fmt.weekdayShort(day),
    };
    final number = !enabled ? AppColors.textDisabled : AppColors.text;
    final caption = !enabled
        ? AppColors.textDisabled
        : selected
        ? AppColors.text
        : AppColors.textMuted;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label:
          '${Fmt.capitalize(Fmt.dayLong(day))}${enabled ? '' : ', zamknięte'}',
      excludeSemantics: true,
      child: PressScale(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          width: 60,
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceRaised : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.ring,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: caption,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: number,
                  fontFeatures: _tabular,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({
    required this.slots,
    required this.selected,
    required this.onSelected,
  });

  final List<DateTime> slots;
  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        const columns = 3;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final s in slots)
              SizedBox(
                width: width,
                height: 48,
                child: _SlotButton(
                  label: Fmt.time(s),
                  selected: s == selected,
                  onTap: () => onSelected(s),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SlotButton extends StatelessWidget {
  const _SlotButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Godzina $label',
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.accentFill : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.accentFill : AppColors.ring,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.onAccent : AppColors.text,
              fontFeatures: _tabular,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.slot,
    required this.party,
    required this.busy,
    required this.onBook,
    this.deposit,
  });

  final DateTime? slot;
  final int party;
  final bool busy;
  final VoidCallback onBook;

  /// Zadatek do wpłaty po rezerwacji. Null: bez zadatku.
  final int? deposit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final start = slot;
    final summary = start == null
        ? 'Wybierz godzinę'
        : '${Fmt.capitalize(Fmt.dayShort(start))} · '
              '${Fmt.time(start)}–${Fmt.time(start.add(Duration(minutes: visitMinutes(party))))} · '
              '${Fmt.people(party)}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Glyph(
                  AppIcons.clock,
                  size: 18,
                  color: start == null
                      ? AppColors.textDisabled
                      : AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: start == null
                          ? AppColors.textMuted
                          : AppColors.text,
                      fontFeatures: _tabular,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: start == null || busy ? null : onBook,
              child: busy
                  ? SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textMuted,
                      ),
                    )
                  : Text(deposit == null ? 'Zarezerwuj stolik' : 'Zarezerwuj i wpłać ${Fmt.price(deposit!)}'),
            ),
          ],
        ),
      ),
    );
  }
}

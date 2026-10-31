import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../floor/floor_canvas.dart';

const _tabular = [FontFeature.tabularFigures()];

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';

DateTime _minute(DateTime t) => DateTime(t.year, t.month, t.day, t.hour, t.minute);

Color activityColor(ActivityGroup g) => switch (g) {
  ActivityGroup.staff => TileColors.blue,
  ActivityGroup.bills => TileColors.green,
  ActivityGroup.kitchen => TileColors.amber,
  ActivityGroup.takeaway => TileColors.violet,
  ActivityGroup.reservations => AppColors.accent,
  ActivityGroup.stock => TileColors.rose,
};

AppIconData activityIcon(ActivityEvent e) => switch (e.kind) {
  'shift_start' => AppIcons.signIn,
  'shift_end' => AppIcons.doorOpen,
  'order_open' => AppIcons.forkKnife,
  'order_close' => AppIcons.checkCircle,
  'payment' => e.method == 'cash' ? AppIcons.money : AppIcons.creditCard,
  'items_added' => AppIcons.receipt,
  'items_sent' => AppIcons.send,
  'items_ready' => AppIcons.bell,
  'items_served' => AppIcons.checkCircle,
  'items_cancelled' => AppIcons.xCircle,
  'takeaway_picked' || 'takeaway_done' => AppIcons.moped,
  'reservation_new' || 'reservation_app' => AppIcons.calendarCheck,
  'reservation_seated' => AppIcons.users,
  'stock_delivery' => AppIcons.truck,
  'stock_removal' => AppIcons.minusCircle,
  'stock_count' => AppIcons.clipboardText,
  _ => AppIcons.shoppingBag,
};

String _groupLabel(ActivityGroup g) => switch (g) {
  ActivityGroup.staff => 'Zmiany',
  ActivityGroup.bills => 'Rachunki',
  ActivityGroup.kitchen => 'Kuchnia',
  ActivityGroup.takeaway => 'Na wynos',
  ActivityGroup.reservations => 'Rezerwacje',
  ActivityGroup.stock => 'Magazyn',
};

/// Management → Logi (uprawnienie `activity`), w stylu UniFi Protect: po lewej oś doby z ikonami zdarzeń,
/// w środku sala, rachunki, zamówienia na wynos i zmiana w wybranej chwili (Time Machine), po prawej zdarzenia do
/// tej chwili. „Na żywo” trzyma chwilę na teraz i odświeża się z zamówieniami; kliknięcie albo przeciągnięcie osi
/// czasu przechodzi do Historii, gdzie wybiera się też dzień.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  bool _live = true;
  DateTime _day = dateOnly(DateTime.now());
  DateTime _at = _minute(DateTime.now());
  String? _zone;
  String? _selectedOrder;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Na żywo: chwila idzie z zegarem (co pół minuty, stan liczy się z dokładnością do minuty).
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_live || !mounted) return;
      final now = DateTime.now();
      setState(() {
        _day = dateOnly(now);
        _at = _minute(now);
      });
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _goLive() {
    final now = DateTime.now();
    setState(() {
      _live = true;
      _day = dateOnly(now);
      _at = _minute(now);
    });
  }

  void _pick(DateTime at) {
    final now = DateTime.now();
    final clamped = at.isAfter(now) ? now : at;
    setState(() {
      _live = false;
      _at = _minute(clamped);
    });
  }

  void _shiftDay(int days) {
    final today = dateOnly(DateTime.now());
    var day = dateOnly(_day.add(Duration(days: days)));
    if (day.isAfter(today)) day = today;
    final keep = Duration(hours: _at.hour, minutes: _at.minute);
    var at = day.add(keep);
    if (at.isAfter(DateTime.now())) at = DateTime.now();
    setState(() {
      _live = false;
      _day = day;
      _at = _minute(at);
    });
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now(),
    );
    if (picked != null) _shiftDay(dateOnly(picked).difference(_day).inDays);
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final rid = restaurant.id;
    final text = Theme.of(context).textTheme;
    final today = dateOnly(DateTime.now());
    final eventsAsync = ref.watch(activityProvider((restaurantId: rid, day: _day)));
    final events = eventsAsync.value ?? const <ActivityEvent>[];
    final tmAsync = ref.watch(timeMachineProvider((restaurantId: rid, at: _at)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          below: Row(
            children: [
              SegmentedTabs<bool>(
                options: const [(true, 'Na żywo'), (false, 'Historia')],
                selected: _live,
                onChanged: (live) => live ? _goLive() : setState(() => _live = false),
              ),
              const SizedBox(width: 12),
              if (!_live)
                StepSwitcher(
                  label: '${Fmt.capitalize(Fmt.dayShort(_day))}${_day == today ? ' · dziś' : ''}',
                  labelWidth: 150,
                  previousTooltip: 'Poprzedni dzień',
                  nextTooltip: 'Następny dzień',
                  onPrevious: () => _shiftDay(-1),
                  onNext: _day == today ? null : () => _shiftDay(1),
                  resetTooltip: 'Wróć do teraz',
                  onReset: _goLive,
                  extras: [(AppIcons.calendar, 'Wybierz dzień', _pickDay)],
                ),
              const Spacer(),
              if (_live) const PanelPill('Na żywo', dotColor: Color(0xFF2FB673)),
              const SizedBox(width: 10),
              Text('Stan o ${_hm(_at)}', style: text.titleMedium?.copyWith(fontFeatures: _tabular)),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 190,
                  child: _Timeline(day: _day, at: _at, events: events, onPick: _pick),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: tmAsync.when(
                    skipLoadingOnReload: true,
                    loading: () => const LoadingView(),
                    error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () => ref.invalidate(timeMachineProvider((restaurantId: rid, at: _at))),
                    ),
                    data: (tm) => _Snapshot(
                      restaurantId: rid,
                      tm: tm,
                      zone: _zone,
                      selectedOrder: _selectedOrder,
                      onZone: (z) => setState(() => _zone = z),
                      onSelectOrder: (id) => setState(() => _selectedOrder = id == _selectedOrder ? null : id),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 340,
                  child: _EventList(
                    events: [
                      for (final e in events.reversed)
                        if (!e.at.isAfter(_at.add(const Duration(seconds: 59)))) e,
                    ],
                    loading: eventsAsync.isLoading && !eventsAsync.hasValue,
                    selectedOrder: _selectedOrder,
                    onPick: (e) {
                      _pick(e.at);
                      if (e.orderId != null) setState(() => _selectedOrder = e.orderId);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Pionowa oś doby (00:00 u góry, 24:00 na dole) z kropkami zdarzeń w pasach grup i kreską wybranej chwili.
/// Kliknięcie albo przeciągnięcie wybiera chwilę.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.day, required this.at, required this.events, required this.onPick});

  final DateTime day;
  final DateTime at;
  final List<ActivityEvent> events;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ring),
      ),
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Legenda pasów.
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final g in ActivityGroup.values)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: activityColor(g), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(_groupLabel(g), style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final h = c.maxHeight;
                DateTime timeAt(double y) =>
                    day.add(Duration(minutes: (y.clamp(0, h) / h * 1440).round().clamp(0, 1439)));
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => onPick(timeAt(d.localPosition.dy)),
                  onVerticalDragUpdate: (d) => onPick(timeAt(d.localPosition.dy)),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: CustomPaint(
                      size: Size(c.maxWidth, h),
                      painter: _TimelinePainter(
                        day: day,
                        at: at,
                        events: events,
                        now: DateTime.now(),
                        line: AppColors.ring,
                        label: AppColors.textMuted,
                        accent: AppColors.accent,
                        future: AppColors.surfaceRaised,
                        textStyle: text.labelSmall ?? const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.day,
    required this.at,
    required this.events,
    required this.now,
    required this.line,
    required this.label,
    required this.accent,
    required this.future,
    required this.textStyle,
  });

  final DateTime day;
  final DateTime at;
  final DateTime now;
  final List<ActivityEvent> events;
  final Color line;
  final Color label;
  final Color accent;
  final Color future;
  final TextStyle textStyle;

  static const _labelWidth = 40.0;

  double _y(DateTime t, double h) => t.difference(day).inSeconds / 86400 * h;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final lanesLeft = _labelWidth + 6;
    final laneWidth = (size.width - lanesLeft) / ActivityGroup.values.length;

    // Przyszłość (dziś po teraz) przygaszona.
    if (now.isBefore(day.add(const Duration(days: 1)))) {
      final y = _y(now, h).clamp(0.0, h);
      canvas.drawRect(Rect.fromLTRB(lanesLeft, y, size.width, h), Paint()..color = future);
    }

    // Godziny: kreska co godzinę, podpis co 2 godziny.
    final tick = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var hour = 0; hour <= 24; hour++) {
      final y = hour / 24 * h;
      canvas.drawLine(Offset(lanesLeft, y), Offset(size.width, y), tick);
      if (hour % 2 == 0 && hour < 24) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${_two(hour)}:00',
            style: textStyle.copyWith(color: label, fontFeatures: _tabular),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(0, (y - tp.height / 2).clamp(0, h - tp.height)));
      }
    }

    // Zdarzenia: kropka w pasie swojej grupy.
    for (final e in events) {
      final lane = e.group.index;
      final x = lanesLeft + laneWidth * lane + laneWidth / 2;
      final y = _y(e.at.toLocal(), h);
      canvas.drawCircle(Offset(x, y), 3.2, Paint()..color = activityColor(e.group).withValues(alpha: 0.85));
    }

    // Wybrana chwila.
    final ay = _y(at, h).clamp(0.0, h);
    canvas.drawLine(
      Offset(lanesLeft - 4, ay),
      Offset(size.width, ay),
      Paint()
        ..color = accent
        ..strokeWidth = 2,
    );
    canvas.drawCircle(Offset(lanesLeft - 4, ay), 4, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.at != at || old.events != events || old.day != day || old.line != line || old.now.minute != now.minute;
}

/// Stan lokalu w wybranej chwili: liczby, sala z rachunkami i rezerwacjami, rachunki z pozycjami, na wynos, zmiana.
class _Snapshot extends ConsumerWidget {
  const _Snapshot({
    required this.restaurantId,
    required this.tm,
    required this.zone,
    required this.selectedOrder,
    required this.onZone,
    required this.onSelectOrder,
  });

  final String restaurantId;
  final TimeMachine tm;
  final String? zone;
  final String? selectedOrder;
  final ValueChanged<String> onZone;
  final ValueChanged<String> onSelectOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final zones = ref.watch(zonesProvider(restaurantId)).value ?? const <FloorZone>[];
    final tables = ref.watch(tablesProvider(restaurantId)).value ?? const <DiningTable>[];
    final elements = ref.watch(elementsProvider(restaurantId)).value ?? const <FloorElement>[];
    final current = zones.where((z) => z.name == zone).firstOrNull ?? zones.firstOrNull;
    final open = tm.bills.fold(0, (s, b) => s + b.total);
    final paid = tm.bills.fold(0, (s, b) => s + b.paid);

    return ListView(
      children: [
        Row(
          children: [
            Expanded(
              child: StatTile(
                label: 'Otwarte rachunki',
                value: '${tm.bills.length}',
                hint: tm.bills.isEmpty ? 'sala pusta' : 'na sali ${Fmt.price(open)}, wpłacone ${Fmt.price(paid)}',
                icon: AppIcons.forkKnife,
                color: TileColors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                label: 'Na wynos w toku',
                value: '${tm.takeaway.length}',
                hint: 'dostawy i odbiór',
                icon: AppIcons.moped,
                color: TileColors.violet,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: StatTile(
                label: 'Na zmianie',
                value: '${tm.staff.length}',
                hint: tm.staff.isEmpty ? 'nikt' : tm.staff.map((s) => s.$1).join(', '),
                icon: AppIcons.users,
                color: TileColors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (current != null)
          Container(
            height: 380,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.ring),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (zones.length > 1)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedTabs<String>(
                      options: [for (final z in zones) (z.name, Fmt.capitalize(z.name))],
                      selected: current.name,
                      onChanged: onZone,
                    ),
                  ),
                if (zones.length > 1) const SizedBox(height: 8),
                Expanded(
                  child: FloorCanvas(
                    zone: current,
                    tables: [
                      for (final t in tables)
                        if (t.zone == current.name) t,
                    ],
                    elements: [
                      for (final e in elements)
                        if (e.zone == current.name) e,
                    ],
                    showGrid: false,
                    selectedId: null,
                    lookOf: (t) => _look(t),
                    onTapTable: (t) {
                      final bill = t.id == null ? null : tm.billAt(t.id!);
                      if (bill != null) onSelectOrder(bill.orderId);
                    },
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        if (tm.bills.isNotEmpty) ...[
          Text('Rachunki o ${_hm(tm.at)}', style: text.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final b in tm.bills)
                _BillCard(bill: b, selected: b.orderId == selectedOrder, onTap: () => onSelectOrder(b.orderId)),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (tm.takeaway.isNotEmpty) ...[
          Text('Na wynos o ${_hm(tm.at)}', style: text.titleSmall),
          const SizedBox(height: 8),
          for (final t in tm.takeaway)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Glyph(AppIcons.moped, size: 16, color: TileColors.violet),
                  const SizedBox(width: 8),
                  Expanded(child: Text([t.label, ?t.customer, t.stageLabel].join(' · '), style: text.bodyMedium)),
                  Text(Fmt.price(t.total), style: text.bodyMedium?.copyWith(fontFeatures: _tabular)),
                ],
              ),
            ),
        ],
        if (tm.bills.isEmpty && tm.takeaway.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'O ${_hm(tm.at)} nie było otwartych rachunków ani zamówień na wynos.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
          ),
      ],
    );
  }

  TableLook _look(DiningTable t) {
    final bill = t.id == null ? null : tm.billAt(t.id!);
    final selected = bill != null && bill.orderId == selectedOrder;
    if (bill != null) {
      return TableLook(
        fill: AppColors.accentTint,
        stroke: AppColors.accent,
        strokeWidth: selected ? 3.5 : 2,
        caption: Fmt.price(bill.total),
        captionColor: AppColors.accent,
      );
    }
    final res = t.id == null ? null : tm.reservationAt(t.id!);
    if (res != null) {
      return TableLook(
        fill: AppColors.warning.withValues(alpha: 0.14),
        stroke: AppColors.warning,
        strokeWidth: 2,
        caption: res.seated ? res.name : 'od ${_hm(res.startsAt)}',
        captionColor: AppColors.warning,
      );
    }
    return TableLook(fill: AppColors.surface, stroke: t.active ? planLine : planLineMuted, dimmed: !t.active);
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({required this.bill, required this.selected, required this.onTap});

  final TmBill bill;
  final bool selected;
  final VoidCallback onTap;

  static (String, Color) _status(String s) => switch (s) {
    'sent' => ('na kuchni', TileColors.amber),
    'ready' => ('do wydania', TileColors.blue),
    'served' => ('wydane', TileColors.green),
    'cancelled' => ('anulowane', TileColors.rose),
    _ => ('niewysłane', AppColors.textMuted),
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 300,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? AppColors.accent : AppColors.ring, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(bill.label, style: text.titleSmall)),
                  Text(Fmt.price(bill.total), style: text.titleSmall?.copyWith(fontFeatures: _tabular)),
                ],
              ),
              Text(
                [
                  'od ${_hm(bill.openedAt)}',
                  if (bill.guests != null) '${bill.guests} ${bill.guests == 1 ? 'gość' : 'gości'}',
                  ?bill.openedBy,
                  if (bill.paid > 0) 'wpłacone ${Fmt.price(bill.paid)}',
                ].join(' · '),
                style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
              ),
              const SizedBox(height: 6),
              for (final i in bill.items)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i.quantity}× ${[i.name, ?i.variant].join(' · ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            decoration: i.status == 'cancelled' ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      Text(_status(i.status).$1, style: text.labelSmall?.copyWith(color: _status(i.status).$2)),
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

/// Zdarzenia do wybranej chwili, najnowsze u góry. Kliknięcie przenosi do chwili zdarzenia.
class _EventList extends StatelessWidget {
  const _EventList({required this.events, required this.loading, required this.selectedOrder, required this.onPick});

  final List<ActivityEvent> events;
  final bool loading;
  final String? selectedOrder;
  final ValueChanged<ActivityEvent> onPick;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ring),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text('Zdarzenia (${events.length})', style: text.titleSmall),
          ),
          Expanded(
            child: loading
                ? const LoadingView()
                : events.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Brak zdarzeń do tej chwili.',
                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: events.length,
                    itemBuilder: (context, i) {
                      final e = events[i];
                      final color = activityColor(e.group);
                      final highlighted = e.orderId != null && e.orderId == selectedOrder;
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onPick(e),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: highlighted ? AppColors.accentTint : null,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 40,
                                child: Text(
                                  _hm(e.at),
                                  style: text.labelMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                                ),
                              ),
                              Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Glyph(activityIcon(e), size: 14, color: color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.title, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                                    if (e.detail case final d?)
                                      Text(
                                        d,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

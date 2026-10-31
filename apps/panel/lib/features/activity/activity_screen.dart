import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
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
String _hms(DateTime t) => '${_hm(t)}:${_two(t.toLocal().second)}';

DateTime _nextDay(DateTime day) => DateTime(day.year, day.month, day.day + 1);

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

/// Stan pozycji rachunku: nazwa i kolor (tabela, pasek pozycji i legenda).
(String, Color) _itemStatus(String status) => switch (status) {
  'sent' => ('na kuchni', TileColors.amber),
  'ready' => ('do wydania', TileColors.blue),
  'served' => ('wydane', TileColors.green),
  'cancelled' => ('anulowane', TileColors.rose),
  _ => ('niewysłane', AppColors.textMuted),
};

const _itemStatuses = ['new', 'sent', 'ready', 'served'];

/// Etap zamówienia na wynos z kolorem.
Color _stageColor(String stage) => switch (stage) {
  'accepted' => TileColors.amber,
  'ready' => TileColors.blue,
  'on_the_way' => TileColors.violet,
  'delivered' => TileColors.green,
  _ => TileColors.rose,
};

/// Stolik w kolejności sali: numery rosnąco jak liczby, reszta alfabetycznie.
int _compareLabels(String a, String b) {
  final x = int.tryParse(a);
  final y = int.tryParse(b);
  if (x != null && y != null) return x.compareTo(y);
  if (x != null) return -1;
  if (y != null) return 1;
  return a.compareTo(b);
}

enum _ListTab { tables, takeaway, staff, events }

/// Logi (pod „Ustawienia lokalu”, uprawnienie `activity`), jak Time Machine w UniFi: po lewej oś czasu, która
/// przesuwa się pod stałą kreską wybranej chwili (przeciąganie z bezwładnością, kółko myszy, Ctrl + kółko zmienia
/// skalę, kliknięcie albo ikona zdarzenia przenosi do chwili), u góry plan sali w tej chwili, pod nim legenda
/// i tabela: stoliki z rachunkami, na wynos, osoby na zmianie i zdarzenia do tej chwili. Cała doba przychodzi
/// z bazy naraz (`timeMachineDayProvider`), a stan w chwili liczy panel, więc wszystko zmienia się od razu.
/// „Na żywo” trzyma chwilę na teraz (co sekundę), „Historia” ma dzień.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  bool _live = true;
  DateTime _day = dateOnly(DateTime.now());
  DateTime _at = DateTime.now();

  /// Skala osi: punkty na minutę.
  double _zoom = 3;
  String? _zone;
  String? _selectedOrder;
  String? _selectedTable;
  _ListTab _tab = _ListTab.tables;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // Na żywo: chwila idzie z zegarem.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_live || !mounted) return;
      final now = DateTime.now();
      setState(() {
        _day = dateOnly(now);
        _at = now;
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
      _at = now;
    });
  }

  DateTime get _latest {
    final now = DateTime.now();
    final end = _nextDay(_day).subtract(const Duration(seconds: 1));
    return end.isAfter(now) ? now : end;
  }

  void _pick(DateTime at) {
    var t = at.isBefore(_day) ? _day : at;
    if (t.isAfter(_latest)) t = _latest;
    if (t == _at && !_live) return;
    setState(() {
      _live = false;
      _at = t;
    });
  }

  void _shiftDay(int days) {
    final today = dateOnly(DateTime.now());
    var day = DateTime(_day.year, _day.month, _day.day + days);
    if (day.isAfter(today)) day = today;
    var at = DateTime(day.year, day.month, day.day, _at.hour, _at.minute, _at.second);
    if (at.isAfter(DateTime.now())) at = DateTime.now();
    setState(() {
      _live = false;
      _day = day;
      _at = at;
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

  void _selectOrder(String? orderId, {String? tableId, String? zone}) {
    setState(() {
      final same = orderId != null ? orderId == _selectedOrder : tableId == _selectedTable;
      _selectedOrder = same ? null : orderId;
      _selectedTable = same ? null : tableId;
      if (zone != null) _zone = zone;
    });
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final rid = restaurant.id;
    final today = dateOnly(DateTime.now());
    final query = (restaurantId: rid, day: _day);
    final dayAsync = ref.watch(timeMachineDayProvider(query));
    final events = ref.watch(activityProvider(query)).value ?? const <ActivityEvent>[];
    final data = dayAsync.value;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _railWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Tryb i dzień nad osią czasu, na całą szerokość jej karty.
                SegmentedTabs<bool>(
                  options: const [(true, 'Na żywo'), (false, 'Historia')],
                  selected: _live,
                  expand: true,
                  onChanged: (live) => live ? _goLive() : setState(() => _live = false),
                ),
                const SizedBox(height: 10),
                StepSwitcher(
                  label: _day == today ? 'Dziś' : Fmt.capitalize(Fmt.dayShort(_day)),
                  expand: true,
                  previousTooltip: 'Poprzedni dzień',
                  nextTooltip: 'Następny dzień',
                  onPrevious: () => _shiftDay(-1),
                  onNext: _day == today ? null : () => _shiftDay(1),
                  resetTooltip: 'Wróć do teraz',
                  onReset: _live ? null : _goLive,
                  extras: [(AppIcons.calendar, 'Wybierz dzień', _pickDay)],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _TimeRail(
                    day: _day,
                    at: _at,
                    latest: _latest,
                    events: events,
                    zoom: _zoom,
                    onPick: _pick,
                    onZoom: (z) => setState(() => _zoom = z),
                    onEvent: (e) {
                      _pick(e.at);
                      if (e.orderId != null) setState(() => _selectedOrder = e.orderId);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: data == null
                ? dayAsync.hasError
                      ? ErrorView(error: dayAsync.error!, onRetry: () => ref.invalidate(timeMachineDayProvider(query)))
                      : const LoadingView()
                : _Snapshot(
                    restaurantId: rid,
                    tm: data.at(_at),
                    events: [
                      for (final e in events.reversed)
                        if (!e.at.isAfter(_at)) e,
                    ],
                    tab: _tab,
                    onTab: (t) => setState(() => _tab = t),
                    zone: _zone,
                    onZone: (z) => setState(() => _zone = z),
                    selectedOrder: _selectedOrder,
                    selectedTable: _selectedTable,
                    onSelect: _selectOrder,
                    onEvent: (e) {
                      _pick(e.at);
                      if (e.orderId != null) setState(() => _selectedOrder = e.orderId);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// Oś czasu
// ---------------------------------------------------------------

/// Szerokość kolumny z osią czasu (mieści przełącznik dnia z kalendarzem).
const _railWidth = 240.0;

/// Kreska wybranej chwili: tyle punktów od góry osi.
const _playY = 52.0;

/// Podpisy godzin zaczynają się tyle od lewej krawędzi (równo z godziną na kresce), za nimi kreski minut i pas osi.
const _labelLeft = 18.0;
const _tickX = 60.0;
const _axisX = 74.0;
const _minZoom = 0.4;
const _maxZoom = 14.0;

/// Zdarzenia blisko siebie na osi (jedna ikona z liczbą).
class _Cluster {
  _Cluster(this.y, this.first);

  final double y;
  final ActivityEvent first;
  final events = <ActivityEvent>[];
}

/// Pionowa oś czasu jak w UniFi: stała kreska z godziną u góry, pod nią wcześniejsze chwile. Oś przesuwa się
/// przeciąganiem (z bezwładnością) i kółkiem myszy; Ctrl + kółko albo suwak zmienia skalę.
class _TimeRail extends StatefulWidget {
  const _TimeRail({
    required this.day,
    required this.at,
    required this.latest,
    required this.events,
    required this.zoom,
    required this.onPick,
    required this.onZoom,
    required this.onEvent,
  });

  final DateTime day;
  final DateTime at;

  /// Najpóźniejsza chwila do wybrania (teraz albo koniec dnia).
  final DateTime latest;
  final List<ActivityEvent> events;
  final double zoom;
  final ValueChanged<DateTime> onPick;
  final ValueChanged<double> onZoom;
  final ValueChanged<ActivityEvent> onEvent;

  @override
  State<_TimeRail> createState() => _TimeRailState();
}

class _TimeRailState extends State<_TimeRail> with SingleTickerProviderStateMixin {
  late final AnimationController _fling = AnimationController.unbounded(vsync: this)..addListener(_onFling);

  /// Ostatnia wysłana chwila: kilka ruchów myszy między klatkami sumuje się od niej, nie od starej [widget.at].
  DateTime? _sent;
  DateTime _flingFrom = DateTime(2000);

  DateTime get _current => _sent ?? widget.at;

  @override
  void didUpdateWidget(_TimeRail old) {
    super.didUpdateWidget(old);
    if (widget.at != _sent) _sent = null;
  }

  @override
  void dispose() {
    _fling.dispose();
    super.dispose();
  }

  void _emit(DateTime at) {
    var t = at.isBefore(widget.day) ? widget.day : at;
    if (t.isAfter(widget.latest)) t = widget.latest;
    if ((t == widget.day || t == widget.latest) && _fling.isAnimating) _fling.stop();
    _sent = t;
    widget.onPick(t);
  }

  /// Przesunięcie osi o [dy] punktów (w dół: późniejsza chwila pod kreską).
  DateTime _moved(DateTime from, double dy) => from.add(Duration(milliseconds: (dy / widget.zoom * 60000).round()));

  void _onFling() => _emit(_moved(_flingFrom, _fling.value));

  void _zoomBy(double factor) => widget.onZoom((widget.zoom * factor).clamp(_minZoom, _maxZoom));

  List<_Cluster> _clusters(double height) {
    final out = <_Cluster>[];
    final at = widget.at;
    for (final e in widget.events.reversed) {
      final y = _playY + at.difference(e.at).inMilliseconds / 60000 * widget.zoom;
      if (y < -20 || y > height + 20) continue;
      final last = out.lastOrNull;
      if (last != null && (y - last.y).abs() < 26) {
        last.events.add(e);
      } else {
        out.add(_Cluster(y, e)..events.add(e));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ring),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Skala: minus, suwak, plus.
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                _RailButton(icon: AppIcons.minus, tooltip: 'Dłuższy czas', onTap: () => _zoomBy(1 / 1.5)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: math.log(widget.zoom),
                      min: math.log(_minZoom),
                      max: math.log(_maxZoom),
                      onChanged: (v) => widget.onZoom(math.exp(v)),
                    ),
                  ),
                ),
                _RailButton(icon: AppIcons.plus, tooltip: 'Więcej szczegółów', onTap: () => _zoomBy(1.5)),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.ring),
          // Godzinę u góry i ikony przycina granica osi: nic nie wchodzi na przyciski skali.
          Expanded(
            child: ClipRect(
              child: LayoutBuilder(
                builder: (context, c) {
                  final h = c.maxHeight;
                  final clusters = _clusters(h);
                  return Listener(
                    onPointerSignal: (signal) {
                      if (signal is! PointerScrollEvent) return;
                      final dy = signal.scrollDelta.dy;
                      if (HardwareKeyboard.instance.isControlPressed) {
                        _zoomBy(math.exp(-dy / 400));
                      } else {
                        _fling.stop();
                        // Kółko w dół: wcześniejsze chwile (jak przewijanie listy w dół).
                        _emit(_moved(_current, -dy));
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragStart: (_) => _fling.stop(),
                      onVerticalDragUpdate: (d) => _emit(_moved(_current, d.delta.dy)),
                      onVerticalDragEnd: (d) {
                        final v = d.primaryVelocity ?? 0;
                        if (v.abs() < 120) return;
                        _flingFrom = _current;
                        _fling.value = 0;
                        _fling.animateWith(FrictionSimulation(0.12, 0, v));
                      },
                      onTapUp: (d) {
                        _fling.stop();
                        _emit(_moved(widget.at, _playY - d.localPosition.dy));
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Stack(
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _RailPainter(
                                  day: widget.day,
                                  at: widget.at,
                                  latest: widget.latest,
                                  zoom: widget.zoom,
                                  line: AppColors.ring,
                                  label: AppColors.textMuted,
                                  accent: AppColors.accent,
                                  shade: AppColors.surfaceRaised,
                                  textStyle: text.labelSmall ?? const TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                            for (final cl in clusters)
                              Positioned(
                                left: _axisX - 5,
                                top: cl.y - 12,
                                child: _EventMarker(
                                  cluster: cl,
                                  future: cl.first.at.isAfter(widget.at),
                                  onTap: () {
                                    _fling.stop();
                                    widget.onEvent(cl.first);
                                  },
                                ),
                              ),
                            // Wybrana chwila: kreska przez całą oś i godzina z sekundami.
                            Positioned(
                              left: _labelLeft - 10,
                              top: _playY - 13,
                              child: IgnorePointer(
                                child: Container(
                                  height: 26,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.accent,
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Text(
                                    _hms(widget.at),
                                    style: text.labelLarge?.copyWith(
                                      color: AppColors.onAccent,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: _tabular,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.tooltip, required this.onTap});

  final AppIconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    iconSize: 16,
    onPressed: onTap,
    icon: Glyph(icon, size: 16, color: AppColors.textMuted),
  );
}

/// Ikona zdarzenia (albo kilku bliskich zdarzeń z liczbą) przy osi. Podpowiedź: co się stało, kliknięcie: ta chwila.
class _EventMarker extends StatelessWidget {
  const _EventMarker({required this.cluster, required this.future, required this.onTap});

  final _Cluster cluster;

  /// Po wybranej chwili: przygaszone.
  final bool future;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = cluster.first;
    final count = cluster.events.length;
    final color = activityColor(e.group).withValues(alpha: future ? 0.4 : 1);
    final lines = [
      for (final x in cluster.events.take(6)) '${_hms(x.at)}  ${x.title}',
      if (count > 6) '… i jeszcze ${count - 6}',
    ];
    return Tooltip(
      message: lines.join('\n'),
      waitDuration: const Duration(milliseconds: 250),
      preferBelow: false,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            height: 24,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 24,
                  constraints: const BoxConstraints(minWidth: 24),
                  padding: EdgeInsets.symmetric(horizontal: count > 1 ? 6 : 0),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: future ? 0.06 : 0.14),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: color.withValues(alpha: future ? 0.2 : 0.45)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Glyph(activityIcon(e), size: 13, color: color),
                      if (count > 1) ...[
                        const SizedBox(width: 4),
                        Text(
                          '$count',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontFeatures: _tabular,
                          ),
                        ),
                      ],
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

class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.day,
    required this.at,
    required this.latest,
    required this.zoom,
    required this.line,
    required this.label,
    required this.accent,
    required this.shade,
    required this.textStyle,
  });

  final DateTime day;
  final DateTime at;
  final DateTime latest;
  final double zoom;
  final Color line;
  final Color label;
  final Color accent;
  final Color shade;
  final TextStyle textStyle;

  /// Podpisy godzin liczone raz (przy przeciąganiu te same napisy wracają co klatkę).
  static final _labels = <String, TextPainter>{};

  double _y(DateTime t) => _playY + at.difference(t).inMilliseconds / 60000 * zoom;

  TextPainter _label(String s) {
    final key = '$s|${label.toARGB32()}|${textStyle.fontSize}';
    return _labels.putIfAbsent(
      key,
      () => TextPainter(
        text: TextSpan(
          text: s,
          style: textStyle.copyWith(color: label, fontFeatures: _tabular),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    final dayEnd = _nextDay(day);
    final top = math.max(_y(latest), 0.0);
    final bottom = math.min(_y(day), h);

    // Po wybranej chwili (nad kreską) przygaszone; poza dniem i po teraz pusto.
    canvas.drawRect(Rect.fromLTRB(0, top, w, _playY), Paint()..color = shade.withValues(alpha: 0.5));

    // Pas osi: jaśniejszy nad kreską, mocniejszy pod nią (to, co już się wydarzyło).
    final axis = Paint()..color = accent.withValues(alpha: 0.12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(_axisX - 3, top, _axisX + 3, bottom), const Radius.circular(3)),
      axis,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(_axisX - 3, _playY, _axisX + 3, bottom), const Radius.circular(3)),
      Paint()..color = accent.withValues(alpha: 0.22),
    );

    // Kreski minut i podpisy godzin: gęstość według skali.
    const minors = [1, 2, 5, 10, 15, 30, 60, 120];
    const majors = [5, 10, 15, 30, 60, 120, 180, 240];
    final minor = minors.firstWhere((m) => m * zoom >= 7, orElse: () => 120);
    final major = majors.firstWhere((m) => m * zoom >= 46 && m % minor == 0, orElse: () => 240);
    final from = at.add(Duration(milliseconds: (-(h - _playY) / zoom * 60000).round()));
    final first = from.isBefore(day) ? day : from;
    var minute = (first.difference(day).inMinutes ~/ minor) * minor;
    final tick = Paint()
      ..color = line
      ..strokeWidth = 1;
    while (true) {
      final t = DateTime(day.year, day.month, day.day, 0, minute);
      if (t.isAfter(latest) || !t.isBefore(dayEnd)) break;
      final y = _y(t);
      if (y < -10) break;
      if (y <= h + 10) {
        final isMajor = minute % major == 0;
        canvas.drawLine(Offset(isMajor ? _tickX : _tickX + 4, y), Offset(_axisX - 6, y), tick);
        // Godzinę przy kresce wybranej chwili zakrywa pigułka z sekundami, więc jej nie rysujemy.
        if (isMajor && (y - _playY).abs() >= 20) {
          final tp = _label('${_two(t.hour)}:${_two(t.minute)}');
          tp.paint(canvas, Offset(_labelLeft, y - tp.height / 2));
        }
      }
      minute += minor;
    }

    // Kreska wybranej chwili przez całą szerokość.
    canvas.drawLine(
      const Offset(0, _playY),
      Offset(w, _playY),
      Paint()
        ..color = accent
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.at != at ||
      old.zoom != zoom ||
      old.day != day ||
      old.latest != latest ||
      old.line != line ||
      old.label != label;
}

// ---------------------------------------------------------------
// Stan w chwili: plan, legenda, tabela
// ---------------------------------------------------------------

class _Snapshot extends ConsumerWidget {
  const _Snapshot({
    required this.restaurantId,
    required this.tm,
    required this.events,
    required this.tab,
    required this.onTab,
    required this.zone,
    required this.onZone,
    required this.selectedOrder,
    required this.selectedTable,
    required this.onSelect,
    required this.onEvent,
  });

  final String restaurantId;
  final TimeMachine tm;

  /// Zdarzenia do wybranej chwili, najnowsze pierwsze.
  final List<ActivityEvent> events;
  final _ListTab tab;
  final ValueChanged<_ListTab> onTab;
  final String? zone;
  final ValueChanged<String> onZone;
  final String? selectedOrder;
  final String? selectedTable;
  final void Function(String? orderId, {String? tableId, String? zone}) onSelect;
  final ValueChanged<ActivityEvent> onEvent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zones = ref.watch(zonesProvider(restaurantId)).value ?? const <FloorZone>[];
    final tables = ref.watch(tablesProvider(restaurantId)).value ?? const <DiningTable>[];
    final elements = ref.watch(elementsProvider(restaurantId)).value ?? const <FloorElement>[];
    final current = zones.where((z) => z.name == zone).firstOrNull ?? zones.firstOrNull;

    void selectTable(DiningTable t) {
      final bill = t.id == null ? null : tm.billAt(t.id!);
      onSelect(bill?.orderId, tableId: t.id, zone: t.zone);
      onTab(_ListTab.tables);
    }

    return LayoutBuilder(
      builder: (context, c) {
        final planHeight = (c.maxHeight * 0.56).clamp(260.0, 680.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (current != null)
              SizedBox(
                height: planHeight,
                child: _PlanCard(
                  tm: tm,
                  zones: zones,
                  zone: current,
                  onZone: onZone,
                  tables: [
                    for (final t in tables)
                      if (t.zone == current.name) t,
                  ],
                  elements: [
                    for (final e in elements)
                      if (e.zone == current.name) e,
                  ],
                  selectedOrder: selectedOrder,
                  selectedTable: selectedTable,
                  onTapTable: selectTable,
                ),
              ),
            const SizedBox(height: 10),
            const _Legend(),
            const SizedBox(height: 12),
            Expanded(
              child: _ListCard(
                tm: tm,
                zones: zones,
                tables: tables,
                events: events,
                tab: tab,
                onTab: onTab,
                selectedOrder: selectedOrder,
                selectedTable: selectedTable,
                onSelect: onSelect,
                onEvent: onEvent,
              ),
            ),
          ],
        );
      },
    );
  }
}

TableLook _lookOf(DiningTable t, TimeMachine tm, {required bool selected}) {
  final bill = t.id == null ? null : tm.billAt(t.id!);
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
      strokeWidth: selected ? 3.5 : 2,
      caption: res.seated ? res.name : 'od ${_hm(res.startsAt)}',
      captionColor: AppColors.warning,
    );
  }
  return TableLook(
    fill: AppColors.surface,
    stroke: selected ? AppColors.accent : (t.active ? planLine : planLineMuted),
    strokeWidth: selected ? 3 : 1.5,
    dimmed: !t.active,
  );
}

/// Plan sali w wybranej chwili: rachunki (kwota), rezerwacje (od której albo goście przy stoliku).
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.tm,
    required this.zones,
    required this.zone,
    required this.onZone,
    required this.tables,
    required this.elements,
    required this.selectedOrder,
    required this.selectedTable,
    required this.onTapTable,
  });

  final TimeMachine tm;
  final List<FloorZone> zones;
  final FloorZone zone;
  final ValueChanged<String> onZone;
  final List<DiningTable> tables;
  final List<FloorElement> elements;
  final String? selectedOrder;
  final String? selectedTable;
  final ValueChanged<DiningTable> onTapTable;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final open = tm.bills.fold(0, (s, b) => s + b.total);
    final paid = tm.bills.fold(0, (s, b) => s + b.paid);
    final guests = tm.bills.fold(0, (s, b) => s + (b.guests ?? 0));
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ring),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            // Jedna strefa: niski wiersz z samym podsumowaniem, więcej miejsca na plan.
            height: zones.length > 1 ? 40 : 24,
            child: Row(
              children: [
                if (zones.length > 1)
                  SegmentedTabs<String>(
                    options: [for (final z in zones) (z.name, Fmt.capitalize(z.name))],
                    selected: zone.name,
                    onChanged: onZone,
                  ),
                const Spacer(),
                Text(
                  tm.bills.isEmpty
                      ? 'Sala pusta'
                      : [
                          '${tm.bills.length} ${tm.bills.length == 1 ? 'rachunek' : 'rachunki'}',
                          if (guests > 0) '$guests ${guests == 1 ? 'gość' : 'gości'}',
                          'na sali ${Fmt.price(open)}',
                          if (paid > 0) 'wpłacone ${Fmt.price(paid)}',
                        ].join(' · '),
                  style: text.labelLarge?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: FloorCanvas(
              zone: zone,
              tables: tables,
              elements: elements,
              showGrid: false,
              selectedId: null,
              lookOf: (t) {
                final bill = t.id == null ? null : tm.billAt(t.id!);
                final selected = bill != null ? bill.orderId == selectedOrder : t.id != null && t.id == selectedTable;
                return _lookOf(t, tm, selected: selected);
              },
              onTapTable: onTapTable,
            ),
          ),
        ],
      ),
    );
  }
}

/// Legenda pod planem, jak w UniFi: stan stolika i stan pozycji w pasku „Pozycje”.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted);
    Widget swatch(Color fill, Color stroke, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: stroke, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: style),
      ],
    );
    Widget bar(String status) {
      final (label, color) = _itemStatus(status);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 5,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 6),
          Text(Fmt.capitalize(label), style: style),
        ],
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 18,
      runSpacing: 6,
      children: [
        swatch(AppColors.accentTint, AppColors.accent, 'Rachunek'),
        swatch(AppColors.warning.withValues(alpha: 0.14), AppColors.warning, 'Rezerwacja'),
        swatch(AppColors.surface, planLine, 'Wolny'),
        swatch(AppColors.surface, planLineMuted, 'Wyłączony'),
        Container(width: 1, height: 14, color: AppColors.ring),
        for (final s in _itemStatuses) bar(s),
      ],
    );
  }
}

/// Kolumna tabeli: nazwa, udział w szerokości i wyrównanie do prawej (liczby).
typedef _Col = (String, int, bool);

/// Tabela pod planem: stoliki (jak porty w UniFi), na wynos, osoby na zmianie i zdarzenia.
class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.tm,
    required this.zones,
    required this.tables,
    required this.events,
    required this.tab,
    required this.onTab,
    required this.selectedOrder,
    required this.selectedTable,
    required this.onSelect,
    required this.onEvent,
  });

  final TimeMachine tm;
  final List<FloorZone> zones;
  final List<DiningTable> tables;
  final List<ActivityEvent> events;
  final _ListTab tab;
  final ValueChanged<_ListTab> onTab;
  final String? selectedOrder;
  final String? selectedTable;
  final void Function(String? orderId, {String? tableId, String? zone}) onSelect;
  final ValueChanged<ActivityEvent> onEvent;

  @override
  Widget build(BuildContext context) {
    final (cols, count, row) = switch (tab) {
      _ListTab.tables => _tablesTab(context),
      _ListTab.takeaway => _takeawayTab(context),
      _ListTab.staff => _staffTab(context),
      _ListTab.events => _eventsTab(context),
    };
    final text = Theme.of(context).textTheme;
    final head = text.labelMedium?.copyWith(color: AppColors.textMuted);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ring),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedTabs<_ListTab>(
                options: [
                  (_ListTab.tables, 'Stoliki (${tm.bills.length})'),
                  (_ListTab.takeaway, 'Na wynos (${tm.takeaway.length})'),
                  (_ListTab.staff, 'Na zmianie (${tm.staff.length})'),
                  (_ListTab.events, 'Zdarzenia (${events.length})'),
                ],
                selected: tab,
                onChanged: onTab,
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.ring),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                for (final (label, flex, end) in cols)
                  Expanded(
                    flex: flex,
                    child: Text(label, textAlign: end ? TextAlign.end : TextAlign.start, style: head),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.ring),
          Expanded(
            child: count == 0
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_emptyText, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: count,
                    separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.ring.withValues(alpha: 0.6)),
                    itemBuilder: row,
                  ),
          ),
        ],
      ),
    );
  }

  String get _emptyText => switch (tab) {
    _ListTab.tables => 'Lokal nie ma jeszcze stolików ani rachunków w tej chwili.',
    _ListTab.takeaway => 'O ${_hm(tm.at)} nie było zamówień na wynos w toku.',
    _ListTab.staff => 'O ${_hm(tm.at)} nikt nie był na zmianie.',
    _ListTab.events => 'Brak zdarzeń do tej chwili.',
  };

  static Widget _cells(List<_Col> cols, List<Widget> cells) => Row(
    children: [
      for (final (i, (_, flex, end)) in cols.indexed)
        Expanded(
          flex: flex,
          child: Align(alignment: end ? Alignment.centerRight : Alignment.centerLeft, child: cells[i]),
        ),
    ],
  );

  static Widget _row({required Widget child, required bool selected, VoidCallback? onTap}) => Material(
    color: selected ? AppColors.accentTint : Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.fromLTRB(16, 9, 16, 9), child: child),
    ),
  );

  (List<_Col>, int, IndexedWidgetBuilder) _tablesTab(BuildContext context) {
    const cols = <_Col>[
      ('Stolik', 3, false),
      ('Strefa', 2, false),
      ('Stan', 4, false),
      ('Od', 2, false),
      ('Goście', 2, false),
      ('Kelner', 3, false),
      ('Pozycje', 4, false),
      ('Kwota', 2, true),
      ('Wpłacone', 2, true),
    ];
    final zoneOrder = {for (final (i, z) in zones.indexed) z.name: i};
    final sorted = [...tables]
      ..sort((a, b) {
        final z = (zoneOrder[a.zone] ?? 999).compareTo(zoneOrder[b.zone] ?? 999);
        return z != 0 ? z : _compareLabels(a.label, b.label);
      });
    final known = {for (final t in sorted) ?t.id};
    // Rachunki bez stolika z planu (np. stolik usunięty) też są w tabeli.
    final loose = [
      for (final b in tm.bills)
        if (b.tableId == null || !known.contains(b.tableId)) b,
    ];
    final scale = math.max(
      1,
      tm.bills.fold(
        0,
        (m, b) => math.max(m, b.items.where((i) => i.status != 'cancelled').fold(0, (s, i) => s + i.quantity)),
      ),
    );
    final text = Theme.of(context).textTheme;
    final body = text.bodyMedium?.copyWith(fontFeatures: _tabular);
    final muted = body?.copyWith(color: AppColors.textMuted);

    Widget build(BuildContext context, int index) {
      final t = index < sorted.length ? sorted[index] : null;
      final bill = t != null ? (t.id == null ? null : tm.billAt(t.id!)) : loose[index - sorted.length];
      final res = t?.id == null || bill != null ? null : tm.reservationAt(t!.id!);
      final selected = bill != null ? bill.orderId == selectedOrder : t?.id != null && t?.id == selectedTable;
      final (state, color) = bill != null
          ? ('Rachunek', AppColors.accent)
          : res != null
          ? (res.seated ? 'Goście przy stoliku' : 'Rezerwacja ${_hm(res.startsAt)}', AppColors.warning)
          : t != null && !t.active
          ? ('Wyłączony', AppColors.textMuted)
          : ('Wolny', AppColors.textMuted);
      final name = t == null ? bill!.label : (t.isSeat ? 'Miejsce ${t.label}' : 'Stolik ${t.label}');
      final row = _cells(cols, [
        Row(
          children: [
            _TableBadge(label: t?.label ?? '?', color: bill != null || res != null ? color : null),
            const SizedBox(width: 10),
            Flexible(
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body),
            ),
          ],
        ),
        Text(t == null ? '—' : Fmt.capitalize(t.zone), maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                res != null && !res.seated ? '$state · ${res.name}' : state,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: body?.copyWith(color: bill != null || res != null ? color : AppColors.textMuted),
              ),
            ),
          ],
        ),
        Text(
          bill != null
              ? _hm(bill.openedAt)
              : res != null
              ? _hm(res.startsAt)
              : '—',
          style: bill != null || res != null ? body : muted,
        ),
        Text('${bill?.guests ?? res?.party ?? '—'}', style: bill != null || res != null ? body : muted),
        Text(
          bill?.openedBy ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: bill?.openedBy != null ? body : muted,
        ),
        bill == null ? Text('—', style: muted) : _ItemsBar(items: bill.items, scale: scale),
        Text(bill == null ? '—' : Fmt.price(bill.total), style: bill == null ? muted : body),
        Text(
          bill == null || bill.paid == 0 ? '—' : Fmt.price(bill.paid),
          style: bill == null || bill.paid == 0 ? muted : body,
        ),
      ]);
      return _row(
        selected: selected,
        onTap: () => onSelect(bill?.orderId, tableId: t?.id, zone: t?.zone),
        child: selected && bill != null && bill.items.isNotEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  row,
                  _BillItems(bill: bill),
                ],
              )
            : row,
      );
    }

    return (cols, sorted.length + loose.length, build);
  }

  (List<_Col>, int, IndexedWidgetBuilder) _takeawayTab(BuildContext context) {
    const cols = <_Col>[
      ('Zamówienie', 3, false),
      ('Rodzaj', 2, false),
      ('Klient', 4, false),
      ('Etap', 3, false),
      ('Złożone', 2, false),
      ('Kwota', 2, true),
    ];
    final text = Theme.of(context).textTheme;
    final body = text.bodyMedium?.copyWith(fontFeatures: _tabular);
    final muted = body?.copyWith(color: AppColors.textMuted);
    Widget build(BuildContext context, int i) {
      final o = tm.takeaway[i];
      final color = _stageColor(o.stage);
      return _row(
        selected: o.orderId == selectedOrder,
        onTap: () => onSelect(o.orderId),
        child: _cells(cols, [
          Text(o.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: body),
          Text(switch (o.kind) {
            'delivery' => 'Dostawa',
            'pickup' => 'Odbiór',
            _ => '—',
          }, style: muted),
          Text(
            o.customer ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: o.customer == null ? muted : body,
          ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(o.stageLabel, style: body?.copyWith(color: color)),
              ),
            ],
          ),
          Text(o.openedAt == null ? '—' : _hm(o.openedAt!), style: body),
          Text(Fmt.price(o.total), style: body),
        ]),
      );
    }

    return (cols, tm.takeaway.length, build);
  }

  (List<_Col>, int, IndexedWidgetBuilder) _staffTab(BuildContext context) {
    const cols = <_Col>[('Pracownik', 5, false), ('Od', 2, false), ('Na zmianie', 2, true)];
    final body = Theme.of(context).textTheme.bodyMedium?.copyWith(fontFeatures: _tabular);
    Widget build(BuildContext context, int i) {
      final (name, since) = tm.staff[i];
      final d = tm.at.difference(since);
      return _row(
        selected: false,
        child: _cells(cols, [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: body),
          Text(_hm(since), style: body),
          Text('${d.inHours}:${_two(d.inMinutes % 60)} h', style: body),
        ]),
      );
    }

    return (cols, tm.staff.length, build);
  }

  (List<_Col>, int, IndexedWidgetBuilder) _eventsTab(BuildContext context) {
    const cols = <_Col>[('Godzina', 2, false), ('Zdarzenie', 6, false), ('Szczegóły', 8, false)];
    final text = Theme.of(context).textTheme;
    final body = text.bodyMedium?.copyWith(fontFeatures: _tabular);
    final muted = body?.copyWith(color: AppColors.textMuted);
    Widget build(BuildContext context, int i) {
      final e = events[i];
      final color = activityColor(e.group);
      return _row(
        selected: e.orderId != null && e.orderId == selectedOrder,
        onTap: () => onEvent(e),
        child: _cells(cols, [
          Text(_hms(e.at), style: muted),
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)),
                child: Glyph(activityIcon(e), size: 13, color: color),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          Text(e.detail ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis, style: muted),
        ]),
      );
    }

    return (cols, events.length, build);
  }
}

/// Kwadracik z numerem stolika w kolorze stanu (jak port w UniFi).
class _TableBadge extends StatelessWidget {
  const _TableBadge({required this.label, required this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c == null ? AppColors.surfaceRaised : c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: c ?? AppColors.ring),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: c ?? AppColors.textMuted,
          fontWeight: FontWeight.w600,
          fontFeatures: _tabular,
        ),
      ),
    );
  }
}

/// Pasek pozycji rachunku jak „Activity” w UniFi: długość według liczby sztuk (najdłuższy rachunek = cały),
/// części w kolorach stanu: niewysłane, na kuchni, do wydania, wydane.
class _ItemsBar extends StatelessWidget {
  const _ItemsBar({required this.items, required this.scale});

  final List<TmItem> items;
  final int scale;

  @override
  Widget build(BuildContext context) {
    final counts = {for (final s in _itemStatuses) s: 0};
    for (final i in items) {
      if (counts.containsKey(i.status)) counts[i.status] = counts[i.status]! + i.quantity;
    }
    final total = counts.values.fold(0, (s, n) => s + n);
    final text = Theme.of(context).textTheme;
    if (total == 0) return Text('—', style: text.bodyMedium?.copyWith(color: AppColors.textMuted));
    return Tooltip(
      message: [
        for (final s in _itemStatuses)
          if (counts[s]! > 0) '${counts[s]} ${_itemStatus(s).$1}',
      ].join(' · '),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: c.maxWidth * (total / scale).clamp(0.12, 1.0),
                  height: 6,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final s in _itemStatuses)
                          if (counts[s]! > 0)
                            Expanded(
                              flex: counts[s]!,
                              child: ColoredBox(color: _itemStatus(s).$2),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text('$total', style: text.labelMedium?.copyWith(fontFeatures: _tabular)),
        ],
      ),
    );
  }
}

/// Pozycje wybranego rachunku pod jego wierszem, ze stanem z tamtej chwili.
class _BillItems extends StatelessWidget {
  const _BillItems({required this.bill});

  final TmBill bill;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 8, 0, 2),
      child: Wrap(
        spacing: 22,
        runSpacing: 4,
        children: [
          for (final i in bill.items)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${i.quantity}× ${[i.name, ?i.variant].join(' · ')}',
                    style: TextStyle(decoration: i.status == 'cancelled' ? TextDecoration.lineThrough : null),
                  ),
                  TextSpan(
                    text: '  ${_itemStatus(i.status).$1}',
                    style: text.labelSmall?.copyWith(color: _itemStatus(i.status).$2),
                  ),
                ],
              ),
              style: text.bodySmall,
            ),
        ],
      ),
    );
  }
}

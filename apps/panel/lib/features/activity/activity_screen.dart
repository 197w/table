import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../../shared/side_panel.dart';

const _tabular = [FontFeature.tabularFigures()];

String _two(int n) => n.toString().padLeft(2, '0');
String _hms(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}:${_two(t.toLocal().second)}';

DateTime _nextDay(DateTime day) => DateTime(day.year, day.month, day.day + 1);

Color activityColor(ActivityGroup g) => switch (g) {
  ActivityGroup.staff => TileColors.blue,
  ActivityGroup.bills => TileColors.green,
  ActivityGroup.kitchen => TileColors.amber,
  ActivityGroup.takeaway => TileColors.violet,
  ActivityGroup.reservations => AppColors.accent,
  ActivityGroup.stock => TileColors.rose,
};

/// Nazwa grupy zdarzeń w filtrach Logów.
String activityGroupLabel(ActivityGroup g) => switch (g) {
  ActivityGroup.staff => 'Zmiany pracowników',
  ActivityGroup.bills => 'Rachunki i płatności',
  ActivityGroup.kitchen => 'Kuchnia',
  ActivityGroup.takeaway => 'Na wynos i dostawy',
  ActivityGroup.reservations => 'Rezerwacje',
  ActivityGroup.stock => 'Magazyn',
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

/// Logi (pod „Ustawienia lokalu”, uprawnienie `activity`) w układzie jak Pracownicy: po lewej zwijany panel
/// z zakładką „Lista”, wyszukiwaniem, dniem, przełącznikiem „Time Machine” i filtrami (rodzaj zdarzenia, osoba)
/// z liczbami, po prawej tabela wszystkich zdarzeń dnia, najnowsze u góry.
/// Time Machine (4.11.2026, prośba użytkownika, wzór: film z UniFi) włącza się przełącznikiem i działa na liście:
/// zza panelu wysuwa się oś czasu, która przesuwa się pod stałą kreską wybranej chwili (przeciąganie
/// z bezwładnością, kółko myszy, Ctrl + kółko zmienia skalę, kliknięcie albo ikona zdarzenia przenosi do chwili),
/// a lista od razu pokazuje dzień w tej chwili: kreska z godziną między zdarzeniami, ostatnie przed nią
/// zaznaczone, późniejsze zamglone. Kliknięcie wiersza przenosi oś do chwili zdarzenia (przy wyłączonym Time
/// Machine najpierw go włącza). „Na żywo” trzyma chwilę na teraz (co sekundę), „Historia” ma dzień.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> with SingleTickerProviderStateMixin {
  bool _live = true;
  DateTime _day = dateOnly(DateTime.now());
  DateTime _at = DateTime.now();

  /// Skala osi: punkty na minutę.
  double _zoom = 3;
  String? _selectedOrder;
  Timer? _clock;

  /// Time Machine włączony: oś obok listy, lista w wybranej chwili.
  bool _machine = false;

  // Panel po lewej: wyszukiwanie, zaznaczone filtry (puste: wszystko), zwinięte grupy i zwinięcie panelu.
  final _search = TextEditingController();
  final _groups = <ActivityGroup>{};
  final _people = <String>{};
  final _closed = <String>{};
  bool _panelOpen = true;

  /// Płynne przewinięcie osi do klikniętego zdarzenia (zamiast przeskoku): od [_glideFrom] do [_glideTarget].
  late final _glide = AnimationController(vsync: this)..addListener(_onGlide);
  DateTime _glideFrom = DateTime(2000);
  DateTime _glideTarget = DateTime(2000);

  @override
  void initState() {
    super.initState();
    // Na żywo: chwila idzie z zegarem (tylko przy włączonym Time Machine, lista bez niego nie ma chwili).
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_machine || !_live || !mounted) return;
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
    _glide.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Zdarzenie pasuje do wyszukiwania (tytuł, szczegóły, osoba) i do zaznaczonych filtrów.
  bool _matches(ActivityEvent e, String query) {
    if (_groups.isNotEmpty && !_groups.contains(e.group)) return false;
    if (_people.isNotEmpty && !_people.contains(e.member ?? '')) return false;
    if (query.isEmpty) return true;
    return [e.title, ?e.detail, ?e.member, ?e.names].any((t) => t.toLowerCase().contains(query));
  }

  void _toggle<T>(Set<T> set, T value) => setState(() => set.contains(value) ? set.remove(value) : set.add(value));

  /// Grupy filtrów w panelu: rodzaj zdarzenia (kropka w kolorze z osi) i osoba, z liczbą zdarzeń dnia.
  List<Widget> _filterSections(List<ActivityEvent> all) {
    final people = <String, int>{};
    for (final e in all) {
      people.update(e.member ?? '', (n) => n + 1, ifAbsent: () => 1);
    }
    final names = people.keys.where((n) => n.isNotEmpty).toList()..sort();
    return [
      FilterSection(
        title: 'Rodzaj',
        first: true,
        open: !_closed.contains('group'),
        onToggle: () => _toggle(_closed, 'group'),
        options: [
          for (final g in ActivityGroup.values)
            (
              label: activityGroupLabel(g),
              count: all.where((e) => e.group == g).length,
              checked: _groups.contains(g),
              onChanged: (_) => _toggle(_groups, g),
              dot: activityColor(g),
            ),
        ],
      ),
      if (people.isNotEmpty)
        FilterSection(
          title: 'Osoba',
          open: !_closed.contains('people'),
          onToggle: () => _toggle(_closed, 'people'),
          options: [
            for (final n in names)
              (label: n, count: people[n]!, checked: _people.contains(n), onChanged: (_) => _toggle(_people, n), dot: null),
            // Zdarzenia bez osoby: z aplikacji gości, kuchnia, rezerwacje.
            if (people.containsKey(''))
              (
                label: 'Bez osoby',
                count: people['']!,
                checked: _people.contains(''),
                onChanged: (_) => _toggle(_people, ''),
                dot: null,
              ),
          ],
        ),
    ];
  }

  void _goLive() {
    _glide.stop();
    final now = DateTime.now();
    setState(() {
      _live = true;
      _day = dateOnly(now);
      _at = now;
    });
  }

  /// Włącza albo wyłącza Time Machine. Na żywo zaczyna od teraz, w innym dniu od ostatnio wybranej chwili.
  void _setMachine(bool on) {
    _glide.stop();
    setState(() {
      _machine = on;
      if (!on) return;
      if (_live) {
        final now = DateTime.now();
        _day = dateOnly(now);
        _at = now;
      } else {
        _at = _clamp(_at);
      }
    });
  }

  DateTime get _latest {
    final now = DateTime.now();
    final end = _nextDay(_day).subtract(const Duration(seconds: 1));
    return end.isAfter(now) ? now : end;
  }

  /// Chwila w obrębie wybranego dnia, nie później niż teraz.
  DateTime _clamp(DateTime at) {
    final t = at.isBefore(_day) ? _day : at;
    return t.isAfter(_latest) ? _latest : t;
  }

  void _pick(DateTime at) {
    // Przeciąganie osi przerywa przewijanie do zdarzenia.
    if (_glide.isAnimating) _glide.stop();
    final t = _clamp(at);
    if (t == _at && !_live) return;
    setState(() {
      _live = false;
      _at = t;
    });
  }

  /// Kliknięte zdarzenie (na osi albo na liście): oś przewija się do jego chwili, dłużej przy dalszej drodze.
  /// Przy „Ogranicz ruch” przeskakuje od razu.
  void _jump(DateTime at) {
    final t = _clamp(at);
    if (MediaQuery.disableAnimationsOf(context) || t == _at) {
      _pick(t);
      return;
    }
    final minutes = t.difference(_at).inSeconds.abs() / 60;
    _glideFrom = _at;
    _glideTarget = t;
    _glide.duration = Duration(milliseconds: (320 + minutes * 3).clamp(360, 800).round());
    setState(() => _live = false);
    _glide.forward(from: 0);
  }

  void _onGlide() {
    final k = Curves.easeInOutCubic.transform(_glide.value);
    // Co do mikrosekundy jak czasy z bazy: na końcu chwila to dokładnie czas zdarzenia, a nie tuż przed nim
    // (wtedy kliknięte zdarzenie byłoby „późniejsze” i zamglone).
    final from = _glideFrom.microsecondsSinceEpoch;
    final us = from + ((_glideTarget.microsecondsSinceEpoch - from) * k).round();
    setState(() => _at = DateTime.fromMicrosecondsSinceEpoch(us));
  }

  void _shiftDay(int days) {
    _glide.stop();
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

  /// Kliknięte zdarzenie (na osi albo na liście): oś jedzie do jego chwili, a jego rachunek się zaznacza.
  /// Przy wyłączonym Time Machine najpierw się on włącza, od razu w chwili zdarzenia (oś dopiero wyjeżdża).
  void _openEvent(ActivityEvent e) {
    if (e.orderId != null) setState(() => _selectedOrder = e.orderId);
    if (_machine) {
      _jump(e.at);
      return;
    }
    _glide.stop();
    setState(() {
      _machine = true;
      _live = false;
      _at = _clamp(e.at);
    });
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final today = dateOnly(DateTime.now());
    final query = (restaurantId: restaurant.id, day: _day);
    final eventsAsync = ref.watch(activityProvider(query));
    final all = eventsAsync.value ?? const <ActivityEvent>[];
    final search = _search.text.trim().toLowerCase();
    final events = [for (final e in all) if (_matches(e, search)) e];

    final panel = SidePanel(
      // Jedna zakładka (4.11.2026, prośba użytkownika: „Zdarzenia” to teraz „Lista”, bez zakładki Time Machine).
      header: SegmentedTabs<int>(
        options: const [(0, 'Lista')],
        icons: const [AppIcons.list],
        selected: 0,
        expand: true,
        onChanged: (_) {},
      ),
      search: _search,
      searchHint: 'Szukaj zdarzenia',
      onSearch: () => setState(() {}),
      actions: [
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
        _MachineSwitch(value: _machine, onChanged: _setMachine),
      ],
      children: _filterSections(all),
    );

    final content = eventsAsync.when(
      skipLoadingOnReload: true,
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(activityProvider(query))),
      data: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 32, 16),
        child: _EventTable(
          key: ValueKey(_day),
          events: events.reversed.toList(),
          at: _machine ? _at : null,
          empty: all.isEmpty
              ? 'Tego dnia nic się nie wydarzyło.'
              : 'Nic nie znaleziono. Zmień wyszukiwanie albo filtry po lewej.',
          selectedOrder: _selectedOrder,
          onOpen: _openEvent,
        ),
      ),
    );

    return SidePanelLayout(
      open: _panelOpen,
      onToggle: () => setState(() => _panelOpen = !_panelOpen),
      panel: panel,
      // Oś czasu wysuwa się zza panelu jak okno dodawania w Pracownikach.
      sheet: _machine
          ? Container(
              key: const ValueKey('time machine'),
              width: _railWidth,
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
              decoration: BoxDecoration(border: Border(right: BorderSide(color: AppColors.ring))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedTabs<bool>(
                    options: const [(true, 'Na żywo'), (false, 'Historia')],
                    selected: _live,
                    expand: true,
                    onChanged: (live) => live ? _goLive() : setState(() => _live = false),
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
                      onEvent: _openEvent,
                    ),
                  ),
                ],
              ),
            )
          : null,
      content: content,
    );
  }
}

/// Wiersz „Time Machine” z przełącznikiem w panelu po lewej (jak w UniFi). Cały wiersz przełącza.
class _MachineSwitch extends StatelessWidget {
  const _MachineSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Glyph(AppIcons.clockCounterClockwise, size: 16, color: value ? AppColors.accent : AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(child: Text('Time Machine', style: Theme.of(context).textTheme.bodyMedium)),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Oś czasu
// ---------------------------------------------------------------

/// Szerokość kolumny z osią czasu.
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
                                      color: AppColors.onAccentStrong,
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
    icon: Glyph(icon, size: 16),
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
// Lista zdarzeń
// ---------------------------------------------------------------

/// Stałe szerokości wąskich kolumn tabeli zdarzeń; zdarzenie i szczegóły dzielą resztę.
const _timeWidth = 92.0;
const _personWidth = 168.0;
const _amountWidth = 104.0;

/// Stała wysokość wiersza (z kreską pod nim) i kreski chwili: lista wie, gdzie jest kreska, i przewija się do niej.
const _rowExtent = 53.0;
const _markHeight = 30.0;

/// Wszystkie zdarzenia dnia jako tabela jak „People” w UniFi: godzina, zdarzenie z ikoną w kolorze rodzaju,
/// szczegóły, osoba i kwota. Z Time Machine ([at]) wybrana chwila to kreska z godziną między wierszami: zdarzenia
/// do niej mają zwykły wygląd, ostatnie przed nią jest zaznaczone, a późniejsze (nad kreską) są zamglone, jak
/// odłączone porty w UniFi. Gdy kreska przeskoczy zdarzenie i wyjdzie poza widok, lista sama do niej przewija
/// (na żywo nowe zdarzenia nie zabierają czytanego miejsca).
class _EventTable extends StatefulWidget {
  const _EventTable({
    super.key,
    required this.events,
    required this.at,
    required this.empty,
    required this.selectedOrder,
    required this.onOpen,
  });

  /// Od najnowszego.
  final List<ActivityEvent> events;

  /// Chwila z Time Machine albo null, gdy jest wyłączony.
  final DateTime? at;

  /// Napis, gdy nie ma czego pokazać.
  final String empty;
  final String? selectedOrder;
  final ValueChanged<ActivityEvent> onOpen;

  /// Ile zdarzeń jest po wybranej chwili (nad kreską).
  int get later {
    final t = at;
    return t == null ? 0 : events.where((e) => e.at.isAfter(t)).length;
  }

  @override
  State<_EventTable> createState() => _EventTableState();
}

class _EventTableState extends State<_EventTable> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.at != null) WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(animate: false));
  }

  @override
  void didUpdateWidget(_EventTable old) {
    super.didUpdateWidget(old);
    if (widget.at == null) return;
    // Włączony Time Machine albo kreska przeskoczyła zdarzenie.
    if (old.at == null || old.later != widget.later) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Kreska poza widokiem: lista przewija się tak, żeby stała w górnej jednej trzeciej.
  void _reveal({bool animate = true}) {
    if (!mounted || !_scroll.hasClients || widget.at == null) return;
    final p = _scroll.position;
    final top = widget.later * _rowExtent;
    final view = p.viewportDimension;
    if (top >= p.pixels && top + _markHeight + _rowExtent <= p.pixels + view) return;
    final target = (top - view / 3).clamp(0.0, p.maxScrollExtent);
    if (!animate || MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(target, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final events = widget.events;
    final at = widget.at;
    final later = widget.later;
    Widget row(ActivityEvent e, {required bool future, required bool current}) => Column(
      children: [
        Expanded(
          child: _EventRow(
            event: e,
            future: future,
            current: current,
            selected: e.orderId != null && e.orderId == widget.selectedOrder,
            onTap: () => widget.onOpen(e),
          ),
        ),
        Divider(height: 1, color: AppColors.ring),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                tableHead(context, 'Godzina', 0, width: _timeWidth),
                tableHead(context, 'Zdarzenie', 3),
                tableHead(context, 'Szczegóły', 3),
                tableHead(context, 'Osoba', 0, width: _personWidth),
                tableHead(context, 'Kwota', 0, align: TextAlign.right, width: _amountWidth),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.ring),
        Expanded(
          child: events.isEmpty
              ? Center(child: Text(widget.empty, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)))
              : CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverFixedExtentList(
                      itemExtent: _rowExtent,
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => row(events[i], future: true, current: false),
                        childCount: later,
                      ),
                    ),
                    if (at != null) SliverToBoxAdapter(child: _TimeMark(at: at)),
                    SliverFixedExtentList(
                      itemExtent: _rowExtent,
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => row(events[later + i], future: false, current: at != null && i == 0),
                        childCount: events.length - later,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Kreska wybranej chwili między zdarzeniami, z godziną w pigułce jak na osi (w kolumnie godzin).
class _TimeMark extends StatelessWidget {
  const _TimeMark({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final line = Container(height: 2, color: AppColors.accent);
    return SizedBox(
      height: _markHeight,
      child: Row(
        children: [
          SizedBox(width: 4, child: line),
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(11)),
            child: Text(
              _hms(at),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.onAccentStrong,
                fontWeight: FontWeight.w600,
                fontFeatures: _tabular,
              ),
            ),
          ),
          Expanded(child: line),
        ],
      ),
    );
  }
}

/// Wiersz zdarzenia. Po wybranej chwili zamglony (przezroczysty i lekko rozmyty), ostatni przed nią zaznaczony
/// kreską akcentu, wiersze klikniętego rachunku podświetlone.
class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.future,
    required this.current,
    required this.selected,
    required this.onTap,
  });

  final ActivityEvent event;
  final bool future;
  final bool current;

  /// Zdarzenie zaznaczonego rachunku.
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = event;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final detail = e.detail;
    // Kwota tylko przy rachunkach, płatnościach i zamówieniach (dostawa towaru ma liczbę składników).
    final amount = e.amount;
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: _timeWidth,
            child: Text(
              _hms(e.at),
              style: current ? muted?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600) : muted,
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                children: [
                  Glyph(activityIcon(e), size: 16, color: activityColor(e.group)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: detail ?? '',
                waitDuration: const Duration(milliseconds: 600),
                child: Text(detail ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
              ),
            ),
          ),
          SizedBox(
            width: _personWidth,
            child: Text(e.member ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
          ),
          SizedBox(
            width: _amountWidth,
            child: Text(
              amount == null ? '—' : Fmt.price(amount),
              textAlign: TextAlign.right,
              style: amount == null ? muted : text.bodyMedium?.copyWith(fontFeatures: _tabular),
            ),
          ),
        ],
      ),
    );
    if (future) {
      content = Opacity(
        opacity: 0.35,
        child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 0.8, sigmaY: 0.8), child: content),
      );
    }
    return Material(
      color: current
          ? AppColors.accentTint
          : selected
          ? AppColors.accentFill.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned.fill(child: content),
            if (current)
              Positioned(
                left: 0,
                top: 12,
                bottom: 12,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

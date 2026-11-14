import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/delivery_map.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../../shared/side_panel.dart';
import '../staff/staff_screen.dart' show staffColors;

const _tabular = [FontFeature.tabularFigures()];

/// Kolor kursu bez dostawcy (czeka w kolejce).
const _waitingColor = TileColors.amber;

/// Niebieski „w drodze”, czytelny w obu motywach.
Color get _info => AppColors.palette.brightness == Brightness.dark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);

/// Napis na wypełnieniu w danym kolorze: ciemny na jasnym, biały na ciemnym.
Color _on(Color fill) =>
    ThemeData.estimateBrightnessForColor(fill) == Brightness.dark ? Colors.white : const Color(0xFF09090B);

String _minutes(Duration d) => '${math.max(1, (d.inSeconds / 60).round())} min';

String _distance(double meters) =>
    meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

/// Etap kursu: słowo, ikona i kolor.
({String label, AppIconData icon, Color color}) _stage(MapCourse c, DateTime now) {
  if (c.onTheWay) return (label: 'W drodze', icon: AppIcons.moped, color: _info);
  if (c.orders.any((o) => o.waitingForKitchen(now))) {
    final at = c.orders.map((o) => o.scheduledFor).nonNulls.firstOrNull;
    return (label: at == null ? 'Na godzinę' : 'Na ${Fmt.time(at)}', icon: AppIcons.alarm, color: AppColors.textMuted);
  }
  if (c.ready) return (label: 'Gotowe do odbioru', icon: AppIcons.shoppingBag, color: AppColors.accent);
  return (label: 'W przygotowaniu', icon: AppIcons.cookingPot, color: AppColors.warning);
}

/// Trasa kursu policzona w Mapbox: od czego zależy (punkt startu i przystanki), kiedy policzona i skąd ruszał.
typedef _Route = ({String signature, DateTime at, LatLng start, List<String> stops, MapTrip trip});

/// Mapa dostawców (Dostawy → Mapa, 14.11.2026, prośba użytkownika: stary projekt „Mapa” na mapie Mapbox; na razie
/// w panelu na komputerze, potem telefony, CarPlay i Android Auto). Mapa Mapbox (styl ciemny albo jasny według
/// motywu), lokal, cele dostaw z numerem przystanku, kursy w kolorze dostawcy z najszybszą trasą (kolejność
/// przystanków dobiera Mapbox Optimization, z korkami), czas jazdy i przyjazd pod każdy adres, dostawcy z pozycją
/// z telefonu, gdy ją wysyła. Sama proponuje połączenie dostaw czekających w lokalu, gdy adresy są blisko siebie
/// („Połącz” = `panel_takeaway_merge`). Po lewej panel z zakładkami Kursy i Dostawcy. Dane z bazy co 15 sekund,
/// trasy co 5 minut albo po zmianie kursu.
class DeliveryMapScreen extends ConsumerStatefulWidget {
  const DeliveryMapScreen({super.key, this.tileProvider});

  /// Kafelki z innego źródła (testy bez sieci). Null: kafelki Mapbox z sieci.
  @visibleForTesting
  final TileProvider? tileProvider;

  @override
  ConsumerState<DeliveryMapScreen> createState() => _DeliveryMapScreenState();
}

class _DeliveryMapScreenState extends ConsumerState<DeliveryMapScreen> {
  final _map = MapController();
  Timer? _poll;
  bool _panelOpen = true;
  int _tab = 0;
  bool _mapReady = false;
  bool _fitted = false;
  DateTime _now = DateTime.now();

  /// Wybrany kurs (klucz kursu) albo dostawca (numer pracownika).
  String? _selected;

  // Wyniki z Mapbox, tylko w pamięci.
  final _targets = <String, LatLng>{};
  final _notFound = <String>{};
  final _geocodeFailedAt = <String, DateTime>{};
  final _routes = <String, _Route>{};
  ({String signature, DateTime at, List<String?> keys, List<List<double?>> durations})? _matrix;
  final _dismissed = <String>{};
  bool _working = false;
  bool _again = false;
  bool _merging = false;
  bool _offline = false;

  String? get _restaurantId => ref.read(currentRestaurantProvider)?.id;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      final id = _restaurantId;
      if (id == null || !mounted) return;
      ref.invalidate(deliveryMapProvider(id));
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _map.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // Mapbox: adresy, trasy kursów, czasy między adresami
  // ---------------------------------------------------------------

  /// Nowe dane z bazy: brakujące adresy, trasy zmienionych kursów i czasy do propozycji. Jedno liczenie naraz;
  /// dane, które przyjdą w trakcie, liczą się zaraz po nim.
  Future<void> _update(DeliveryMap map) async {
    final mapbox = ref.read(mapboxProvider);
    if (!mapbox.configured) return;
    if (_working) {
      _again = true;
      return;
    }
    _working = true;
    try {
      await _geocode(map, mapbox);
      await _trips(map, mapbox);
      await _durations(map, mapbox);
      if (mounted) setState(() => _offline = false);
    } on Object {
      if (mounted) setState(() => _offline = true);
    } finally {
      _working = false;
    }
    final id = _restaurantId;
    if (_again && mounted && id != null) {
      _again = false;
      final next = ref.read(deliveryMapProvider(id)).value;
      if (next != null) unawaited(_update(next));
    }
  }

  Future<void> _geocode(DeliveryMap map, MapboxClient mapbox) async {
    final now = DateTime.now();
    for (final o in map.orders) {
      if (_targets.containsKey(o.id) || _notFound.contains(o.id)) continue;
      final failed = _geocodeFailedAt[o.id];
      if (failed != null && now.difference(failed) < const Duration(minutes: 2)) continue;
      try {
        final point = await mapbox.geocode(o.address ?? '', near: map.restaurant, city: map.restaurantCity);
        if (!mounted) return;
        setState(() {
          if (point == null) {
            _notFound.add(o.id);
          } else {
            _targets[o.id] = point;
          }
        });
      } on Object {
        _geocodeFailedAt[o.id] = now;
        rethrow;
      }
    }
    if (!_fitted && _mapReady) {
      _fitted = true;
      _fitAll(map);
    }
  }

  /// Start kursu: dostawca w drodze ze świeżą pozycją z telefonu, inaczej lokal.
  LatLng? _startOf(DeliveryMap map, MapCourse c) {
    final courier = map.courier(c.courierId);
    if (c.onTheWay && courier?.position != null) return courier!.position;
    return map.restaurant;
  }

  Future<void> _trips(DeliveryMap map, MapboxClient mapbox) async {
    final now = DateTime.now();
    final live = <String>{};
    for (final c in map.courses) {
      live.add(c.key);
      final start = _startOf(map, c);
      final stops = [
        for (final o in c.orders)
          if (_targets[o.id] != null) o.id,
      ];
      if (start == null || stops.isEmpty) {
        _routes.remove(c.key);
        continue;
      }
      final signature = [
        start.latitude.toStringAsFixed(3),
        start.longitude.toStringAsFixed(3),
        ...stops,
      ].join('|');
      final old = _routes[c.key];
      if (old != null && old.signature == signature && now.difference(old.at) < const Duration(minutes: 5)) continue;
      final trip = await mapbox.trip(start, [for (final id in stops) _targets[id]!]);
      if (!mounted) return;
      if (trip == null) continue;
      setState(() => _routes[c.key] = (signature: signature, at: now, start: start, stops: stops, trip: trip));
    }
    _routes.removeWhere((key, _) => !live.contains(key));
  }

  /// Czasy jazdy między lokalem a adresami kursów czekających w lokalu (do propozycji kursów).
  Future<void> _durations(DeliveryMap map, MapboxClient mapbox) async {
    final restaurant = map.restaurant;
    if (restaurant == null) return;
    final ids = [
      for (final c in map.courses)
        if (c.atRestaurant)
          for (final o in c.orders)
            if (_targets[o.id] != null) o.id,
    ]..sort();
    if (ids.length < 2) {
      if (_matrix != null && mounted) setState(() => _matrix = null);
      return;
    }
    final keys = <String?>[null, ...ids.take(24)];
    final signature = keys.join('|');
    final now = DateTime.now();
    final old = _matrix;
    if (old != null && old.signature == signature && now.difference(old.at) < const Duration(minutes: 10)) return;
    final durations = await mapbox.matrix([restaurant, for (final id in keys.skip(1)) _targets[id!]!]);
    if (!mounted || durations == null) return;
    setState(() => _matrix = (signature: signature, at: now, keys: keys, durations: durations));
  }

  double? _seconds(String? from, String? to) {
    final m = _matrix;
    if (m == null) return null;
    final i = m.keys.indexOf(from);
    final j = m.keys.indexOf(to);
    if (i < 0 || j < 0 || i >= m.durations.length || j >= m.durations[i].length) return null;
    return m.durations[i][j];
  }

  // ---------------------------------------------------------------
  // Widok
  // ---------------------------------------------------------------

  List<LatLng> _points(DeliveryMap map, [MapCourse? course]) => [
    ?map.restaurant,
    if (course == null)
      for (final c in map.couriers)
        if (c.position != null) c.position!,
    for (final o in course?.orders ?? map.orders)
      if (_targets[o.id] != null) _targets[o.id]!,
    if (course != null) ...?_routes[course.key]?.trip.geometry,
  ];

  void _fit(List<LatLng> points) {
    if (points.isEmpty || !_mapReady) return;
    if (points.length == 1) {
      _map.move(points.first, 15);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.fromLTRB(70, 90, 70, 60),
        maxZoom: 16,
      ),
    );
  }

  void _fitAll(DeliveryMap map) => _fit(_points(map));

  void _selectCourse(DeliveryMap map, MapCourse c) {
    final same = _selected == c.key;
    setState(() => _selected = same ? null : c.key);
    _fit(same ? _points(map) : _points(map, c));
  }

  void _selectCourier(MapCourier c) {
    setState(() => _selected = _selected == c.memberId ? null : c.memberId);
    if (c.position != null && _mapReady) _map.move(c.position!, math.max(_map.camera.zoom, 15));
  }

  void _zoom(double by) {
    if (!_mapReady) return;
    _map.move(_map.camera.center, (_map.camera.zoom + by).clamp(5, 19).toDouble());
  }

  Future<void> _merge(String restaurantId, CourseSuggestion s) async {
    if (_merging) return;
    setState(() => _merging = true);
    try {
      await ref
          .read(repositoryProvider)
          .mergeCourse(s.orderIds, memberId: ref.read(panelMemberProvider)?.dbMemberId);
      ref
        ..invalidate(deliveryMapProvider(restaurantId))
        ..invalidate(takeawayOrdersProvider(restaurantId));
      if (mounted) showMessage(context, 'Połączone w jeden kurs: ${s.orderIds.length} dostawy.', tone: ToastTone.success);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _merging = false);
    }
  }

  Color _courseColor(DeliveryMap map, MapCourse c) {
    final courier = map.courier(c.courierId);
    return courier == null ? _waitingColor : staffColors[courier.color % staffColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    if (!restaurant.isPro) return const ProGate(feature: 'Mapa dostawców');
    final async = ref.watch(deliveryMapProvider(restaurant.id));
    ref.listen(deliveryMapProvider(restaurant.id), (_, next) {
      if (next.value case final map?) unawaited(_update(map));
    });
    final map = async.value;
    final mapbox = ref.watch(mapboxProvider);
    final suggestions = map == null
        ? const <CourseSuggestion>[]
        : suggestCourses(courses: map.courses, seconds: _seconds, now: _now, dismissed: _dismissed);

    final panel = SidePanel(
      header: SegmentedTabs<int>(
        options: const [(0, 'Kursy'), (1, 'Dostawcy')],
        selected: _tab,
        expand: true,
        onChanged: (t) => setState(() => _tab = t),
      ),
      children: map == null
          ? const []
          : _tab == 0
          ? [
              if (suggestions.isNotEmpty) ...[
                const _PanelHeading('Propozycje kursów'),
                for (final s in suggestions)
                  _SuggestionCard(
                    suggestion: s,
                    busy: _merging,
                    onMerge: () => _merge(restaurant.id, s),
                    onDismiss: () => setState(() => _dismissed.add(s.key)),
                  ),
                const SizedBox(height: 8),
              ],
              _PanelHeading('Kursy · ${map.courses.length}'),
              if (map.courses.isEmpty) const _PanelNote('Żadna dostawa nie jest teraz w toku.'),
              for (final c in map.courses)
                _CourseCard(
                  course: c,
                  courier: map.courier(c.courierId),
                  color: _courseColor(map, c),
                  route: _routes[c.key],
                  targets: _targets,
                  notFound: _notFound,
                  courierLive: c.onTheWay && map.courier(c.courierId)?.position != null,
                  now: _now,
                  selected: _selected == c.key,
                  onTap: () => _selectCourse(map, c),
                ),
            ]
          : [
              _PanelHeading('Na zmianie · ${map.couriers.length}'),
              if (map.couriers.isEmpty) const _PanelNote('Nikt z dostawców nie jest teraz na zmianie.'),
              for (final c in map.couriers)
                _CourierRow(
                  courier: c,
                  courses: map.courses.where((x) => x.courierId == c.memberId).length,
                  now: _now,
                  selected: _selected == c.memberId,
                  onTap: () => _selectCourier(c),
                ),
            ],
    );

    return SidePanelLayout(
      open: _panelOpen,
      onToggle: () => setState(() => _panelOpen = !_panelOpen),
      panel: panel,
      content: async.when(
        skipLoadingOnReload: true,
        skipError: true,
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(deliveryMapProvider(restaurant.id))),
        data: (map) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 32, 32),
          child: _mapCard(map, mapbox, suggestions),
        ),
      ),
    );
  }

  Widget _mapCard(DeliveryMap map, MapboxClient mapbox, List<CourseSuggestion> suggestions) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final courses = map.courses;
    final selectedCourse = courses.where((c) => c.key == _selected).firstOrNull;
    final dim = selectedCourse != null;
    final stopNumber = <String, int>{
      for (final c in courses)
        if (_routes[c.key] case final r? when r.stops.length > 1)
          for (final (n, i) in r.trip.order.indexed) r.stops[i]: n + 1,
    };
    final onTheWay = courses.where((c) => c.onTheWay).length;
    final waiting = courses.where((c) => c.courierId == null).length;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.ring),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: map.restaurant ?? const LatLng(52.23, 21.01),
                initialZoom: 13,
                minZoom: 5,
                maxZoom: 19,
                backgroundColor: dark ? const Color(0xFF1B1C1F) : const Color(0xFFEDEDE9),
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onMapReady: () {
                  _mapReady = true;
                  if (!_fitted) {
                    _fitted = true;
                    _fitAll(map);
                  }
                  unawaited(_update(map));
                },
                onTap: (_, _) => setState(() => _selected = null),
              ),
              children: [
                if (mapbox.configured)
                  TileLayer(
                    key: ValueKey(dark),
                    urlTemplate: mapbox.tileUrl(dark ? Env.mapboxStyleDark : Env.mapboxStyleLight),
                    tileDimension: 512,
                    zoomOffset: -1,
                    maxNativeZoom: 22,
                    retinaMode: RetinaMode.isHighDensity(context),
                    userAgentPackageName: 'pl.table.panel',
                    tileProvider: widget.tileProvider,
                  ),
                PolylineLayer(
                  polylines: [
                    for (final c in courses)
                      if (_routes[c.key] case final r? when r.trip.geometry.length > 1)
                        Polyline(
                          points: r.trip.geometry,
                          strokeWidth: _selected == c.key ? 7 : 5,
                          color: _courseColor(map, c).withValues(alpha: dim && _selected != c.key ? 0.3 : 1),
                          borderStrokeWidth: 2,
                          borderColor: AppColors.background.withValues(alpha: dim && _selected != c.key ? 0.3 : 1),
                        ),
                    // Propozycje kursów: przerywana kreska między najbliższymi adresami.
                    for (final s in suggestions)
                      if (_closestPair(s) case final pair?)
                        Polyline(
                          points: pair,
                          strokeWidth: 3,
                          color: AppColors.warning,
                          pattern: StrokePattern.dashed(segments: const [10, 8]),
                        ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (map.restaurant != null)
                      Marker(
                        point: map.restaurant!,
                        width: 40,
                        height: 40,
                        child: Tooltip(message: map.restaurantName, child: const _RestaurantPin()),
                      ),
                    for (final c in courses)
                      for (final o in c.orders)
                        if (_targets[o.id] case final point?)
                          Marker(
                            point: point,
                            width: 110,
                            height: 48,
                            alignment: Alignment.topCenter,
                            child: Opacity(
                              opacity: dim && _selected != c.key ? 0.45 : 1,
                              child: _DestinationPin(
                                order: o,
                                stop: stopNumber[o.id],
                                color: _courseColor(map, c),
                                selected: _selected == c.key,
                                onTap: () => _selectCourse(map, c),
                              ),
                            ),
                          ),
                    for (final c in map.couriers)
                      if (c.position != null)
                        Marker(
                          point: c.position!,
                          width: 44,
                          height: 44,
                          child: _CourierPin(
                            courier: c,
                            selected: _selected == c.memberId,
                            onTap: () => _selectCourier(c),
                          ),
                        ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 70,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MapChip(label: 'Na zmianie: ${map.couriers.length}', icon: AppIcons.users, color: AppColors.text),
                  _MapChip(label: 'W drodze: $onTheWay', icon: AppIcons.moped, color: _info),
                  if (waiting > 0)
                    _MapChip(label: 'Czekają na dostawcę: $waiting', icon: AppIcons.hourglass, color: AppColors.warning),
                  if (_notFound.isNotEmpty)
                    _MapChip(
                      label: 'Bez adresu na mapie: ${_notFound.where((id) => map.orders.any((o) => o.id == id)).length}',
                      icon: AppIcons.mapPin,
                      color: AppColors.warning,
                    ),
                  if (_offline)
                    _MapChip(label: 'Mapbox nie odpowiada', icon: AppIcons.warning, color: AppColors.error),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                children: [
                  _MapButton(icon: AppIcons.cornersOut, tooltip: 'Pokaż wszystko', onTap: () => _fitAll(map)),
                  const SizedBox(height: 6),
                  _MapButton(icon: AppIcons.plus, tooltip: 'Przybliż', onTap: () => _zoom(1)),
                  const SizedBox(height: 6),
                  _MapButton(icon: AppIcons.minus, tooltip: 'Oddal', onTap: () => _zoom(-1)),
                ],
              ),
            ),
            if (!mapbox.configured) const Center(child: _NoKey()),
            if (mapbox.configured) const Positioned(right: 8, bottom: 8, child: _Attribution()),
          ],
        ),
      ),
    );
  }

  /// Najbliższe sobie adresy dwóch kursów z propozycji (do przerywanej kreski).
  List<LatLng>? _closestPair(CourseSuggestion s) {
    List<LatLng>? best;
    double? bestSeconds;
    for (final x in s.courses.first.orders) {
      for (final y in s.courses.last.orders) {
        final a = _targets[x.id];
        final b = _targets[y.id];
        if (a == null || b == null) continue;
        final t = _seconds(x.id, y.id) ?? double.infinity;
        if (bestSeconds == null || t < bestSeconds) {
          bestSeconds = t;
          best = [a, b];
        }
      }
    }
    return best;
  }
}

// ---------------------------------------------------------------
// Panel po lewej
// ---------------------------------------------------------------

class _PanelHeading extends StatelessWidget {
  const _PanelHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontFeatures: _tabular),
        ),
      ),
    );
  }
}

class _PanelNote extends StatelessWidget {
  const _PanelNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted)),
    );
  }
}

/// Propozycja: połączyć dwa kursy czekające w lokalu, bo adresy są blisko.
class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion, required this.busy, required this.onMerge, required this.onDismiss});

  final CourseSuggestion suggestion;
  final bool busy;
  final VoidCallback onMerge;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final numbers = [
      for (final c in suggestion.courses)
        for (final o in c.orders) '#${o.number}',
    ];
    final extra = suggestion.extraSeconds;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Glyph(AppIcons.arrowsMerge, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Jeden kurs: ${numbers.join(' i ')}',
                  style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              'Adresy ok. ${_minutes(Duration(seconds: suggestion.gapSeconds.round()))} jazdy od siebie',
              if (extra != null)
                extra < 60
                    ? 'nikt nie czeka dłużej'
                    : 'ostatni klient ok. +${_minutes(Duration(seconds: extra.round()))}',
            ].join(' · '),
            style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onMerge,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(34)),
                  child: const Text('Połącz'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onDismiss, child: const Text('Pomiń')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kurs na liście: dostawca (albo „Czeka na dostawcę”), etap, cała trasa i przystanki po kolei z czasem.
class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.courier,
    required this.color,
    required this.route,
    required this.targets,
    required this.notFound,
    required this.courierLive,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  final MapCourse course;
  final MapCourier? courier;
  final Color color;
  final _Route? route;
  final Map<String, LatLng> targets;
  final Set<String> notFound;

  /// Dostawca w drodze z pozycją z telefonu: trasa liczy się od niego i teraz.
  final bool courierLive;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stage = _stage(course, now);
    final r = route;
    // Przystanki w kolejności trasy, a bez trasy w kolejności z bazy.
    final ordered = r == null
        ? course.orders
        : [
            for (final i in r.trip.order) course.orders.firstWhere((o) => o.id == r.stops[i]),
            for (final o in course.orders)
              if (!r.stops.contains(o.id)) o,
          ];
    final times = r?.trip.cumulative();
    // Kurs w drodze: przyjazd o godzinie (od pozycji dostawcy albo od odbioru w lokalu); w lokalu: sam czas jazdy.
    final base = course.onTheWay ? (courierLive ? r?.at : (course.pickedUpAt ?? r?.at)) : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.surfaceRaised : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? color : AppColors.ring, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Avatar(courier: courier, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            courier?.name ?? 'Czeka na dostawcę',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall,
                          ),
                          Row(
                            children: [
                              Glyph(stage.icon, size: 13, color: stage.color),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  stage.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall?.copyWith(color: stage.color),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Cała trasa kursu: czas jazdy i długość.
                    if (r != null) ...[
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _minutes(Duration(seconds: r.trip.seconds.round())),
                            style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                          ),
                          Text(
                            _distance(r.trip.meters),
                            style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                for (final (n, o) in ordered.indexed)
                  _StopLine(
                    order: o,
                    number: ordered.length > 1 ? n + 1 : null,
                    color: color,
                    drive: times != null && r != null && n < r.trip.order.length ? times[n] : null,
                    base: base,
                    missing: notFound.contains(o.id),
                    locating: !targets.containsKey(o.id) && !notFound.contains(o.id),
                    now: now,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Przystanek kursu: numer w kolejności, numer zamówienia z adresem i dojazd.
class _StopLine extends StatelessWidget {
  const _StopLine({
    required this.order,
    required this.number,
    required this.color,
    required this.drive,
    required this.base,
    required this.missing,
    required this.locating,
    required this.now,
  });

  final MapOrder order;
  final int? number;
  final Color color;

  /// Jazda od startu kursu do tego adresu (z postojami pod wcześniejszymi).
  final Duration? drive;

  /// Chwila startu kursu w drodze; null: kurs jeszcze w lokalu.
  final DateTime? base;
  final bool missing;
  final bool locating;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final promised = order.promisedAt;
    String detail;
    Color tone = AppColors.textMuted;
    if (missing) {
      detail = 'Nie znaleziono adresu na mapie';
      tone = AppColors.warning;
    } else if (drive == null) {
      detail = locating ? 'Szukam adresu…' : (promised == null ? '—' : 'Na ${Fmt.time(promised)}');
    } else if (base != null) {
      final arrival = base!.add(drive!);
      detail = arrival.isBefore(now) ? 'Lada chwila' : 'Będzie ok. ${Fmt.time(arrival)}';
      if (promised != null && arrival.isAfter(promised.add(const Duration(minutes: 1)))) {
        detail += ' · spóźni się ok. ${_minutes(arrival.difference(promised))}';
        tone = AppColors.error;
      } else {
        tone = _info;
      }
    } else {
      detail = 'Jazda ok. ${_minutes(drive!)}';
      if (promised != null) {
        detail += ' · na ${Fmt.time(promised)}';
        if (now.add(drive!).isAfter(promised)) tone = AppColors.warning;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: number == null
                ? Glyph(AppIcons.mapPin, size: 11, color: _on(color))
                : Text(
                    '$number',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _on(color),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${order.number} · ${order.address ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                ),
                Text(detail, style: text.bodySmall?.copyWith(color: tone, fontFeatures: _tabular)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.courier, required this.color});

  final MapCourier? courier;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: courier == null
          ? Glyph(AppIcons.hourglass, size: 16, color: _on(color))
          : Text(
              courier!.initials,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _on(color),
              ),
            ),
    );
  }
}

/// Dostawca na zmianie: stan, auto na dziś i pozycja z telefonu.
class _CourierRow extends StatelessWidget {
  const _CourierRow({
    required this.courier,
    required this.courses,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  final MapCourier courier;
  final int courses;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = courier;
    final color = staffColors[c.color % staffColors.length];
    final status = !c.ready
        ? (label: 'Bez kontroli auta', icon: AppIcons.warning, color: AppColors.warning)
        : c.busy
        ? (label: courses > 1 ? 'Kursy: $courses' : 'W kursie', icon: AppIcons.moped, color: _info)
        : (label: 'Wolny', icon: AppIcons.checkCircle, color: AppColors.accent);
    final updated = c.updatedAt;
    final where = c.position == null || updated == null
        ? 'Brak pozycji z telefonu'
        : now.difference(updated).inSeconds < 45
        ? 'Pozycja przed chwilą'
        : 'Pozycja ${now.difference(updated).inMinutes} min temu';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.surfaceRaised : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: selected ? AppColors.ringStrong : AppColors.ring),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _Avatar(courier: c, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                      Text(
                        [?c.vehicleName, where].join(' · '),
                        maxLines: 2,
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                      ),
                      const SizedBox(height: 6),
                      StatusChip(label: status.label, icon: status.icon, color: status.color),
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

// ---------------------------------------------------------------
// Na mapie
// ---------------------------------------------------------------

class _MapChip extends StatelessWidget {
  const _MapChip({required this.label, required this.icon, required this.color});

  final String label;
  final AppIconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ring),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.text, fontFeatures: _tabular),
          ),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.tooltip, required this.onTap});

  final AppIconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.ring),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(child: Glyph(icon, size: 18, color: AppColors.text)),
          ),
        ),
      ),
    );
  }
}

/// Bez klucza Mapbox: mapa bez kafelków i informacja, jak go dodać.
class _NoKey extends StatelessWidget {
  const _NoKey();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: 420,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ring),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Glyph(AppIcons.mapTrifold, size: 20, color: AppColors.warning),
              const SizedBox(width: 10),
              Text('Mapa potrzebuje klucza Mapbox', style: text.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Dodaj publiczny klucz „pk.…” z konta Mapbox jako MAPBOX_TOKEN w env.json (a do wydania panelu jako '
            'sekret repozytorium) i uruchom panel ponownie. Do tego czasu lista kursów działa bez mapy i tras.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Oznaczenie danych mapy wymagane przez Mapbox.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 11, color: AppColors.textMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('mapbox', style: style.copyWith(fontWeight: FontWeight.w600, color: AppColors.text)),
          Text('  © Mapbox © OpenStreetMap', style: style),
        ],
      ),
    );
  }
}

class _RestaurantPin extends StatelessWidget {
  const _RestaurantPin();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: Glyph(AppIcons.storefront.duotone, size: 20, color: AppColors.accent),
    );
  }
}

/// Cel dostawy: numer przystanku i numer zamówienia w kolorze kursu, z kreską do punktu na mapie.
class _DestinationPin extends StatelessWidget {
  const _DestinationPin({
    required this.order,
    required this.stop,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final MapOrder order;
  final int? stop;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = _on(color);
    final style = TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: fg,
      fontFeatures: _tabular,
    );
    return Tooltip(
      message: [order.address ?? '', ?order.customerName].join(' · '),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 3, 8, 3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: selected ? AppColors.text : Colors.transparent, width: 2),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (stop != null) ...[
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: fg.withValues(alpha: 0.18), shape: BoxShape.circle),
                      child: Text('$stop', style: style.copyWith(fontSize: 11)),
                    ),
                    const SizedBox(width: 4),
                  ] else ...[
                    Glyph(AppIcons.mapPin, size: 13, color: fg),
                    const SizedBox(width: 3),
                  ],
                  Text('#${order.number}', style: style),
                ],
              ),
            ),
            Container(width: 2, height: 9, color: color),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.background, width: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dostawca z pozycją z telefonu: kółko z inicjałami w jego kolorze.
class _CourierPin extends StatelessWidget {
  const _CourierPin({required this.courier, required this.selected, required this.onTap});

  final MapCourier courier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = staffColors[courier.color % staffColors.length];
    return Tooltip(
      message: courier.name,
      child: GestureDetector(
        onTap: onTap,
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: selected ? AppColors.text : Colors.white, width: selected ? 3 : 2),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Text(
              courier.initials,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _on(color),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

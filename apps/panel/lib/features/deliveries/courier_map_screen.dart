import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/courier_map.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';
import '../staff/staff_screen.dart' show staffColors;

const _tabular = [FontFeature.tabularFigures()];

/// Niebieski „w drodze”, czytelny w obu motywach (kontrast tekstu co najmniej 4,5:1).
Color get _info => AppColors.palette.brightness == Brightness.dark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);

/// Napis na wypełnieniu w danym kolorze: ciemny na jasnym, biały na ciemnym.
Color _on(Color fill) =>
    ThemeData.estimateBrightnessForColor(fill) == Brightness.dark ? Colors.white : const Color(0xFF09090B);

/// Etap dostawy: słowo, ikona i kolor (nie sam kolor).
({String label, AppIconData icon, Color color}) _stage(MapOrder o) => switch (o.stage) {
  'on_the_way' => (label: 'W drodze', icon: AppIcons.moped, color: _info),
  'ready' => (label: 'Gotowe do odbioru', icon: AppIcons.shoppingBag, color: AppColors.accent),
  _ when o.kitchenAt != null => (label: 'Na godzinę', icon: AppIcons.alarm, color: AppColors.textMuted),
  _ => (label: 'W przygotowaniu', icon: AppIcons.cookingPot, color: AppColors.warning),
};

/// Stan dostawcy: w kursie, wolny albo bez lokalizacji (wtedy nie dostaje kursów).
({String label, AppIconData icon, Color color}) _courierStatus(MapCourier c, bool tracking, DateTime now) {
  if (tracking && !c.located) return (label: 'Bez lokalizacji', icon: AppIcons.gpsSlash, color: AppColors.warning);
  if (c.busy) return (label: 'W kursie', icon: AppIcons.moped, color: _info);
  return (label: 'Wolny', icon: AppIcons.checkCircle, color: AppColors.accent);
}

String _ago(DateTime? t, DateTime now) {
  if (t == null) return 'brak pozycji';
  final d = now.difference(t);
  if (d.inSeconds < 45) return 'pozycja przed chwilą';
  if (d.inMinutes < 60) return 'pozycja ${d.inMinutes} min temu';
  return 'ostatnia pozycja o ${Fmt.time(t)}';
}

String _distance(int meters) =>
    meters < 1000 ? '$meters m' : '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

/// Mapa dostawców (Dostawy → Mapa): pozycje dostawców na zmianie, cele dostaw w toku i trasy
/// z czasem dojazdu. Dane odświeżają się co 10 sekund, trasy co minutę (funkcja Edge „maps” liczy
/// je najwyżej co kilka minut na kurs, resztę oddaje z pamięci).
class CourierMapScreen extends ConsumerStatefulWidget {
  const CourierMapScreen({super.key});

  @override
  ConsumerState<CourierMapScreen> createState() => _CourierMapScreenState();
}

class _CourierMapScreenState extends ConsumerState<CourierMapScreen> {
  final _map = MapController();
  Timer? _poll;
  Timer? _routes;
  Timer? _attributionTimer;
  MapTiles? _tiles;
  bool? _tilesDark;
  bool _tilesLoading = false;
  String? _copyright;
  final _geocoding = <String>{};

  /// Wybrany dostawca albo dostawa (identyfikator), podświetlony na mapie i na liście.
  String? _selected;
  bool _fitted = false;
  bool _mapReady = false;
  DateTime _now = DateTime.now();

  String? get _restaurantId => ref.read(currentRestaurantProvider)?.id;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      final id = _restaurantId;
      if (id == null || !mounted) return;
      ref.invalidate(courierMapProvider(id));
      setState(() => _now = DateTime.now());
    });
    _routes = Timer.periodic(const Duration(minutes: 1), (_) => _refreshRoutes());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _routes?.cancel();
    _attributionTimer?.cancel();
    _map.dispose();
    super.dispose();
  }

  Future<void> _ensureTiles(String restaurantId, bool dark) async {
    if (_tilesLoading) return;
    if (_tiles != null && _tilesDark == dark && !_tiles!.expired(DateTime.now())) return;
    _tilesLoading = true;
    try {
      final tiles = await ref.read(repositoryProvider).mapTiles(restaurantId, dark: dark);
      if (mounted) {
        setState(() {
          _tiles = tiles;
          _tilesDark = dark;
        });
      }
    } catch (_) {
      // Bez sesji Google mapa i tak działa na OpenStreetMap.
      if (mounted) {
        setState(() {
          _tiles = const MapTiles.osm();
          _tilesDark = dark;
        });
      }
    } finally {
      _tilesLoading = false;
    }
  }

  /// Nowe dane: brakujące współrzędne adresów i (za pierwszym razem) widok na wszystko oraz trasy.
  void _onData(CourierMap map) {
    final repo = ref.read(repositoryProvider);
    final id = _restaurantId;
    for (final o in map.orders.where((o) => o.needsGeocode)) {
      if (!_geocoding.add(o.id)) continue;
      repo.geocodeOrder(o.id).then((_) {
        if (mounted && id != null) ref.invalidate(courierMapProvider(id));
      }, onError: (_) {});
    }
    if (!_fitted && _mapReady) {
      _fitted = true;
      _fitAll(map);
      _refreshRoutes(map);
    }
  }

  Future<void> _refreshRoutes([CourierMap? given]) async {
    final id = _restaurantId;
    if (id == null) return;
    final map = given ?? ref.read(courierMapProvider(id)).value;
    if (map == null) return;
    final now = DateTime.now();
    var changed = false;
    for (final o in map.orders.where((o) => o.onTheWay && o.target != null)) {
      final c = map.courier(o.courierId);
      if (c?.position == null || c!.stale(now)) continue;
      try {
        await ref.read(repositoryProvider).courierRoute(c.memberId, o.id);
        changed = true;
      } catch (_) {
        // Trasa wróci przy następnej próbie; mapa działa bez niej.
      }
    }
    if (changed && mounted) ref.invalidate(courierMapProvider(id));
  }

  List<LatLng> _points(CourierMap map) => [
    ?map.restaurant,
    for (final c in map.couriers)
      if (c.position != null && !c.stale(_now)) c.position!,
    for (final o in map.orders)
      if (o.target != null) o.target!,
  ];

  void _fitAll(CourierMap map) {
    final points = _points(map);
    if (points.isEmpty || !_mapReady) return;
    if (points.length == 1) {
      _map.move(points.first, 15);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(80), maxZoom: 16),
    );
  }

  void _focus(String id, LatLng? point) {
    setState(() => _selected = _selected == id ? null : id);
    if (point != null && _mapReady) _map.move(point, math.max(_map.camera.zoom, 15));
  }

  void _zoom(double by) {
    if (!_mapReady) return;
    _map.move(_map.camera.center, (_map.camera.zoom + by).clamp(5, 19).toDouble());
  }

  /// Podpis danych mapy Google zależy od widoku: pobieramy go po każdym przesunięciu (z opóźnieniem).
  void _scheduleAttribution(MapCamera camera) {
    final tiles = _tiles;
    if (tiles == null || !tiles.google) return;
    _attributionTimer?.cancel();
    _attributionTimer = Timer(const Duration(milliseconds: 700), () async {
      final b = camera.visibleBounds;
      final uri = Uri.https('tile.googleapis.com', '/tile/v1/viewport', {
        'session': tiles.session!,
        'key': tiles.key!,
        'zoom': camera.zoom.round().toString(),
        'north': b.north.toString(),
        'south': b.south.toString(),
        'east': b.east.toString(),
        'west': b.west.toString(),
      });
      try {
        final res = await http.get(uri);
        final copyright = (jsonDecode(res.body) as Map<String, dynamic>)['copyright'] as String?;
        if (mounted && copyright != null) setState(() => _copyright = copyright);
      } catch (_) {
        // Zostaje poprzedni podpis.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_tiles == null || _tilesDark != dark) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTiles(restaurant.id, dark));
    }
    final async = ref.watch(courierMapProvider(restaurant.id));
    ref.listen(courierMapProvider(restaurant.id), (_, next) {
      if (next.value case final map?) _onData(map);
    });
    final map = async.value;
    final canSettings = ref.watch(memberPermissionsProvider).contains('profile');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          below: map == null ? const SizedBox(height: 32) : _Summary(map: map, now: _now),
          actions: [
            OutlinedButton.icon(
              onPressed: map == null ? null : () => _fitAll(map),
              icon: const Glyph(AppIcons.mapTrifold, size: 18),
              label: const Text('Pokaż wszystko'),
            ),
          ],
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(courierMapProvider(restaurant.id))),
            data: (map) => Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _mapCard(map, dark)),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 360,
                    child: _SidePanel(
                      map: map,
                      now: _now,
                      selected: _selected,
                      onCourier: (c) => _focus(c.memberId, c.position),
                      onOrder: (o) => _focus(o.id, o.target),
                      onSettings: canSettings ? () => context.go(PanelRoutes.settings) : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _mapCard(CourierMap map, bool dark) {
    final tiles = _tiles;
    final google = tiles?.google ?? false;
    final selectedCourier = map.courier(_selected);
    final routes = [
      for (final o in map.orders)
        if (map.routeFor(o) case final r? when r.points.length > 1) (o, r),
    ];
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
                backgroundColor: AppColors.surfaceRaised,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onMapReady: () {
                  _mapReady = true;
                  if (!_fitted) {
                    _fitted = true;
                    _fitAll(map);
                    _refreshRoutes(map);
                    _onData(map);
                  }
                },
                onPositionChanged: (camera, _) => _scheduleAttribution(camera),
                onTap: (_, _) => setState(() => _selected = null),
              ),
              children: [
                if (tiles != null)
                  TileLayer(
                    key: ValueKey(tiles.urlTemplate),
                    urlTemplate: tiles.urlTemplate,
                    userAgentPackageName: 'pl.table.panel',
                    maxNativeZoom: google ? 20 : 19,
                    // OpenStreetMap nie ma ciemnej wersji: w ciemnym motywie odwracamy kolory kafelków.
                    tileBuilder: dark && !google ? darkModeTileBuilder : null,
                  ),
                PolylineLayer(
                  polylines: [
                    for (final (o, r) in routes)
                      Polyline(
                        points: r.points,
                        strokeWidth: _selected == o.courierId || _selected == o.id ? 7 : 5,
                        color: _info,
                        borderStrokeWidth: 2,
                        borderColor: AppColors.background,
                      ),
                  ],
                ),
                // Dokładność pozycji wybranego dostawcy (gdy telefon podaje ją słabo, koło jest duże).
                if (selectedCourier?.position != null && (selectedCourier!.accuracy ?? 0) > 25)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: selectedCourier.position!,
                        radius: selectedCourier.accuracy!,
                        useRadiusInMeter: true,
                        color: _info.withValues(alpha: 0.12),
                        borderColor: _info.withValues(alpha: 0.4),
                        borderStrokeWidth: 1,
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
                    for (final o in map.orders)
                      if (o.target != null)
                        Marker(
                          point: o.target!,
                          width: 84,
                          height: 46,
                          alignment: Alignment.topCenter,
                          child: _DestinationPin(
                            order: o,
                            selected: _selected == o.id,
                            onTap: () => _focus(o.id, o.target),
                          ),
                        ),
                    for (final c in map.couriers)
                      if (c.position != null && !c.stale(_now))
                        Marker(
                          point: c.position!,
                          width: _selected == c.memberId ? 140 : 44,
                          height: _selected == c.memberId ? 70 : 44,
                          child: _CourierPin(
                            courier: c,
                            tracking: map.tracking,
                            selected: _selected == c.memberId,
                            onTap: () => _focus(c.memberId, c.position),
                          ),
                        ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                children: [
                  _MapButton(icon: AppIcons.plus, tooltip: 'Przybliż', onTap: () => _zoom(1)),
                  const SizedBox(height: 6),
                  _MapButton(icon: AppIcons.minus, tooltip: 'Oddal', onTap: () => _zoom(-1)),
                ],
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: _Attribution(
                google: google,
                copyright: _copyright,
                osrm: routes.any((x) => x.$2.provider == 'osm'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Liczby nad mapą: kto jest na zmianie, w kursie, wolny, bez lokalizacji i ile dostaw czeka.
class _Summary extends StatelessWidget {
  const _Summary({required this.map, required this.now});

  final CourierMap map;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final busy = map.couriers.where((c) => c.busy).length;
    final hidden = map.tracking ? map.couriers.where((c) => !c.located).length : 0;
    final free = map.couriers.where((c) => !c.busy && (!map.tracking || c.located)).length;
    final waiting = map.waiting.length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatusChip(label: 'Na zmianie: ${map.couriers.length}', icon: AppIcons.users, color: AppColors.text),
        StatusChip(label: 'W kursie: $busy', icon: AppIcons.moped, color: _info),
        StatusChip(label: 'Wolni: $free', icon: AppIcons.checkCircle, color: AppColors.accent),
        if (hidden > 0)
          StatusChip(label: 'Bez lokalizacji: $hidden', icon: AppIcons.gpsSlash, color: AppColors.warning),
        if (waiting > 0)
          StatusChip(label: 'Czekają na dostawcę: $waiting', icon: AppIcons.hourglass, color: AppColors.warning),
      ],
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

/// Oznaczenie danych mapy: „Google Maps” z podpisem danych dla widoku albo OpenStreetMap.
class _Attribution extends StatelessWidget {
  const _Attribution({required this.google, required this.copyright, required this.osrm});

  final bool google;
  final String? copyright;
  final bool osrm;

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
          if (google) ...[
            Semantics(
              label: 'Google Maps',
              child: Text(
                'Google Maps',
                style: style.copyWith(fontWeight: FontWeight.w600, color: AppColors.text),
              ),
            ),
            if (copyright != null) ...[const SizedBox(width: 8), Text(copyright!, style: style)],
          ] else
            Text('© OpenStreetMap${osrm ? ' · trasy: OSRM' : ''}', style: style),
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

/// Cel dostawy: numer zamówienia na kolorze etapu, z kreską do punktu na mapie.
class _DestinationPin extends StatelessWidget {
  const _DestinationPin({required this.order, required this.selected, required this.onTap});

  final MapOrder order;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stage = _stage(order);
    final fill = order.stage == 'ready' ? AppColors.accentFill : stage.color;
    final fg = _on(fill);
    return Tooltip(
      message: [order.address ?? '', stage.label].join(' · '),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: selected ? AppColors.text : Colors.transparent, width: 2),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Glyph(stage.icon, size: 13, color: fg),
                  const SizedBox(width: 4),
                  Text(
                    '#${order.number}',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 2, height: 9, color: fill),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: fill,
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

/// Dostawca: kółko z inicjałami w jego kolorze. Kurs i brak lokalizacji mają znaczek z ikoną.
class _CourierPin extends StatelessWidget {
  const _CourierPin({required this.courier, required this.tracking, required this.selected, required this.onTap});

  final MapCourier courier;
  final bool tracking;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = courier;
    final color = staffColors[c.color % staffColors.length];
    final status = _courierStatus(c, tracking, DateTime.now());
    final dot = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
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
            c.initials,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _on(color),
            ),
          ),
        ),
        if (c.busy || (tracking && !c.located))
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: status.color,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child: Glyph(status.icon, size: 11, color: _on(status.color)),
            ),
          ),
      ],
    );
    return Tooltip(
      message: '${c.name} · ${status.label}',
      child: GestureDetector(
        onTap: onTap,
        child: selected
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  dot,
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.ring),
                    ),
                    child: Text(
                      c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 12, color: AppColors.text),
                    ),
                  ),
                ],
              )
            : Center(child: dot),
      ),
    );
  }
}

/// Lista obok mapy: dostawcy z kursami i czasem dojazdu, potem dostawy czekające na dostawcę.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.map,
    required this.now,
    required this.selected,
    required this.onCourier,
    required this.onOrder,
    required this.onSettings,
  });

  final CourierMap map;
  final DateTime now;
  final String? selected;
  final ValueChanged<MapCourier> onCourier;
  final ValueChanged<MapOrder> onOrder;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final waiting = map.waiting;
    Widget header(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Semantics(
        header: true,
        child: Text(title, style: text.titleMedium?.copyWith(fontFeatures: _tabular)),
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!map.tracking) ...[_TrackingOff(onSettings: onSettings), const SizedBox(height: 16)],
          header('Dostawcy · ${map.couriers.length}'),
          if (map.couriers.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                'Nikt z dostawców nie jest teraz na zmianie.',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ),
          for (final c in map.couriers)
            _CourierTile(
              courier: c,
              map: map,
              now: now,
              selected: selected == c.memberId,
              onTap: () => onCourier(c),
              onOrder: onOrder,
            ),
          if (waiting.isNotEmpty) ...[
            const SizedBox(height: 12),
            header('Czekają na dostawcę · ${waiting.length}'),
            for (final o in waiting) _OrderTile(order: o, selected: selected == o.id, onTap: () => onOrder(o)),
          ],
        ],
      ),
    );
  }
}

class _TrackingOff extends StatelessWidget {
  const _TrackingOff({required this.onSettings});

  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Glyph(AppIcons.gpsSlash, size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(child: Text('Lokalizacja dostawców wyłączona', style: text.titleSmall)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Bez niej na mapie widać dostawcę tylko w trakcie kursu. Włącz ją w „Ustawienia lokalu” → '
            '„Dostawa i odbiór”: telefony wyślą pozycję przez całą zmianę.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          if (onSettings != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onSettings, child: const Text('Otwórz ustawienia lokalu')),
          ],
        ],
      ),
    );
  }
}

class _CourierTile extends StatelessWidget {
  const _CourierTile({
    required this.courier,
    required this.map,
    required this.now,
    required this.selected,
    required this.onTap,
    required this.onOrder,
  });

  final MapCourier courier;
  final CourierMap map;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<MapOrder> onOrder;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = courier;
    final color = staffColors[c.color % staffColors.length];
    final status = _courierStatus(c, map.tracking, now);
    final orders = map.ordersOf(c.memberId);
    final where = c.position == null
        ? (map.tracking ? 'Nie udostępnia lokalizacji' : 'Pozycja pojawi się w trakcie kursu')
        : Fmt.capitalize(_ago(c.updatedAt, now));
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      child: Text(
                        c.initials,
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _on(color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(where, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusChip(label: status.label, icon: status.icon, color: status.color),
                  ],
                ),
                for (final o in orders) ...[
                  const SizedBox(height: 8),
                  _CourseLine(order: o, route: map.routeFor(o), onTap: () => onOrder(o)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kurs dostawcy: numer, adres i dojazd (z trasy) albo etap.
class _CourseLine extends StatelessWidget {
  const _CourseLine({required this.order, required this.route, required this.onTap});

  final MapOrder order;
  final MapRoute? route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stage = _stage(order);
    final r = route;
    final arrival = r?.arrival;
    final detail = order.onTheWay && arrival != null
        ? 'Dojazd ok. ${Fmt.time(arrival)}${r!.distanceM == null ? '' : ' · ${_distance(r.distanceM!)}'}'
        : stage.label;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(color: stage.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Glyph(stage.icon, size: 16, color: stage.color),
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
                  Text(
                    order.notFound ? 'Nie znaleziono adresu na mapie' : detail,
                    style: text.bodySmall?.copyWith(
                      color: order.notFound ? AppColors.warning : stage.color,
                      fontFeatures: _tabular,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.selected, required this.onTap});

  final MapOrder order;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stage = _stage(order);
    final when = order.promisedAt ?? order.scheduledFor;
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
                Glyph(AppIcons.mapPin, size: 18, color: order.notFound ? AppColors.warning : AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#${order.number} · ${order.address ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                      ),
                      Text(
                        order.notFound
                            ? 'Nie znaleziono adresu na mapie'
                            : [stage.label, if (when != null) 'na ${Fmt.time(when)}'].join(' · '),
                        style: text.bodySmall?.copyWith(
                          color: order.notFound ? AppColors.warning : AppColors.textMuted,
                          fontFeatures: _tabular,
                        ),
                      ),
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

part of 'delivery_map_screen.dart';

/// 1 dostawa, 2–4 dostawy, 5+ dostaw (12–14 dostaw).
String _deliveries(int n) {
  final last = n % 10;
  final lastTwo = n % 100;
  if (n == 1) return '1 dostawa';
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) return '$n dostawy';
  return '$n dostaw';
}

String _span(Duration d) {
  final minutes = math.max(0, (d.inSeconds / 60).round());
  if (minutes < 60) return '$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h $rest min';
}

/// Historia tras (Mapa → Historia, 24.11.2026, prośba użytkownika: „historia tras, które wykonał dany kierowca …
/// żeby sprawdzić np. czy dany kierowca nie pojechał naokoło”). Dzień lokalu i dostawca po lewej, pod nimi jego kursy
/// i powroty do lokalu: godziny, dostawy, przejechane kilometry wobec najkrótszej trasy z Mapbox przez te same
/// miejsca (miejsce dowiezienia = pozycja telefonu przy „Dostarczone”), objazd ponad 30% i 1 km, inna kolejność
/// adresów niż najszybsza, postoje i przerwy w danych. Na mapie cała trasa dnia, kursy w kolorze dostawcy,
/// wybrany kurs z najkrótszą trasą przerywaną kreską. Dziś odświeża się co minutę.
class _CourierHistory extends ConsumerStatefulWidget {
  const _CourierHistory({
    required this.header,
    required this.panelOpen,
    required this.onToggle,
    required this.live,
    this.tileProvider,
  });

  final Widget header;
  final bool panelOpen;
  final VoidCallback onToggle;

  /// Mapa na żywo: położenie, nazwa i miasto lokalu.
  final DeliveryMap? live;
  final TileProvider? tileProvider;

  @override
  ConsumerState<_CourierHistory> createState() => _CourierHistoryState();
}

class _CourierHistoryState extends ConsumerState<_CourierHistory> {
  final _map = MapController();
  bool _mapReady = false;
  Timer? _poll;

  /// Wybrany dzień lokalu; null = dziś.
  DateTime? _day;
  String? _memberId;

  /// Wybrany odcinek (klucz kursu albo powrotu).
  String? _ride;

  /// Dla jakiego dostawcy i dnia widok jest już dopasowany do trasy.
  String? _fitted;

  /// Najkrótsze trasy z Mapbox (klucz: dostawca, dzień, odcinek, liczba punktów); null = nie da się policzyć.
  final _trips = <String, MapTrip?>{};
  bool _checking = false;
  DateTime? _failedAt;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || _day != null) return;
      final id = ref.read(currentRestaurantProvider)?.id;
      if (id == null) return;
      final today = businessToday(ref.read(dayCloseProvider));
      ref.invalidate(courierDaysProvider((restaurantId: id, day: today)));
      final member = _memberId;
      if (member != null) ref.invalidate(courierHistoryProvider((restaurantId: id, memberId: member, day: today)));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _map.dispose();
    super.dispose();
  }

  static String _iso(DateTime d) => '${d.year}-${d.month}-${d.day}';

  String _tripKey(String memberId, DateTime day, CourierRide r) =>
      '$memberId|${_iso(day)}|${r.key}|${r.points.length}';

  void _shiftDay(int days, DateTime today) {
    final current = _day ?? today;
    var day = DateTime(current.year, current.month, current.day + days);
    if (!day.isBefore(today)) day = today;
    setState(() {
      _day = day == today ? null : day;
      _ride = null;
    });
  }

  Future<void> _pickDay(DateTime today) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? today,
      firstDate: today.subtract(const Duration(days: 30)),
      lastDate: today,
    );
    if (picked != null && mounted) _shiftDay(dateOnly(picked).difference(_day ?? today).inDays, today);
  }

  // ---------------------------------------------------------------
  // Mapbox: najkrótsza trasa każdego zakończonego odcinka
  // ---------------------------------------------------------------

  /// Miejsca odcinka do porównania: kurs = miejsca dowiezienia po kolei (pozycja telefonu przy „Dostarczone”, bez
  /// niej adres z Mapbox; to samo miejsce raz), powrót = lokal. Null: któregoś miejsca nie da się ustalić.
  Future<List<LatLng>?> _stopsOf(CourierRide ride, CourierTrack track, MapboxClient mapbox) async {
    final live = widget.live;
    if (ride.back) return live?.restaurant == null ? null : [live!.restaurant!];
    final drops = ride.dropPoints(track.points);
    final stops = <LatLng>[];
    for (final (i, o) in ride.orders.indexed) {
      final point =
          drops[i] ?? await mapbox.geocode(o.address ?? '', near: live?.restaurant, city: live?.restaurantCity);
      if (point == null) return null;
      if (stops.isEmpty || metersBetween(stops.last, point) > 50) stops.add(point);
    }
    return stops;
  }

  Future<void> _check(List<(String, CourierRide)> todo, CourierTrack track) async {
    final mapbox = ref.read(mapboxProvider);
    if (_checking || !mapbox.configured) return;
    _checking = true;
    try {
      for (final (key, ride) in todo) {
        if (_trips.containsKey(key)) continue;
        final stops = await _stopsOf(ride, track, mapbox);
        final trip = stops == null || stops.isEmpty ? null : await mapbox.trip(ride.points.first.point, stops);
        if (!mounted) return;
        setState(() => _trips[key] = trip);
      }
      _failedAt = null;
    } on Object {
      _failedAt = DateTime.now();
    } finally {
      _checking = false;
    }
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------
  // Widok
  // ---------------------------------------------------------------

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

  List<LatLng> _dayPoints(CourierTrack track) => [?widget.live?.restaurant, for (final p in track.points) p.point];

  void _selectRide(CourierRide r, CourierTrack track, MapTrip? trip) {
    final same = _ride == r.key;
    setState(() => _ride = same ? null : r.key);
    _fit(same ? _dayPoints(track) : [for (final p in r.points) p.point, ...?trip?.geometry]);
  }

  void _zoom(double by) {
    if (!_mapReady) return;
    _map.move(_map.camera.center, (_map.camera.zoom + by).clamp(5, 19).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider)!;
    final today = businessToday(ref.watch(dayCloseProvider));
    final day = _day ?? today;
    final daysAsync = ref.watch(courierDaysProvider((restaurantId: restaurant.id, day: day)));
    final days = daysAsync.value ?? const <CourierDay>[];
    final member =
        days.where((d) => d.memberId == _memberId).firstOrNull ??
        days.where((d) => d.points > 0).firstOrNull ??
        days.firstOrNull;
    final historyAsync = member == null
        ? null
        : ref.watch(courierHistoryProvider((restaurantId: restaurant.id, memberId: member.memberId, day: day)));
    final track = historyAsync?.value ?? CourierTrack.empty;
    final rides = courierRides(track, restaurant: widget.live?.restaurant);
    final color = member == null ? AppColors.accent : staffColors[member.color % staffColors.length];

    // Najkrótsze trasy zakończonych odcinków z trasą z telefonu, po kolei, bez powtórek po błędzie przez minutę.
    final todo = [
      if (member != null)
        for (final r in rides)
          if (r.finished && r.hasTrack && !_trips.containsKey(_tripKey(member.memberId, day, r)))
            (_tripKey(member.memberId, day, r), r),
    ];
    final failed = _failedAt;
    final mapbox = ref.watch(mapboxProvider);
    if (todo.isNotEmpty &&
        !_checking &&
        mapbox.configured &&
        (failed == null || DateTime.now().difference(failed) > const Duration(minutes: 1))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_check(todo, track));
      });
    }
    MapTrip? tripOf(CourierRide r) => member == null ? null : _trips[_tripKey(member.memberId, day, r)];
    bool pending(CourierRide r) =>
        member != null && mapbox.configured && !_trips.containsKey(_tripKey(member.memberId, day, r));

    // Pierwsze dopasowanie widoku do trasy dostawcy w tym dniu.
    final fitKey = member == null ? null : '${member.memberId}|${_iso(day)}';
    if (fitKey != null && _fitted != fitKey && historyAsync?.hasValue == true && _mapReady) {
      _fitted = fitKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fit(_dayPoints(track));
      });
    }

    final drops = <LatLng>[for (final r in rides) ...r.dropPoints(track.points).nonNulls];
    final stops = trackStops(track.points, skip: [?widget.live?.restaurant, ...drops]);
    final summary = daySummary(rides, track.points);
    final checks = {for (final r in rides) r.key: checkRide(r, tripOf(r))};
    final detours = checks.values.where((c) => c?.detour ?? false).length;
    final gaps = trackGaps(track.points);

    final panel = SidePanel(
      header: widget.header,
      actions: [
        StepSwitcher(
          label: day == today ? 'Dziś' : Fmt.capitalize(Fmt.dayShort(day)),
          expand: true,
          previousTooltip: 'Poprzedni dzień',
          nextTooltip: 'Następny dzień',
          onPrevious: () => _shiftDay(-1, today),
          onNext: day == today ? null : () => _shiftDay(1, today),
          resetTooltip: 'Wróć do dziś',
          onReset: day == today ? null : () => _shiftDay(today.difference(day).inDays, today),
          extras: [(AppIcons.calendar, 'Wybierz dzień', () => _pickDay(today))],
        ),
        if (days.isNotEmpty)
          PanelSelect<String>(
            key: ValueKey('kierowca-${_iso(day)}-${member?.memberId}'),
            initialValue: member?.memberId,
            decoration: const InputDecoration(labelText: 'Dostawca'),
            items: [
              for (final d in days)
                DropdownMenuItem(
                  value: d.memberId,
                  child: Text('${d.name} · ${_deliveries(d.deliveries)}'),
                ),
            ],
            onChanged: (v) => setState(() {
              _memberId = v;
              _ride = null;
            }),
          ),
      ],
      children: [
        if (daysAsync.isLoading && !daysAsync.hasValue)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else if (daysAsync.hasError && !daysAsync.hasValue)
          _PanelNote('Nie udało się wczytać dostawców: ${daysAsync.error}')
        else if (days.isEmpty)
          const _PanelNote('Tego dnia żaden dostawca nie miał dostaw ani trasy z telefonu.')
        else if (historyAsync != null && historyAsync.isLoading && !historyAsync.hasValue)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else ...[
          _HistorySummary(
            meters: summary.meters,
            riding: summary.riding,
            courses: summary.courses,
            hasTrack: track.points.length >= 2,
          ),
          _PanelHeading('Kursy · ${summary.courses}'),
          if (rides.isEmpty) const _PanelNote('Bez odebranych kursów tego dnia.'),
          for (final r in rides)
            _RideCard(
              ride: r,
              color: color,
              check: checks[r.key],
              checking: r.finished && r.hasTrack && pending(r),
              noRoute: r.finished && r.hasTrack && !pending(r) && tripOf(r) == null && mapbox.configured,
              stops: [
                for (final s in stops)
                  if (!s.from.isBefore(r.from) && !s.to.isAfter(r.to)) s,
              ],
              selected: _ride == r.key,
              onTap: () => _selectRide(r, track, tripOf(r)),
            ),
        ],
      ],
    );

    return SidePanelLayout(
      open: widget.panelOpen,
      onToggle: widget.onToggle,
      panel: panel,
      content: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 32, 32),
        child: _historyMap(
          track: track,
          rides: rides,
          stops: stops,
          color: color,
          tripOf: tripOf,
          chips: [
            if (track.points.length >= 2)
              _MapChip(label: 'Przejechane: ${_distance(summary.meters)}', icon: AppIcons.navigation, color: color),
            _MapChip(label: 'Kursy: ${summary.courses}', icon: AppIcons.moped, color: _info),
            if (detours > 0)
              _MapChip(label: 'Objazdy: $detours', icon: AppIcons.warning, color: AppColors.error),
            if (stops.isNotEmpty)
              _MapChip(label: 'Postoje: ${stops.length}', icon: AppIcons.timer, color: AppColors.warning),
            if (gaps > 0)
              _MapChip(label: 'Przerwy w danych: $gaps', icon: AppIcons.gpsSlash, color: AppColors.warning),
            if (failed != null)
              _MapChip(label: 'Mapbox nie odpowiada', icon: AppIcons.warning, color: AppColors.error),
          ],
        ),
      ),
    );
  }

  Widget _historyMap({
    required CourierTrack track,
    required List<CourierRide> rides,
    required List<TrackStop> stops,
    required Color color,
    required MapTrip? Function(CourierRide) tripOf,
    required List<Widget> chips,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mapbox = ref.watch(mapboxProvider);
    final restaurant = widget.live?.restaurant;
    final selected = rides.where((r) => r.key == _ride).firstOrNull;
    final dim = selected != null;
    final planned = selected == null ? null : tripOf(selected);
    double alpha(CourierRide r) => dim && r.key != _ride ? 0.3 : 1;

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
                initialCenter: restaurant ?? track.points.firstOrNull?.point ?? const LatLng(52.23, 21.01),
                initialZoom: 13,
                minZoom: 5,
                maxZoom: 19,
                backgroundColor: dark ? const Color(0xFF1B1C1F) : const Color(0xFFEDEDE9),
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onMapReady: () {
                  _mapReady = true;
                  if (track.points.isNotEmpty) setState(() => _fitted = null);
                },
                onTap: (_, _) => setState(() => _ride = null),
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
                    // Cała trasa dnia cienko (także między kursami), kursy grubo w kolorze dostawcy.
                    if (track.points.length > 1)
                      Polyline(
                        points: [for (final p in track.points) p.point],
                        strokeWidth: 3,
                        color: color.withValues(alpha: dim ? 0.2 : 0.45),
                      ),
                    for (final r in rides)
                      if (r.hasTrack)
                        Polyline(
                          points: [for (final p in r.points) p.point],
                          strokeWidth: r.key == _ride ? 7 : 5,
                          color: color.withValues(alpha: alpha(r)),
                          borderStrokeWidth: 2,
                          borderColor: AppColors.background.withValues(alpha: alpha(r)),
                          pattern: r.back ? StrokePattern.dashed(segments: const [12, 8]) : const StrokePattern.solid(),
                        ),
                    // Najkrótsza trasa wybranego odcinka.
                    if (planned != null && planned.geometry.length > 1)
                      Polyline(
                        points: planned.geometry,
                        strokeWidth: 3,
                        color: AppColors.text.withValues(alpha: 0.85),
                        pattern: StrokePattern.dashed(segments: const [8, 7]),
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    if (restaurant != null)
                      Marker(
                        point: restaurant,
                        width: 40,
                        height: 40,
                        child: Tooltip(message: widget.live?.restaurantName ?? '', child: const _RestaurantPin()),
                      ),
                    for (final s in stops)
                      Marker(
                        point: s.point,
                        width: 26,
                        height: 26,
                        child: Tooltip(
                          message: 'Postój ${_span(s.duration)} · ${Fmt.time(s.from)}–${Fmt.time(s.to)}',
                          child: const _StopPin(),
                        ),
                      ),
                    // Początek i koniec trasy dnia, gdy nie są przy lokalu (tam stoi znak lokalu).
                    for (final (p, end) in [(track.points.firstOrNull, false), (track.points.lastOrNull, true)])
                      if (p != null && (restaurant == null || metersBetween(p.point, restaurant) > 150))
                        Marker(
                          point: p.point,
                          width: 100,
                          height: 26,
                          child: _TimePin(label: Fmt.time(p.at), color: color, end: end),
                        ),
                    for (final r in rides)
                      for (final (i, point) in r.dropPoints(track.points).indexed)
                        if (point != null)
                          Marker(
                            point: point,
                            width: 110,
                            height: 48,
                            alignment: Alignment.topCenter,
                            child: Opacity(
                              opacity: alpha(r) < 1 ? 0.45 : 1,
                              child: _DropPin(
                                order: r.orders[i],
                                color: color,
                                selected: r.key == _ride,
                                onTap: () => _selectRide(r, track, tripOf(r)),
                              ),
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
              child: Wrap(spacing: 8, runSpacing: 8, children: chips),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                children: [
                  _MapButton(icon: AppIcons.cornersOut, tooltip: 'Pokaż całą trasę', onTap: () => _fit(_dayPoints(track))),
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
}

/// Dzień dostawcy w liczbach: przejechane kilometry, czas w kursach, liczba kursów.
class _HistorySummary extends StatelessWidget {
  const _HistorySummary({required this.meters, required this.riding, required this.courses, required this.hasTrack});

  final double meters;
  final Duration riding;
  final int courses;
  final bool hasTrack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget value(String label, String v) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
          Text(v, style: text.titleMedium?.copyWith(fontFeatures: _tabular)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              value('Przejechane', hasTrack ? _distance(meters) : '—'),
              value('W kursach', _span(riding)),
            ],
          ),
          if (!hasTrack)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Telefon dostawcy nie wysłał trasy tego dnia (starsza wersja Table for employees albo trasa '
                'sprzed 24.11.2026). Kursy i godziny są z zamówień.',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kurs albo powrót do lokalu: godziny, dostawy, kilometry wobec najkrótszej trasy i postoje.
class _RideCard extends StatelessWidget {
  const _RideCard({
    required this.ride,
    required this.color,
    required this.check,
    required this.checking,
    required this.noRoute,
    required this.stops,
    required this.selected,
    required this.onTap,
  });

  final CourierRide ride;
  final Color color;
  final RideCheck? check;
  final bool checking;
  final bool noRoute;
  final List<TrackStop> stops;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = ride;
    final muted = text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    final title = r.back ? 'Powrót do lokalu' : r.orders.map((o) => '#${o.number}').join(' · ');
    final when = r.finished
        ? '${Fmt.time(r.from)}–${Fmt.time(r.to)} · ${_span(r.duration)}'
        : 'od ${Fmt.time(r.from)} · w drodze';
    final c = check;
    final status = !r.hasTrack
        ? (label: 'Bez trasy z telefonu', icon: AppIcons.gpsSlash, color: AppColors.textMuted)
        : !r.finished
        ? (label: 'W drodze', icon: AppIcons.moped, color: _info)
        : checking
        ? (label: 'Sprawdzam trasę…', icon: AppIcons.hourglass, color: AppColors.textMuted)
        : c == null
        ? (noRoute ? (label: 'Bez porównania z trasą', icon: AppIcons.info, color: AppColors.textMuted) : null)
        : c.detour
        ? (label: 'Objazd +${_distance(c.extra)} (+${c.extraPercent}%)', icon: AppIcons.warning, color: AppColors.error)
        : (label: 'Trasa w normie', icon: AppIcons.checkCircle, color: AppColors.accent);
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: r.back ? Colors.transparent : color,
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(when, style: muted),
                for (final o in r.orders) _DropLine(order: o),
                if (r.hasTrack) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      'Przejechane ${_distance(r.meters)}',
                      if (c != null) 'najkrótsza ${_distance(c.planned)}',
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(fontFeatures: _tabular),
                  ),
                ],
                if (c?.otherOrder ?? false)
                  Text('Kolejność adresów inna niż najszybsza', style: muted?.copyWith(color: AppColors.warning)),
                if (stops.isNotEmpty)
                  Text(
                    'Postoje: ${stops.map((s) => '${Fmt.time(s.from)} (${_span(s.duration)})').join(', ')}',
                    style: muted?.copyWith(color: AppColors.warning),
                  ),
                if (r.gaps > 0)
                  Text('Przerwa w danych z telefonu: kilometry mogą być zaniżone', style: muted),
                if (status != null) ...[
                  const SizedBox(height: 8),
                  StatusChip(label: status.label, icon: status.icon, color: status.color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dostawa w kursie: adres i godzina dowiezienia (spóźnienie wobec obiecanej godziny na czerwono).
class _DropLine extends StatelessWidget {
  const _DropLine({required this.order});

  final TrackOrder order;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final o = order;
    final delivered = o.deliveredAt;
    final promised = o.promisedAt;
    final late = delivered != null && promised != null ? delivered.difference(promised) : null;
    final lateText = late != null && late.inMinutes >= 1 ? 'spóźnione ${_span(late)}' : null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '#${o.number} ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: o.address ?? 'Bez adresu'),
            TextSpan(
              text: delivered == null
                  ? ' · nie dowiezione'
                  : ' · ${Fmt.time(delivered)}${promised == null ? '' : ' (na ${Fmt.time(promised)})'}',
              style: TextStyle(color: AppColors.textMuted),
            ),
            if (lateText != null) TextSpan(text: ' · $lateText', style: TextStyle(color: AppColors.error)),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall?.copyWith(fontFeatures: _tabular),
      ),
    );
  }
}

/// Miejsce dowiezienia: numer zamówienia w kolorze dostawcy, z kreską do punktu na mapie.
class _DropPin extends StatelessWidget {
  const _DropPin({required this.order, required this.color, required this.selected, required this.onTap});

  final TrackOrder order;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = _on(color);
    final delivered = order.deliveredAt;
    return Tooltip(
      message: [
        order.address ?? '',
        ?order.customer,
        if (delivered != null) 'dowiezione ${Fmt.time(delivered)}',
      ].join(' · '),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(5, 3, 8, 3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: selected ? AppColors.text : Colors.transparent, width: 2),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Glyph(AppIcons.checkCircle, size: 13, color: fg),
                  const SizedBox(width: 3),
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

/// Postój: żółte kółko z zegarem.
class _StopPin extends StatelessWidget {
  const _StopPin();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.warning,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.background, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Glyph(AppIcons.timer, size: 12, color: _on(AppColors.warning)),
      ),
    );
  }
}

/// Początek albo koniec trasy dnia z godziną.
class _TimePin extends StatelessWidget {
  const _TimePin({required this.label, required this.color, this.end = false});

  final String label;
  final Color color;
  final bool end;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: end ? 'Ostatnia pozycja' : 'Pierwsza pozycja',
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: 2),
          ),
          child: Text(
            '${end ? 'Koniec' : 'Start'} $label',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
              fontFeatures: _tabular,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_car/table_car.dart';
import 'package:table_core/table_core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data.dart';
import 'deliveries_data.dart';
import 'courier_location.dart';
import 'ui.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Kolor gotówki do pobrania: ciepły, żeby dostawca nie przeoczył kwoty (czytelny w obu motywach).
Color get _cash => StaffColors.pending;

/// Etap kursu: słowo, ikona i kolor.
({String label, AppIconData icon, Color color}) _stage(CourseStage stage) => switch (stage) {
  CourseStage.preparing => (label: 'W przygotowaniu', icon: AppIcons.cookingPot, color: StaffColors.pending),
  CourseStage.ready => (label: 'Gotowe do odbioru', icon: AppIcons.shoppingBag, color: AppColors.accent),
  CourseStage.onTheWay => (label: 'W drodze', icon: AppIcons.moped, color: StaffColors.info),
};

/// Zakładka „Dostawy” dla stanowiska Dostawca: moje kursy, kolejka i dzisiejsze podsumowanie.
/// Kurs przydziela baza: kto pierwszy zaczął zmianę (albo najdawniej skończył kurs), ten dostaje pierwszy.
class DeliveriesTab extends ConsumerWidget {
  const DeliveriesTab({super.key, required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(jobsProvider).value ?? const <Job>[];
    final couriers = jobs.where((j) => j.permissions.contains('deliveries')).toList();
    final working = couriers.where((j) => j.working).firstOrNull;
    if (working == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Dostawy')),
        body: MessageView(
          icon: AppIcons.moped,
          title: couriers.isEmpty ? 'Nie rozwozisz zamówień' : 'Kursy po rozpoczęciu zmiany',
          message: couriers.isEmpty
              ? 'Kursy dostają osoby na stanowisku Dostawca. Jeśli to pomyłka, porozmawiaj z przełożonym.'
              : 'Zeskanuj kod w lokalu, żeby zacząć zmianę. Kto pierwszy zacznie zmianę, dostaje pierwszy kurs.',
          actionLabel: couriers.isEmpty ? null : 'Zeskanuj kod',
          onAction: couriers.isEmpty ? null : onScan,
        ),
      );
    }
    return DeliveriesScreen(job: working);
  }
}

class DeliveriesScreen extends ConsumerStatefulWidget {
  const DeliveriesScreen({super.key, required this.job});

  final Job job;

  @override
  ConsumerState<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends ConsumerState<DeliveriesScreen> {
  bool _busy = false;
  bool _askedLocation = false;

  CourierKey get _key => (memberId: widget.job.memberId, restaurantId: widget.job.restaurantId);

  @override
  void initState() {
    super.initState();
    // Kurs w drodze: telefon wysyła pozycję, gość widzi ją na mapie. Po dostarczeniu wysyłanie się kończy.
    ref.listenManual(deliveryBoardProvider(_key), (_, next) async {
      final board = next.value;
      if (board == null) return;
      final onTheWay = [for (final c in board.courses) if (c.stage == CourseStage.onTheWay) c.id];
      final ok = await ref.read(courierTrackerProvider).update(widget.job.memberId, onTheWay);
      if (!ok && !_askedLocation && !widget.job.courierTracking && mounted) {
        _askedLocation = true;
        showMessage(
          context,
          'Włącz lokalizację dla Table for employees, żeby gość widział na mapie, gdzie jest zamówienie.',
          tone: ToastTone.warning,
        );
      }
    }, fireImmediately: true);
  }

  Future<void> _run(Future<void> Function() action, [String? done]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(deliveryBoardProvider(_key));
      if (done != null && mounted) showMessage(context, done, tone: ToastTone.success);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Uri uri, String problem) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showMessage(context, problem, tone: ToastTone.error);
  }

  Future<void> _delivered(Course course) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Dostarczone #${course.number}?'),
        content: Text(
          course.cash
              ? 'Pobrałeś od gościa ${Fmt.price(course.totalGrosze)} gotówką?'
              : 'Zamówienie jest opłacone kartą online. Nic nie pobierasz.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Jeszcze nie')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: Text(course.cash ? 'Tak, pobrałem' : 'Dostarczone'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    HapticFeedback.mediumImpact();
    await _run(
      () => ref.read(deliveriesRepositoryProvider).delivered(course.id, widget.job.memberId),
      'Kurs #${course.number} zakończony. Wracasz do kolejki.',
    );
  }

  Future<void> _handOver(Course course, DeliveryBoard board) async {
    final others = board.queue.where((q) => q.memberId != widget.job.memberId).toList();
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _HandOverSheet(course: course, others: others),
    );
    if (choice == null) return;
    await _run(() async {
      final name = await ref.read(deliveriesRepositoryProvider).handOver(
        course.id,
        widget.job.memberId,
        toMemberId: choice.isEmpty ? null : choice,
      );
      if (mounted) showMessage(context, 'Kurs #${course.number} przekazany: $name.', tone: ToastTone.success);
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(deliveryBoardProvider(_key));

    // Każdy nowy stan trafia też na ekran samochodu (Android Auto, CarPlay).
    ref.listen(deliveryBoardProvider(_key), (_, next) {
      if (next.value case final board?) showOnCar(board, widget.job.memberId);
    });

    // Nowy kurs: wibracja i powiadomienie, także gdy ekran jest otwarty na innej zakładce.
    ref.listen(deliveryBoardProvider(_key), (previous, next) {
      final before = {for (final c in previous?.value?.courses ?? const <Course>[]) c.id};
      final added = (next.value?.courses ?? const <Course>[]).where((c) => !before.contains(c.id)).toList();
      if (previous?.value != null && added.isNotEmpty) {
        HapticFeedback.heavyImpact();
        final c = added.first;
        showMessage(
          context,
          c.address,
          title: 'Nowy kurs #${c.number}',
          tone: ToastTone.success,
          icon: AppIcons.moped,
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dostawy'),
        actions: [
          IconButton(
            tooltip: 'Odśwież',
            onPressed: () => ref.invalidate(deliveryBoardProvider(_key)),
            icon: const Glyph(AppIcons.refresh, size: 20),
          ),
        ],
      ),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const CardsSkeleton(count: 2),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(deliveryBoardProvider(_key))),
        data: (board) {
          if (!board.isCourier) {
            return const MessageView(
              icon: AppIcons.moped,
              title: 'Nie jesteś w kolejce dostawców',
              message: 'Kursy dostają osoby na stanowisku Dostawca. Twoje stanowisko widzi tylko podgląd.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(deliveryBoardProvider(_key)),
            child: ContentWidth(
              child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                // Lokal wymaga lokalizacji: bez niej dostawca nie dostaje kursów, więc mówimy, co zrobić.
                if (board.tracking || widget.job.courierTracking)
                  _LocationGate(restaurantName: board.restaurantName, serverSeesMe: board.located),
                if (board.courses.isEmpty)
                  _WaitingCard(board: board, memberId: widget.job.memberId)
                else
                  // Dostawy połączone w jeden kurs są obok siebie i odbiera się je razem.
                  for (final (course, mates) in groupCourses(board.courses)) ...[
                    _CourseCard(
                      course: course,
                      mates: mates,
                      busy: _busy,
                      restaurantName: board.restaurantName,
                      onNavigate: () => _open(course.navigationUri, 'Nie udało się otworzyć nawigacji.'),
                      onCall: () => _open(course.phoneUri, 'Nie udało się zadzwonić. Numer: ${course.customerPhone}'),
                      onPickUp: () => _run(
                        () => ref.read(deliveriesRepositoryProvider).pickUp(course.id, widget.job.memberId),
                        mates.isEmpty
                            ? 'Kurs #${course.number} w drodze. Szerokiej drogi!'
                            : 'Kurs w drodze: ${[course, ...mates.where((m) => m.stage != CourseStage.onTheWay)].map((m) => '#${m.number}').join(', ')}. Szerokiej drogi!',
                      ),
                      onDelivered: () => _delivered(course),
                      onHandOver: course.canHandOver ? () => _handOver(course, board) : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                if (board.courses.isNotEmpty && board.waiting > 0)
                  _Hint(
                    icon: AppIcons.clock,
                    text: board.waiting == 1
                        ? 'Jedno zamówienie czeka na wolnego dostawcę.'
                        : 'Zamówienia czekające na wolnego dostawcę: ${board.waiting}.',
                  ),
                const SizedBox(height: 18),
                _QueueCard(board: board, memberId: widget.job.memberId),
                const SizedBox(height: 14),
                _TodayCard(board: board),
              ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Lokalizacja na zmianie (gdy lokal jej wymaga): co się dzieje i jak to naprawić.
/// Gdy wszystko działa, tylko cienki wiersz „Udostępniasz lokalizację”.
class _LocationGate extends ConsumerWidget {
  const _LocationGate({required this.restaurantName, required this.serverSeesMe});

  final String restaurantName;

  /// Serwer ma moją świeżą pozycję.
  final bool serverSeesMe;

  Future<void> _fix(WidgetRef ref, ShareState state) async {
    final tracker = ref.read(courierTrackerProvider);
    if (state == ShareState.serviceOff) {
      await Geolocator.openLocationSettings();
      return;
    }
    if (await tracker.deniedForever()) {
      await Geolocator.openAppSettings();
      return;
    }
    await tracker.retry();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder<ShareState>(
      valueListenable: ref.watch(courierTrackerProvider).state,
      builder: (context, state, _) {
        if (state == ShareState.on || state == ShareState.starting) {
          final ok = state == ShareState.on && serverSeesMe;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Glyph(
                    ok ? AppIcons.navigation : AppIcons.hourglass,
                    size: 16,
                    color: ok ? AppColors.accent : StaffColors.pending,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ok
                          ? 'Udostępniasz lokalizację do końca zmiany.'
                          : 'Wysyłam pozycję. Za chwilę wrócisz do kolejki.',
                      style: text.bodyMedium?.copyWith(color: ok ? AppColors.textMuted : StaffColors.pending),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final serviceOff = state == ShareState.serviceOff;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: StaffColors.pending.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: StaffColors.pending.withValues(alpha: 0.45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Glyph(AppIcons.gpsSlash.duotone, size: 26, color: StaffColors.pending),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          serviceOff ? 'Włącz lokalizację w telefonie' : 'Zezwól na lokalizację',
                          style: text.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$restaurantName wymaga lokalizacji dostawców na zmianie. Bez niej nie dostajesz kursów. '
                    'Lokal widzi Cię na mapie tylko do końca zmiany.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => _fix(ref, state),
                    icon: const Glyph(AppIcons.navigation, size: 18),
                    label: Text(serviceOff ? 'Otwórz ustawienia lokalizacji' : 'Zezwól na lokalizację'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Bez kursu: miejsce w kolejce i spokojnie pulsująca kropka „na zmianie”.
class _WaitingCard extends StatelessWidget {
  const _WaitingCard({required this.board, required this.memberId});

  final DeliveryBoard board;
  final String memberId;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final position = board.positionOf(memberId);
    final free = board.queue.where((q) => !q.busy).length;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          children: [
            const ExcludeSemantics(child: _Pulse()),
            const SizedBox(height: 16),
            Semantics(header: true, child: Text('Czekasz na kurs', style: text.headlineSmall)),
            const SizedBox(height: 6),
            Text(
              board.tracking && !board.located
                  ? 'Kursy dostaniesz, gdy lokal zobaczy Cię na mapie.'
                  : position == null
                  ? 'Jesteś na zmianie w ${board.restaurantName}.'
                  : position == 1
                  ? 'Jesteś pierwszy w kolejce: następne zamówienie z dostawą jest Twoje.'
                  : 'Jesteś $position. w kolejce. Wolnych dostawców na zmianie: $free.',
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // „Ogranicz ruch” w telefonie: kropka bez pulsowania.
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _controller.isAnimating) _controller.stop();
    if (!still && !_controller.isAnimating) _controller.repeat();
    return SizedBox(
      width: 64,
      height: 64,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = still ? 0.0 : Curves.easeOut.transform(_controller.value);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 24 + 40 * t,
                height: 24 + 40 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.28 * (1 - t)),
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent.withValues(alpha: 0.16)),
                alignment: Alignment.center,
                child: Glyph(AppIcons.moped.duotone, size: 24, color: AppColors.accent),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  const _CourseCard({
    required this.course,
    required this.mates,
    required this.busy,
    required this.restaurantName,
    required this.onNavigate,
    required this.onCall,
    required this.onPickUp,
    required this.onDelivered,
    required this.onHandOver,
  });

  final Course course;

  /// Inne dostawy z tego samego kursu (połączone w panelu).
  final List<Course> mates;
  final bool busy;
  final String restaurantName;
  final VoidCallback onNavigate;
  final VoidCallback onCall;
  final VoidCallback onPickUp;
  final VoidCallback onDelivered;
  final VoidCallback? onHandOver;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = course;
    final stage = _stage(c.stage);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Numer, etap (słowo z ikoną) i godzina obiecana gościowi. Przy dużej czcionce schodzą niżej.
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('#${c.number}', style: text.headlineSmall?.copyWith(fontFeatures: _tabular)),
                StatusChip(label: stage.label, icon: stage.icon, color: stage.color),
                if (c.promisedAt != null)
                  StatusChip(label: 'na ${hm(c.promisedAt!)}', icon: AppIcons.clock, color: AppColors.textMuted),
              ],
            ),
            if (mates.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: StaffColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Glyph(AppIcons.arrowsMerge, size: 18, color: StaffColors.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Jeden kurs z ${mates.map((m) => '#${m.number}').join(', ')}',
                        style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(c.address, style: text.titleLarge),
            if (c.note != null) ...[
              const SizedBox(height: 6),
              // Uwaga gościa: ikona dymku i ciepły kolor, żeby nie zginęła pod adresem.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Glyph(AppIcons.chatText, size: 15, color: _cash),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(c.note!, style: text.bodyMedium?.copyWith(color: _cash))),
                ],
              ),
            ],
            if (c.staffNote != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Glyph(AppIcons.lock, size: 14, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(c.staffNote!, style: text.bodyMedium?.copyWith(color: AppColors.textMuted))),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Text(
              '${[?c.company, if (c.customerName != c.company) c.customerName].join(' · ')} · ${c.customerPhone}',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
            ),
            const SizedBox(height: 14),
            // Przy dużej czcionce przyciski stają jeden pod drugim. Pełny kolor ma tylko główne działanie
            // na dole karty („Odebrałem” albo „Dostarczone”), nawigacja ma obrys w kolorze akcentu.
            ButtonPair(
              first: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  foregroundColor: AppColors.accent,
                  side: BorderSide(color: AppColors.accent.withValues(alpha: 0.6)),
                ),
                onPressed: onNavigate,
                icon: const Glyph(AppIcons.navigation, size: 18),
                label: const Text('Nawiguj'),
              ),
              second: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: onCall,
                icon: const Glyph(AppIcons.phone, size: 18),
                label: const Text('Zadzwoń'),
              ),
            ),
            const SizedBox(height: 14),
            _PaymentBox(course: c),
            const SizedBox(height: 12),
            for (final i in c.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${i.quantity}×',
                        style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.name, style: text.bodyMedium),
                          if (i.details != null)
                            Text(i.details!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                          if (i.note != null) Text(i.note!, style: text.bodySmall?.copyWith(color: _cash)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            if (c.stage == CourseStage.onTheWay)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: busy ? null : onDelivered,
                icon: const Glyph(AppIcons.checkCircle, size: 20),
                label: const Text('Dostarczone'),
              )
            else ...[
              if (c.stage == CourseStage.preparing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Kuchnia jeszcze przygotowuje. Zamówienie odbierasz w $restaurantName.',
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: busy ? null : onPickUp,
                icon: const Glyph(AppIcons.shoppingBag, size: 20),
                label: Text(
                  mates.any((m) => m.stage != CourseStage.onTheWay)
                      ? 'Odebrałem cały kurs (${1 + mates.where((m) => m.stage != CourseStage.onTheWay).length})'
                      : 'Odebrałem z lokalu',
                ),
              ),
            ],
            if (onHandOver != null) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: busy ? null : onHandOver,
                icon: const Glyph(AppIcons.arrowsClockwise, size: 18),
                label: const Text('Oddaj kurs'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kwota do pobrania gotówką albo informacja, że zamówienie jest opłacone kartą.
class _PaymentBox extends StatelessWidget {
  const _PaymentBox({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = course;
    final (color, icon, title) = c.prepaid
        ? (AppColors.accent, AppIcons.checkCircle, 'Opłacone · ${Fmt.price(c.totalGrosze)}. Nic nie pobierasz.')
        : c.cash
        ? (_cash, AppIcons.money, 'Pobierz ${Fmt.price(c.totalGrosze)}')
        : (AppColors.accent, AppIcons.creditCard, 'Opłacone kartą online · ${Fmt.price(c.totalGrosze)}');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Glyph(icon, size: 22, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium?.copyWith(color: color, fontFeatures: _tabular)),
                if (!c.cash && c.testPayment)
                  Text('Płatność testowa', style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final AppIconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Glyph(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
        ),
      ],
    );
  }
}

/// Kolejka dostawców na zmianie: wolni od najdłużej czekającego, potem zajęci.
class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.board, required this.memberId});

  final DeliveryBoard board;
  final String memberId;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    var place = 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text('Kolejka dostawców', style: text.titleMedium)),
            const SizedBox(height: 2),
            Text(
              'Kto dłużej czeka, dostaje następny kurs.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 8),
            for (final q in board.queue)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(
                        q.busy || !q.located ? '–' : '${++place}.',
                        style: text.titleSmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        q.memberId == memberId ? '${q.name} (Ty)' : q.name,
                        style: text.bodyLarge?.copyWith(
                          fontWeight: q.memberId == memberId ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                    q.busy
                        ? StatusChip(label: 'W kursie', icon: AppIcons.moped, color: StaffColors.info)
                        : !q.located
                        ? StatusChip(label: 'Bez lokalizacji', icon: AppIcons.gpsSlash, color: StaffColors.pending)
                        : StatusChip(label: 'Wolny', icon: AppIcons.checkCircle, color: AppColors.accent),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.board});

  final DeliveryBoard board;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: StatTile(label: 'Kursy', value: '${board.todayCount}', caption: 'dzisiaj', icon: AppIcons.moped),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StatTile(
              label: 'Gotówka',
              value: Fmt.price(board.todayCashGrosze),
              caption: 'do rozliczenia',
              icon: AppIcons.money,
              color: board.todayCashGrosze > 0 ? _cash : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Oddanie kursu: następny wolny w kolejce albo wybrana osoba. Zwraca numer pracownika ('' = następny wolny).
class _HandOverSheet extends StatelessWidget {
  const _HandOverSheet({required this.course, required this.others});

  final Course course;
  final List<QueuedCourier> others;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Oddaj kurs #${course.number}', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Po oddaniu wracasz na koniec kolejki.',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Glyph(AppIcons.arrowsClockwise, size: 22, color: AppColors.accent),
            title: const Text('Następny wolny w kolejce'),
            subtitle: const Text('Baza wybierze osobę, która najdłużej czeka'),
            onTap: () => Navigator.pop(context, ''),
          ),
          if (others.isNotEmpty) Divider(height: 1, color: AppColors.ring),
          for (final q in others)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Glyph(AppIcons.users, size: 22, color: AppColors.textMuted),
              title: Text(q.name),
              subtitle: Text(q.busy ? 'W kursie, dostanie go jako kolejny' : 'Wolny'),
              onTap: () => Navigator.pop(context, q.memberId),
            ),
          if (others.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Nikt inny nie jest teraz na zmianie.',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bieżący kurs albo miejsce w kolejce na ekranie samochodu. Krótkie teksty, bez szczegółów zamówienia.
void showOnCar(DeliveryBoard board, String memberId) {
  final course = board.courses.firstOrNull;
  final position = board.positionOf(memberId);
  final status = !board.isCourier
      ? 'Kursy dostają osoby na stanowisku Dostawca.'
      : position == null
      ? 'Na zmianie w ${board.restaurantName}.'
      : position == 1
      ? 'Czekasz na kurs: jesteś pierwszy w kolejce.'
      : 'Czekasz na kurs: jesteś $position. w kolejce.';
  TableCar.show(
    status: status,
    next: board.courses.length > 1 ? board.courses.length - 1 : 0,
    course: course == null
        ? null
        : CarCourse(
            number: course.number,
            stage: switch (course.stage) {
              CourseStage.preparing => 'W przygotowaniu',
              CourseStage.ready => 'Gotowe do odbioru',
              CourseStage.onTheWay => 'W drodze',
            },
            address: course.address,
            customer: course.customerName,
            phone: course.customerPhone,
            payment: course.cash
                ? 'Pobierz ${Fmt.price(course.totalGrosze)} gotówką'
                : 'Opłacone kartą online',
            items: switch (course.items.fold(0, (s, i) => s + i.quantity)) {
              1 => '1 pozycja',
              final n when n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14) => '$n pozycje',
              final n => '$n pozycji',
            },
            note: course.note,
            promised: course.promisedAt == null ? null : 'na ${hm(course.promisedAt!)}',
          ),
  );
}

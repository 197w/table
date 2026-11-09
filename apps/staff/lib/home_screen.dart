import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'announcements_screen.dart';
import 'inventory_screen.dart';
import 'data.dart';
import 'scan_screen.dart';
import 'ui.dart';
import 'vehicle_check.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Zakładka „Zeskanuj”: lokale, w których pracuję, skan kodu z panelu i moje godziny.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.onOrders});

  /// Przejście do zakładki „Zamówienia”.
  final VoidCallback onOrders;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // Czas trwającej zmiany rośnie na ekranie co pół minuty.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  void _refresh() {
    ref
      ..invalidate(jobsProvider)
      ..invalidate(shiftsProvider)
      ..invalidate(codesProvider)
      ..invalidate(announcementsProvider);
  }

  Future<void> _scan() async {
    final result = await Navigator.push<ScanResult>(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (result == null || !mounted) return;
    _refresh();
    final at = result.startedAt;
    final ended = result.endedAt;
    // Skan zaczyna zmianę i loguje w panelu na komputerze, jeśli nikt inny nie użył tego kodu.
    // Kod z ekranu „Zakończ zmianę” kończy zmianę.
    // To samo okno od dołu co „Zakończyć zmianę?”.
    await showMessageSheet(
      context: context,
      icon: result.endedNow ? AppIcons.doorOpen : AppIcons.checkCircle,
      title: result.endedNow
          ? 'Zmiana zakończona'
          : result.startedNow
          ? 'Zmiana rozpoczęta'
          : 'Zmiana trwa',
      message: result.endedNow
          ? [
              '${result.restaurant}'
                  '${at == null || ended == null ? '' : ', ${hm(at)}–${hm(ended)} (${hoursText(ended.difference(at))} h)'}.',
              'Dobrego odpoczynku!',
            ].join('\n\n')
          : [
              result.startedNow
                  ? '${result.restaurant}, od ${at == null ? 'teraz' : hm(at)}.'
                  : 'Twoja zmiana w ${result.restaurant} trwa${at == null ? '' : ' od ${hm(at)}'}.',
              result.openedPanel
                  ? 'Jesteś zalogowany w panelu na komputerze. Panel wyloguje Cię sam po 30 sekundach bez ruchu.'
                  : 'Ktoś już zalogował się tym kodem. Żeby pracować przy komputerze, '
                        'zeskanuj nowy kod albo wpisz swój czterocyfrowy kod.',
            ].join('\n\n'),
    );
    // Dostawca w lokalu z flotą: przed pierwszym kursem przebieg i zdjęcia auta.
    if (result.endedNow || !mounted) return;
    final jobs = await ref.read(jobsProvider.future);
    final job = jobs.where((j) => j.working && j.restaurantName == result.restaurant).firstOrNull;
    if (job == null || !job.permissions.contains('deliveries') || !mounted) return;
    final status = await ref.read(vehicleStatusProvider(job.memberId).future);
    if (status.needsStart && mounted) await VehicleCheckScreen.open(context, job, end: false);
  }

  Future<void> _end(Job job) async {
    // Okno od dołu jak w aplikacjach iOS (wzór od użytkownika): zakończenie w aplikacji albo kodem z panelu.
    final start = job.shiftStartedAt;
    final how = await showOptionSheet<_EndBy>(
      context: context,
      title: 'Zakończyć zmianę?',
      message: [
        job.restaurantName,
        if (start != null) 'od ${hm(start)}, ${hoursText(DateTime.now().difference(start))} h',
      ].join(' · '),
      options: [
        SheetOption(
          value: _EndBy.app,
          icon: AppIcons.doorOpen,
          title: 'Zakończ w aplikacji',
          subtitle: 'Zmiana skończy się od razu',
          color: AppColors.error,
        ),
        const SheetOption(
          value: _EndBy.scan,
          icon: AppIcons.qrCode,
          title: 'Zeskanuj kod z panelu',
          subtitle: 'Kod z „Zakończ zmianę” na komputerze w lokalu',
        ),
      ],
    );
    if (how == null || !mounted) return;
    // Dostawca z autem z floty: przed końcem zmiany przebieg i zdjęcia auta.
    if (job.permissions.contains('deliveries')) {
      try {
        final status = await ref.read(vehicleStatusProvider(job.memberId).future);
        if (status.needsEnd) {
          if (!mounted) return;
          final done = await VehicleCheckScreen.open(context, job, end: true);
          if (!done) return;
        }
      } catch (_) {
        // Bez połączenia ze stanem auta i tak pozwalamy zakończyć zmianę.
      }
    }
    if (how == _EndBy.scan) {
      if (mounted) await _scan();
      return;
    }
    try {
      await ref.read(staffRepositoryProvider).endShift(job.memberId);
      _refresh();
      final end = DateTime.now();
      if (mounted) {
        await showMessageSheet(
          context: context,
          icon: AppIcons.doorOpen,
          title: 'Zmiana zakończona',
          message: [
            '${job.restaurantName}'
                '${start == null ? '' : ', ${hm(start)}–${hm(end)} (${hoursText(end.difference(start))} h)'}.',
            'Dobrego odpoczynku!',
          ].join('\n\n'),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final jobs = ref.watch(jobsProvider);
    final codes = ref.watch(codesProvider).value ?? const <String, String>{};
    final phone = ref.watch(accountProvider).value?.phone;
    final list = jobs.value ?? const <Job>[];
    final working = list.where((j) => j.working).firstOrNull;
    final announcements = ref.watch(announcementsProvider).value ?? const <StaffAnnouncement>[];

    return Scaffold(
      appBar: AppBar(
        leading: glassLeading(context),
        title: const Text('Zeskanuj'),
        actions: [IconButton(tooltip: 'Odśwież', onPressed: _refresh, icon: const Glyph(AppIcons.refresh, size: 20))],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: jobs.when(
          skipLoadingOnReload: true,
          loading: () => const CardsSkeleton(count: 2, top: 72),
          error: (e, _) => ErrorView(error: e, onRetry: _refresh),
          data: (list) => list.isEmpty
              ? ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: MessageView(
                        icon: AppIcons.userMinus,
                        title: 'Nie jesteś jeszcze na liście pracowników',
                        message:
                            'Poproś kierownika, żeby w panelu Table dodał Cię w zakładce „Pracownicy” '
                            'z numerem ${phone == null ? 'telefonu, którym się logujesz' : '+$phone'}.',
                        actionLabel: 'Sprawdź ponownie',
                        onAction: _refresh,
                      ),
                    ),
                  ],
                )
              : ContentWidth(
                  child: ListView(
                    // Ostatnia karta nad pływającym dolnym menu.
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text('Cześć, ${list.first.memberName.split(' ').first}!', style: text.headlineMedium),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          working == null
                              ? 'Zeskanuj kod w lokalu, żeby zacząć zmianę.'
                              : 'Jesteś w pracy w ${working.restaurantName} od ${hm(working.shiftStartedAt!)}.',
                          style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (announcements.isNotEmpty) ...[
                        AnnouncementsCard(
                          announcements: announcements,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(builder: (_) => const AnnouncementsScreen()),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      for (final job in list) ...[
                        _JobCard(
                          job: job,
                          code: codes[job.memberId],
                          onEnd: () => _end(job),
                          onOrders: widget.onOrders,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
        ),
      ),
      // Główne działanie zakładki na stałe na dole, w zasięgu kciuka.
      bottomNavigationBar: list.isEmpty
          ? null
          : BottomActionBar(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                onPressed: _scan,
                icon: const Glyph(AppIcons.qrCode, size: 22),
                label: Text(working != null ? 'Zeskanuj kod' : 'Zeskanuj kod i zacznij zmianę'),
              ),
            ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.code, required this.onEnd, required this.onOrders});

  final Job job;

  /// Mój czterocyfrowy kod do panelu na komputerze.
  final String? code;
  final VoidCallback onEnd;
  final VoidCallback onOrders;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final started = job.shiftStartedAt;
    final running = started == null ? null : DateTime.now().difference(started);
    final week = Duration(seconds: job.weekSeconds);
    final status = job.working
        ? StatusChip(label: 'W pracy', icon: AppIcons.briefcase, color: AppColors.accent)
        : StatusChip(label: 'Poza pracą', icon: AppIcons.moon, color: AppColors.textMuted);
    final summary = [
      job.restaurantName,
      ?job.position,
      if (started != null) 'w pracy od ${hm(started)}, ${hoursSpoken(running!)}' else 'poza pracą',
      'w tym tygodniu ${hoursSpoken(week)}',
    ].join(', ');

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: summary,
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconTile(AppIcons.storefront, active: job.working),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(job.restaurantName, style: text.titleMedium),
                            if (job.position != null)
                              Text(job.position!, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                            const SizedBox(height: 6),
                            status,
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Kafle tej samej wysokości także wtedy, gdy podpis zawija się przy dużej czcionce.
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (started != null) ...[
                          Expanded(
                            child: StatTile(
                              label: 'Ta zmiana',
                              value: '${hoursText(running!)} h',
                              caption: 'od ${hm(started)}',
                              icon: AppIcons.timer,
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: StatTile(
                            label: 'Ten tydzień',
                            value: '${hoursText(week)} h',
                            caption: started == null ? 'bez trwającej zmiany' : 'z trwającą zmianą',
                            icon: AppIcons.calendarDots,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (code != null) ...[const SizedBox(height: 10), _CodeRow(code: code!)],
            // Spis składników z telefonu, także poza zmianą.
            if (job.permissions.contains('inventory_count')) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: AppColors.ringStrong),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => InventoryScreen(job: job)),
                ),
                icon: const Glyph(AppIcons.clipboardText, size: 18),
                label: const Text('Inwentaryzacja'),
              ),
            ],
            // Kelner nabija zamówienia z telefonu, ale tylko w trakcie zmiany. Przyciski jeden pod drugim:
            // „Zakończ zmianę” w połowie szerokości łamie się już przy czcionce telefonu powiększonej o 15%.
            if (job.working) ...[
              const SizedBox(height: 14),
              if (job.canTakeOrders) ...[
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: onOrders,
                  icon: const Glyph(AppIcons.receipt, size: 18),
                  label: const Text('Zamówienia'),
                ),
                const SizedBox(height: 8),
              ],
              _EndButton(onPressed: onEnd),
            ] else if (job.canTakeOrders) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Glyph(AppIcons.info, size: 16, color: AppColors.textMuted),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Zamówienia nabijesz po rozpoczęciu zmiany.',
                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EndButton extends StatelessWidget {
  const _EndButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(48),
      side: BorderSide(color: AppColors.ringStrong),
    ),
    onPressed: onPressed,
    icon: const Glyph(AppIcons.doorOpen, size: 18),
    label: const Text('Zakończ zmianę'),
  );
}

/// Mój czterocyfrowy kod do panelu na komputerze, cyfry z odstępami.
class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: 'Mój kod do panelu: ${code.split('').join(' ')}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.ring),
        ),
        child: Row(
          children: [
            Glyph(AppIcons.monitor, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Mój kod do panelu', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
            ),
            Text(code, style: text.titleLarge?.copyWith(letterSpacing: 4, fontFeatures: _tabular)),
          ],
        ),
      ),
    );
  }
}

/// Jak pracownik kończy zmianę: od razu w aplikacji albo kodem QR z „Zakończ zmianę” w panelu.
enum _EndBy { app, scan }

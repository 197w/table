import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'scan_screen.dart';

const _tabular = [FontFeature.tabularFigures()];

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// Czas trwania jako „7:45”.
String _hours(Duration d) => '${d.inMinutes ~/ 60}:${_two(d.inMinutes % 60)}';

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
      ..invalidate(codesProvider);
  }

  Future<void> _scan() async {
    final result = await Navigator.push<ScanResult>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (result == null || !mounted) return;
    _refresh();
    final at = result.startedAt;
    // Skan zaczyna zmianę i loguje w panelu na komputerze, jeśli nikt inny nie użył tego kodu.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Glyph(AppIcons.checkCircle, size: 40, color: AppColors.accent),
        title: Text(result.startedNow ? 'Zmiana rozpoczęta' : 'Zmiana trwa'),
        content: Text(
          [
            result.startedNow
                ? '${result.restaurant}, od ${at == null ? 'teraz' : _hm(at)}.'
                : 'Twoja zmiana w ${result.restaurant} trwa${at == null ? '' : ' od ${_hm(at)}'}.',
            result.openedPanel
                ? 'Jesteś zalogowany w panelu na komputerze. Po pracy wyloguj się tam ręcznie.'
                : 'Ktoś już zalogował się tym kodem. Żeby pracować przy komputerze, '
                      'zeskanuj nowy kod albo wpisz swój czterocyfrowy kod.',
          ].join('\n\n'),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Gotowe'),
          ),
        ],
      ),
    );
  }

  Future<void> _end(Job job) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zakończyć zmianę?'),
        content: Text('Kończysz pracę w ${job.restaurantName}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Zakończ')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(staffRepositoryProvider).endShift(job.memberId);
      _refresh();
      if (mounted) showMessage(context, 'Zmiana zakończona. Dobrego odpoczynku!');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final jobs = ref.watch(jobsProvider);
    final codes = ref.watch(codesProvider).value ?? const <String, String>{};
    final phone = ref.watch(staffRepositoryProvider).phone;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Zeskanuj'),
        actions: [
          IconButton(tooltip: 'Odśwież', onPressed: _refresh, icon: const Glyph(AppIcons.refresh, size: 20)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: jobs.when(
          skipLoadingOnReload: true,
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(error: e, onRetry: _refresh),
          data: (list) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              if (list.isEmpty)
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
                )
              else ...[
                Text('Cześć, ${list.first.memberName.split(' ').first}!', style: text.headlineSmall),
                const SizedBox(height: 16),
                for (final job in list) ...[
                  _JobCard(
                    job: job,
                    code: codes[job.memberId],
                    onEnd: () => _end(job),
                    onOrders: widget.onOrders,
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 4),
                SizedBox(
                  height: 60,
                  child: FilledButton.icon(
                    onPressed: _scan,
                    icon: const Glyph(AppIcons.squaresFour, size: 22),
                    label: Text(
                      list.any((j) => j.working) ? 'Zeskanuj kod' : 'Zeskanuj kod i zacznij zmianę',
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ],
            ],
          ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job.restaurantName, style: text.titleMedium),
                      if (job.position != null)
                        Text(job.position!, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                      if (code != null)
                        Text(
                          'Mój kod do panelu: $code',
                          style: text.bodyMedium?.copyWith(fontFeatures: _tabular, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: job.working ? AppColors.accentTint : AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    job.working ? 'W pracy' : 'Poza pracą',
                    style: text.labelMedium?.copyWith(color: job.working ? AppColors.accent : AppColors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              started == null
                  ? 'W tym tygodniu: ${_hours(Duration(seconds: job.weekSeconds))} h'
                  : 'Od ${_hm(started)} · ${_hours(running!)} h\nW tym tygodniu: ${_hours(Duration(seconds: job.weekSeconds))} h',
              style: text.bodyLarge?.copyWith(fontFeatures: _tabular),
            ),
            // Kelner nabija zamówienia z telefonu, ale tylko w trakcie zmiany.
            if (job.canTakeOrders) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: job.working ? onOrders : null,
                icon: const Glyph(AppIcons.receipt, size: 20),
                label: Text(job.working ? 'Zamówienia' : 'Zamówienia po rozpoczęciu zmiany'),
              ),
            ],
            // Przyciski w motywie Table zajmują całą szerokość, więc kończenie zmiany ma własny wiersz.
            if (job.working) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: onEnd, child: const Text('Zakończ zmianę')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Moje zmiany z ostatniego miesiąca, dzień po dniu, z sumą.

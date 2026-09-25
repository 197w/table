import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'scan_screen.dart';
import 'waiter_screens.dart';

const _tabular = [FontFeature.tabularFigures()];

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// Czas trwania jako „7:45”.
String _hours(Duration d) => '${d.inMinutes ~/ 60}:${_two(d.inMinutes % 60)}';

/// Ekran główny: lokale, w których pracuję, przycisk skanowania i moje godziny.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

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
      ..invalidate(shiftsProvider);
  }

  Future<void> _scan() async {
    final result = await Navigator.push<ScanResult>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (result == null || !mounted) return;
    _refresh();
    final at = result.startedAt;
    // Kod jest wspólny dla całej zmiany. Panel na komputerze otwiera się dopiero na życzenie.
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Glyph(AppIcons.checkCircle, size: 40, color: AppColors.accent),
        title: Text(result.startedNow ? 'Zmiana rozpoczęta' : 'Zmiana trwa'),
        content: Text(
          result.startedNow
              ? '${result.restaurant}, od ${at == null ? 'teraz' : _hm(at)}.'
              : 'Twoja zmiana w ${result.restaurant} trwa${at == null ? '' : ' od ${_hm(at)}'}.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Otwórz panel na komputerze')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Gotowe'),
          ),
        ],
      ),
    );
    if (open != true || !mounted) return;
    try {
      await ref.read(staffRepositoryProvider).openPanel(result.token);
      if (mounted) showMessage(context, 'Panel na komputerze otworzył się na Twoje konto.');
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
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
      if (mounted) showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final jobs = ref.watch(jobsProvider);
    final shifts = ref.watch(shiftsProvider).value ?? const <Shift>[];
    final phone = ref.watch(staffRepositoryProvider).phone;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Table for workers'),
        actions: [
          IconButton(tooltip: 'Odśwież', onPressed: _refresh, icon: const Glyph(AppIcons.refresh, size: 20)),
          IconButton(
            tooltip: 'Wyloguj się',
            onPressed: () => ref.read(staffRepositoryProvider).signOut(),
            icon: const Glyph(AppIcons.signOut, size: 20),
          ),
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
                    onEnd: () => _end(job),
                    onOrders: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => WaiterTablesScreen(job: job)),
                    ),
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
                      list.any((j) => j.working) ? 'Zeskanuj kod z panelu' : 'Zeskanuj kod i zacznij zmianę',
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _History(shifts: shifts),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job, required this.onEnd, required this.onOrders});

  final Job job;
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
class _History extends StatelessWidget {
  const _History({required this.shifts});

  final List<Shift> shifts;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = shifts.fold(Duration.zero, (sum, s) => sum + s.duration);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Moje godziny', style: text.titleMedium)),
            Text(
              '31 dni: ${_hours(total)} h',
              style: text.titleSmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (shifts.isEmpty)
          Text('Tu pojawią się Twoje zmiany.', style: text.bodyMedium?.copyWith(color: AppColors.textMuted))
        else
          for (final s in shifts)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.ring))),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(Fmt.capitalize(Fmt.dayShort(s.startedAt)), style: text.bodyLarge),
                        Text(
                          '${s.restaurantName} · ${_hm(s.startedAt)}–${s.endedAt == null ? 'trwa' : _hm(s.endedAt!)}',
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                      ],
                    ),
                  ),
                  Text('${_hours(s.duration)} h', style: text.titleSmall?.copyWith(fontFeatures: _tabular)),
                ],
              ),
            ),
      ],
    );
  }
}

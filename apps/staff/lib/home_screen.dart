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
      ..invalidate(shiftsProvider)
      ..invalidate(scheduleProvider)
      ..invalidate(loginsProvider);
  }

  Future<void> _scan() async {
    final result = await Navigator.push<ScanResult>(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    if (result == null || !mounted) return;
    _refresh();
    final at = result.startedAt;
    // Skan zaczyna zmianę i loguje na głównym stanowisku, jeśli nikt inny nie użył tego kodu.
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
                ? 'Jesteś zalogowany na głównym stanowisku. Po pracy wyloguj się tam ręcznie.'
                : 'Na stanowisku ktoś już zalogował się tym kodem. Żeby pracować przy komputerze, '
                      'zeskanuj nowy kod albo wpisz login i hasło.',
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

  Future<void> _answer(PlannedShift shift, {required bool accept}) async {
    final repo = ref.read(staffRepositoryProvider);
    try {
      if (accept) {
        await repo.answerShift(shift.id, accept: true);
        if (mounted) showMessage(context, 'Przyjęte: ${shift.starts}–${shift.ends}.');
      } else {
        final change = await showModalBottomSheet<({String starts, String ends, String reply})>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => _ChangeSheet(shift: shift),
        );
        if (change == null) return;
        await repo.answerShift(shift.id, accept: false, starts: change.starts, ends: change.ends, reply: change.reply);
        if (mounted) showMessage(context, 'Wysłano propozycję: ${change.starts}–${change.ends}.');
      }
      ref.invalidate(scheduleProvider);
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
    final schedule = ref.watch(scheduleProvider).value ?? const <PlannedShift>[];
    final logins = ref.watch(loginsProvider).value ?? const <String, String>{};
    final phone = ref.watch(staffRepositoryProvider).phone;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Table for employees'),
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
                    login: logins[job.memberId],
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
                _Schedule(
                  shifts: schedule,
                  onAccept: (s) => _answer(s, accept: true),
                  onChange: (s) => _answer(s, accept: false),
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
  const _JobCard({required this.job, required this.login, required this.onEnd, required this.onOrders});

  final Job job;

  /// Login do głównego stanowiska. Null: przełożony jeszcze go nie utworzył.
  final String? login;
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
                      Text(
                        login == null ? 'Bez loginu do stanowiska' : 'Login do stanowiska: $login',
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
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

/// Mój grafik: godziny zaproponowane przez przełożonego. Przyjmuję je albo proponuję inne.
class _Schedule extends StatelessWidget {
  const _Schedule({required this.shifts, required this.onAccept, required this.onChange});

  final List<PlannedShift> shifts;
  final ValueChanged<PlannedShift> onAccept;
  final ValueChanged<PlannedShift> onChange;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final waiting = shifts.where((s) => s.waiting).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Mój grafik', style: text.titleMedium)),
            if (waiting > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: AppColors.accentTint, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  waiting == 1 ? '1 nowa propozycja' : 'Nowe propozycje: $waiting',
                  style: text.labelMedium?.copyWith(color: AppColors.accent),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (shifts.isEmpty)
          Text(
            'Tu pojawią się godziny, które zaproponuje Ci przełożony.',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          )
        else
          for (final s in shifts)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.ring))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Fmt.capitalize(Fmt.dayShort(s.day)), style: text.bodyLarge),
                            Text(
                              '${s.restaurantName} · ${s.starts}–${s.ends}',
                              style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                            ),
                          ],
                        ),
                      ),
                      Glyph(
                        s.accepted ? AppIcons.checkCircle : (s.changed ? AppIcons.chatText : AppIcons.clock),
                        size: 18,
                        color: s.accepted ? AppColors.accent : AppColors.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        s.accepted ? 'Przyjęte' : (s.changed ? 'Wysłano zmianę' : 'Do decyzji'),
                        style: text.labelMedium?.copyWith(
                          color: s.accepted ? AppColors.accent : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (s.note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Uwagi: ${s.note}', style: text.bodySmall),
                    ),
                  if (s.changed)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Proponujesz ${s.changeStarts}–${s.changeEnds}${s.reply == null ? '' : ': „${s.reply}”'}',
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                      ),
                    ),
                  if (!s.accepted) ...[
                    const SizedBox(height: 10),
                    // Przyciski w motywie Table zajmują całą szerokość, więc w wierszu dostają Expanded.
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                            onPressed: () => onAccept(s),
                            child: const Text('Przyjmij'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                            onPressed: () => onChange(s),
                            child: const Text('Inne godziny'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}

/// Moja propozycja innych godzin w danym dniu.
class _ChangeSheet extends StatefulWidget {
  const _ChangeSheet({required this.shift});

  final PlannedShift shift;

  @override
  State<_ChangeSheet> createState() => _ChangeSheetState();
}

class _ChangeSheetState extends State<_ChangeSheet> {
  late TimeOfDay _starts = _parse(widget.shift.changeStarts ?? widget.shift.starts);
  late TimeOfDay _ends = _parse(widget.shift.changeEnds ?? widget.shift.ends);
  late final _reply = TextEditingController(text: widget.shift.reply ?? '');

  static TimeOfDay _parse(String hm) {
    final p = hm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  static String _fmt(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _starts : _ends,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) setState(() => start ? _starts = picked : _ends = picked);
  }

  void _send() {
    if (_ends.hour * 60 + _ends.minute <= _starts.hour * 60 + _starts.minute) {
      showMessage(context, 'Koniec musi być później niż początek.');
      return;
    }
    Navigator.pop(context, (starts: _fmt(_starts), ends: _fmt(_ends), reply: _reply.text));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Klawiatura albo przyciski systemu Androida: okno kończy się nad tym, co jest wyżej.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final system = MediaQuery.viewPaddingOf(context).bottom;
    Widget time(TimeOfDay t, bool start) => Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 52)),
        onPressed: () => _pick(start),
        child: Text(_fmt(t), style: const TextStyle(fontSize: 18, fontFeatures: _tabular)),
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + (keyboard > system ? keyboard : system)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Inne godziny', style: text.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${Fmt.capitalize(Fmt.dayShort(widget.shift.day))}. Przełożony proponuje '
              '${widget.shift.starts}–${widget.shift.ends}.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                time(_starts, true),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('–', style: text.titleMedium),
                ),
                time(_ends, false),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reply,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Wiadomość (opcjonalnie)', hintText: 'Na przykład: rano mam zajęcia'),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _send, child: const Text('Wyślij propozycję')),
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

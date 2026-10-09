import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'ui.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Ustawienia: moje konto, lokale z kodami do panelu i wylogowanie. Układ jak w aplikacji dla gości.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wylogować się?'),
        content: const Text('Żeby wrócić, zalogujesz się ponownie numerem telefonu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Anuluj')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Wyloguj'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(staffRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final phone = ref.watch(staffRepositoryProvider).phone;
    final jobs = ref.watch(jobsProvider).value ?? const <Job>[];
    final codes = ref.watch(codesProvider).value ?? const <String, String>{};
    final name = jobs.firstOrNull?.memberName;

    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // Konto: okrągły znak z inicjałem, imię i numer, którym się logujesz.
            Semantics(
              label: [?name, 'numer telefonu ${phone == null ? 'nieznany' : Fmt.phone(phone)}'].join(', '),
              excludeSemantics: true,
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.accentTint, shape: BoxShape.circle),
                        child: name == null || name.isEmpty
                            ? Glyph(AppIcons.userCheck.duotone, size: 24, color: AppColors.accent)
                            : Text(
                                name.characters.first.toUpperCase(),
                                style: text.titleLarge?.copyWith(color: AppColors.accent),
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name ?? 'Pracownik', style: text.titleMedium),
                            Text(
                              phone == null ? 'Brak numeru' : Fmt.phone(phone),
                              style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            _Group(
              title: 'Moje lokale',
              footer: jobs.isEmpty
                  ? 'Nie jesteś jeszcze na liście pracowników żadnego lokalu.'
                  : 'Kod wpisujesz w panelu na komputerze, gdy nie masz przy sobie telefonu.',
              children: [for (final job in jobs) _JobRow(job: job, code: codes[job.memberId])],
            ),
            const SizedBox(height: 24),
            _Group(
              title: 'Aplikacja',
              children: [
                _Row(
                  icon: AppIcons.refresh,
                  title: 'Odśwież dane',
                  onTap: () {
                    ref
                      ..invalidate(jobsProvider)
                      ..invalidate(shiftsProvider)
                      ..invalidate(codesProvider)
                      ..invalidate(schedulePeriodProvider);
                    showMessage(context, 'Odświeżono.');
                  },
                ),
                _Row(
                  icon: AppIcons.signOut,
                  title: 'Wyloguj się',
                  destructive: true,
                  onTap: () => _signOut(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Grupa wierszy na jednej karcie z nagłówkiem i opisem pod spodem.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children, this.footer});

  final String title;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Semantics(
            header: true,
            child: Text(
              title.toUpperCase(),
              style: text.labelSmall?.copyWith(
                color: AppColors.textMuted,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (children.isNotEmpty)
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 62, color: AppColors.ring),
                  children[i],
                ],
              ],
            ),
          ),
        if (footer != null)
          Padding(
            padding: EdgeInsets.fromLTRB(6, children.isEmpty ? 0 : 8, 6, 0),
            child: Text(footer!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
          ),
      ],
    );
  }
}

/// Lokal: nazwa, stanowisko i czterocyfrowy kod do panelu.
class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.code});

  final Job job;
  final String? code;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: [
        job.restaurantName,
        ?job.position,
        code == null ? 'bez kodu do panelu' : 'kod do panelu: ${code!.split('').join(' ')}',
      ].join(', '),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          child: Row(
            children: [
              IconTile(AppIcons.storefront, size: 36, active: job.working),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.restaurantName, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
                    if (job.position != null)
                      Text(job.position!, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Krótki podpis, żeby nazwa lokalu się mieściła; co to za kod, mówi opis pod kartą.
                  Text('Kod', style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
                  Text(code ?? '—', style: text.titleLarge?.copyWith(letterSpacing: 4, fontFeatures: _tabular)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wiersz z działaniem (bez strzałki, bo nie prowadzi do podstrony): co najmniej 56 px wysokości,
/// nazwa przechodzi do drugiej linii zamiast się ucinać.
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.onTap, this.destructive = false});

  final AppIconData icon;
  final String title;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = destructive ? AppColors.error : AppColors.accent;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: AppColors.ring,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: destructive ? AppColors.error.withValues(alpha: 0.12) : AppColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Glyph(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: destructive ? AppColors.error : AppColors.text,
                    ),
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

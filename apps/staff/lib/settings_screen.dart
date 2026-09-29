import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';

/// Ustawienia: moje konto, lokale z kodami do panelu i wylogowanie.
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
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
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

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        title.toUpperCase(),
        style: text.labelMedium?.copyWith(color: AppColors.textMuted, letterSpacing: 1),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          section('Konto'),
          Card(
            child: ListTile(
              leading: const Glyph(AppIcons.phone, size: 22),
              title: const Text('Numer telefonu'),
              subtitle: Text(phone == null ? '—' : '+$phone'),
            ),
          ),
          section('Moje lokale'),
          if (jobs.isEmpty)
            Text(
              'Nie jesteś jeszcze na liście pracowników żadnego lokalu.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            )
          else
            for (final job in jobs)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
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
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Kod do panelu', style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
                          Text(
                            codes[job.memberId] ?? '—',
                            style: text.headlineSmall?.copyWith(
                              letterSpacing: 4,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          section('Aplikacja'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Glyph(AppIcons.refresh, size: 22),
                  title: const Text('Odśwież dane'),
                  onTap: () {
                    ref
                      ..invalidate(jobsProvider)
                      ..invalidate(shiftsProvider)
                      ..invalidate(codesProvider)
                      ..invalidate(scheduleMonthProvider);
                    showMessage(context, 'Odświeżono.');
                  },
                ),
                Divider(height: 1, color: AppColors.ring),
                ListTile(
                  leading: Glyph(AppIcons.signOut, size: 22, color: AppColors.error),
                  title: Text('Wyloguj się', style: TextStyle(color: AppColors.error)),
                  onTap: () => _signOut(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

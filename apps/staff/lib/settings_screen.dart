import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/settings_list.dart';
import 'package:table_core/table_core.dart';

import 'data.dart';
import 'login_screen.dart';
import 'ui.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Konto: moje konto, lokale z kodami do panelu, motyw i wylogowanie. Układ i wiersze jak w Koncie aplikacji Table
/// (`package:table_core/settings_list.dart`, 10.11.2026), bez opisów pod grupami.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// Strona „Motyw” jest otwarta. Zmiana motywu buduje aplikację od nowa (klucz z jasnością w `main.dart`), więc
  /// Konto otwiera ją z powrotem bez animacji, jak w Table, gdzie strona zostaje po wyborze.
  static bool _themeOpen = false;

  @override
  void initState() {
    super.initState();
    if (_themeOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openTheme(animate: false);
      });
    }
  }

  Future<void> _openTheme({bool animate = true}) async {
    _themeOpen = true;
    await Navigator.of(context).push(
      animate
          ? MaterialPageRoute<void>(builder: (_) => const ThemeSettingsScreen())
          : PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: const Duration(milliseconds: 300),
              pageBuilder: (_, _, _) => const ThemeSettingsScreen(),
            ),
    );
    if (mounted) _themeOpen = false;
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmSheet(
      context: context,
      title: 'Wylogować się?',
      message: 'Żeby wrócić, zalogujesz się ponownie e-mailem, kodem z e-maila i hasłem.',
      icon: AppIcons.signOut,
      action: 'Wyloguj się',
      color: AppColors.error,
    );
    if (ok) await ref.read(staffRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final account = ref.watch(accountProvider).value;
    final phone = account?.phone;
    final email = account?.email;
    final jobs = ref.watch(jobsProvider).value ?? const <Job>[];
    final codes = ref.watch(codesProvider).value ?? const <String, String>{};
    final name = jobs.firstOrNull?.memberName;
    final theme = ref.watch(themeSettingProvider);

    return Scaffold(
      appBar: AppBar(leading: glassLeading(context), title: const Text('Konto')),
      body: ContentWidth(
        child: ListView(
          // „Wyloguj się” nad pływającym dolnym menu.
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
          children: [
            // Konto: okrągły znak z inicjałem, imię i numer, którym się logujesz.
            Semantics(
              label: [
                ?name,
                'numer telefonu ${phone == null ? 'nieznany' : Fmt.phone(phone)}',
                if (email != null && email.isNotEmpty) 'e-mail $email',
              ].join(', '),
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
                            if (email != null && email.isNotEmpty)
                              Text(email, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Stare konto z logowania SMS: e-mail do logowania.
            if (account != null && (email == null || email.isEmpty)) ...[
              const SizedBox(height: 24),
              SettingsGroup(
                title: 'Logowanie',
                children: [
                  SettingsRow(
                    icon: AppIcons.envelope,
                    title: 'Dodaj e-mail',
                    onTap: () =>
                        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AddEmailScreen())),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            _Group(
              title: 'Moje lokale',
              footer: jobs.isEmpty ? 'Nie jesteś jeszcze na liście pracowników żadnego lokalu.' : null,
              children: [for (final job in jobs) _JobRow(job: job, code: codes[job.memberId])],
            ),
            const SizedBox(height: 20),
            // Motyw jak w Table: osobna strona z wyborem (10.11.2026, prośba użytkownika).
            SettingsGroup(
              children: [
                SettingsRow(icon: theme.icon, title: 'Motyw', value: theme.label, onTap: _openTheme),
              ],
            ),
            const SizedBox(height: 20),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: AppIcons.refresh,
                  title: 'Odśwież dane',
                  showChevron: false,
                  onTap: () {
                    ref
                      ..invalidate(jobsProvider)
                      ..invalidate(shiftsProvider)
                      ..invalidate(codesProvider)
                      ..invalidate(schedulePeriodProvider);
                    showMessage(context, 'Odświeżono.');
                  },
                ),
                SettingsRow(
                  icon: AppIcons.signOut,
                  title: 'Wyloguj się',
                  destructive: true,
                  showChevron: false,
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
                  // Krótki podpis, żeby nazwa lokalu się mieściła.
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

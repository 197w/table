import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../app/preferences.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'settings_widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(userIdProvider) != null;
    final profile = loggedIn ? ref.watch(profileProvider).value : null;
    final version = ref.watch(appVersionProvider).value;
    final theme = ref.watch(themeSettingProvider);
    final language = ref.watch(languageProvider);
    final unit = ref.watch(distanceUnitProvider);

    void open(String route, {bool needsAccount = false}) {
      if (needsAccount && !loggedIn) {
        context.push(AppRoutes.withNext(AppRoutes.login, route));
      } else {
        context.push(route);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _AccountHeader(
            profile: profile,
            loggedIn: loggedIn,
            onTap: () => open(AppRoutes.accountDetails, needsAccount: true),
          ),
          const SizedBox(height: 20),
          SettingsGroup(
            children: [
              // Bieżące wybory widać od razu, bez wchodzenia w podstronę.
              SettingsRow(
                icon: AppIcons.sliders,
                title: 'Ogólne',
                value: '${language.label} · ${unit.short}',
                onTap: () => open(AppRoutes.settingsGeneral),
              ),
              SettingsRow(
                icon: theme.icon,
                title: 'Motyw',
                value: theme.label,
                onTap: () => open(AppRoutes.settingsTheme),
              ),
              SettingsRow(
                icon: AppIcons.bell,
                title: 'Powiadomienia',
                locked: !loggedIn,
                onTap: () =>
                    open(AppRoutes.settingsNotifications, needsAccount: true),
              ),
              SettingsRow(
                icon: AppIcons.question,
                title: 'Pomoc',
                onTap: () => open(AppRoutes.settingsHelp),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SettingsGroup(
            children: [
              SettingsRow(
                icon: AppIcons.userGear,
                title: 'Konto i logowanie',
                locked: !loggedIn,
                onTap: () =>
                    open(AppRoutes.settingsAccount, needsAccount: true),
              ),
              SettingsRow(
                icon: AppIcons.wrench,
                title: 'Zaawansowane',
                locked: !loggedIn,
                onTap: () =>
                    open(AppRoutes.settingsAdvanced, needsAccount: true),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            version == null
                ? 'Table · wersja testowa'
                : 'Table $version · wersja testowa',
            textAlign: TextAlign.center,
            // Przygaszony, ale czytelny (kontrast co najmniej 4,5:1).
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.profile,
    required this.loggedIn,
    required this.onTap,
  });

  final Profile? profile;
  final bool loggedIn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    if (!loggedIn) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.accentTint, shape: BoxShape.circle),
                  child: Glyph(AppIcons.signIn.duotone, size: 24, color: AppColors.accent),
                ),
              ),
              const SizedBox(height: 12),
              Text('Nie jesteś zalogowany', style: text.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Zaloguj się, żeby rezerwować stoliki, dodawać opinie i zarządzać powiadomieniami.',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onTap, child: const Text('Zaloguj się')),
            ],
          ),
        ),
      );
    }

    final name = profile?.firstName?.trim();
    final hasName = name != null && name.isNotEmpty;
    final initial = hasName ? name.characters.first.toUpperCase() : '?';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: AppColors.ring,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Znak w rogu karty: promień 8 = promień karty 22 minus odstęp 14.
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accentTint, shape: BoxShape.circle),
                child: Text(
                  initial,
                  style: text.titleLarge?.copyWith(color: AppColors.accent),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasName ? name : 'Dodaj swoje imię',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Fmt.phone(profile?.phone),
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text('Dane konta', style: text.bodySmall?.copyWith(color: AppColors.accent)),
                  ],
                ),
              ),
              Glyph(AppIcons.caretRight, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

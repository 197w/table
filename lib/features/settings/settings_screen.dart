import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app.dart';
import '../../app/preferences.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'settings_widgets.dart';
import '../../shared/app_icons.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(userIdProvider) != null;
    final profile = loggedIn ? ref.watch(profileProvider).value : null;
    final version = ref.watch(appVersionProvider).value;

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
              SettingsRow(
                icon: AppIcons.sliders,
                title: 'Ogólne',
                onTap: () => open(AppRoutes.settingsGeneral),
              ),
              SettingsRow(
                icon: AppIcons.circleHalf,
                title: 'Motyw',
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
                ? 'Rarytka · wersja testowa'
                : 'Rarytka $version · wersja testowa',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textDisabled),
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
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(8),
                ),
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
                  ],
                ),
              ),
              Glyph(
                AppIcons.caretRight,
                size: 18,
                color: AppColors.textDisabled,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

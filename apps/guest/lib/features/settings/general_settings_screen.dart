import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/preferences.dart';
import 'settings_widgets.dart';

class GeneralSettingsScreen extends ConsumerWidget {
  const GeneralSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final unit = ref.watch(distanceUnitProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Ogólne')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsGroup(
            title: 'Język',
            children: [
              for (final option in AppLanguage.values)
                SettingsChoiceRow(
                  title: option.label,
                  selected: option == language,
                  onTap: () => ref.read(languageProvider.notifier).set(option),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SettingsGroup(
            title: 'Jednostki odległości',
            footer:
                'Dotyczy odległości do lokali i promienia wyszukiwania w pobliżu.',
            children: [
              for (final option in DistanceUnit.values)
                SettingsChoiceRow(
                  title: option.label,
                  selected: option == unit,
                  onTap: () =>
                      ref.read(distanceUnitProvider.notifier).set(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setting = ref.watch(themeSettingProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Motyw')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsGroup(
            footer:
                'Motyw systemowy zmienia się razem z ustawieniami telefonu.',
            children: [
              for (final option in AppThemeSetting.values)
                SettingsChoiceRow(
                  icon: option.icon,
                  title: option.label,
                  selected: option == setting,
                  onTap: () => ThemeFade.run(
                    context,
                    () => ref.read(themeSettingProvider.notifier).set(option),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'settings_widgets.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationPreferencesProvider);

    return SignedInOnly(
      title: 'Powiadomienia',
      next: AppRoutes.settingsNotifications,
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(notificationPreferencesProvider),
        ),
        data: (prefs) => prefs == null
            ? const LoadingView()
            : _NotificationForm(initial: prefs),
      ),
    );
  }
}

class _NotificationForm extends ConsumerStatefulWidget {
  const _NotificationForm({required this.initial});

  final NotificationPreferences initial;

  @override
  ConsumerState<_NotificationForm> createState() => _NotificationFormState();
}

class _NotificationFormState extends ConsumerState<_NotificationForm> {
  late NotificationPreferences _prefs = widget.initial;

  /// Przełącznik zmienia się od razu, a przy błędzie zapisu wraca do poprzedniej wartości.
  Future<void> _update(NotificationPreferences next) async {
    final previous = _prefs;
    setState(() => _prefs = next);
    try {
      await ref.read(repositoryProvider).saveNotificationPreferences(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _prefs = previous);
      showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        SettingsGroup(
          title: 'Rezerwacje',
          children: [
            SettingsSwitchRow(
              icon: AppIcons.alarm,
              title: 'Przypomnienia o wizycie',
              value: _prefs.reservationReminders,
              onChanged: (v) =>
                  _update(_prefs.copyWith(reservationReminders: v)),
            ),
            SettingsSwitchRow(
              icon: AppIcons.arrowsClockwise,
              title: 'Zmiany w rezerwacji',
              value: _prefs.reservationUpdates,
              onChanged: (v) => _update(_prefs.copyWith(reservationUpdates: v)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SettingsGroup(
          title: 'Opinie',
          children: [
            SettingsSwitchRow(
              icon: AppIcons.chatText,
              title: 'Prośba o opinię',
              value: _prefs.reviewRequests,
              onChanged: (v) => _update(_prefs.copyWith(reviewRequests: v)),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SettingsGroup(
          title: 'Inne',
          footer:
              'Nowości wysyłamy tylko za twoją zgodą. Możesz ją wycofać w każdej chwili.',
          children: [
            SettingsSwitchRow(
              icon: AppIcons.megaphone,
              title: 'Nowości w Table',
              subtitle: 'Nowe lokale i funkcje aplikacji',
              value: _prefs.news,
              onChanged: (v) => _update(_prefs.copyWith(news: v)),
            ),
          ],
        ),
      ],
    );
  }
}

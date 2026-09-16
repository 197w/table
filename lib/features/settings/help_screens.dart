import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app.dart';
import '../../app/preferences.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../shared/widgets.dart';
import 'settings_widgets.dart';
import '../../shared/app_icons.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pomoc')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                icon: AppIcons.bug,
                title: 'Zgłoś błąd',
                onTap: () => context.push(AppRoutes.reportBug),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ReportBugScreen extends ConsumerStatefulWidget {
  const ReportBugScreen({super.key});

  @override
  ConsumerState<ReportBugScreen> createState() => _ReportBugScreenState();
}

class _ReportBugScreenState extends ConsumerState<ReportBugScreen> {
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final message = _message.text.trim();
    if (message.length < 10) {
      showMessage(context, 'Opisz błąd w co najmniej 10 znakach.');
      return;
    }

    final platform = Theme.of(context).platform.name;
    setState(() => _sending = true);
    try {
      String version;
      try {
        version = await ref.read(appVersionProvider.future);
      } catch (_) {
        version = 'nieznana';
      }
      await ref
          .read(repositoryProvider)
          .reportBug(message: message, appVersion: version, platform: platform);
      if (!mounted) return;
      showMessage(
        context,
        'Dziękujemy. Zgłoszenie trafiło do zespołu Rarytki.',
      );
      context.pop();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Zgłoś błąd')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text('Co poszło nie tak?', style: text.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Opisz, co działo się tuż przed błędem i co zobaczyłeś na ekranie. '
            'Do zgłoszenia dołączymy wersję aplikacji i system telefonu.',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _message,
            minLines: 6,
            maxLines: 12,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Opis błędu',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _sending ? null : _send,
          child: const Text('Wyślij zgłoszenie'),
        ),
      ),
    );
  }
}

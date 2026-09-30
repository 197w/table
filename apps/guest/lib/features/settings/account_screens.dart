import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'settings_widgets.dart';

// ---------------------------------------------------------------
// Konto i logowanie
// ---------------------------------------------------------------

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final name = profile?.firstName?.trim();

    return SignedInOnly(
      title: 'Konto i logowanie',
      next: AppRoutes.settingsAccount,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                icon: AppIcons.identification,
                title: 'Szczegóły konta',
                value: (name == null || name.isEmpty) ? null : name,
                onTap: () => context.push(AppRoutes.accountDetails),
              ),
              SettingsRow(
                icon: AppIcons.lock,
                title: 'Informacje o logowaniu',
                onTap: () => context.push(AppRoutes.loginInfo),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// Szczegóły konta
// ---------------------------------------------------------------

class AccountDetailsScreen extends ConsumerWidget {
  const AccountDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider);
    return SignedInOnly(
      title: 'Szczegóły konta',
      next: AppRoutes.accountDetails,
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(profileProvider)),
        data: (profile) =>
            profile == null ? const LoadingView() : _NameForm(profile: profile),
      ),
    );
  }
}

class _NameForm extends ConsumerStatefulWidget {
  const _NameForm({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_NameForm> createState() => _NameFormState();
}

class _NameFormState extends ConsumerState<_NameForm> {
  late final _firstName = TextEditingController(
    text: widget.profile.firstName ?? '',
  );
  late final _fullName = TextEditingController(
    text: widget.profile.fullName ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _firstName.dispose();
    _fullName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .updateNames(firstName: _firstName.text, fullName: _fullName.text);
      ref.invalidate(profileProvider);
      if (mounted) showMessage(context, 'Zapisano.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        TextField(
          controller: _firstName,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.givenName],
          decoration: const InputDecoration(labelText: 'Imię'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 16),
          child: Text(
            'Widoczne dla innych gości przy twoich opiniach.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ),
        TextField(
          controller: _fullName,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(labelText: 'Imię i nazwisko'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 16),
          child: Text(
            'Widoczne tylko dla restauracji, w której rezerwujesz stolik. Nigdy przy opiniach.',
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Zapisz'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------
// Informacje o logowaniu
// ---------------------------------------------------------------

class LoginInfoScreen extends ConsumerWidget {
  const LoginInfoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final phone = ref.watch(profileProvider).value?.phone;

    return SignedInOnly(
      title: 'Informacje o logowaniu',
      next: AppRoutes.loginInfo,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsGroup(
            title: 'Numer telefonu',
            footer: 'Numer służy do logowania kodem SMS.',
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(
                  children: [
                    Glyph(
                      AppIcons.deviceMobile,
                      size: 18,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      Fmt.phone(phone),
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              SettingsRow(
                icon: AppIcons.phoneSwap,
                title: 'Zmień numer telefonu',
                onTap: () => context.push(AppRoutes.changePhone),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SettingsGroup(
            title: 'Hasło',
            children: [
              SettingsRow(
                icon: AppIcons.password,
                title: 'Zmień hasło',
                onTap: () => context.push(AppRoutes.changePassword),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------
// Zmiana hasła
// ---------------------------------------------------------------

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  String? _nextError;
  String? _repeatError;
  bool _busy = false;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final next = _next.text;
    setState(() {
      _nextError = next.length < 8
          ? 'Hasło musi mieć co najmniej 8 znaków.'
          : null;
      _repeatError = _repeat.text != next ? 'Hasła różnią się.' : null;
    });
    if (_current.text.isEmpty) {
      showMessage(context, 'Wpisz obecne hasło.');
      return;
    }
    if (_nextError != null || _repeatError != null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .changePassword(currentPassword: _current.text, newPassword: next);
      if (!mounted) return;
      showMessage(context, 'Hasło zostało zmienione.');
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SignedInOnly(
      title: 'Zmień hasło',
      next: AppRoutes.changePassword,
      body: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _PasswordInput(controller: _current, label: 'Obecne hasło'),
            const SizedBox(height: 16),
            _PasswordInput(
              controller: _next,
              label: 'Nowe hasło, co najmniej 8 znaków',
              errorText: _nextError,
              isNew: true,
            ),
            const SizedBox(height: 16),
            _PasswordInput(
              controller: _repeat,
              label: 'Powtórz nowe hasło',
              errorText: _repeatError,
              isNew: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      bottom: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Zmień hasło'),
        ),
      ),
    );
  }
}

class _PasswordInput extends StatefulWidget {
  const _PasswordInput({
    required this.controller,
    required this.label,
    this.errorText,
    this.isNew = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? errorText;
  final bool isNew;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PasswordInput> createState() => _PasswordInputState();
}

class _PasswordInputState extends State<_PasswordInput> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      autofillHints: [
        widget.isNew ? AutofillHints.newPassword : AutofillHints.password,
      ],
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Pokaż hasło' : 'Ukryj hasło',
          icon: Glyph(_obscure ? AppIcons.eye : AppIcons.eyeSlash),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Zaawansowane
// ---------------------------------------------------------------

class AdvancedSettingsScreen extends ConsumerWidget {
  const AdvancedSettingsScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(repositoryProvider).signOut();
      if (context.mounted) context.go(AppRoutes.settings);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Usunąć konto?'),
        content: const Text(
          'Usuniemy twoje konto i profil. Opinie zostaną jako anonimowe, bez twojego imienia. '
          'Nadchodzące rezerwacje odwołaj wcześniej, bo restauracja nadal będzie na ciebie czekać. '
          'Tej operacji nie da się cofnąć.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Usuń konto'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(repositoryProvider).deleteAccount();
      if (!context.mounted) return;
      showMessage(context, 'Konto zostało usunięte.');
      context.go(AppRoutes.settings);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SignedInOnly(
      title: 'Zaawansowane',
      next: AppRoutes.settingsAdvanced,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsGroup(
            children: [
              SettingsRow(
                icon: AppIcons.signOut,
                title: 'Wyloguj się',
                showChevron: false,
                onTap: () => _signOut(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SettingsGroup(
            footer:
                'Opinie zostaną jako anonimowe. Tej operacji nie da się cofnąć.',
            children: [
              SettingsRow(
                icon: AppIcons.trash,
                title: 'Usuń konto',
                destructive: true,
                showChevron: false,
                onTap: () => _deleteAccount(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

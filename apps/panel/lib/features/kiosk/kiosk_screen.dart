import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Co ile sekund panel pokazuje nowy kod. Zdjęcie kodu szybko przestaje działać.
const _tokenSeconds = 30;

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';

/// Ekran trybu obsługi: panel na wspólnym komputerze czeka na pracownika.
/// Pracownik skanuje kod aplikacją Table for workers, zaczyna zmianę i panel otwiera się
/// z zakładkami jego stanowiska.
class KioskLockScreen extends ConsumerStatefulWidget {
  const KioskLockScreen({super.key});

  @override
  ConsumerState<KioskLockScreen> createState() => _KioskLockScreenState();
}

class _KioskLockScreenState extends ConsumerState<KioskLockScreen> {
  String? _token;
  DateTime? _issuedAt;
  String? _problem;
  bool _checking = false;
  late final Timer _poll;
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    unawaited(_newToken());
    // Co półtorej sekundy pytamy, czy ktoś już zeskanował kod.
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _check());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final issued = _issuedAt;
      if (issued != null && DateTime.now().difference(issued).inSeconds >= _tokenSeconds) {
        unawaited(_newToken());
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _poll.cancel();
    _tick.cancel();
    super.dispose();
  }

  Future<void> _newToken() async {
    final restaurant = ref.read(currentRestaurantProvider);
    if (restaurant == null) return;
    try {
      final token = await ref.read(repositoryProvider).newLoginToken(restaurant.id);
      if (!mounted) return;
      setState(() {
        _token = token;
        _issuedAt = DateTime.now();
        _problem = null;
      });
    } catch (e) {
      if (mounted) setState(() => _problem = errorText(e));
    }
  }

  Future<void> _check() async {
    final token = _token;
    if (token == null || _checking || !mounted) return;
    _checking = true;
    try {
      final member = await ref.read(repositoryProvider).loginTokenStatus(token);
      if (member != null && mounted && _token == token) {
        ref.read(actingMemberProvider.notifier).set(member);
      }
    } catch (_) {
      // Chwilowy brak internetu: spróbujemy przy następnym sprawdzeniu.
    } finally {
      _checking = false;
    }
  }

  Future<void> _exit() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => const _ExitDialog());
    if (ok == true) await ref.read(kioskModeProvider.notifier).set(false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();

    final now = DateTime.now();
    final today = dateOnly(now);
    final shifts = ref.watch(
      shiftsProvider((restaurantId: restaurant.id, from: today, to: today.add(const Duration(days: 1)))),
    ).value ?? const <StaffShift>[];
    final staff = ref.watch(staffProvider(restaurant.id)).value ?? const <StaffMember>[];
    final names = {for (final m in staff) m.id: m.name};
    final working = shifts.where((s) => s.isOpen).toList();
    final left = _issuedAt == null
        ? _tokenSeconds
        : (_tokenSeconds - now.difference(_issuedAt!).inSeconds).clamp(0, _tokenSeconds);

    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 40, 48, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      restaurant.name,
                      style: text.titleLarge?.copyWith(color: AppColors.textMuted),
                    ),
                  ),
                  Text(
                    '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}',
                    style: text.headlineMedium?.copyWith(fontSize: 36, fontFeatures: _tabular),
                  ),
                ],
              ),
              // Instrukcja i kod blisko siebie, na środku ekranu, także na szerokim monitorze.
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Zaloguj się do pracy',
                            style: text.displaySmall?.copyWith(fontSize: 44, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 28),
                          for (final (i, step) in const [
                            'Otwórz aplikację Table for workers na swoim telefonie.',
                            'Stuknij „Zeskanuj kod” i skieruj aparat na kod obok. Kod jest wspólny dla wszystkich.',
                            'Zaczynasz zmianę. Żeby pracować na tym komputerze, stuknij „Otwórz panel”.',
                          ].indexed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.accentTint,
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Text(
                                      '${i + 1}',
                                      style: text.titleMedium?.copyWith(color: AppColors.accent),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(step, style: text.titleLarge?.copyWith(fontSize: 22)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48),
                    // Kod QR na białym tle, żeby aparat telefonu łapał go także w ciemnym motywie.
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 380,
                          height: 380,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: _token == null
                              ? Center(
                                  child: _problem == null
                                      ? const CircularProgressIndicator()
                                      : Text(
                                          _problem!,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Colors.black),
                                        ),
                                )
                              : QrImageView(
                                  data: 'table-praca:$_token',
                                  padding: EdgeInsets.zero,
                                  backgroundColor: Colors.white,
                                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Colors.black,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 380,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: left / _tokenSeconds,
                              minHeight: 6,
                              backgroundColor: AppColors.surfaceRaised,
                              color: AppColors.accentFill,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Nowy kod za $left s',
                          style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                        ),
                      ],
                    ),
                  ],
                ),
                  ),
                ),
              ),
              // Kto jest teraz w pracy, żeby kierownik widział to bez logowania.
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          working.isEmpty ? 'Nikt nie jest teraz w pracy' : 'W pracy:',
                          style: text.titleMedium?.copyWith(color: AppColors.textMuted),
                        ),
                        for (final s in working)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.ring),
                            ),
                            child: Text(
                              '${names[s.memberId] ?? 'Pracownik'} · od ${_hm(s.startedAt)}',
                              style: text.titleSmall?.copyWith(fontFeatures: _tabular),
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _exit,
                    style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                    icon: const Glyph(AppIcons.lock, size: 16),
                    label: const Text('Wyjdź z trybu obsługi'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wyjście z trybu obsługi wymaga hasła konta restauracji,
/// żeby pracownik nie dostał przypadkiem pełnego dostępu.
class _ExitDialog extends ConsumerStatefulWidget {
  const _ExitDialog();

  @override
  ConsumerState<_ExitDialog> createState() => _ExitDialogState();
}

class _ExitDialogState extends ConsumerState<_ExitDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _problem;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await ref.read(repositoryProvider).confirmPassword(_password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _problem = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(repositoryProvider).email;
    return AlertDialog(
      title: const Text('Wyjść z trybu obsługi?'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Wpisz hasło konta restauracji${email == null ? '' : ' ($email)'}.'),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              autofocus: true,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Hasło', errorText: _problem),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Anuluj'),
        ),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Wyjdź')),
      ],
    );
  }
}

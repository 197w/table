import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Co ile sekund panel pokazuje nowy kod. Zdjęcie kodu szybko przestaje działać.
const _tokenSeconds = 30;

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';

/// Ekran „Wejdź na zmianę” na głównym stanowisku. Pracownik skanuje kod aplikacją
/// Table for employees albo wpisuje login i hasło. Po zalogowaniu ekran znika, a panel
/// pokazuje zakładki jego stanowiska. Wylogowanie jest ręczne i wraca do tego ekranu.
class KioskLockScreen extends ConsumerStatefulWidget {
  const KioskLockScreen({super.key});

  @override
  ConsumerState<KioskLockScreen> createState() => _KioskLockScreenState();
}

class _KioskLockScreenState extends ConsumerState<KioskLockScreen> {
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  Future<void> _exit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const RestaurantPasswordDialog(
        title: 'Pełny dostęp do panelu?',
        action: 'Odblokuj',
      ),
    );
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
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Wejdź na zmianę',
                            style: text.displaySmall?.copyWith(fontSize: 44, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Zeskanuj kod aplikacją Table for employees na telefonie prywatnym albo służbowym '
                            'albo wpisz swój login i hasło. Po pracy wyloguj się ręcznie.',
                            style: text.titleMedium?.copyWith(color: AppColors.textMuted, fontSize: 18),
                          ),
                          const SizedBox(height: 32),
                          StationLogin(restaurantId: restaurant.id, qrSize: 340, autofocus: true),
                        ],
                      ),
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
                    label: const Text('Pełny dostęp'),
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

/// Logowanie pracownika na głównym stanowisku: kod QR (zmienia się co 30 sekund) i obok
/// login z hasłem. Po zalogowaniu zapisuje pracownika w [actingMemberProvider] (albo robi [onLogin]). Na innym
/// komputerze niż główne stanowisko pokazuje, gdzie się zalogować.
class StationLogin extends ConsumerStatefulWidget {
  const StationLogin({
    super.key,
    required this.restaurantId,
    this.qrSize = 280,
    this.autofocus = false,
    this.onLogin,
  });

  final String restaurantId;
  final double qrSize;
  final bool autofocus;

  /// Co zrobić z zalogowanym pracownikiem. Domyślnie loguje go do całego panelu
  /// i od razu do Zamówień.
  final ValueChanged<ActingMember>? onLogin;

  @override
  ConsumerState<StationLogin> createState() => _StationLoginState();
}

class _StationLoginState extends ConsumerState<StationLogin> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  String? _token;
  DateTime? _issuedAt;
  String? _tokenProblem;
  String? _formProblem;
  bool _fetching = false;
  bool _checking = false;
  bool _busy = false;
  late final Timer _poll;
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // Co półtorej sekundy pytamy, czy ktoś już zeskanował kod.
    _poll = Timer.periodic(const Duration(milliseconds: 1500), (_) => _check());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final issued = _issuedAt;
      if (issued == null || DateTime.now().difference(issued).inSeconds >= _tokenSeconds) {
        unawaited(_newToken());
      } else {
        setState(() {});
      }
    });
    unawaited(_newToken());
  }

  @override
  void dispose() {
    _poll.cancel();
    _tick.cancel();
    _login.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _newToken() async {
    if (_fetching || ref.read(isMainStationProvider(widget.restaurantId)) != true) return;
    final device = ref.read(deviceIdProvider).value;
    if (device == null) return;
    _fetching = true;
    try {
      final token = await ref.read(repositoryProvider).newLoginToken(widget.restaurantId, device);
      if (!mounted) return;
      setState(() {
        _token = token;
        _issuedAt = DateTime.now();
        _tokenProblem = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _tokenProblem = errorText(e);
          // Ponowna próba za kilka sekund, a nie co sekundę.
          _issuedAt = DateTime.now().subtract(const Duration(seconds: _tokenSeconds - 5));
        });
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> _check() async {
    final token = _token;
    if (token == null || _checking || !mounted) return;
    _checking = true;
    try {
      final member = await ref.read(repositoryProvider).loginTokenStatus(token);
      if (member != null && mounted && _token == token) {
        // Ten kod jest już zużyty: następny pracownik dostanie nowy.
        setState(() {
          _token = null;
          _issuedAt = null;
        });
        _done(member);
      }
    } catch (_) {
      // Chwilowy brak internetu: spróbujemy przy następnym sprawdzeniu.
    } finally {
      _checking = false;
    }
  }

  void _done(ActingMember member) {
    if (widget.onLogin case final onLogin?) {
      onLogin(member);
      return;
    }
    ref.read(actingMemberProvider.notifier).set(member);
    // Kto wszedł na zmianę, od razu może nabijać zamówienia.
    ref.read(orderMemberProvider.notifier).set(member);
  }

  Future<void> _submit() async {
    final device = ref.read(deviceIdProvider).value;
    if (_login.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _formProblem = 'Wpisz login i hasło.');
      return;
    }
    if (device == null) return;
    setState(() {
      _busy = true;
      _formProblem = null;
    });
    try {
      final member = await ref.read(repositoryProvider).memberLogin(
        restaurantId: widget.restaurantId,
        login: _login.text,
        password: _password.text,
        deviceId: device,
      );
      if (!mounted) return;
      ref.invalidate(shiftsProvider);
      _login.clear();
      _password.clear();
      _done(member);
    } catch (e) {
      if (!mounted) return;
      _password.clear();
      setState(() => _formProblem = errorText(e));
      _passwordFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isMain = ref.watch(isMainStationProvider(widget.restaurantId));
    if (isMain == null) return const SizedBox(height: 200, child: LoadingView());
    if (!isMain) {
      return _NotMainStation(
        station: ref.watch(mainStationProvider(widget.restaurantId)).value,
      );
    }

    final left = _issuedAt == null
        ? _tokenSeconds
        : (_tokenSeconds - DateTime.now().difference(_issuedAt!).inSeconds).clamp(0, _tokenSeconds);

    final qr = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Kod QR na białym tle, żeby aparat telefonu łapał go także w ciemnym motywie.
        Container(
          width: widget.qrSize,
          height: widget.qrSize,
          padding: EdgeInsets.all(widget.qrSize * 0.06),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: _token == null
              ? Center(
                  child: _tokenProblem == null
                      ? const CircularProgressIndicator()
                      : Text(
                          _tokenProblem!,
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
        const SizedBox(height: 14),
        SizedBox(
          width: widget.qrSize,
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
    );

    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Login i hasło', style: text.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Login i krótkie hasło daje przełożony w zakładce „Pracownicy”.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _login,
              autofocus: widget.autofocus,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Login', hintText: 'np. anna.k27'),
              onSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              focusNode: _passwordFocus,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: 'Hasło', errorText: _formProblem, errorMaxLines: 3),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Zaloguj się'),
            ),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        // Wąskie okno: kod nad formularzem.
        if (box.maxWidth < widget.qrSize + 460) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [qr, const SizedBox(height: 28), form],
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            qr,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Column(
                children: [
                  Container(width: 1, height: 90, color: AppColors.ring),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text('albo', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                  ),
                  Container(width: 1, height: 90, color: AppColors.ring),
                ],
              ),
            ),
            Flexible(child: form),
          ],
        );
      },
    );
  }
}

/// Ten komputer nie jest głównym stanowiskiem: pracownik loguje się gdzie indziej.
class _NotMainStation extends ConsumerWidget {
  const _NotMainStation({required this.station});

  final MainStation? station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final canSet = ref.watch(currentRestaurantProvider)?.canManage ?? false;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(AppIcons.lock, size: 36, color: AppColors.textMuted),
          const SizedBox(height: 14),
          Text(
            station == null ? 'Nie ustawiono głównego stanowiska' : 'To nie jest główne stanowisko',
            style: text.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            station == null
                ? 'Pracownicy logują się tylko na głównym stanowisku. Ustaw je w Ustawieniach '
                    'na komputerze, przy którym obsługa nabija zamówienia.'
                : 'Pracownicy logują się tylko na głównym stanowisku: „${station!.label}”.',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          if (canSet) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => context.go(PanelRoutes.settings),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Glyph(AppIcons.gear, size: 18),
              label: const Text('Otwórz Ustawienia'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Potwierdzenie hasłem konta restauracji, np. przed zdjęciem blokady stanowiska,
/// żeby pracownik nie dostał przypadkiem pełnego dostępu.
class RestaurantPasswordDialog extends ConsumerStatefulWidget {
  const RestaurantPasswordDialog({super.key, required this.title, required this.action, this.message});

  final String title;
  final String action;
  final String? message;

  @override
  ConsumerState<RestaurantPasswordDialog> createState() => _RestaurantPasswordDialogState();
}

class _RestaurantPasswordDialogState extends ConsumerState<RestaurantPasswordDialog> {
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
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.message != null) ...[
              Text(widget.message!),
              const SizedBox(height: 10),
            ],
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
        FilledButton(onPressed: _busy ? null : _submit, child: Text(widget.action)),
      ],
    );
  }
}

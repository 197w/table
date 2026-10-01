import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// „Anna Nowak, 14:02–22:10 (8:08 h).”
String _endedText(ActingMember member) {
  final from = member.endedShiftStartedAt;
  final to = member.shiftEndedAt ?? DateTime.now();
  if (from == null) return '${member.name}: zmiana zakończona.';
  final minutes = to.difference(from).inMinutes;
  return '${member.name}, ${_hm(from)}–${_hm(to)} (${minutes ~/ 60}:${_two(minutes % 60)} h).';
}

/// Ekran „Wejdź na zmianę”. Pracownik skanuje kod aplikacją
/// Table for employees albo wpisuje swój kod, zmiana się zaczyna, pracownik jest zalogowany
/// w panelu, a ekran znika.
class ShiftScreen extends ConsumerStatefulWidget {
  const ShiftScreen({super.key});

  /// Otwiera ekran na całe okno.
  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const ShiftScreen()),
  );

  @override
  ConsumerState<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends ConsumerState<ShiftScreen> {
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

  void _started(ActingMember member) {
    final since = member.shiftStartedAt;
    ref.read(panelMemberProvider.notifier).signIn(member);
    Navigator.of(context).pop();
    showMessage(context, '${member.name}: zmiana trwa${since == null ? '' : ' od ${_hm(since)}'}.');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const Scaffold(body: LoadingView());

    final now = DateTime.now();
    final today = dateOnly(now);
    final shifts = ref.watch(
      shiftsProvider((restaurantId: restaurant.id, from: today, to: today.add(const Duration(days: 1)))),
    ).value ?? const <StaffShift>[];
    final staff = ref.watch(staffProvider(restaurant.id)).value ?? const <StaffMember>[];
    final names = {for (final m in staff) m.id: m.name};
    final working = shifts.where((s) => s.isOpen).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 32, 32, 28),
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
                  const SizedBox(width: 20),
                  IconButton(
                    tooltip: 'Zamknij',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Glyph(AppIcons.close, size: 22),
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
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Wejdź na zmianę',
                            textAlign: TextAlign.center,
                            style: text.displaySmall?.copyWith(fontSize: 44, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Zeskanuj kod aplikacją Table for employees na telefonie prywatnym albo służbowym '
                            'albo wpisz swój czterocyfrowy kod. Zmiana zacznie się od razu.',
                            textAlign: TextAlign.center,
                            style: text.titleMedium?.copyWith(color: AppColors.textMuted, fontSize: 18),
                          ),
                          const SizedBox(height: 32),
                          StationLogin(
                            restaurantId: restaurant.id,
                            qrSize: 340,
                            autofocus: true,
                            onLogin: _started,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Kto jest teraz w pracy.
              Wrap(
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Logowanie pracownika w panelu: kod QR (zmienia się co 30 sekund) i obok
/// klawiatura na czterocyfrowy kod pracownika. Zalogowanego pracownika (jego zmiana już trwa) dostaje [onLogin].
/// Z [endShiftOf] kod (albo kod QR) tej osoby kończy jej zmianę, a [onLogin] dostaje pracownika
/// z godzinami zakończonej zmiany.
class StationLogin extends ConsumerStatefulWidget {
  const StationLogin({
    super.key,
    required this.restaurantId,
    this.qrSize = 280,
    this.autofocus = false,
    this.endShiftOf,
    required this.onLogin,
  });

  final String restaurantId;
  final double qrSize;
  final bool autofocus;

  /// Pracownik, którego zmianę kończy potwierdzenie. Null: zwykłe logowanie.
  final String? endShiftOf;

  /// Co zrobić z zalogowanym pracownikiem, np. zalogować go w zakładce.
  final ValueChanged<ActingMember> onLogin;

  @override
  ConsumerState<StationLogin> createState() => _StationLoginState();
}

class _StationLoginState extends ConsumerState<StationLogin> {
  /// Wpisywany kod pracownika (do 4 cyfr).
  String _code = '';
  final _pinFocus = FocusNode(debugLabel: 'kod pracownika');
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
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _newToken() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final token = await ref.read(repositoryProvider).newLoginToken(
        widget.restaurantId,
        endShiftOf: widget.endShiftOf,
      );
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

  void _done(ActingMember member) => widget.onLogin(member);

  void _digit(String d) {
    if (_busy || _code.length >= 4) return;
    setState(() {
      _code += d;
      _formProblem = null;
    });
    // Czwarta cyfra od razu loguje.
    if (_code.length == 4) unawaited(_submit());
  }

  void _backspace() {
    if (_busy || _code.isEmpty) return;
    setState(() => _code = _code.substring(0, _code.length - 1));
  }

  /// Cyfry, Backspace i Enter z klawiatury komputera.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final label = event.character ?? '';
    if (RegExp(r'^[0-9]$').hasMatch(label)) {
      _digit(label);
      return KeyEventResult.handled;
    }
    const numpad = [
      LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3, LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5,
      LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8,
      LogicalKeyboardKey.numpad9,
    ];
    if (numpad.contains(key)) {
      _digit('${numpad.indexOf(key)}');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _code = '');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _submit() async {
    if (_code.length != 4) return;
    setState(() {
      _busy = true;
      _formProblem = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      final endOf = widget.endShiftOf;
      final member = endOf != null
          ? await repo.memberEndShift(restaurantId: widget.restaurantId, code: _code, memberId: endOf)
          : await repo.memberLogin(restaurantId: widget.restaurantId, code: _code);
      if (!mounted) return;
      ref.invalidate(shiftsProvider);
      setState(() => _code = '');
      _done(member);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _code = '';
        _formProblem = errorText(e);
      });
      _pinFocus.requestFocus();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

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

    Widget key(Widget child, VoidCallback onTap, {bool muted = false}) => SizedBox(
      height: 60,
      child: OutlinedButton(
        onPressed: _busy ? null : onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 60),
          padding: EdgeInsets.zero,
          foregroundColor: muted ? AppColors.textMuted : AppColors.text,
        ),
        child: child,
      ),
    );
    final digitStyle = text.headlineSmall?.copyWith(fontFeatures: _tabular);

    // Klawiatura numeryczna na kod pracownika. Działa też klawiatura komputera.
    final form = Focus(
      focusNode: _pinFocus,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: _pinFocus.requestFocus,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Kod pracownika', style: text.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Wpisz swój czterocyfrowy kod. Znajdziesz go w aplikacji Table for employees.',
                style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _formProblem != null
                                ? AppColors.error
                                : i == _code.length
                                ? AppColors.accent
                                : AppColors.ringStrong,
                            width: i == _code.length || _formProblem != null ? 2 : 1,
                          ),
                        ),
                        child: i < _code.length
                            ? Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(color: AppColors.text, shape: BoxShape.circle),
                              )
                            : null,
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(
                height: 34,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(
                          _formProblem ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(color: AppColors.error),
                        ),
                ),
              ),
              for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']]) ...[
                Row(
                  children: [
                    for (final (i, d) in row.indexed) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: key(Text(d, style: digitStyle), () => _digit(d))),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
              ],
              Row(
                children: [
                  Expanded(
                    child: key(
                      Text('Wyczyść', style: text.labelLarge),
                      () => setState(() => _code = ''),
                      muted: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: key(Text('0', style: digitStyle), () => _digit('0'))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: key(const Glyph(AppIcons.arrowLeft, size: 22), _backspace, muted: true),
                  ),
                ],
              ),
            ],
          ),
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

/// Logowanie w zakładce panelu, gdy nikt nie jest zalogowany. Logowanie jest jedno dla wszystkich
/// zakładek. Wejść może tylko ktoś z uprawnieniem do zakładki. Właściciel może otworzyć panel
/// hasłem konta restauracji (np. przy pierwszym uruchomieniu albo na innym komputerze).
class TabLoginGate extends ConsumerWidget {
  const TabLoginGate({super.key, required this.tab, required this.label});

  /// Ścieżka zakładki, np. „/zamowienia”.
  final String tab;
  final String label;

  Future<void> _unlock(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const RestaurantPasswordDialog(
        title: 'Otworzyć panel jako właściciel?',
        message: 'Panel będzie otwarty z pełnym dostępem, dopóki się nie wylogujesz.',
        action: 'Otwórz',
      ),
    );
    if (ok == true) ref.read(panelMemberProvider.notifier).signIn(ActingMember.account());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zaloguj się kodem albo kodem QR, żeby otworzyć „$label”. Zostaniesz zalogowany we wszystkich '
                      'zakładkach, do których masz uprawnienia. Panel wyloguje Cię sam po 30 sekundach bez ruchu.',
                      style: text.bodyLarge?.copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              if (restaurant.canManage)
                TextButton.icon(
                  onPressed: () => _unlock(context, ref),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
                  icon: const Glyph(AppIcons.lock, size: 16),
                  label: const Text('Właściciel: otwórz hasłem konta'),
                ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: StationLogin(
                restaurantId: restaurant.id,
                autofocus: true,
                onLogin: (member) {
                  if (!canOpenRoute(tab, member.permissions)) {
                    showMessage(
                      context,
                      '${member.name} nie ma uprawnienia do zakładki „$label”'
                      '${member.position == null ? '' : ' (stanowisko „${member.position}”)'}.',
                    );
                    return;
                  }
                  ref.read(panelMemberProvider.notifier).signIn(member);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// „Zakończ zmianę” z paska nad zakładką. Pracownik potwierdza swoim czterocyfrowym kodem albo kodem QR
/// zeskanowanym własnym telefonem, więc nikt nie zakończy cudzej zmiany jednym kliknięciem.
class EndShiftDialog extends ConsumerWidget {
  const EndShiftDialog({super.key, required this.member});

  final ActingMember member;

  static Future<void> open(BuildContext context, ActingMember member) =>
      showDialog<void>(context: context, builder: (_) => EndShiftDialog(member: member));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final restaurant = ref.watch(currentRestaurantProvider);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Zakończyć zmianę?', style: text.headlineSmall),
                        const SizedBox(height: 6),
                        Text(
                          '${member.name}: potwierdź swoim czterocyfrowym kodem albo zeskanuj kod '
                          'aplikacją Table for employees. Zmiana skończy się od razu.',
                          style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Anuluj',
                    onPressed: () => Navigator.pop(context),
                    icon: const Glyph(AppIcons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (restaurant == null)
                const LoadingView()
              else
                StationLogin(
                  restaurantId: restaurant.id,
                  qrSize: 240,
                  autofocus: true,
                  endShiftOf: member.memberId,
                  onLogin: (ended) {
                    ref.read(panelMemberProvider.notifier).signOutMember(ended.memberId);
                    ref.invalidate(shiftsProvider);
                    Navigator.pop(context);
                    showMessage(context, _endedText(ended), tone: ToastTone.success, title: 'Zmiana zakończona');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pasek nad zakładką: kto jest zalogowany w panelu, „Wyloguj” i „Zakończ zmianę”.
class TabSessionBar extends ConsumerWidget {
  const TabSessionBar({super.key, required this.member});

  final ActingMember member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    // Ostatnie 10 sekund przed automatycznym wylogowaniem: odliczanie przy przycisku „Wyloguj”.
    final idle = ref.watch(idleSecondsProvider.select((s) => s >= kIdleLogoutSeconds - 10 ? s : 0));
    final initials = member.name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    final since = member.shiftStartedAt;
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 8, 24, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.ring)),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentTint,
              borderRadius: BorderRadius.circular(15),
            ),
            child: member.isAccount
                ? Glyph(AppIcons.lock, size: 14, color: AppColors.accent)
                : Text(initials, style: text.labelMedium?.copyWith(color: AppColors.accent)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: member.name, style: text.labelLarge),
                  TextSpan(
                    text: [
                      '',
                      ?member.position,
                      if (since != null) 'na zmianie od ${_hm(since)}',
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (idle > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Wylogowanie za ${kIdleLogoutSeconds - idle} s',
                style: text.labelMedium?.copyWith(color: AppColors.warning, fontFeatures: _tabular),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (!member.isAccount && since != null)
            TextButton.icon(
              onPressed: () => EndShiftDialog.open(context, member),
              style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
              icon: const Glyph(AppIcons.doorOpen, size: 16),
              label: const Text('Zakończ zmianę'),
            ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            onPressed: () => ref.read(panelMemberProvider.notifier).signOut(),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
            icon: const Glyph(AppIcons.signOut, size: 16),
            label: Text('Wyloguj (${member.name.split(' ').first})'),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../data/providers.dart';
import 'app.dart';

/// Automatyczne wylogowanie pracownika z panelu po [kIdleLogoutSeconds] sekundach bez ruchu myszy,
/// kliknięcia, przewinięcia i klawisza. Kuchnia i Wydanie nie wylogowują pracownika: to ekrany, na które się patrzy.
/// Pełny dostęp właściciela (hasło konta restauracji) nie wylogowuje się sam: trwa, dopóki właściciel się nie wyloguje.
/// Wylogowanie zamyka otwarte okna (np. rachunek), żeby następna osoba nie pracowała na cudzym koncie.
class IdleLogout extends ConsumerStatefulWidget {
  const IdleLogout({
    super.key,
    required this.location,
    required this.navigators,
    required this.child,
  });

  /// Bieżąca ścieżka panelu, np. „/zamowienia”.
  final String Function() location;

  /// Nawigatory, z których wylogowanie zdejmuje okna dialogowe i menu.
  final List<GlobalKey<NavigatorState>> navigators;
  final Widget child;

  /// Zakładki bez wylogowania pracownika.
  static const exempt = [PanelRoutes.kitchen, PanelRoutes.serving];

  @override
  ConsumerState<IdleLogout> createState() => _IdleLogoutState();
}

class _IdleLogoutState extends ConsumerState<IdleLogout> {
  /// Sekundy bez ruchu. Zegar dolicza co sekundę, każdy ruch zeruje.
  int _idle = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    ref.listenManual(panelMemberProvider, (previous, member) {
      // Właściciel z hasłem konta zostaje zalogowany, więc zegar nie liczy.
      if (member == null || member.isAccount) {
        _stop();
      } else {
        // Nowa osoba (albo właściciel) zaczyna liczenie od zera; zegar startuje, gdy jeszcze nie chodzi.
        if (previous?.memberId != member.memberId) _idle = 0;
        _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _timer?.cancel();
    super.dispose();
  }

  /// Klawisz liczy się jako ruch. Zwraca false, więc zdarzenie idzie dalej: nic nie jest połykane.
  bool _onKey(KeyEvent event) {
    _touch();
    return false;
  }

  void _touch() {
    _idle = 0;
    if (_timer != null) ref.read(idleSecondsProvider.notifier).set(0);
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    ref.read(idleSecondsProvider.notifier).set(0);
  }

  void _tick() {
    if (!mounted) return;
    final member = ref.read(panelMemberProvider);
    if (member == null || member.isAccount) {
      _stop();
      return;
    }
    if (IdleLogout.exempt.any(widget.location().startsWith)) {
      _touch();
      return;
    }
    final idle = ++_idle;
    if (idle < kIdleLogoutSeconds) {
      ref.read(idleSecondsProvider.notifier).set(idle);
      return;
    }
    // Otwarte okna (rachunek, menu, potwierdzenie) znikają razem z pracownikiem.
    for (final key in widget.navigators) {
      key.currentState?.popUntil((route) => route is! PopupRoute);
    }
    ref.read(panelMemberProvider.notifier).signOut();
    Toasts.instance.show(
      'Panel wylogował pracownika po $kIdleLogoutSeconds sekundach bez ruchu. Zaloguj się kodem.',
      title: 'Wylogowano',
      icon: AppIcons.lock,
    );
  }

  @override
  Widget build(BuildContext context) {
    void moved(PointerEvent _) => _touch();
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: moved,
      onPointerMove: moved,
      onPointerHover: moved,
      onPointerSignal: moved,
      onPointerPanZoomUpdate: moved,
      child: widget.child,
    );
  }
}

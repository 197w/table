import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import '../features/auth/login_screen.dart';
import '../features/floor/floor_screen.dart';
import '../features/gift_cards/gift_cards_screen.dart';
import '../features/menu/menu_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/reservations/reservations_screen.dart';
import '../features/reviews/reviews_screen.dart';
import '../features/staff/staff_screen.dart';
import '../features/stats/stats_screen.dart';
import 'panel_theme.dart';
import 'shell.dart';

class PanelApp extends ConsumerStatefulWidget {
  const PanelApp({super.key});

  @override
  ConsumerState<PanelApp> createState() => _PanelAppState();
}

class _PanelAppState extends ConsumerState<PanelApp>
    with WidgetsBindingObserver {
  late final _AuthRefresh _authRefresh;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authRefresh = _AuthRefresh(
      Supabase.instance.client.auth.onAuthStateChange,
    );
    _router = _buildRouter(_authRefresh);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    _authRefresh.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (ref.read(themeSettingProvider) == AppThemeSetting.system) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final setting = ref.watch(themeSettingProvider);
    final brightness = switch (setting) {
      AppThemeSetting.light => Brightness.light,
      AppThemeSetting.dark => Brightness.dark,
      AppThemeSetting.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
    final palette = brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    AppColors.use(palette);

    // Windows odtwarza dźwięk błędu, gdy aplikacja nie obsłuży naciśniętego klawisza,
    // na przykład po kliknięciu w puste pole, kiedy żadne pole tekstowe nie jest aktywne.
    // Ten Focus jest nad całą aplikacją, więc dostaje tylko klawisze, których nic nie obsłużyło.
    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: (_, _) => KeyEventResult.handled,
      child: MaterialApp.router(
      key: ValueKey(brightness),
      title: 'Table · Panel restauracji',
      debugShowCheckedModeBanner: false,
      theme: PanelTheme.build(palette),
      locale: const Locale('pl', 'PL'),
      supportedLocales: const [Locale('pl', 'PL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
      ),
    );
  }
}

GoRouter _buildRouter(Listenable refresh) {
  return GoRouter(
    initialLocation: PanelRoutes.reservations,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = Supabase.instance.client.auth.currentSession != null;
      final onLogin = state.uri.path == PanelRoutes.login;
      if (!loggedIn && !onLogin) return PanelRoutes.login;
      if (loggedIn && onLogin) return PanelRoutes.reservations;
      return null;
    },
    routes: [
      GoRoute(
        path: PanelRoutes.login,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: LoginScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            PanelShell(location: state.uri.path, child: child),
        routes: [
          _page(PanelRoutes.reservations, const ReservationsScreen()),
          _page(PanelRoutes.floor, const FloorScreen()),
          _page(PanelRoutes.staff, const StaffScreen()),
          _page(PanelRoutes.giftCards, const GiftCardsScreen()),
          _page(PanelRoutes.menu, const MenuScreen()),
          _page(PanelRoutes.profile, const ProfileScreen()),
          _page(PanelRoutes.reviews, const ReviewsScreen()),
          _page(PanelRoutes.stats, const StatsScreen()),
        ],
      ),
    ],
  );
}

/// Zmiana sekcji bez animacji: w panelu przełącza się często, animacja by spowalniała.
GoRoute _page(String path, Widget child) => GoRoute(
  path: path,
  pageBuilder: (context, state) => NoTransitionPage(child: child),
);

abstract final class PanelRoutes {
  static const login = '/logowanie';
  static const reservations = '/rezerwacje';
  static const floor = '/sala';
  static const staff = '/pracownicy';
  static const giftCards = '/karty';
  static const menu = '/menu';
  static const profile = '/lokal';
  static const reviews = '/opinie';
  static const stats = '/statystyki';
}

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<AuthState> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

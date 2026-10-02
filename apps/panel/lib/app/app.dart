import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_core/table_core.dart';

import '../features/auth/login_screen.dart';
import '../features/customers/customers_screen.dart';
import '../features/deliveries/deliveries_screen.dart';
import '../features/fleet/fleet_screen.dart';
import '../features/floor/floor_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/kitchen/kitchen_screen.dart';
import '../features/menu/menu_screen.dart';
import '../features/orders/order_history_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/reservations/reservations_screen.dart';
import '../features/reviews/reviews_screen.dart';
import '../features/serving/serving_screen.dart';
import '../features/staff/staff_screen.dart';
import '../features/staff/team_stats_screen.dart';
import '../features/stats/stats_screen.dart';
import 'idle_logout.dart';
import '../shared/panel_widgets.dart';
import 'panel_theme.dart';
import 'reservation_alerts.dart';
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
  final _rootNavigator = GlobalKey<NavigatorState>(debugLabel: 'panel');
  final _shellNavigator = GlobalKey<NavigatorState>(debugLabel: 'zakładki');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authRefresh = _AuthRefresh(
      Supabase.instance.client.auth.onAuthStateChange,
    );
    _router = _buildRouter(_authRefresh, root: _rootNavigator, shell: _shellNavigator);
    // Przycisk „Pokaż” w powiadomieniu o nowej rezerwacji otwiera Rezerwacje.
    ReservationAlerts.instance.onOpen = () => _router.go(PanelRoutes.reservations);
    ReservationAlerts.instance.onOpenTakeaway = () => _router.go(PanelRoutes.deliveries);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReservationAlerts.instance.onOpen = null;
    ReservationAlerts.instance.onOpenTakeaway = null;
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
        ? PanelPalette.dark
        : AppPalette.light;
    AppColors.use(palette);

    // Zmiana motywu przechodzi płynnie: ThemeFade wygasza zdjęcie starego wyglądu.
    return ThemeFade(
      child: MaterialApp.router(
      key: ValueKey(brightness),
      title: 'Table · Panel restauracji',
      debugShowCheckedModeBanner: false,
      theme: PanelTheme.build(palette),
      locale: const Locale('pl', 'PL'),
      supportedLocales: const [Locale('pl', 'PL')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
      // Powiadomienia w stylu Table nad całym panelem, także nad oknami dialogowymi.
      // Automatyczne wylogowanie pracownika liczy ruch w całym oknie, także w oknach dialogowych.
      builder: (context, child) => ToastHost(
        child: IdleLogout(
          location: () => _router.routerDelegate.currentConfiguration.uri.path,
          navigators: [_rootNavigator, _shellNavigator],
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      ),
    );
  }
}

GoRouter _buildRouter(
  Listenable refresh, {
  required GlobalKey<NavigatorState> root,
  required GlobalKey<NavigatorState> shell,
}) {
  return GoRouter(
    navigatorKey: root,
    initialLocation: PanelRoutes.reservations,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = Supabase.instance.client.auth.currentSession != null;
      final onLogin = state.uri.path == PanelRoutes.login;
      // Po wygaśnięciu sesji zapamiętujemy, gdzie była obsługa, i po zalogowaniu tam wracamy.
      if (!loggedIn && !onLogin) {
        return Uri(
          path: PanelRoutes.login,
          queryParameters: {'dalej': state.uri.toString()},
        ).toString();
      }
      if (loggedIn && onLogin) {
        final next = state.uri.queryParameters['dalej'];
        final safe = next != null &&
            next.startsWith('/') &&
            !next.startsWith(PanelRoutes.login);
        return safe ? next : PanelRoutes.reservations;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: PanelRoutes.login,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: LoginScreen()),
      ),
      ShellRoute(
        navigatorKey: shell,
        builder: (context, state, child) =>
            PanelShell(location: state.uri.path, child: child),
        routes: [
          _page(PanelRoutes.reservations, const ReservationsScreen()),
          GoRoute(
            path: PanelRoutes.floor,
            // Wyjście z edycji z niezapisanymi zmianami wymaga potwierdzenia.
            onExit: (context, state) => confirmLeaveFloor(context),
            pageBuilder: (context, state) => _tabPage(state, const FloorScreen()),
          ),
          GoRoute(
            path: PanelRoutes.orders,
            // ?stolik=<id> otwiera od razu rachunek stolika klikniętego na planie sali.
            pageBuilder: (context, state) => _tabPage(
              state,
              OrdersScreen(tableId: state.uri.queryParameters['stolik']),
            ),
          ),
          _page(PanelRoutes.history, const OrderHistoryScreen()),
          _page(PanelRoutes.deliveries, const DeliveriesScreen()),
          _page(PanelRoutes.fleet, const FleetScreen()),
          _page(PanelRoutes.kitchen, const KitchenScreen()),
          _page(PanelRoutes.serving, const ServingScreen()),
          _page(PanelRoutes.staff, const StaffScreen()),
          _page(PanelRoutes.teamStats, const TeamStatsScreen()),
          _page(PanelRoutes.customers, const CustomersScreen()),
          _page(PanelRoutes.settings, const SettingsScreen()),
          _page(PanelRoutes.menu, const MenuScreen()),
          _page(PanelRoutes.inventory, const InventoryScreen()),
          _page(PanelRoutes.profile, const ProfileScreen()),
          _page(PanelRoutes.reviews, const ReviewsScreen()),
          _page(PanelRoutes.stats, const StatsScreen()),
        ],
      ),
    ],
  );
}

GoRoute _page(String path, Widget child) => GoRoute(
  path: path,
  pageBuilder: (context, state) => _tabPage(state, child),
);

/// Zmiana zakładki w menu bocznym: stara treść szybko gaśnie, nowa pojawia się lekko z dołu.
/// Krótko (220 ms), bo w panelu przełącza się często. Ten sam ruch co zakładki wewnątrz ekranu.
Page<void> _tabPage(GoRouterState state, Widget child) => CustomTransitionPage<void>(
  key: state.pageKey,
  child: child,
  transitionDuration: PanelMotion.tab,
  reverseTransitionDuration: PanelMotion.tabOut,
  transitionsBuilder: (context, animation, secondaryAnimation, child) => PanelMotion.tabTransition(
    child,
    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic),
  ),
);

abstract final class PanelRoutes {
  static const login = '/logowanie';
  static const reservations = '/rezerwacje';
  static const floor = '/sala';
  static const orders = '/zamowienia';
  static const history = '/historia';
  static const deliveries = '/dostawy';
  static const fleet = '/flota';
  static const kitchen = '/kuchnia';
  static const serving = '/wydanie';
  static const staff = '/pracownicy';
  static const teamStats = '/zespol';
  static const customers = '/klienci';
  static const settings = '/ustawienia';
  static const menu = '/menu';
  static const inventory = '/inwentaryzacja';
  static const profile = '/lokal';
  static const reviews = '/opinie';
  static const stats = '/statystyki';
}

/// Uprawnienia, z których wystarczy jedno, żeby otworzyć zakładkę.
const _routePermissions = {
  PanelRoutes.reservations: {'reservations'},
  PanelRoutes.orders: {'orders'},
  PanelRoutes.history: {'orders', 'stats'},
  PanelRoutes.deliveries: {'orders'},
  PanelRoutes.fleet: {'fleet'},
  PanelRoutes.kitchen: {'kitchen'},
  PanelRoutes.serving: {'serving'},
  PanelRoutes.floor: {'floor_edit'},
  // W Pracownikach każda część ma własne uprawnienie: zespół, loginy, grafik, czas pracy, stanowiska.
  PanelRoutes.staff: {'staff', 'staff_logins', 'schedule', 'timesheet', 'positions'},
  PanelRoutes.teamStats: {'stats'},
  PanelRoutes.customers: {'customers'},
  PanelRoutes.settings: {'profile'},
  PanelRoutes.profile: {'profile'},
  PanelRoutes.menu: {'menu'},
  PanelRoutes.inventory: {'inventory_edit', 'inventory_count'},
  PanelRoutes.reviews: {'reviews'},
  PanelRoutes.stats: {'stats'},
};

/// Nazwy zakładek, np. w logowaniu do zakładki.
const panelTabLabels = {
  PanelRoutes.reservations: 'Rezerwacje',
  PanelRoutes.orders: 'Zamówienia',
  PanelRoutes.history: 'Historia zamówień',
  PanelRoutes.deliveries: 'Dostawy',
  PanelRoutes.fleet: 'Flota',
  PanelRoutes.kitchen: 'Kuchnia',
  PanelRoutes.serving: 'Wydanie',
  PanelRoutes.floor: 'Edycja sali',
  PanelRoutes.staff: 'Pracownicy',
  PanelRoutes.teamStats: 'Statystyki zespołu',
  PanelRoutes.customers: 'Klienci',
  PanelRoutes.settings: 'Ustawienia lokalu',
  PanelRoutes.profile: 'Dane lokalu',
  PanelRoutes.menu: 'Menu',
  PanelRoutes.inventory: 'Inwentaryzacja',
  PanelRoutes.reviews: 'Opinie',
  PanelRoutes.stats: 'Statystyki',
};

/// Zakładka (jej ścieżka) dla adresu. Null: adres poza zakładkami.
String? tabForRoute(String location) {
  for (final tab in _routePermissions.keys) {
    if (location.startsWith(tab)) return tab;
  }
  return null;
}

/// Uprawnienia, z których wystarczy jedno, żeby otworzyć zakładkę. Null: zakładka dla każdego.
Set<String>? permissionsForRoute(String location) => _routePermissions[tabForRoute(location)];

/// Czy osoba z [permissions] może otworzyć zakładkę. Bez uprawnienia zakładki nie widać w menu.
bool canOpenRoute(String location, Set<String> permissions) {
  final need = permissionsForRoute(location);
  return need == null || need.any(permissions.contains);
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

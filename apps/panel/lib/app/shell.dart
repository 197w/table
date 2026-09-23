import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../data/models.dart';
import '../data/providers.dart';
import 'app.dart';
import '../shared/panel_widgets.dart';
import 'panel_theme.dart';

/// Układ panelu: boczne menu z wyborem lokalu i treść sekcji.
class PanelShell extends ConsumerWidget {
  const PanelShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurants = ref.watch(restaurantsProvider);

    return Scaffold(
      body: Row(
        children: [
          // Menu rzuca cień na treść, żeby warstwy były od siebie odsunięte.
          DecoratedBox(
            decoration: BoxDecoration(boxShadow: PanelDepth.sidebarEdge),
            child: _Sidebar(location: location),
          ),
          Expanded(
            child: ColoredBox(
              color: PanelDepth.content,
              child: restaurants.when(
                loading: () => const LoadingView(),
                error: (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(restaurantsProvider),
                ),
                data: (list) => list.isEmpty
                    ? MessageView(
                        icon: AppIcons.storefront,
                        title: 'To konto nie ma jeszcze lokalu',
                        message:
                            'Poproś właściciela lokalu o dodanie Cię do zespołu albo napisz do nas, '
                            'żeby dodać restaurację do Table.',
                        actionLabel: 'Wyloguj się',
                        onAction: () => ref.read(repositoryProvider).signOut(),
                      )
                    : child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem(this.route, this.label, this.icon);
  final String route;
  final String label;
  final AppIconData icon;
}

/// Sekcje panelu pogrupowane według tego, kto i kiedy z nich korzysta.
const _groups = <(String, List<_NavItem>)>[
  ('Sala', [
    _NavItem(PanelRoutes.reservations, 'Rezerwacje', AppIcons.calendarDots),
    _NavItem(PanelRoutes.floor, 'Edycja sali', AppIcons.squaresFour),
  ]),
  ('Zespół', [
    _NavItem(PanelRoutes.staff, 'Pracownicy', AppIcons.users),
  ]),
  ('Lokal', [
    _NavItem(PanelRoutes.profile, 'Dane lokalu', AppIcons.storefront),
    _NavItem(PanelRoutes.menu, 'Menu', AppIcons.bookOpen),
    _NavItem(PanelRoutes.giftCards, 'Karty podarunkowe', AppIcons.envelope),
  ]),
  ('Wyniki', [
    _NavItem(PanelRoutes.reviews, 'Opinie', AppIcons.chatCircle),
    _NavItem(PanelRoutes.stats, 'Statystyki', AppIcons.chartBar),
  ]),
];

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.location});

  final String location;

  /// Szerokość paska: zwiniętego i rozwiniętego.
  static const _narrow = 76.0;
  static const _wide = 256.0;
  static const _pad = 14.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentRestaurantProvider);
    final list = ref.watch(restaurantsProvider).value ?? const [];
    final collapsed = ref.watch(sidebarCollapsedProvider);

    // Jedna wartość prowadzi całą zmianę: 1 to menu rozwinięte, 0 zwinięte.
    // Wysokości są stałe w obu stanach, więc ikony nie ruszają się w pionie.
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: collapsed ? 0 : 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        final width = _narrow + (_wide - _narrow) * t;
        final inner = width - _pad * 2;
        return RepaintBoundary(
          child: Container(
            width: width,
            decoration: BoxDecoration(
              color: PanelDepth.sidebar,
              border: PanelDepth.sidebarBorder,
            ),
            padding: const EdgeInsets.fromLTRB(_pad, 20, _pad, 14),
            child: _content(
              context,
              ref,
              inner: inner,
              fade: t,
              current: current,
              list: list,
            ),
          ),
        );
      },
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref, {
    required double inner,
    required double fade,
    required PanelRestaurant? current,
    required List<PanelRestaurant> list,
  }) {
    final text = Theme.of(context).textTheme;
    final theme = ref.watch(themeSettingProvider);
    final email = ref.watch(repositoryProvider).email;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: inner,
          height: 40,
          child: _IconRow(
            icon: AppIcons.menu,
            label: fade < 0.5 ? 'Rozwiń menu' : 'Zwiń menu',
            width: inner,
            fade: fade,
            muted: true,
            onTap: () => ref.read(sidebarCollapsedProvider.notifier).toggle(),
          ),
        ),
        const SizedBox(height: 10),
        if (current != null)
          _RestaurantSwitcher(
            current: current,
            restaurants: list,
            width: inner,
            fade: fade,
          ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (final (title, items) in _groups) ...[
                // Nagłówek grupy trzyma stałą wysokość: napis gaśnie,
                // a na jego miejscu zostaje kreska.
                SizedBox(
                  width: inner,
                  height: 30,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Opacity(
                        opacity: 1 - fade,
                        child: Divider(height: 1, color: AppColors.ring),
                      ),
                      Opacity(
                        opacity: labelFade(fade),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10, top: 6),
                          child: Text(
                            title.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: text.labelSmall?.copyWith(
                              color: AppColors.textDisabled,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                for (final item in items)
                  _IconRow(
                    icon: item.icon,
                    label: item.label,
                    width: inner,
                    fade: fade,
                    selected: location.startsWith(item.route),
                    onTap: () => context.go(item.route),
                  ),
              ],
            ],
          ),
        ),
        SizedBox(width: inner, child: Divider(color: AppColors.ring)),
        const SizedBox(height: 6),
        // Motyw i wylogowanie to takie same wiersze jak sekcje,
        // więc dół menu ma tę samą wysokość w obu stanach.
        _IconRow(
          icon: theme.icon,
          label: 'Motyw: ${theme.label}',
          width: inner,
          fade: fade,
          muted: true,
          onTap: () {
            final values = AppThemeSetting.values;
            ref
                .read(themeSettingProvider.notifier)
                .set(values[(theme.index + 1) % values.length]);
          },
        ),
        _IconRow(
          icon: AppIcons.signOut,
          label: 'Wyloguj się',
          width: inner,
          fade: fade,
          muted: true,
          onTap: () => ref.read(repositoryProvider).signOut(),
        ),
        SizedBox(
          width: inner,
          height: 26,
          child: Opacity(
            opacity: labelFade(fade),
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                email ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Szerokość treści w zwiniętym pasku: 76 minus odstępy po bokach.
const kRailInner = 48.0;

/// Widoczność podpisów: gasną w pierwszej części ruchu, więc znikają,
/// zanim zwężający się pasek zacznie je ucinać.
double labelFade(double fade) => ((fade - 0.45) / 0.55).clamp(0.0, 1.0);

/// Szerokość kwadratu z ikoną przy danym stanie menu (1 rozwinięte, 0 zwinięte).
/// Obie krańcowe wartości są stałe, więc ikona jedzie w jedną stronę i nie wraca.
double railSlot(double fade) => kRailInner + (40 - kRailInner) * fade;

/// Wiersz menu: ikona w kwadracie, który przy zwijaniu przesuwa się na środek
/// paska, i podpis, który gaśnie. Wysokość jest stała, więc nic nie skacze.
class _IconRow extends StatelessWidget {
  const _IconRow({
    required this.icon,
    required this.label,
    required this.width,
    required this.fade,
    required this.onTap,
    this.selected = false,
    this.muted = false,
  });

  final AppIconData icon;
  final String label;
  final double width;

  /// 1 to menu rozwinięte, 0 zwinięte.
  final double fade;
  final bool selected;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Kwadrat z ikoną wędruje między dwiema stałymi szerokościami.
    // Liczenie go od bieżącej szerokości paska dawało wychylenie i powrót,
    // bo obie wartości zmieniały się naraz.
    final slot = railSlot(fade);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: fade < 0.5 ? label : '',
        child: PanelPress(
          child: Material(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            elevation: selected ? 6 : 0,
            shadowColor: AppColors.palette.brightness == Brightness.dark
                ? Colors.black
                : const Color(0x330C2A22),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              hoverColor: AppColors.ring,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: SizedBox(
                width: width,
                height: 40,
                child: Row(
                  children: [
                    SizedBox(
                      width: slot,
                      child: Center(
                        child: Glyph(
                          icon,
                          size: 19,
                          color: selected
                              ? AppColors.accent
                              : (muted ? AppColors.textDisabled : AppColors.textMuted),
                        ),
                      ),
                    ),
                    if (fade > 0)
                      Expanded(
                        child: Opacity(
                          opacity: labelFade(fade),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: text.labelLarge?.copyWith(
                              color: selected
                                  ? AppColors.text
                                  : (muted ? AppColors.textMuted : AppColors.textMuted),
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RestaurantSwitcher extends ConsumerWidget {
  const _RestaurantSwitcher({
    required this.current,
    required this.restaurants,
    required this.width,
    required this.fade,
  });

  final PanelRestaurant current;
  final List<PanelRestaurant> restaurants;

  /// Szerokość pudełka w trakcie zwijania.
  final double width;

  /// 1 to menu rozwinięte, 0 zwinięte.
  final double fade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final canSwitch = restaurants.length > 1;

    // Stałe krańce, żeby logo nie wychylało się w bok w trakcie animacji.
    final slot = kRailInner + (44 - kRailInner) * fade;
    final body = Tooltip(
      message: fade < 0.5 ? '${current.name} · ${current.city}' : '',
      child: Container(
        width: width,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.4 + 0.6 * fade),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.ring.withValues(alpha: fade)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: slot,
              child: Center(
                child: ImageOutline(
                  radius: 9,
                  child: RestaurantLogo(
                    name: current.name,
                    logoUrl: current.logoUrl,
                    size: 40,
                    radius: 9,
                  ),
                ),
              ),
            ),
            if (fade > 0)
              Expanded(
                child: Opacity(
                  opacity: labelFade(fade),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: text.labelLarge,
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              current.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              softWrap: false,
                              style: text.bodySmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _PlanBadge(isPro: current.isPro),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (fade > 0)
              Opacity(
                opacity: canSwitch ? labelFade(fade) : 0,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Glyph(AppIcons.caretDown, size: 16, color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );

    if (!canSwitch) return body;

    return PopupMenuButton<String>(
      tooltip: 'Zmień lokal',
      position: PopupMenuPosition.under,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.ring),
      ),
      onSelected: (id) =>
          ref.read(selectedRestaurantIdProvider.notifier).select(id),
      itemBuilder: (context) => [
        for (final r in restaurants)
          PopupMenuItem(
            value: r.id,
            child: SizedBox(
              width: 200,
              child: Row(
                children: [
                  Expanded(
                    child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  if (r.id == current.id)
                    Glyph(AppIcons.check, size: 16, color: AppColors.accent)
                  else
                    _PlanBadge(isPro: r.isPro),
                ],
              ),
            ),
          ),
      ],
      child: body,
    );
  }
}

class _PlanBadge extends StatelessWidget {
  const _PlanBadge({required this.isPro});

  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isPro ? AppColors.accentTint : AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        isPro ? 'PRO' : 'FREE',
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: isPro ? AppColors.accent : AppColors.textMuted,
        ),
      ),
    );
  }
}

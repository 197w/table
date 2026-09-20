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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final current = ref.watch(currentRestaurantProvider);
    final list = ref.watch(restaurantsProvider).value ?? const [];
    final theme = ref.watch(themeSettingProvider);
    final email = ref.watch(repositoryProvider).email;

    final collapsed = ref.watch(sidebarCollapsedProvider);
    final width = collapsed ? 76.0 : 256.0;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          Align(
            alignment: collapsed ? Alignment.center : Alignment.centerLeft,
            child: Tooltip(
              message: collapsed ? 'Rozwiń menu' : 'Zwiń menu',
              child: PanelPress(
                child: IconButton(
                  icon: const Glyph(AppIcons.menu, size: 18),
                  onPressed: () =>
                      ref.read(sidebarCollapsedProvider.notifier).toggle(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (current != null)
            _RestaurantSwitcher(
              current: current,
              restaurants: list,
              collapsed: collapsed,
            ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final (title, items) in _groups) ...[
                  // Zwinięte menu nie ma miejsca na nagłówki grup, więc zostaje sama kreska.
                  if (collapsed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: AppColors.ring),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
                      child: Text(
                        title.toUpperCase(),
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textDisabled,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  for (final item in items)
                    _SidebarButton(
                      item: item,
                      selected: location.startsWith(item.route),
                      collapsed: collapsed,
                      onTap: () => context.go(item.route),
                    ),
                ],
              ],
            ),
          ),
          Divider(color: AppColors.ring),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Flex(
              direction: collapsed ? Axis.vertical : Axis.horizontal,
              children: [
                if (!collapsed)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                        if (current != null)
                          Text(
                            current.role.label,
                            style: text.bodySmall?.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                PanelPress(
                  child: IconButton(
                    tooltip: collapsed
                        ? '${email ?? ''} · motyw: ${theme.label}'
                        : 'Motyw: ${theme.label}',
                    icon: Glyph(theme.icon, size: 18),
                    onPressed: () {
                      final values = AppThemeSetting.values;
                      ref
                          .read(themeSettingProvider.notifier)
                          .set(values[(theme.index + 1) % values.length]);
                    },
                  ),
                ),
                if (collapsed) const SizedBox(height: 8),
                PanelPress(
                  child: IconButton(
                    tooltip: 'Wyloguj się',
                    icon: const Glyph(AppIcons.signOut, size: 18),
                    onPressed: () => ref.read(repositoryProvider).signOut(),
                  ),
                ),
              ],
            ),
          ),
        ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: AppMotion.easeOut,
      width: width,
      color: PanelDepth.sidebar,
      padding: EdgeInsets.fromLTRB(collapsed ? 12 : 14, 20, collapsed ? 12 : 14, 14),
      // Podczas zwijania treść jest szersza niż pasek, więc ją przycinamy.
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: width - (collapsed ? 24 : 28),
          maxWidth: width - (collapsed ? 24 : 28),
          child: content,
        ),
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.item,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Tooltip(
          message: item.label,
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
                  height: 44,
                  child: Center(
                    child: Glyph(
                      item.icon,
                      size: 20,
                      color: selected ? AppColors.accent : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Glyph(
                  item.icon,
                  size: 18,
                  color: selected ? AppColors.accent : AppColors.textMuted,
                ),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: text.labelLarge?.copyWith(
                    color: selected ? AppColors.text : AppColors.textMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
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
    this.collapsed = false,
  });

  final PanelRestaurant current;
  final List<PanelRestaurant> restaurants;
  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final canSwitch = restaurants.length > 1;

    // W zwiniętym menu zostaje samo logo lokalu.
    if (collapsed) {
      final logo = Tooltip(
        message: '${current.name} · ${current.city}',
        child: Center(
          child: ImageOutline(
            radius: 10,
            child: RestaurantLogo(
              name: current.name,
              logoUrl: current.logoUrl,
              size: 44,
              radius: 10,
            ),
          ),
        ),
      );
      if (!canSwitch) return logo;
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
        child: logo,
      );
    }

    final body = Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ring),
      ),
      child: Row(
        children: [
          ImageOutline(
            radius: 8,
            child: RestaurantLogo(name: current.name, logoUrl: current.logoUrl, size: 34, radius: 8),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelLarge,
                ),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        current.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
          if (canSwitch)
            Glyph(AppIcons.caretDown, size: 16, color: AppColors.textMuted),
        ],
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../features/kiosk/kiosk_screen.dart';
import '../features/onboarding/create_restaurant_screen.dart';
import '../shared/panel_widgets.dart';
import 'app.dart';
import 'panel_theme.dart';
import 'reservation_alerts.dart';
import 'sections.dart';
import 'updater.dart';

const _tabular = [FontFeature.tabularFigures()];

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime t) => '${_two(t.toLocal().hour)}:${_two(t.toLocal().minute)}';

/// Układ panelu: górny pasek (lokal, grupy zakładek, motyw i pracownik), wąski pasek boczny z zakładkami
/// wybranej grupy i zakładkami lokalu na dole, a obok treść zakładki.
class PanelShell extends ConsumerWidget {
  const PanelShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final restaurants = ref.watch(restaurantsProvider);
    // Połączenie na żywo z rezerwacjami działa na każdej zakładce,
    // żeby dźwięk nowej rezerwacji z aplikacji było słychać zawsze.
    final current = ref.watch(currentRestaurantProvider);
    if (current != null && current.isPro) {
      ref.watch(reservationsLiveProvider(current.id).select((s) => s.status));
      // Nowe zamówienie na wynos (gotówka od razu, karta po opłaceniu): dźwięk i powiadomienie na każdej zakładce.
      ref.listen(takeawayOrdersProvider(current.id), (previous, next) {
        final before = previous?.value;
        final now = next.value;
        if (before == null || now == null) return;
        final waiting = {for (final o in before) if (o.stage == TakeawayStage.placed) o.id};
        for (final o in now) {
          if (o.stage == TakeawayStage.placed && !waiting.contains(o.id)) {
            ReservationAlerts.instance.onTakeaway(o, muted: ref.read(alertsMutedProvider));
          }
        }
      });
    }

    // Ekran kuchni na cały ekran: bez pasków, same bileciki.
    if (ref.watch(kitchenFullscreenProvider) && location.startsWith(PanelRoutes.kitchen)) {
      return Scaffold(body: _RouteGuard(location: location, child: child));
    }

    // Grupy według uprawnień zalogowanego pracownika (bez niego: konta panelu).
    final permissions = current == null
        ? const <String>{}
        : ref.watch(effectivePermissionsProvider(current.id)) ?? const <String>{};
    bool allowed(String route) => canOpenRoute(route, permissions);
    final sections = [
      for (final s in PanelSection.values)
        if (s.tabs.any((t) => allowed(t.route))) s,
    ];
    final here = PanelSection.forRoute(location);
    final remembered = PanelSection.byName(ref.watch(panelSectionProvider));
    final section = here ?? (sections.contains(remembered) ? remembered : sections.firstOrNull);
    if (here != null && here != remembered) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(panelSectionProvider.notifier).set(here.name));
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TopBar(
            sections: sections,
            section: section,
            onSection: (s) {
              ref.read(panelSectionProvider.notifier).set(s.name);
              final first = s.tabs.where((t) => allowed(t.route)).firstOrNull;
              if (first != null && !location.startsWith(first.route)) context.go(first.route);
            },
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Rail(
                  location: location,
                  tabs: [
                    for (final t in section?.tabs ?? const <PanelTab>[])
                      if (allowed(t.route)) t,
                  ],
                  placeTabs: [
                    for (final t in placeTabs)
                      if (allowed(t.route)) t,
                  ],
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
                      // Nowe konto restauracji zaczyna od utworzenia lokalu.
                      data: (list) => list.isEmpty
                          ? const CreateRestaurantScreen()
                          : _RouteGuard(location: location, child: child),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pokazuje zakładkę tylko wtedy, gdy stanowisko ma do niej uprawnienie.
/// W przeciwnym razie przenosi do pierwszej dostępnej zakładki.
class _RouteGuard extends ConsumerWidget {
  const _RouteGuard({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentRestaurantProvider);
    if (current == null) return child;
    final permissions = ref.watch(effectivePermissionsProvider(current.id));
    if (permissions == null) return const LoadingView();
    if (canOpenRoute(location, permissions)) {
      // Jedno logowanie pracownika na cały panel. Bez niego każda zakładka pokazuje logowanie.
      final tab = tabForRoute(location);
      if (tab == null) return child;
      if (ref.watch(panelMemberProvider) == null) {
        return const TabLoginGate();
      }
      return child;
    }

    final first = allPanelTabs.where((t) => canOpenRoute(t.route, permissions)).firstOrNull?.route;
    if (first != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(first);
      });
      return const LoadingView();
    }
    return MessageView(
      icon: AppIcons.lock,
      title: 'Brak dostępu do panelu',
      message:
          'Twoje stanowisko nie ma jeszcze żadnych uprawnień. Poproś kierownika o ich ustawienie '
          'w zakładce „Pracownicy” → „Stanowiska”.',
      actionLabel: 'Wyloguj się',
      onAction: () => ref.read(repositoryProvider).signOut(),
    );
  }
}

// ---------------------------------------------------------------
// Górny pasek
// ---------------------------------------------------------------

/// Górny pasek: lokal po lewej, grupy zakładek, nazwa Table na środku, a po prawej nowa wersja,
/// odliczanie do wylogowania, motyw i zalogowany pracownik.
class _TopBar extends ConsumerWidget {
  const _TopBar({required this.sections, required this.section, required this.onSection});

  final List<PanelSection> sections;
  final PanelSection? section;
  final ValueChanged<PanelSection> onSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final current = ref.watch(currentRestaurantProvider);
    final list = ref.watch(restaurantsProvider).value ?? const <PanelRestaurant>[];
    final theme = ref.watch(themeSettingProvider);
    final release = ref.watch(availableUpdateProvider);
    // Ostatnie 10 sekund przed automatycznym wylogowaniem.
    final idle = ref.watch(idleSecondsProvider.select((s) => s >= kIdleLogoutSeconds - 10 ? s : 0));

    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: PanelDepth.sidebar,
        border: Border(bottom: BorderSide(color: AppColors.ring)),
      ),
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          alignment: Alignment.center,
          children: [
            // Nazwa Table na środku paska, gdy jest na nią miejsce.
            if (box.maxWidth >= 1280)
              Text(
                'Table',
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: AppColors.textDisabled,
                ),
              ),
            Row(
              children: [
                if (current != null) _RestaurantSwitcher(current: current, restaurants: list),
                if (sections.isNotEmpty && section != null) ...[
                  const SizedBox(width: 16),
                  for (final s in sections)
                    _SectionTab(section: s, selected: s == section, onTap: () => onSection(s)),
                ],
                const Spacer(),
                // Nowa wersja znaleziona w trakcie pracy: instaluje się dopiero po kliknięciu,
                // żeby nie przerwać obsługi w środku serwisu.
                if (release != null) ...[
                  TextButton.icon(
                    onPressed: () => showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => _UpdateDialog(release: release),
                    ),
                    icon: const Glyph(AppIcons.arrowsClockwise, size: 16),
                    label: Text('Nowa wersja ${release.version}'),
                  ),
                  const SizedBox(width: 8),
                ],
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
                _BareIcon(
                  icon: theme.icon,
                  tooltip: 'Motyw: ${theme.label}',
                  size: 26,
                  onTap: () {
                    final values = AppThemeSetting.values;
                    ThemeFade.run(
                      context,
                      () => ref.read(themeSettingProvider.notifier).set(values[(theme.index + 1) % values.length]),
                    );
                  },
                ),
                const SizedBox(width: 10),
                if (current != null) _MemberMenu(restaurant: current),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lokal w lewym rogu: logo, nazwa i kropka połączenia na żywo. Strzałka i lista tylko wtedy,
/// gdy konto ma kilka lokali.
class _RestaurantSwitcher extends ConsumerWidget {
  const _RestaurantSwitcher({required this.current, required this.restaurants});

  final PanelRestaurant current;
  final List<PanelRestaurant> restaurants;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final canSwitch = restaurants.length > 1;
    final live = current.isPro ? ref.watch(reservationsLiveProvider(current.id).select((s) => s.status)) : null;
    final dot = switch (live) {
      LiveStatus.live => const Color(0xFF2FB673),
      LiveStatus.connecting => const Color(0xFFD99A15),
      LiveStatus.offline => AppColors.error,
      null => null,
    };

    final body = Container(
      height: 42,
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.ring),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ImageOutline(
            radius: 7,
            child: RestaurantLogo(name: current.name, logoUrl: current.logoUrl, size: 30, radius: 7),
          ),
          const SizedBox(width: 10),
          if (dot != null) ...[
            Tooltip(
              message: live == LiveStatus.live ? 'Na żywo' : 'Łączenie z lokalem…',
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              current.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelLarge,
            ),
          ),
          const SizedBox(width: 8),
          _PlanBadge(isPro: current.isPro),
          if (canSwitch) ...[
            const SizedBox(width: 6),
            Glyph(AppIcons.caretDown, size: 14, color: AppColors.textMuted),
          ],
        ],
      ),
    );

    if (!canSwitch) {
      return Tooltip(message: '${current.name} · ${current.city}', child: body);
    }

    return PopupMenuButton<String>(
      tooltip: 'Zmień lokal',
      position: PopupMenuPosition.under,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.ring),
      ),
      onSelected: (id) => ref.read(selectedRestaurantIdProvider.notifier).select(id),
      itemBuilder: (context) => [
        for (final r in restaurants)
          PopupMenuItem(
            value: r.id,
            child: SizedBox(
              width: 220,
              child: Row(
                children: [
                  Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
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

enum _MemberAction { endShift, signOut, startShift, accountSignOut }

/// Zalogowany pracownik w prawym rogu: kółko z inicjałami. Po kliknięciu jego kod, „Zakończ zmianę”
/// i „Wyloguj”, a niżej „Wejdź na zmianę” i konto restauracji.
class _MemberMenu extends ConsumerWidget {
  const _MemberMenu({required this.restaurant});

  final PanelRestaurant restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final member = ref.watch(panelMemberProvider);
    final person = member != null && !member.isAccount ? member : null;
    final code = person == null ? null : ref.watch(staffCodesProvider(restaurant.id)).value?[person.memberId];
    final email = ref.watch(repositoryProvider).email;
    final version = ref.watch(panelVersionProvider).value;
    final since = person?.shiftStartedAt;
    final initials = person == null
        ? ''
        : person.name.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();

    PopupMenuItem<_MemberAction> action(_MemberAction value, AppIconData icon, String label, {bool muted = false}) =>
        PopupMenuItem(
          value: value,
          height: 44,
          child: Row(
            children: [
              Glyph(icon, size: 18, color: muted ? AppColors.textMuted : AppColors.text),
              const SizedBox(width: 12),
              Text(label, style: text.labelLarge?.copyWith(color: muted ? AppColors.textMuted : AppColors.text)),
            ],
          ),
        );

    return PopupMenuButton<_MemberAction>(
      tooltip: member?.name ?? 'Nikt nie jest zalogowany',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      color: AppColors.surface,
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 320),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.ring),
      ),
      onSelected: (value) => switch (value) {
        _MemberAction.endShift => EndShiftDialog.open(context, person!),
        _MemberAction.signOut => ref.read(panelMemberProvider.notifier).signOut(),
        _MemberAction.startShift => ShiftScreen.open(context),
        _MemberAction.accountSignOut => ref.read(repositoryProvider).signOut(),
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          height: 0,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: member == null
              ? Text('Nikt nie jest zalogowany', style: text.labelLarge?.copyWith(color: AppColors.textMuted))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.name, style: text.titleSmall?.copyWith(color: AppColors.text)),
                    const SizedBox(height: 2),
                    Text(
                      [
                        ?member.position,
                        if (since != null) 'na zmianie od ${_hm(since)}',
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                    ),
                    if (code != null) ...[
                      const SizedBox(height: 12),
                      Text('Kod pracownika', style: text.labelSmall?.copyWith(color: AppColors.textMuted)),
                      const SizedBox(height: 2),
                      Text(
                        code,
                        style: text.headlineSmall?.copyWith(
                          color: AppColors.text,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 6,
                          fontFeatures: _tabular,
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const PopupMenuDivider(),
        if (person != null && since != null) action(_MemberAction.endShift, AppIcons.doorOpen, 'Zakończ zmianę'),
        if (member != null) action(_MemberAction.signOut, AppIcons.signOut, 'Wyloguj (${member.name.split(' ').first})'),
        action(_MemberAction.startShift, AppIcons.signIn, 'Wejdź na zmianę'),
        const PopupMenuDivider(),
        PopupMenuItem(
          enabled: false,
          height: 0,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            [?email, if (version != null) 'wersja $version'].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
        ),
        action(_MemberAction.accountSignOut, AppIcons.lock, 'Wyloguj konto restauracji', muted: true),
      ],
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: member == null ? AppColors.surfaceRaised : AppColors.accentTint,
          shape: BoxShape.circle,
        ),
        child: member == null
            ? Glyph(AppIcons.users, size: 18, color: AppColors.textMuted)
            : member.isAccount
            ? Glyph(AppIcons.lock, size: 16, color: AppColors.accent)
            : Text(initials, style: text.labelLarge?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ---------------------------------------------------------------
// Boczny pasek
// ---------------------------------------------------------------

/// Wąski pasek boczny: zakładki wybranej grupy u góry, zakładki lokalu na dole. Same ikony, nazwy w podpowiedziach.
class _Rail extends StatelessWidget {
  const _Rail({required this.location, required this.tabs, required this.placeTabs});

  final String location;
  final List<PanelTab> tabs;
  final List<PanelTab> placeTabs;

  @override
  Widget build(BuildContext context) {
    Widget button(PanelTab t) => _RailButton(
      tab: t,
      selected: location.startsWith(t.route),
      onTap: () => context.go(t.route),
    );
    return Container(
      width: 68,
      decoration: BoxDecoration(
        color: PanelDepth.sidebar,
        border: Border(right: BorderSide(color: AppColors.ring)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          // Zakładki grupy pojawiają się płynnie przy zmianie grupy.
          AnimatedSwitcher(
            duration: PanelMotion.tab,
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topCenter,
              children: [...previous, ?current],
            ),
            child: Column(
              key: ValueKey(tabs.map((t) => t.route).join()),
              children: [for (final t in tabs) button(t)],
            ),
          ),
          const Spacer(),
          if (placeTabs.isNotEmpty) ...[
            SizedBox(width: 36, child: Divider(height: 17, color: AppColors.ring)),
            for (final t in placeTabs) button(t),
          ],
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.tab, required this.selected, required this.onTap});

  final PanelTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: _BareIcon(
        icon: tab.icon,
        tooltip: tab.label,
        selected: selected,
        size: 30,
        box: 46,
        tooltipRight: true,
        onTap: onTap,
      ),
    );
  }
}

/// Sama ikona bez tła i ramki. Wybrana ma wypełnienie (duotone) w kolorze akcentu, najechana myszą jaśnieje.
class _BareIcon extends StatefulWidget {
  const _BareIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.size = 24,
    this.box = 40,
    this.tooltipRight = false,
  });

  final AppIconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;
  final double size;

  /// Pole do kliknięcia wokół ikony.
  final double box;
  /// Podpowiedź po prawej stronie ikony (boczny pasek), a nie pod nią.
  final bool tooltipRight;

  @override
  State<_BareIcon> createState() => _BareIconState();
}

class _BareIconState extends State<_BareIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected
        ? AppColors.accent
        : _hovered
        ? AppColors.text
        : AppColors.textMuted;
    return Tooltip(
      message: widget.tooltip,
      positionDelegate: widget.tooltipRight ? tooltipOnRight : null,
      waitDuration: const Duration(milliseconds: 250),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: PanelPress(
            scale: 0.9,
            child: SizedBox(
              width: widget.box,
              height: widget.box,
              child: Center(
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color),
                  duration: const Duration(milliseconds: 180),
                  builder: (context, c, _) => Glyph(
                    widget.selected ? widget.icon.duotone : widget.icon,
                    size: widget.size,
                    color: c,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Grupa w górnym pasku: sama ikona, a wybrana w kolorze akcentu i z nazwą, która wysuwa się obok.
class _SectionTab extends StatefulWidget {
  const _SectionTab({required this.section, required this.selected, required this.onTap});

  final PanelSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SectionTab> createState() => _SectionTabState();
}

class _SectionTabState extends State<_SectionTab> {
  bool _hovered = false;

  static const _duration = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final selected = widget.selected;
    final color = selected
        ? AppColors.accent
        : _hovered
        ? AppColors.text
        : AppColors.textMuted;
    final tab = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: PanelPress(
          scale: 0.92,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color),
                  duration: const Duration(milliseconds: 180),
                  builder: (context, c, _) => Glyph(
                    selected ? widget.section.icon.duotone : widget.section.icon,
                    size: 26,
                    color: c,
                  ),
                ),
                // Nazwa wybranej grupy wysuwa się zza ikony.
                ClipRect(
                  child: AnimatedAlign(
                    alignment: Alignment.centerLeft,
                    widthFactor: selected ? 1 : 0,
                    duration: _duration,
                    curve: AppMotion.easeOut,
                    child: AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: selected ? _duration : const Duration(milliseconds: 120),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          widget.section.label,
                          maxLines: 1,
                          softWrap: false,
                          style: text.labelLarge?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return selected ? tab : Tooltip(message: widget.section.label, child: tab);
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

/// Instalacja nowej wersji na prośbę obsługi: opis zmian, postęp pobierania, restart.
class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.release});

  final PanelRelease release;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double? _progress;

  Future<void> _install() async {
    setState(() => _busy = true);
    try {
      await PanelUpdater.install(
        widget.release,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final notes = widget.release.notes.trim();
    return AlertDialog(
      title: Text('Nowa wersja ${widget.release.version}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              notes.isEmpty ? 'Poprawki i nowości w panelu.' : notes,
              style: text.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'Panel zamknie się na kilka sekund i uruchomi ponownie. '
              'Niezapisane zmiany, na przykład w Edycji sali, przepadną.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  color: AppColors.accentFill,
                  backgroundColor: AppColors.surfaceRaised,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          style: TextButton.styleFrom(foregroundColor: AppColors.textMuted),
          child: const Text('Później'),
        ),
        FilledButton(
          onPressed: _busy ? null : _install,
          child: const Text('Zainstaluj teraz'),
        ),
      ],
    );
  }
}

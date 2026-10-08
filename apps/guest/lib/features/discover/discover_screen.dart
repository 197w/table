import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/preferences.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'restaurant_cards.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Odkrywaj: wyszukiwarka, kategorie kuchni z własnymi ikonami, szybkie filtry z „Filtry” i „Sortuj”,
/// liczba lokali i przełącznik widoku (karty ze zdjęciem albo zwarte wiersze).
class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(discoverResultsProvider);
    final filter = ref.watch(discoverFilterProvider);
    final location = ref.watch(locationProvider);
    final city = ref.watch(effectiveCityProvider);
    final unit = ref.watch(distanceUnitProvider);
    final layout = ref.watch(discoverLayoutProvider);
    final hasLocation = location.value != null;
    final locationOff = location.hasValue && location.value == null;
    final notifier = ref.read(discoverFilterProvider.notifier);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref
              ..invalidate(citiesProvider)
              ..invalidate(cuisineRowsProvider)
              ..invalidate(searchResultsProvider);
            await ref.read(searchResultsProvider.future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const SliverToBoxAdapter(child: _Header()),
              const SliverToBoxAdapter(child: _SearchField()),
              SliverToBoxAdapter(child: _CuisineRow(selected: filter.cuisine)),
              SliverToBoxAdapter(child: _FilterRow(filter: filter, city: city, hasLocation: hasLocation)),
              if (locationOff && filter.city == null && city != null)
                SliverToBoxAdapter(
                  child: _LocationHint(city: city, onEnable: () => ref.invalidate(locationProvider)),
                ),
              ...results.when(
                skipLoadingOnReload: true,
                loading: () => const [
                  SliverFillRemaining(hasScrollBody: false, child: LoadingView()),
                ],
                error: (e, _) => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorView(error: e, onRetry: () => ref.invalidate(searchResultsProvider)),
                  ),
                ],
                data: (data) {
                  final items = data.items;
                  if (items.isEmpty) {
                    final filtered = data.total > 0;
                    final byCuisine = filter.cuisine != null;
                    return [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: MessageView(
                          icon: AppIcons.search,
                          title: filtered
                              ? 'Żaden lokal nie pasuje do filtrów'
                              : byCuisine
                              ? 'Brak lokali z tą kuchnią'
                              : 'Brak lokali w pobliżu',
                          message: filtered
                              ? 'Bez filtrów jest ${Fmt.restaurants(data.total)}.'
                              : byCuisine
                              ? 'Wybierz inną kuchnię albo pokaż wszystkie.'
                              : 'W promieniu ${Fmt.radius(10, unit)} nie ma jeszcze lokali. Wybierz miasto u góry.',
                          actionLabel: filtered
                              ? 'Wyczyść filtry'
                              : byCuisine
                              ? 'Pokaż wszystkie kuchnie'
                              : null,
                          onAction: filtered
                              ? () => notifier.set(filter.withoutExtras())
                              : byCuisine
                              ? () => notifier.setCuisine(null)
                              : null,
                        ),
                      ),
                    ];
                  }
                  final cards = layout == DiscoverLayout.cards;
                  return [
                    SliverToBoxAdapter(
                      child: _ResultsBar(
                        count: items.length,
                        city: city,
                        unit: unit,
                        layout: layout,
                        onLayout: (l) => ref.read(discoverLayoutProvider.notifier).set(l),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.paddingOf(context).bottom),
                      sliver: SliverList.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => SizedBox(height: cards ? 16 : 8),
                        itemBuilder: (context, i) {
                          final r = items[i];
                          final best = r.id == data.bestMatchId;
                          return cards
                              ? RestaurantCard(restaurant: r, showDistance: hasLocation, unit: unit, bestMatch: best)
                              : RestaurantRow(restaurant: r, showDistance: hasLocation, unit: unit, bestMatch: best);
                        },
                      ),
                    ),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Powitanie na całą szerokość (na telefonie z większą czcionką imię się nie ucina).
class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    // Bez konta albo bez podanego imienia samo „Witaj!”.
    final name = ref.watch(profileProvider).value?.firstName?.trim();
    final greeting = (name == null || name.isEmpty) ? 'Witaj!' : 'Witaj, $name!';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Text(greeting, style: text.headlineMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Wyszukiwarka z jasnym opisem, czego można szukać.
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();

  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(searchQueryProvider);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // Szukamy dopiero, gdy gość przestanie pisać, żeby nie pytać bazy o każdą literę.
  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(searchQueryProvider.notifier).set(value);
    });
    setState(() {});
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(searchQueryProvider.notifier).set('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        height: 50,
        padding: const EdgeInsets.only(left: 14, right: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.ring),
        ),
        child: Row(
          children: [
            Glyph(AppIcons.search, size: 20, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (v) => ref.read(searchQueryProvider.notifier).set(v),
                style: text.bodyLarge,
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'Szukaj lokali, dań albo kuchni',
                  hintStyle: text.bodyLarge?.copyWith(color: AppColors.textMuted),
                ),
              ),
            ),
            if (_controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Wyczyść',
                icon: Glyph(AppIcons.close, size: 18, color: AppColors.textMuted),
                onPressed: _clear,
              ),
          ],
        ),
      ),
    );
  }
}

/// Kategorie kuchni: własne ikony na spokojnym tle, żeby nie konkurowały ze zdjęciami jedzenia niżej.
class _CuisineRow extends ConsumerWidget {
  const _CuisineRow({required this.selected});

  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cuisines = ref.watch(cuisinesProvider);
    if (cuisines.isEmpty) return const SizedBox(height: 8);
    final notifier = ref.read(discoverFilterProvider.notifier);
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
        children: [
          _CuisineTile(
            icon: AppIcons.squaresFour,
            label: 'Wszystkie',
            selected: selected == null,
            onTap: () => notifier.setCuisine(null),
          ),
          for (final c in cuisines)
            _CuisineTile(
              icon: cuisineIcon(c.slug),
              label: cuisineLabel(c.slug),
              selected: selected == c.slug,
              // Drugie dotknięcie wybranej kuchni pokazuje znowu wszystkie.
              onTap: () => notifier.setCuisine(selected == c.slug ? null : c.slug),
            ),
        ],
      ),
    );
  }
}

class _CuisineTile extends StatelessWidget {
  const _CuisineTile({required this.icon, required this.label, required this.selected, required this.onTap});

  final AppIconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Kuchnia: $label',
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.accentTint : AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.accent : AppColors.ring,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Glyph(
                  selected ? icon.duotone : icon,
                  size: 26,
                  color: selected ? AppColors.accent : AppColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppColors.text : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gdzie szukać („W pobliżu” albo miasto), „Filtry” (więcej opcji), „Sortuj” i szybkie filtry zawsze pod ręką.
class _FilterRow extends ConsumerWidget {
  const _FilterRow({required this.filter, required this.city, required this.hasLocation});

  final DiscoverFilter filter;

  /// Miasto, którego lokale są na liście. Null oznacza „W pobliżu”.
  final String? city;
  final bool hasLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(discoverFilterProvider.notifier);
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    final unit = ref.watch(distanceUnitProvider);
    final count = filter.extraCount;
    return SizedBox(
      height: 58,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        children: [
          DropdownPill<String?>(
            icon: AppIcons.mapPin,
            title: 'Gdzie szukać',
            label: city ?? 'W pobliżu',
            selected: city,
            options: [
              DropdownOption(
                value: null,
                label: 'W pobliżu',
                trailing: hasLocation ? Fmt.radius(10, unit) : 'wyłączone',
              ),
              for (final c in cities) DropdownOption(value: c.name, label: c.name, trailing: '${c.restaurants}'),
            ],
            onSelected: (value) {
              notifier.setCity(value);
              if (value == null && !hasLocation) ref.invalidate(locationProvider);
            },
          ),
          const SizedBox(width: 8),
          _Chip(
            icon: AppIcons.sliders,
            label: count == 0 ? 'Filtry' : 'Filtry · $count',
            selected: count > 0,
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              showDragHandle: true,
              builder: (_) => _FilterSheet(hasLocation: hasLocation),
            ),
          ),
          const SizedBox(width: 8),
          DropdownPill<DiscoverSort>(
            icon: AppIcons.sort,
            title: 'Sortuj',
            label: filter.sort.label,
            selected: filter.sort,
            options: [for (final s in DiscoverSort.values) DropdownOption(value: s, label: s.label)],
            onSelected: notifier.setSort,
          ),
          const SizedBox(width: 8),
          _Chip(
            icon: AppIcons.shoppingBag,
            label: 'Zamów online',
            selected: filter.orderOnline,
            onTap: () => notifier.set(filter.copyWith(orderOnline: !filter.orderOnline)),
          ),
          const SizedBox(width: 8),
          _Chip(
            icon: AppIcons.calendarCheck,
            label: 'Rezerwacja w aplikacji',
            selected: filter.bookable,
            onTap: () => notifier.set(filter.copyWith(bookable: !filter.bookable)),
          ),
          const SizedBox(width: 8),
          _Chip(
            icon: AppIcons.star,
            label: 'Ocena 4,5+',
            selected: filter.minRating == 4.5,
            onTap: () => notifier.set(filter.copyWith(minRating: filter.minRating == 4.5 ? null : 4.5)),
          ),
        ],
      ),
    );
  }
}

/// Pigułka filtra: wybrana w kolorze akcentu.
class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.selected, required this.onTap});

  final AppIconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentTint : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppColors.accent : AppColors.ring),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Glyph(icon, size: 16, color: selected ? AppColors.accent : AppColors.textMuted),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: selected ? AppColors.accent : AppColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationHint extends StatelessWidget {
  const _LocationHint({required this.city, required this.onEnable});

  final String city;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
      child: Row(
        children: [
          Glyph(AppIcons.gpsSlash, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Lokalizacja wyłączona. Pokazujemy lokale w mieście $city.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
          TextButton(onPressed: onEnable, child: const Text('Włącz')),
        ],
      ),
    );
  }
}

/// Ile jest lokali (np. „12 lokali”), gdzie, i przełącznik widoku: karty albo wiersze.
class _ResultsBar extends StatelessWidget {
  const _ResultsBar({
    required this.count,
    required this.city,
    required this.unit,
    required this.layout,
    required this.onLayout,
  });

  final int count;
  final String? city;
  final DistanceUnit unit;
  final DiscoverLayout layout;
  final ValueChanged<DiscoverLayout> onLayout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: Fmt.restaurants(count), style: text.titleMedium?.copyWith(fontFeatures: _tabular)),
                  TextSpan(
                    text: city == null ? ' w promieniu ${Fmt.radius(10, unit)}' : ' · $city',
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.ring),
            ),
            child: Row(
              children: [
                _LayoutButton(
                  icon: AppIcons.cards,
                  label: 'Karty ze zdjęciem',
                  selected: layout == DiscoverLayout.cards,
                  onTap: () => onLayout(DiscoverLayout.cards),
                ),
                _LayoutButton(
                  icon: AppIcons.rows,
                  label: 'Zwarta lista',
                  selected: layout == DiscoverLayout.list,
                  onTap: () => onLayout(DiscoverLayout.list),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LayoutButton extends StatelessWidget {
  const _LayoutButton({required this.icon, required this.label, required this.selected, required this.onTap});

  final AppIconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 38,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceRaised : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Glyph(
            selected ? icon.duotone : icon,
            size: 18,
            color: selected ? AppColors.text : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Więcej filtrów: ceny, ocena, rezerwacja, dostawa i odbiór, odległość. Licznik na przycisku pokazuje,
/// ile lokali zostanie po filtrach.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.hasLocation});

  final bool hasLocation;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late DiscoverFilter _f = ref.read(discoverFilterProvider);

  void _set(DiscoverFilter f) => setState(() => _f = f);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final all = ref.watch(searchResultsProvider).value ?? const <RestaurantSummary>[];
    final matching = applyDiscoverFilter(all, _f, hasLocation: widget.hasLocation).length;
    final unit = ref.watch(distanceUnitProvider);

    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 10),
      child: Text(title, style: text.titleSmall),
    );

    Widget toggle(String label, String hint, AppIconData icon, bool value, ValueChanged<bool> onChanged) =>
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: value,
          onChanged: onChanged,
          secondary: Glyph(icon, size: 20, color: value ? AppColors.accent : AppColors.textMuted),
          title: Text(label, style: text.bodyLarge),
          subtitle: Text(hint, style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Filtry', style: text.titleLarge)),
              if (_f.extraCount > 0)
                TextButton(onPressed: () => _set(_f.withoutExtras()), child: const Text('Wyczyść')),
            ],
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  section('Ceny'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var level = 1; level <= 4; level++)
                        _Chip(
                          icon: AppIcons.money,
                          label: Fmt.priceLevel(level),
                          selected: _f.prices.contains(level),
                          onTap: () => _set(
                            _f.copyWith(
                              prices: _f.prices.contains(level)
                                  ? ({..._f.prices}..remove(level))
                                  : {..._f.prices, level},
                            ),
                          ),
                        ),
                    ].map((c) => SizedBox(height: 40, child: c)).toList(),
                  ),
                  section('Ocena kuchni'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (value, label) in const [(null, 'Wszystkie'), (4.0, '4,0+'), (4.5, '4,5+')])
                        SizedBox(
                          height: 40,
                          child: _Chip(
                            icon: AppIcons.star,
                            label: label,
                            selected: _f.minRating == value,
                            onTap: () => _set(_f.copyWith(minRating: value)),
                          ),
                        ),
                    ],
                  ),
                  if (widget.hasLocation) ...[
                    section('Odległość'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final km in const [null, 2, 5])
                          SizedBox(
                            height: 40,
                            child: _Chip(
                              icon: AppIcons.mapPin,
                              label: km == null ? 'Do ${Fmt.radius(10, unit)}' : 'Do ${Fmt.radius(km, unit)}',
                              selected: _f.maxKm == km,
                              onTap: () => _set(_f.copyWith(maxKm: km)),
                            ),
                          ),
                      ],
                    ),
                  ],
                  section('W aplikacji'),
                  toggle(
                    'Rezerwacja w aplikacji',
                    'Stolik od razu, bez dzwonienia',
                    AppIcons.calendarCheck,
                    _f.bookable,
                    (v) => _set(_f.copyWith(bookable: v)),
                  ),
                  toggle(
                    'Dostawa',
                    'Zamówienie z dowozem pod drzwi',
                    AppIcons.moped,
                    _f.delivery,
                    (v) => _set(_f.copyWith(delivery: v)),
                  ),
                  toggle(
                    'Na wynos',
                    'Odbiór osobisty w lokalu',
                    AppIcons.shoppingBag,
                    _f.pickup,
                    (v) => _set(_f.copyWith(pickup: v)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              ref.read(discoverFilterProvider.notifier).set(_f);
              Navigator.pop(context);
            },
            child: Text(matching == 0 ? 'Brak lokali' : 'Pokaż ${Fmt.restaurants(matching)}'),
          ),
        ],
      ),
    );
  }
}

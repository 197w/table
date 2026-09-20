import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../app/preferences.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(searchResultsProvider);
    final filter = ref.watch(discoverFilterProvider);
    final location = ref.watch(locationProvider);
    final city = ref.watch(effectiveCityProvider);
    final unit = ref.watch(distanceUnitProvider);
    final hasLocation = location.value != null;
    final locationOff = location.hasValue && location.value == null;

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
              SliverToBoxAdapter(
                child: _FilterBar(
                  filter: filter,
                  city: city,
                  hasLocation: hasLocation,
                ),
              ),
              if (locationOff && filter.city == null && city != null)
                SliverToBoxAdapter(
                  child: _LocationHint(
                    city: city,
                    onEnable: () => ref.invalidate(locationProvider),
                  ),
                ),
              ...results.when(
                loading: () => const [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: LoadingView(),
                  ),
                ],
                error: (e, _) => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ErrorView(
                      error: e,
                      onRetry: () => ref.invalidate(searchResultsProvider),
                    ),
                  ),
                ],
                data: (items) {
                  if (items.isEmpty) {
                    final byCuisine = filter.cuisine != null;
                    return [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: MessageView(
                          icon: AppIcons.search,
                          title: byCuisine
                              ? 'Brak lokali z tą kuchnią'
                              : 'Brak lokali w pobliżu',
                          message: byCuisine
                              ? 'Wybierz inną kuchnię albo pokaż wszystkie.'
                              : 'W promieniu ${Fmt.radius(10, unit)} nie ma jeszcze lokali. Wybierz miasto z listy.',
                          actionLabel: byCuisine
                              ? 'Pokaż wszystkie kuchnie'
                              : null,
                          onAction: byCuisine
                              ? () => ref
                                    .read(discoverFilterProvider.notifier)
                                    .setCuisine(null)
                              : null,
                        ),
                      ),
                    ];
                  }

                  final ranking = filter.sort == DiscoverSort.ranking;
                  return [
                    SliverToBoxAdapter(
                      child: _ResultsCaption(
                        count: items.length,
                        city: city,
                        unit: unit,
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverList.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _RestaurantCard(
                          restaurant: items[i],
                          position: ranking && items[i].foodScore != null
                              ? i + 1
                              : null,
                          showDistance: hasLocation,
                          unit: unit,
                        ),
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

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    // Bez konta albo bez podanego imienia samo „Witaj!”.
    final name = ref.watch(profileProvider).value?.firstName?.trim();
    final greeting = (name == null || name.isEmpty)
        ? 'Witaj!'
        : 'Witaj, $name!';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Text(
        greeting,
        style: text.headlineMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Wyszukiwarka lokali: sama ikona i słowo „Wyszukaj”, bez ramki i tła.
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
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
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
              style: text.titleMedium,
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Wyszukaj',
                hintStyle: text.titleMedium?.copyWith(color: AppColors.textMuted),
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
    );
  }
}

class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.filter,
    required this.city,
    required this.hasLocation,
  });

  final DiscoverFilter filter;

  /// Miasto, którego lokale są na liście. Null oznacza „W pobliżu”.
  final String? city;
  final bool hasLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cities = ref.watch(citiesProvider).value ?? const <City>[];
    final cuisines = ref.watch(cuisinesProvider);
    final notifier = ref.read(discoverFilterProvider.notifier);
    final unit = ref.watch(distanceUnitProvider);

    return SizedBox(
      height: 64,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        children: [
          DropdownPill<String?>(
            icon: AppIcons.mapPin,
            title: 'Miasto',
            label: city ?? 'W pobliżu',
            selected: city,
            options: [
              DropdownOption(
                value: null,
                label: 'W pobliżu',
                trailing: hasLocation ? Fmt.radius(10, unit) : 'wyłączone',
              ),
              for (final c in cities)
                DropdownOption(
                  value: c.name,
                  label: c.name,
                  trailing: '${c.restaurants}',
                ),
            ],
            onSelected: (value) {
              notifier.setCity(value);
              if (value == null && !hasLocation) {
                ref.invalidate(locationProvider);
              }
            },
          ),
          const SizedBox(width: 8),
          DropdownPill<String?>(
            icon: AppIcons.bowlFood,
            title: 'Kuchnia',
            label: filter.cuisine == null
                ? 'Wszystkie kuchnie'
                : cuisineLabel(filter.cuisine!),
            selected: filter.cuisine,
            options: [
              const DropdownOption(value: null, label: 'Wszystkie kuchnie'),
              for (final c in cuisines)
                DropdownOption(
                  value: c.slug,
                  label: cuisineLabel(c.slug),
                  trailing: '${c.count}',
                ),
            ],
            onSelected: notifier.setCuisine,
          ),
          const SizedBox(width: 8),
          DropdownPill<DiscoverSort>(
            icon: AppIcons.sort,
            title: 'Sortowanie',
            label: filter.sort.label,
            selected: filter.sort,
            options: [
              for (final s in DiscoverSort.values)
                DropdownOption(value: s, label: s.label),
            ],
            onSelected: notifier.setSort,
          ),
        ],
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ),
          TextButton(onPressed: onEnable, child: const Text('Włącz')),
        ],
      ),
    );
  }
}

class _ResultsCaption extends StatelessWidget {
  const _ResultsCaption({
    required this.count,
    required this.city,
    required this.unit,
  });

  final int count;
  final String? city;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final label = city == null
        ? '${Fmt.restaurants(count)} w promieniu ${Fmt.radius(10, unit)}'
        : '${Fmt.restaurants(count)} · $city';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _RestaurantCard extends StatelessWidget {
  const _RestaurantCard({
    required this.restaurant,
    required this.showDistance,
    required this.unit,
    this.position,
  });

  final RestaurantSummary restaurant;
  final DistanceUnit unit;

  /// Miejsce w rankingu. Null przy sortowaniu po odległości albo bez ocen.
  final int? position;

  /// Odległość ma sens tylko liczona od gościa, a nie od środka miasta.
  final bool showDistance;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = restaurant;
    final meta = [
      cuisineLabel(r.cuisine),
      Fmt.priceLevel(r.priceLevel),
      if (showDistance) Fmt.distance(r.distanceM, unit),
    ].join(' · ');

    return PressScale(
      onTap: () => context.push(AppRoutes.restaurant(r.id)),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _RankedMark(name: r.name, logoUrl: r.logoUrl, position: position),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          style: text.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          style: text.bodySmall?.copyWith(
                            color: AppColors.textMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const ArrowBadge(),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
              _StatRow(
                icon: AppIcons.forkKnife,
                label: 'Kuchnia',
                value: FoodScore(
                  score: r.foodAvg,
                  verifiedCount: r.verifiedReviews,
                ),
              ),
              const SizedBox(height: 8),
              _StatRow(
                icon: AppIcons.calendarCheck,
                label: 'Rezerwacja',
                value: Text(
                  r.isPro ? 'W aplikacji' : 'Telefonicznie',
                  style: text.labelLarge?.copyWith(
                    color: r.isPro ? AppColors.accent : AppColors.textMuted,
                    fontWeight: r.isPro ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RankedMark extends StatelessWidget {
  const _RankedMark({required this.name, this.logoUrl, this.position});

  final String name;
  final String? logoUrl;
  final int? position;

  @override
  Widget build(BuildContext context) {
    // Znak siedzi w rogu karty: promień 8 = promień karty 22 minus odstęp 14.
    final mark = ImageOutline(
      radius: 8,
      child: RestaurantLogo(name: name, logoUrl: logoUrl, size: 48, radius: 8),
    );
    if (position == null) return mark;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        mark,
        Positioned(
          right: -6,
          bottom: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 22),
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentFill,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.surface, width: 2),
            ),
            child: Text(
              '$position',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.onAccent,
                fontFeatures: [const FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final AppIconData icon;
  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Glyph(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        ),
        const Spacer(),
        value,
      ],
    );
  }
}

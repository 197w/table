import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Własna ikona kategorii kuchni (zamiast zdjęć, żeby nie konkurowała ze zdjęciami jedzenia).
AppIconData cuisineIcon(String slug) => switch (slug) {
  'polska' => AppIcons.cookingPot,
  'wloska' => AppIcons.pizza,
  'francuska' => AppIcons.wine,
  'grecka' => AppIcons.cheese,
  'hiszpanska' => AppIcons.shrimp,
  'gruzinska' => AppIcons.bread,
  'turecka' => AppIcons.fire,
  'japonska' => AppIcons.fish,
  'chinska' => AppIcons.bowlSteam,
  'tajska' => AppIcons.pepper,
  'wietnamska' => AppIcons.bowlFood,
  'koreanska' => AppIcons.fireSimple,
  'indyjska' => AppIcons.grains,
  'meksykanska' => AppIcons.avocado,
  'amerykanska' => AppIcons.hamburger,
  'wegetarianska' => AppIcons.carrot,
  'weganska' => AppIcons.plant,
  'srodziemnomorska' => AppIcons.fishSimple,
  'kawiarnia' => AppIcons.coffee,
  _ => AppIcons.forkKnife,
};

/// Kolor kuchni na karcie bez zdjęcia: przygaszony, żeby karty bez zdjęć nie krzyczały.
Color cuisineColor(String slug) => switch (slug) {
  'polska' => const Color(0xFFE5484D),
  'wloska' => const Color(0xFF22A06B),
  'francuska' => const Color(0xFF8E6FE0),
  'grecka' => const Color(0xFF3B82F6),
  'hiszpanska' => const Color(0xFFF59E0B),
  'gruzinska' => const Color(0xFFD9772B),
  'turecka' => const Color(0xFFDC5A3C),
  'japonska' => const Color(0xFFE2557A),
  'chinska' => const Color(0xFFE0533F),
  'tajska' => const Color(0xFF3FAE5A),
  'wietnamska' => const Color(0xFF1FA2D8),
  'koreanska' => const Color(0xFFF07D35),
  'indyjska' => const Color(0xFFE8A317),
  'meksykanska' => const Color(0xFF7DB52F),
  'amerykanska' => const Color(0xFFC4782F),
  'wegetarianska' => const Color(0xFF8DBE2E),
  'weganska' => const Color(0xFF2FB98A),
  'srodziemnomorska' => const Color(0xFF16A8BE),
  'kawiarnia' => const Color(0xFFB0813F),
  _ => const Color(0xFF7C8796),
};

/// Zdjęcie lokalu na kartę. Bez zdjęcia: spokojna karta w kolorze kuchni z jej ikoną,
/// żeby wszystkie karty miały ten sam układ niezależnie od tego, co wgrał lokal.
class RestaurantCover extends StatelessWidget {
  const RestaurantCover({
    super.key,
    required this.url,
    required this.cuisine,
    this.height,
    this.compact = false,
  });

  /// Zdjęcie lokalu albo dania. Null: karta z ikoną kuchni.
  final String? url;
  final String cuisine;
  final double? height;

  /// Mała miniatura w widoku listy: bez podpisu kuchni.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    final fallback = _CuisineCover(slug: cuisine, compact: compact);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: url == null
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              // Zanim zdjęcie dojdzie, karta ma już kolor kuchni, a nie białą plamę.
              frameBuilder: (context, child, frame, sync) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
                child: frame == null && !sync ? fallback : child,
              ),
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}

class _CuisineCover extends StatelessWidget {
  const _CuisineCover({required this.slug, required this.compact});

  final String slug;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = cuisineColor(slug);
    final dark = AppColors.palette.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(color.withValues(alpha: dark ? 0.26 : 0.18), AppColors.surface),
            Color.alphaBlend(color.withValues(alpha: dark ? 0.10 : 0.06), AppColors.surface),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Duża, wyblakła ikona w rogu daje karcie charakter bez zdjęcia.
          if (!compact)
            Positioned(
              right: -18,
              bottom: -26,
              child: Glyph(cuisineIcon(slug).duotone, size: 150, color: color.withValues(alpha: 0.16)),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Glyph(cuisineIcon(slug).duotone, size: compact ? 28 : 46, color: color),
                if (!compact) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Kuchnia ${cuisineLabel(slug).toLowerCase()}',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color.lerp(color, AppColors.text, 0.35),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ocena kuchni z gwiazdką: „4,7 (23)”. Bez zweryfikowanych opinii: „Brak ocen”.
class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, required this.restaurant, this.large = false});

  final RestaurantSummary restaurant;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = restaurant;
    if (r.foodAvg == null || r.verifiedReviews == 0) {
      return Text(
        'Brak ocen',
        style: text.labelMedium?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w500),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Glyph(AppIcons.starFill, size: large ? 16 : 14, color: const Color(0xFFE0A21B)),
        const SizedBox(width: 4),
        Text(
          Fmt.rating(r.foodAvg!),
          style: (large ? text.titleSmall : text.labelLarge)?.copyWith(fontFeatures: _tabular),
        ),
        const SizedBox(width: 3),
        Text(
          '(${r.verifiedReviews})',
          style: text.labelMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
        ),
      ],
    );
  }
}

/// Kuchnia, ceny i odległość w jednym wierszu.
String restaurantMeta(RestaurantSummary r, {required bool showDistance, required DistanceUnit unit}) => [
  cuisineLabel(r.cuisine),
  Fmt.priceLevel(r.priceLevel),
  if (showDistance) Fmt.distance(r.distanceM, unit),
].join(' · ');

/// Karta lokalu do przeglądania: zdjęcie na całą szerokość, a nazwa i szczegóły pod nim,
/// więc karta wygląda tak samo bez względu na zdjęcie, które wgrał lokal.
class RestaurantCard extends StatelessWidget {
  const RestaurantCard({
    super.key,
    required this.restaurant,
    required this.showDistance,
    required this.unit,
    this.bestMatch = false,
  });

  final RestaurantSummary restaurant;
  final bool showDistance;
  final DistanceUnit unit;

  /// Najlepsze dopasowanie dla gościa (górna karta przy sortowaniu „Polecane”).
  final bool bestMatch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = restaurant;
    return PressScale(
      onTap: () => context.push(AppRoutes.restaurant(r.id)),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                AspectRatio(aspectRatio: 16 / 9, child: RestaurantCover(url: r.coverUrl, cuisine: r.cuisine)),
                if (bestMatch) const Positioned(top: 12, left: 12, child: BestMatchLabel()),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ImageOutline(
                        radius: 8,
                        child: RestaurantLogo(name: r.name, logoUrl: r.logoUrl, size: 30, radius: 8),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                      ),
                      const SizedBox(width: 8),
                      RatingBadge(restaurant: r),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    restaurantMeta(r, showDistance: showDistance, unit: unit),
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                  ),
                  if (r.matchedDish != null) ...[
                    const SizedBox(height: 4),
                    _MatchedDish(name: r.matchedDish!),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Feature(
                        icon: AppIcons.calendarCheck,
                        label: r.isPro ? 'Rezerwacja online' : 'Rezerwacja telefoniczna',
                        on: r.isPro,
                      ),
                      if (r.canOrder)
                        _Feature(
                          icon: r.deliveryEnabled ? AppIcons.moped : AppIcons.shoppingBag,
                          label: r.deliveryEnabled && r.pickupEnabled
                              ? 'Dostawa i na wynos'
                              : r.deliveryEnabled
                              ? 'Dostawa'
                              : 'Na wynos',
                          on: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Zwarty wiersz lokalu do szybkiego porównania: miniatura, nazwa, szczegóły, ocena i odległość w kolumnie.
class RestaurantRow extends StatelessWidget {
  const RestaurantRow({
    super.key,
    required this.restaurant,
    required this.showDistance,
    required this.unit,
    this.bestMatch = false,
  });

  final RestaurantSummary restaurant;
  final bool showDistance;
  final DistanceUnit unit;
  final bool bestMatch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = restaurant;
    return PressScale(
      onTap: () => context.push(AppRoutes.restaurant(r.id)),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: bestMatch ? AppColors.accent.withValues(alpha: 0.6) : AppColors.ring),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 72, height: 72, child: RestaurantCover(url: r.coverUrl, cuisine: r.cuisine, compact: true)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bestMatch) ...[
                    Text(
                      'Najlepsze dopasowanie',
                      style: text.labelSmall?.copyWith(color: AppColors.accent, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    restaurantMeta(r, showDistance: false, unit: unit),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                  if (r.matchedDish != null) _MatchedDish(name: r.matchedDish!),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _MiniFeature(icon: AppIcons.calendarCheck, on: r.isPro, label: 'Rezerwacja w aplikacji'),
                      if (r.isPro && r.deliveryEnabled) const _MiniFeature(icon: AppIcons.moped, on: true, label: 'Dostawa'),
                      if (r.isPro && r.pickupEnabled)
                        const _MiniFeature(icon: AppIcons.shoppingBag, on: true, label: 'Na wynos'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                RatingBadge(restaurant: r),
                if (showDistance) ...[
                  const SizedBox(height: 6),
                  Text(
                    Fmt.distance(r.distanceM, unit),
                    style: text.labelMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// „Najlepsze dopasowanie” na zdjęciu górnej karty.
class BestMatchLabel extends StatelessWidget {
  const BestMatchLabel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: AppColors.accentFill,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(AppIcons.starFill, size: 13, color: AppColors.onAccent),
          const SizedBox(width: 5),
          Text(
            'Najlepsze dopasowanie',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.onAccent,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchedDish extends StatelessWidget {
  const _MatchedDish({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Glyph(AppIcons.forkKnife, size: 13, color: AppColors.accent),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            'W menu: $name',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.accent),
          ),
        ),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.label, required this.on});

  final AppIconData icon;
  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final color = on ? AppColors.text : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(icon, size: 13, color: on ? AppColors.accent : AppColors.textMuted),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 12, fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }
}

class _MiniFeature extends StatelessWidget {
  const _MiniFeature({required this.icon, required this.on, required this.label});

  final AppIconData icon;
  final bool on;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Glyph(
        icon,
        size: 15,
        color: on ? AppColors.accent : AppColors.textDisabled,
        semanticLabel: label,
      ),
    );
  }
}

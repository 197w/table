import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../app/preferences.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../discover/restaurant_cards.dart';

/// Kolor serca polubionego lokalu: czerwony z kontrastem na zdjęciu (na tle przycisku) w obu motywach.
const likeColor = Color(0xFFE5484D);

/// Serce „Polub”: okrągły przycisk 48 dp na zdjęciu karty albo w pasku strony lokalu.
/// Bez konta prosi o zalogowanie. Zmiana widać od razu, a przy błędzie serce wraca.
class LikeButton extends ConsumerStatefulWidget {
  const LikeButton({
    super.key,
    required this.restaurantId,
    required this.restaurantName,
    this.nativeGlass = false,
    this.glass = false,
  });

  final String restaurantId;
  final String restaurantName;

  /// Na iOS 26 natywny przycisk Liquid Glass (pasek strony lokalu, stoi w miejscu).
  final bool nativeGlass;

  /// Na iOS 26 szkło rysowane przez Fluttera (karty w Odkrywaj: natywny widok w przewijanej liście zacinał).
  final bool glass;

  @override
  ConsumerState<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends ConsumerState<LikeButton> {
  /// Krótkie „podskoczenie” serca przy polubieniu.
  bool _pop = false;

  Future<void> _toggle() async {
    if (ref.read(userIdProvider) == null) {
      showMessage(
        context,
        'Zaloguj się, żeby polubić lokal i mieć go w „Konto” → Polubione.',
        actionLabel: 'Zaloguj się',
        onAction: () => context.push(AppRoutes.withNext(AppRoutes.login, AppRoutes.restaurant(widget.restaurantId))),
      );
      return;
    }
    try {
      final liked = await ref.read(likedIdsProvider.notifier).toggle(widget.restaurantId);
      if (liked && mounted && !MediaQuery.disableAnimationsOf(context)) {
        setState(() => _pop = true);
        Future<void>.delayed(const Duration(milliseconds: 160), () {
          if (mounted) setState(() => _pop = false);
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liked = ref.watch(likedIdsProvider.select((s) => s.value?.contains(widget.restaurantId) ?? false));
    final label = liked
        ? '${widget.restaurantName} jest w polubionych. Stuknij, żeby usunąć'
        : 'Polub ${widget.restaurantName}';
    if ((widget.nativeGlass || widget.glass) && nativeLiquidGlass) {
      return GlassIconButton(
        symbol: liked ? 'heart.fill' : 'heart',
        icon: liked ? AppIcons.heartFill : AppIcons.heart,
        native: widget.nativeGlass,
        frosted: true,
        size: widget.nativeGlass ? 44 : 40,
        iconScale: _pop ? 1.25 : 1,
        color: liked ? likeColor : null,
        label: label,
        onTap: _toggle,
        fallback: const SizedBox.shrink(),
      );
    }
    return Semantics(
      button: true,
      toggled: liked,
      label: liked
          ? '${widget.restaurantName} jest w polubionych. Stuknij, żeby usunąć'
          : 'Polub ${widget.restaurantName}',
      excludeSemantics: true,
      child: PressScale(
        onTap: _toggle,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.ring),
              ),
              child: AnimatedScale(
                scale: _pop ? 1.25 : 1,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: Glyph(
                  liked ? AppIcons.heartFill : AppIcons.heart,
                  size: 20,
                  color: liked ? likeColor : AppColors.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// „Moje” → Polubione: polubione lokale jako karty, ostatnio polubione pierwsze. Serce na karcie usuwa lokal z listy.
class LikedRestaurantsList extends ConsumerWidget {
  const LikedRestaurantsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(likedRestaurantsProvider);
    // Serce zdjęte na tej liście chowa kartę od razu, zanim lista pobierze się od nowa.
    final likedIds = ref.watch(likedIdsProvider).value;
    final unit = ref.watch(distanceUnitProvider);
    final hasLocation = ref.watch(locationProvider).value != null;

    return async.when(
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(likedRestaurantsProvider)),
      data: (all) {
        final items = [
          for (final r in all)
            if (likedIds == null || likedIds.contains(r.id)) r,
        ];
        if (items.isEmpty) {
          return MessageView(
            icon: AppIcons.heart.duotone,
            title: 'Nie masz jeszcze polubionych lokali',
            message: 'Stuknij serce przy lokalu, a znajdziesz go tutaj, kiedy będziesz chciał wrócić.',
            actionLabel: 'Odkrywaj lokale',
            onAction: () => context.go(AppRoutes.discover),
          );
        }
        return RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref
              ..invalidate(likedIdsProvider)
              ..invalidate(likedRestaurantsProvider);
            await ref.read(likedRestaurantsProvider.future);
          },
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + MediaQuery.paddingOf(context).bottom),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, i) =>
                    RestaurantCard(restaurant: items[i], showDistance: hasLocation, unit: unit),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Mały znak polubionego lokalu w zwartym wierszu (bez przycisku; zmienia się na karcie albo stronie lokalu).
class LikedMark extends ConsumerWidget {
  const LikedMark({super.key, required this.restaurant});

  final RestaurantSummary restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(likedIdsProvider.select((s) => s.value?.contains(restaurant.id) ?? false));
    if (!liked) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(right: 6),
      child: Glyph(AppIcons.heartFill, size: 16, color: likeColor),
    );
  }
}

/// Konto → Polubione: polubione lokale (wcześniej zakładka w „Moje”).
class LikedScreen extends StatelessWidget {
  const LikedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: glassLeading(context), title: const Text('Polubione')),
    body: const LikedRestaurantsList(),
  );
}

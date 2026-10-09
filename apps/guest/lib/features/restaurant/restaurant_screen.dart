import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../discover/restaurant_cards.dart';

const _tabular = [FontFeature.tabularFigures()];
const _weekdayNames = ['Poniedziałek', 'Wtorek', 'Środa', 'Czwartek', 'Piątek', 'Sobota', 'Niedziela'];

/// Czas animacji albo zero przy włączonym „Ogranicz ruch”.
Duration _motion(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : Duration(milliseconds: ms);

/// Strona lokalu w stylu listy lokali: zdjęcie na całą szerokość, pod nim nazwa, ocena i czy jest otwarte,
/// szybkie akcje (menu, telefon, mapa, opinie), dania ze zdjęciami, oceny, godziny i opinie.
/// Na dole jedno główne działanie: rezerwacja (obok „Zamów”, gdy lokal przyjmuje zamówienia).
class RestaurantScreen extends ConsumerStatefulWidget {
  const RestaurantScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  ConsumerState<RestaurantScreen> createState() => _RestaurantScreenState();
}

class _RestaurantScreenState extends ConsumerState<RestaurantScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(repositoryProvider).logEvent(widget.restaurantId, 'view');
  }

  Future<void> _call(RestaurantDetail r) async {
    ref.read(repositoryProvider).logEvent(r.id, 'call_click');
    final ok = await launchUrl(Uri(scheme: 'tel', path: r.phone));
    if (!ok && mounted) {
      showMessage(context, 'Nie udało się otworzyć telefonu. Numer: ${r.phone}');
    }
  }

  Future<void> _map(RestaurantDetail r) async {
    final ok = await launchUrl(
      Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '${r.name}, ${r.address}, ${r.city}'}),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) showMessage(context, 'Nie udało się otworzyć mapy. Adres: ${r.address}, ${r.city}');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(restaurantProvider(widget.restaurantId));
    final r = async.value;

    return Scaffold(
      // Przy ładowaniu i błędzie zwykły pasek ze strzałką; strona lokalu ma własny nad zdjęciem.
      appBar: r == null ? AppBar() : null,
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const _Skeleton(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(restaurantProvider(widget.restaurantId))),
        data: (r) => _Page(restaurant: r, onCall: () => _call(r), onMap: () => _map(r)),
      ),
      bottomNavigationBar: r == null ? null : _BottomBar(restaurant: r, onCall: () => _call(r)),
    );
  }
}

class _Page extends ConsumerStatefulWidget {
  const _Page({required this.restaurant, required this.onCall, required this.onMap});

  final RestaurantDetail restaurant;
  final VoidCallback onCall;
  final VoidCallback onMap;

  @override
  ConsumerState<_Page> createState() => _PageState();
}

class _PageState extends ConsumerState<_Page> {
  final _reviewsKey = GlobalKey();
  bool _allReviews = false;

  void _toReviews() {
    final target = _reviewsKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(target, duration: _motion(context, 350), curve: AppMotion.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.restaurant;
    final text = Theme.of(context).textTheme;
    final reviews = ref.watch(reviewsProvider(r.id));
    final dishes = r.menu.fold<int>(0, (sum, s) => sum + s.items.length);
    final description = r.description?.trim();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: CustomScrollView(
          slivers: [
            _Hero(restaurant: r),
            SliverToBoxAdapter(
              child: _Header(restaurant: r, onMap: widget.onMap),
            ),
            SliverToBoxAdapter(
              child: _QuickActions(
                onMenu: dishes > 0 ? () => context.push(AppRoutes.menu(r.id)) : null,
                onCall: widget.onCall,
                onMap: widget.onMap,
                onReviews: _toReviews,
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Features(restaurant: r),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _Description(
                        text: description,
                        style: text.bodyMedium?.copyWith(color: AppColors.textMuted, height: 1.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (dishes > 0)
              SliverToBoxAdapter(
                child: _MenuPreview(restaurant: r, dishes: dishes),
              ),
            const SliverToBoxAdapter(child: SectionTitle('Oceny')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _RatingCard(rating: r.rating),
              ),
            ),
            const SliverToBoxAdapter(child: SectionTitle('Godziny otwarcia')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _HoursCard(hours: r.hours),
              ),
            ),
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _reviewsKey,
                child: SectionTitle(
                  reviews.value == null || reviews.value!.isEmpty ? 'Opinie' : 'Opinie (${reviews.value!.length})',
                  trailing: TextButton(
                    onPressed: () => context.push(AppRoutes.review(r.id)),
                    child: const Text('Napisz opinię'),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: reviews.when(
                loading: () => const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(errorText(e), style: TextStyle(color: AppColors.textMuted)),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Nikt jeszcze nie ocenił tego lokalu. Twoja opinia będzie pierwsza.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    );
                  }
                  final shown = _allReviews ? items : items.take(3).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final review in shown) _ReviewTile(review: review),
                      if (items.length > 3)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: OutlinedButton(
                            onPressed: () => setState(() => _allReviews = !_allReviews),
                            child: Text(
                              _allReviews ? 'Pokaż mniej opinii' : 'Pokaż wszystkie opinie (${items.length})',
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }
}

/// Opis lokalu: najwyżej cztery linie, a „Pokaż więcej” tylko wtedy, gdy tekst naprawdę się nie mieści
/// (sprawdzane przy bieżącej szerokości i czcionce systemu).
class _Description extends StatefulWidget {
  const _Description({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  static const _lines = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: _lines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: overflows && !_expanded ? _lines : null,
              overflow: overflows && !_expanded ? TextOverflow.ellipsis : null,
              style: widget.style,
            ),
            if (overflows)
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(48, 48),
                  alignment: Alignment.centerLeft,
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Pokaż mniej' : 'Pokaż więcej'),
              ),
          ],
        );
      },
    );
  }
}

/// Zdjęcie na całą szerokość. Przy przewijaniu chowa się w pasek z nazwą lokalu.
class _Hero extends StatelessWidget {
  const _Hero({required this.restaurant});

  final RestaurantDetail restaurant;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 960.0);
    final background = Theme.of(context).scaffoldBackgroundColor;
    return SliverAppBar(
      pinned: true,
      expandedHeight: width * 9 / 16,
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leading: Center(
        child: _RoundButton(
          icon: AppIcons.arrowLeft,
          label: 'Wróć',
          onTap: () => context.canPop() ? context.pop() : context.go(AppRoutes.discover),
        ),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, box) {
          final top = MediaQuery.paddingOf(context).top;
          final collapsed = box.maxHeight <= kToolbarHeight + top + 12;
          return FlexibleSpaceBar(
            collapseMode: reduceMotion ? CollapseMode.pin : CollapseMode.parallax,
            expandedTitleScale: 1,
            titlePadding: const EdgeInsetsDirectional.only(start: 64, end: 16, bottom: 16),
            // Nazwa w pasku dopiero po schowaniu zdjęcia, wcześniej jest pod zdjęciem.
            title: AnimatedOpacity(
              opacity: collapsed ? 1 : 0,
              duration: _motion(context, 150),
              child: Text(
                r.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            background: Stack(
              fit: StackFit.expand,
              children: [
                RestaurantCover(url: r.coverPhoto, cuisine: r.cuisine),
                // Przyciemnienie u góry: pasek stanu i przycisk „Wróć” czytelne na każdym zdjęciu.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [Colors.black.withValues(alpha: 0.45), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Okrągły przycisk na zdjęciu (48 dp do dotyku), czytelny na jasnym i ciemnym zdjęciu.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap});

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
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
              child: Glyph(icon, size: 20, color: AppColors.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nazwa, logo, kuchnia, ceny, adres, ocena i czy lokal jest teraz otwarty.
class _Header extends StatelessWidget {
  const _Header({required this.restaurant, required this.onMap});

  final RestaurantDetail restaurant;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final text = Theme.of(context).textTheme;
    final status = r.openStatusAt(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ImageOutline(
                radius: 14,
                child: RestaurantLogo(name: r.name, logoUrl: r.logoUrl, size: 56, radius: 14),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: text.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      '${cuisineLabel(r.cuisine)} · ${Fmt.priceLevel(r.priceLevel)}',
                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _RatingLine(rating: r.rating),
              if (status != null) _StatusLine(open: status.open, label: status.label),
            ],
          ),
          const SizedBox(height: 6),
          // Adres prowadzi do mapy: lokalizacja to jedna z pierwszych rzeczy, których gość szuka.
          Semantics(
            button: true,
            label: 'Adres: ${r.address}, ${r.city}. Otwórz na mapie',
            excludeSemantics: true,
            child: InkWell(
              onTap: onMap,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Glyph(AppIcons.mapPin, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${r.address}, ${r.city}', style: text.bodyMedium)),
                    Glyph(AppIcons.arrowUpRight, size: 16, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingLine extends StatelessWidget {
  const _RatingLine({required this.rating});

  final Rating rating;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final food = rating.food;
    if (rating.verified == 0 || food == null) {
      return Text('Brak ocen', style: text.labelLarge?.copyWith(color: AppColors.textMuted));
    }
    return Semantics(
      label: 'Ocena kuchni ${Fmt.rating(food)} na 5, ${Fmt.reviews(rating.verified)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(AppIcons.starFill, size: 16, color: starColor()),
          const SizedBox(width: 5),
          Text(Fmt.rating(food), style: text.titleSmall?.copyWith(fontFeatures: _tabular)),
          const SizedBox(width: 4),
          Text(
            '(${Fmt.reviews(rating.verified)})',
            style: text.labelLarge?.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// „Otwarte do 22:00” albo „Zamknięte · otwiera jutro o 12:00”: kropka w kolorze i słowo, nie sam kolor.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.open, required this.label});

  final bool open;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = open ? AppColors.accent : AppColors.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            style: text.labelLarge?.copyWith(color: open ? AppColors.accent : AppColors.text, fontFeatures: _tabular),
          ),
        ),
      ],
    );
  }
}

/// Menu, telefon, mapa i opinie pod ręką: ikony na spokojnym tle jak kategorie na liście lokali.
class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onMenu, required this.onCall, required this.onMap, required this.onReviews});

  final VoidCallback? onMenu;
  final VoidCallback onCall;
  final VoidCallback onMap;
  final VoidCallback onReviews;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onMenu != null)
            Expanded(
              child: _ActionTile(icon: AppIcons.bookOpen, label: 'Menu', onTap: onMenu!),
            ),
          Expanded(
            child: _ActionTile(icon: AppIcons.phone, label: 'Zadzwoń', onTap: onCall),
          ),
          Expanded(
            child: _ActionTile(icon: AppIcons.mapTrifold, label: 'Mapa', onTap: onMap),
          ),
          Expanded(
            child: _ActionTile(icon: AppIcons.chatCircle, label: 'Opinie', onTap: onReviews),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap});

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.ring),
                ),
                child: Glyph(icon, size: 22, color: AppColors.text),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Co lokal oferuje w aplikacji: rezerwacja, dostawa, na wynos, zadatek.
class _Features extends StatelessWidget {
  const _Features({required this.restaurant});

  final RestaurantDetail restaurant;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final takeaway = r.canOrder;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FeatureChip(
          icon: r.isPro ? AppIcons.calendarCheck : AppIcons.phone,
          label: r.isPro ? 'Rezerwacja online' : 'Rezerwacja telefoniczna',
          on: r.isPro,
        ),
        if (takeaway && r.deliveryEnabled)
          _FeatureChip(
            icon: AppIcons.moped,
            label: r.deliveryFeeGrosze > 0 ? 'Dostawa ${Fmt.price(r.deliveryFeeGrosze)}' : 'Dostawa za darmo',
            on: true,
          ),
        if (takeaway && r.pickupEnabled) const _FeatureChip(icon: AppIcons.shoppingBag, label: 'Na wynos', on: true),
        if (r.depositMinParty != null && r.depositPerPersonGrosze != null)
          _FeatureChip(icon: AppIcons.coins, label: 'Zadatek od ${Fmt.people(r.depositMinParty!)}', on: false),
      ],
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label, required this.on});

  final AppIconData icon;
  final String label;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 11, 6),
      decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Glyph(icon, size: 15, color: on ? AppColors.accent : AppColors.textMuted),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.text,
                fontFeatures: _tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dania z menu w poziomym pasku, najpierw te ze zdjęciem: jedzenie jest tu najważniejsze.
class _MenuPreview extends StatelessWidget {
  const _MenuPreview({required this.restaurant, required this.dishes});

  final RestaurantDetail restaurant;
  final int dishes;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final text = Theme.of(context).textTheme;
    final all = [for (final s in r.menu) ...s.items];
    final items =
        ([...all]..sort((a, b) {
              final photo = (a.photoUrl == null ? 1 : 0).compareTo(b.photoUrl == null ? 1 : 0);
              if (photo != 0) return photo;
              return (a.available ? 0 : 1).compareTo(b.available ? 0 : 1);
            }))
            .take(10)
            .toList();
    final scaler = MediaQuery.textScalerOf(context);
    const width = 168.0;
    // Zdjęcie 4:3, dwie linie nazwy i cena: wysokość rośnie z czcionką systemu.
    final height = width * 3 / 4 + 12 + scaler.scale(14) * 1.35 * 2 + scaler.scale(14) * 1.35 + 14;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Menu',
          trailing: TextButton(onPressed: () => context.push(AppRoutes.menu(r.id)), child: Text('Całe menu ($dishes)')),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final item = items[i];
              final price = item.priceVaries ? 'od ${Fmt.price(item.priceGrosze)}' : Fmt.price(item.priceGrosze);
              return Semantics(
                button: true,
                label: '${item.name}, $price${item.available ? '' : ', chwilowo niedostępne'}. Otwórz menu',
                excludeSemantics: true,
                child: PressScale(
                  onTap: () => context.push(AppRoutes.menu(r.id)),
                  child: SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: Opacity(
                              opacity: item.available ? 1 : 0.5,
                              child: RestaurantCover(url: item.photoUrl, cuisine: r.cuisine, compact: true),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          item.available ? price : 'Chwilowo niedostępne',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelLarge?.copyWith(
                            color: item.available ? AppColors.accent : AppColors.textMuted,
                            fontFeatures: _tabular,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Ocena kuchni dużą liczbą z gwiazdkami, obok obsługa i atmosfera.
class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.rating});

  final Rating rating;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final food = rating.food;
    if (rating.verified == 0 || food == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            rating.unverified > 0
                ? 'Brak zweryfikowanych opinii. ${Fmt.reviews(rating.unverified)} bez weryfikacji nie wpływa na ranking.'
                : 'Ten lokal nie ma jeszcze ocen.',
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
          ),
        ),
      );
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  label: 'Kuchnia ${Fmt.rating(food)} na 5, ${Fmt.reviews(rating.verified)} zweryfikowanych',
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Fmt.rating(food),
                        style: text.displaySmall?.copyWith(fontWeight: FontWeight.w600, fontFeatures: _tabular),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 1; i <= 5; i++)
                            Glyph(
                              i <= food.round() ? AppIcons.starFill : AppIcons.star,
                              size: 14,
                              color: i <= food.round() ? starColor() : AppColors.textMuted,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(Fmt.reviews(rating.verified), style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      _Bar(label: 'Kuchnia', value: rating.food, emphasized: true),
                      _Bar(label: 'Obsługa', value: rating.service),
                      _Bar(label: 'Atmosfera', value: rating.ambience),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Liczą się tylko opinie po rezerwacji albo z paragonem.',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.value, this.emphasized = false});

  final String label;
  final double? value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final v = value ?? 0;
    return Semantics(
      label: '$label ${value == null ? 'brak oceny' : '${Fmt.rating(v)} na 5'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
                  color: emphasized ? AppColors.text : AppColors.textMuted,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: v / 5,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceRaised,
                  color: emphasized ? AppColors.accent : AppColors.textMuted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              value == null ? '–' : Fmt.rating(v),
              style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: _tabular),
            ),
          ],
        ),
      ),
    );
  }
}

/// Godziny otwarcia na karcie, dzisiejszy dzień wyróżniony.
class _HoursCard extends StatelessWidget {
  const _HoursCard({required this.hours});

  final List<OpeningHours> hours;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          children: [
            for (var day = 1; day <= 7; day++)
              Builder(
                builder: (context) {
                  OpeningHours? h;
                  for (final e in hours) {
                    if (e.weekday == day) h = e;
                  }
                  final isToday = day == today;
                  final value = h == null ? 'Zamknięte' : '${h.opens}–${h.closes}';
                  final style = TextStyle(
                    color: isToday ? AppColors.text : AppColors.textMuted,
                    fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                    fontFeatures: _tabular,
                  );
                  return Semantics(
                    label: '${_weekdayNames[day - 1]}: $value${isToday ? ', dzisiaj' : ''}',
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(child: Text(_weekdayNames[day - 1], style: style)),
                          if (isToday) ...[const Tag('DZIŚ'), const SizedBox(width: 10)],
                          Text(value, style: style),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final author = review.isMine ? '${review.author} (ty)' : review.author;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle),
                      child: Text(
                        review.author.isEmpty ? '?' : review.author.characters.first.toUpperCase(),
                        style: text.titleSmall?.copyWith(color: AppColors.accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(author, style: text.titleSmall),
                        Text(
                          Fmt.dayShort(review.createdAt),
                          style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _VerificationTag(review: review),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Score(label: 'Kuchnia', value: review.food),
                  _Score(label: 'Obsługa', value: review.service),
                  _Score(label: 'Atmosfera', value: review.ambience),
                ],
              ),
              if (review.body != null && review.body!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(review.body!, style: text.bodyMedium?.copyWith(height: 1.5)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Oznaczenie weryfikacji opinii. Mieści się w jednej linii, gdy zajmuje najwyżej 40% szerokości karty;
/// dłuższe („Zweryfikowana paragonem”) przechodzi do drugiej linii między słowami, nigdy w środku słowa,
/// a imię autora dostaje resztę miejsca.
class _VerificationTag extends StatelessWidget {
  const _VerificationTag({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final label = review.verificationLabel.toUpperCase();
    // Ten sam styl co w Tag z table_core, żeby zmierzyć napis tak, jak zostanie narysowany.
    const style = TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double width(String value) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    const padding = 16.0 + 2; // Tag ma 8 px z każdej strony; zapas na zaokrąglenia.
    final full = width(label) + padding;
    final longestWord = label.split(' ').map(width).fold<double>(0, (a, b) => a > b ? a : b) + padding;
    final card = MediaQuery.sizeOf(context).width.clamp(0.0, 960.0) - 32 - 28;
    final tagWidth = full <= card * 0.4 ? full : longestWord.clamp(0.0, card * 0.55);
    return SizedBox(
      width: tagWidth,
      child: Align(
        alignment: Alignment.centerRight,
        child: Tag(label, color: review.isVerified ? AppColors.accent : AppColors.textMuted),
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label $value na 5',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 9, 4),
        decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label ',
              style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 12, color: AppColors.textMuted),
            ),
            Glyph(AppIcons.starFill, size: 11, color: starColor()),
            const SizedBox(width: 3),
            Text(
              '$value',
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
                fontFeatures: _tabular,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Jedno główne działanie na dole: rezerwacja (albo telefon w planie Free), obok „Zamów”, gdy lokal przyjmuje
/// zamówienia. Przy dużej czcionce przyciski stają jeden pod drugim, żeby napisy się nie ucinały.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.restaurant, required this.onCall});

  final RestaurantDetail restaurant;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    final dishes = r.menu.fold<int>(0, (sum, s) => sum + s.items.length);
    final order = r.canOrder && dishes > 0;
    final stacked = MediaQuery.textScalerOf(context).scale(16) > 20;
    final primary = r.isPro
        ? FilledButton(onPressed: () => context.push(AppRoutes.booking(r.id)), child: const Text('Zarezerwuj stolik'))
        : FilledButton.icon(
            onPressed: onCall,
            icon: const Glyph(AppIcons.phone, size: 20),
            label: const Text('Zadzwoń, żeby zarezerwować'),
          );
    final secondary = order
        ? OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.orderMenu(r.id)),
            icon: Glyph(r.deliveryEnabled ? AppIcons.moped : AppIcons.shoppingBag, size: 20),
            label: const Text('Zamów'),
          )
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: AppColors.ring)),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: secondary == null
            ? primary
            : stacked
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [primary, const SizedBox(height: 8), secondary],
              )
            : Row(
                children: [
                  Expanded(flex: 2, child: secondary),
                  const SizedBox(width: 10),
                  Expanded(flex: 3, child: primary),
                ],
              ),
      ),
    );
  }
}

/// Szkielet strony, zanim dane dojdą (bez animacji).
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(6)),
    );
    return ExcludeSemantics(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(color: AppColors.surfaceRaised),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bar(220, 22),
                const SizedBox(height: 10),
                bar(140, 14),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (var i = 0; i < 4; i++)
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(color: AppColors.surfaceRaised, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

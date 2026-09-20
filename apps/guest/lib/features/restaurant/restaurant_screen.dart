import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:table_core/table_core.dart';

import '../../app/app.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

const _weekdayNames = ['Pon', 'Wt', 'Śr', 'Czw', 'Pt', 'Sob', 'Nie'];

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
      showMessage(
        context,
        'Nie udało się otworzyć telefonu. Numer: ${r.phone}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(restaurantProvider(widget.restaurantId));

    return Scaffold(
      appBar: AppBar(),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () =>
              ref.invalidate(restaurantProvider(widget.restaurantId)),
        ),
        data: (r) => _Body(restaurant: r),
      ),
      bottomNavigationBar: async.value == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: async.value!.isPro
                  ? FilledButton(
                      onPressed: () =>
                          context.push(AppRoutes.booking(widget.restaurantId)),
                      child: const Text('Zarezerwuj stolik'),
                    )
                  : FilledButton.icon(
                      onPressed: () => _call(async.value!),
                      icon: const Glyph(AppIcons.phone, size: 20),
                      label: const Text('Zadzwoń, żeby zarezerwować'),
                    ),
            ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.restaurant});

  final RestaurantDetail restaurant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = restaurant;
    final text = Theme.of(context).textTheme;
    final reviews = ref.watch(reviewsProvider(r.id));

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Row(
            children: [
              ImageOutline(
                radius: 16,
                child: RestaurantLogo(name: r.name, logoUrl: r.logoUrl, size: 64),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: text.headlineMedium),
                    const SizedBox(height: 4),
                    Text(
                      '${cuisineLabel(r.cuisine)} · ${Fmt.priceLevel(r.priceLevel)}',
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Glyph(AppIcons.mapPin, size: 18, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${r.address}, ${r.city}')),
                ],
              ),
              if (r.description != null) ...[
                const SizedBox(height: 12),
                Text(
                  r.description!,
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
              ],
              if (r.isPro) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.buyGiftCard(r.id)),
                  icon: const Glyph(AppIcons.envelope, size: 18),
                  label: const Text('Kup kartę podarunkową'),
                ),
              ],
            ],
          ),
        ),
        const SectionTitle('Oceny'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _RatingCard(rating: r.rating),
        ),
        const SectionTitle('Godziny otwarcia'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _HoursTable(hours: r.hours),
        ),
        if (r.menu.isNotEmpty) ...[
          const SectionTitle('Menu'),
          for (final section in r.menu) _MenuSectionView(section: section),
        ],
        SectionTitle(
          'Opinie',
          trailing: TextButton(
            onPressed: () => context.push(AppRoutes.review(r.id)),
            child: const Text('Napisz opinię'),
          ),
        ),
        reviews.when(
          loading: () =>
              const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              errorText(e),
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          data: (items) => items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Nikt jeszcze nie ocenił tego lokalu.',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              : Column(
                  children: [
                    for (final review in items) _ReviewTile(review: review),
                  ],
                ),
        ),
      ],
    );
  }
}

class _RatingCard extends StatelessWidget {
  const _RatingCard({required this.rating});

  final Rating rating;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (rating.verified == 0) {
      return Card(
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Bar(label: 'Kuchnia', value: rating.food, emphasized: true),
            _Bar(label: 'Obsługa', value: rating.service),
            _Bar(label: 'Atmosfera', value: rating.ambience),
            const SizedBox(height: 8),
            Text(
              'Na podstawie: ${Fmt.reviews(rating.verified)} zweryfikowanych'
              '${rating.unverified > 0 ? '. Niezweryfikowane: ${rating.unverified}, nie liczą się do rankingu.' : '.'}',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final double? value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final v = value ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
                color: emphasized ? AppColors.text : AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
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
          const SizedBox(width: 12),
          SizedBox(
            width: 28,
            child: Text(
              value == null ? '–' : Fmt.rating(v),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoursTable extends StatelessWidget {
  const _HoursTable({required this.hours});

  final List<OpeningHours> hours;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday;
    return Column(
      children: [
        for (var day = 1; day <= 7; day++)
          Builder(
            builder: (context) {
              OpeningHours? h;
              for (final e in hours) {
                if (e.weekday == day) h = e;
              }
              final isToday = day == today;
              final style = TextStyle(
                color: isToday ? AppColors.text : AppColors.textMuted,
                fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
                fontFeatures: const [FontFeature.tabularFigures()],
              );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(_weekdayNames[day - 1], style: style),
                    ),
                    Text(
                      h == null ? 'Zamknięte' : '${h.opens}–${h.closes}',
                      style: style,
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 8),
                      const Tag('DZIŚ'),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _MenuSectionView extends StatelessWidget {
  const _MenuSectionView({required this.section});

  final MenuSection section;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.name.toUpperCase(),
            style: text.labelMedium?.copyWith(
              color: AppColors.accent,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          for (final item in section.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: text.titleSmall),
                        if (item.description != null)
                          Text(
                            item.description!,
                            style: text.bodySmall?.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        if (item.allergens.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Alergeny: ${item.allergens.join(', ')}',
                              style: text.bodySmall?.copyWith(
                                color: AppColors.textDisabled,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    Fmt.price(item.priceGrosze),
                    style: text.titleSmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
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

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      review.isMine ? '${review.author} (ty)' : review.author,
                      style: text.titleSmall,
                    ),
                  ),
                  Text(
                    Fmt.dayShort(review.createdAt),
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Kuchnia ${review.food} · Obsługa ${review.service} · Atmosfera ${review.ambience}',
                style: text.bodySmall?.copyWith(
                  color: AppColors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (review.body != null) ...[
                const SizedBox(height: 8),
                Text(review.body!),
              ],
              const SizedBox(height: 10),
              Tag(
                review.verificationLabel.toUpperCase(),
                color: review.isVerified
                    ? AppColors.accent
                    : AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

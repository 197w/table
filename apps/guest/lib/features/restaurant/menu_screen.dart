import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Całe menu lokalu na osobnym ekranie. U góry przypięte nazwy działów:
/// stuknięcie przewija do działu, żeby na telefonie nie przewijać wszystkiego ręcznie.
class RestaurantMenuScreen extends ConsumerStatefulWidget {
  const RestaurantMenuScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  ConsumerState<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends ConsumerState<RestaurantMenuScreen> {
  final _keys = <String, GlobalKey>{};

  void _jump(String sectionId) {
    final target = _keys[sectionId]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 300),
      curve: AppMotion.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(restaurantProvider(widget.restaurantId));
    return Scaffold(
      appBar: AppBar(title: Text(async.value == null ? 'Menu' : 'Menu · ${async.value!.name}')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(restaurantProvider(widget.restaurantId)),
        ),
        data: (r) {
          final sections = [for (final s in r.menu) if (s.items.isNotEmpty) s];
          if (sections.isEmpty) {
            return const MessageView(
              icon: AppIcons.bookOpen,
              title: 'Menu jest puste',
              message: 'Lokal nie dodał jeszcze dań.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sections.length > 1)
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                    children: [
                      for (final s in sections)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            label: Text(s.name),
                            onPressed: () => _jump(s.id),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final s in sections)
                          Padding(
                            key: _keys.putIfAbsent(s.id, GlobalKey.new),
                            padding: const EdgeInsets.only(bottom: 16),
                            child: MenuSectionCard(section: s),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Dział menu na karcie: wyraźny nagłówek i dania oddzielone liniami.
class MenuSectionCard extends StatelessWidget {
  const MenuSectionCard({super.key, required this.section, this.limit});

  final MenuSection section;

  /// Ile dań pokazać (podgląd na stronie lokalu). Null: wszystkie.
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final items = limit == null ? section.items : section.items.take(limit!).toList();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(section.name, style: text.titleLarge)),
                Text(
                  _dishes(section.items.length),
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final (i, item) in items.indexed) ...[
              if (i > 0) Divider(height: 1, color: AppColors.ring),
              MenuItemTile(item: item),
            ],
          ],
        ),
      ),
    );
  }
}

String _dishes(int n) {
  if (n == 1) return '1 danie';
  final last = n % 10;
  final lastTwo = n % 100;
  return last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14) ? '$n dania' : '$n dań';
}

/// Jedno danie: nazwa i cena dużym drukiem, pod spodem opis, warianty, dodatki i alergeny.
class MenuItemTile extends StatelessWidget {
  const MenuItemTile({super.key, required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: item.available ? null : AppColors.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                item.variants.isEmpty ? Fmt.price(item.priceGrosze) : 'od ${Fmt.price(item.priceGrosze)}',
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: item.available ? AppColors.accent : AppColors.textMuted,
                  fontFeatures: _tabular,
                ),
              ),
            ],
          ),
          if (!item.available)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Chwilowo niedostępne',
                style: text.bodyMedium?.copyWith(color: AppColors.error),
              ),
            ),
          if (item.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(item.description!, style: muted),
            ),
          // Warianty z cenami, np. „Mała 25 zł · Duża 39 zł”.
          if (item.variants.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final v in item.variants)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceRaised,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${v.name}  ${Fmt.price(v.priceGrosze)}',
                        style: text.bodyMedium?.copyWith(fontFeatures: _tabular),
                      ),
                    ),
                ],
              ),
            ),
          if (item.addons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Dodatki: ${item.addons.map((a) => '${a.name.toLowerCase()} +${Fmt.price(a.priceGrosze)}').join(', ')}',
                style: muted,
              ),
            ),
          if (item.allergens.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Alergeny: ${item.allergens.join(', ')}',
                style: text.bodySmall?.copyWith(color: AppColors.textDisabled),
              ),
            ),
        ],
      ),
    );
  }
}

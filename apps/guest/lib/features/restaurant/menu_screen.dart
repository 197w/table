import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Całe menu lokalu na osobnym ekranie. U góry przypięte nazwy działów: stuknięcie przewija do działu,
/// a przy przewijaniu podświetla się dział, który właśnie widać.
class RestaurantMenuScreen extends ConsumerStatefulWidget {
  const RestaurantMenuScreen({super.key, required this.restaurantId});

  final String restaurantId;

  @override
  ConsumerState<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends ConsumerState<RestaurantMenuScreen> {
  final _keys = <String, GlobalKey>{};
  final _chipKeys = <String, GlobalKey>{};
  final _scrollKey = GlobalKey();

  /// Dział widoczny u góry listy (podświetlony w pasku działów).
  String? _current;

  /// Po stuknięciu działu przewijanie samo ustawia podświetlenie, bez przeskakiwania po drodze.
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    // Strona lokalu pod spodem trzyma stare dane. Menu pobiera je od nowa (np. nowe zdjęcia dań),
    // a do czasu odpowiedzi widać poprzednie.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(restaurantProvider(widget.restaurantId));
    });
  }

  Duration get _duration => MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 300);

  Future<void> _jump(String sectionId) async {
    final target = _keys[sectionId]?.currentContext;
    if (target == null) return;
    setState(() => _current = sectionId);
    _showChip(sectionId);
    _jumping = true;
    await Scrollable.ensureVisible(target, duration: _duration, curve: AppMotion.easeOut);
    _jumping = false;
  }

  void _showChip(String sectionId) {
    final chip = _chipKeys[sectionId]?.currentContext;
    if (chip != null) Scrollable.ensureVisible(chip, duration: _duration, alignment: 0.3);
  }

  /// Który dział jest teraz u góry listy: ostatni, którego nagłówek minął górną krawędź.
  void _spy(List<MenuSection> sections) {
    if (_jumping) return;
    final list = _scrollKey.currentContext?.findRenderObject() as RenderBox?;
    if (list == null) return;
    final top = list.localToGlobal(Offset.zero).dy + 24;
    String? current = sections.firstOrNull?.id;
    for (final s in sections) {
      final box = _keys[s.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      if (box.localToGlobal(Offset.zero).dy <= top) current = s.id;
    }
    if (current != _current) {
      setState(() => _current = current);
      if (current != null) _showChip(current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(restaurantProvider(widget.restaurantId));
    return Scaffold(
      appBar: AppBar(title: Text(async.value == null ? 'Menu' : 'Menu · ${async.value!.name}')),
      body: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(restaurantProvider(widget.restaurantId))),
        data: (r) {
          final sections = [
            for (final s in r.menu)
              if (s.items.isNotEmpty) s,
          ];
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
                // Pasek działów: pole dotyku 48 dp, rośnie z czcionką systemu.
                SizedBox(
                  height: (MediaQuery.textScalerOf(context).scale(14) * 1.3 + 22).clamp(48.0, 120.0) + 14,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    children: [
                      for (final s in sections)
                        Padding(
                          key: _chipKeys.putIfAbsent(s.id, GlobalKey.new),
                          padding: const EdgeInsets.only(right: 8),
                          child: _SectionChip(
                            label: s.name,
                            selected: (_current ?? sections.first.id) == s.id,
                            onTap: () => _jump(s.id),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => ref.refresh(restaurantProvider(widget.restaurantId).future),
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (_) {
                      _spy(sections);
                      return false;
                    },
                    child: SingleChildScrollView(
                      key: _scrollKey,
                      physics: const AlwaysScrollableScrollPhysics(),
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Dział menu w pasku u góry: wybrany w kolorze akcentu (i z grubszym obrysem, nie tylko kolorem).
class _SectionChip extends StatelessWidget {
  const _SectionChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Dział menu: $label',
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentTint : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppColors.accent : AppColors.ring, width: selected ? 1.5 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
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
                Text(_dishes(section.items.length), style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
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
    final details = Padding(
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
                item.priceVaries ? 'od ${Fmt.price(item.priceGrosze)}' : Fmt.price(item.priceGrosze),
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
              child: Text('Chwilowo niedostępne', style: text.bodyMedium?.copyWith(color: AppColors.error)),
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
                      decoration: BoxDecoration(color: AppColors.surfaceRaised, borderRadius: BorderRadius.circular(8)),
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
              // Przygaszony, ale z kontrastem co najmniej 4,5:1: alergeny to ważna informacja.
              child: Text(
                'Alergeny: ${item.allergens.join(', ')}',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ),
        ],
      ),
    );
    final photo = item.photoUrl;
    if (photo == null) return details;
    // Zdjęcie dania po prawej. Stuknięcie powiększa je na cały ekran.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: details),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 0, 12),
          child: Semantics(
            button: true,
            label: 'Powiększ zdjęcie: ${item.name}',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  clipBehavior: Clip.antiAlias,
                  insetPadding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InteractiveViewer(child: Image.network(photo, fit: BoxFit.contain)),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(item.name, style: text.titleMedium),
                      ),
                    ],
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  photo,
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  cacheWidth: 264,
                  errorBuilder: (_, _, _) => const SizedBox(width: 88, height: 88),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

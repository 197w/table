import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/panel_widgets.dart';

const _tabular = [FontFeature.tabularFigures()];

enum _Sort {
  recent('Ostatnia wizyta'),
  visits('Wizyty'),
  spent('Wydatki');

  const _Sort(this.label);
  final String label;
}

String _plural(int n, String one, String few, String many) {
  if (n == 1) return '1 $one';
  final isFew = n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14);
  return '$n ${isFew ? few : many}';
}

/// Baza klientów: goście z rezerwacji i zamówień na wynos. Wizyty, nieobecności, zamówienia, wydatki,
/// ostatnia wizyta i najbliższa rezerwacja. Uprawnienie „Baza klientów”.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  var _sort = _Sort.recent;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Customer> _visible(List<Customer> all) {
    final query = _search.text.trim().toLowerCase();
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    final list = [
      for (final c in all)
        if (query.isEmpty ||
            c.name.toLowerCase().contains(query) ||
            (digits.length >= 3 && (c.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '').contains(digits)))
          c,
    ];
    switch (_sort) {
      case _Sort.recent:
        break;
      case _Sort.visits:
        list.sort((a, b) => (b.visits + b.orders).compareTo(a.visits + a.orders));
      case _Sort.spent:
        list.sort((a, b) => b.spentGrosze.compareTo(a.spentGrosze));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = ref.watch(currentRestaurantProvider);
    if (restaurant == null) return const LoadingView();
    final async = ref.watch(customersProvider(restaurant.id));
    final all = async.value ?? const <Customer>[];
    final returning = all.where((c) => c.returning).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          below: Row(
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Szukaj po imieniu albo telefonie',
                    isDense: true,
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Glyph(AppIcons.search, size: 18, color: AppColors.textMuted),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SegmentedTabs<_Sort>(
                options: [for (final s in _Sort.values) (s, s.label)],
                selected: _sort,
                onChanged: (s) => setState(() => _sort = s),
              ),
              const Spacer(),
              if (all.isNotEmpty) ...[
                PanelPill(_plural(all.length, 'klient', 'klientów', 'klientów'), icon: AppIcons.userList),
                const SizedBox(width: 8),
                PanelPill(_plural(returning, 'powracający', 'powracający', 'powracających'), icon: AppIcons.arrowsClockwise),
              ],
            ],
          ),
        ),
        Expanded(
          child: async.when(
            skipLoadingOnReload: true,
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(customersProvider(restaurant.id))),
            data: (all) {
              if (all.isEmpty) {
                return const MessageView(
                  icon: AppIcons.userList,
                  title: 'Brak klientów',
                  message: 'Goście z rezerwacji i zamówień na wynos pojawią się tutaj.',
                );
              }
              final list = _visible(all);
              return Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _HeaderRow(),
                      Divider(height: 1, color: AppColors.ring),
                      Expanded(
                        child: list.isEmpty
                            ? const MessageView(
                                icon: AppIcons.search,
                                title: 'Nikogo nie znaleziono',
                                message: 'Sprawdź pisownię albo wpisz kilka cyfr telefonu.',
                              )
                            : ListView.separated(
                                itemCount: list.length,
                                separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.ring),
                                itemBuilder: (context, i) => _CustomerRow(customer: list[i]),
                              ),
                      ),
                    ],
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

/// Szerokości kolumn liczb w tabeli klientów.
const _numberColumn = 104.0;
const _dateColumn = 132.0;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textMuted);
    Widget cell(String label, double width) =>
        SizedBox(width: width, child: Text(label, textAlign: TextAlign.end, style: style));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Expanded(child: Text('Gość', style: style)),
          cell('Wizyty', _numberColumn),
          cell('Nieobecności', _numberColumn),
          cell('Na wynos', _numberColumn),
          cell('Wydatki', _numberColumn + 16),
          cell('Ostatnio', _dateColumn),
          cell('Następna', _dateColumn),
        ],
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = customer;
    final value = text.bodyLarge?.copyWith(fontFeatures: _tabular);
    Widget cell(String label, double width, {Color? color}) => SizedBox(
      width: width,
      child: Text(label, textAlign: TextAlign.end, style: value?.copyWith(color: color)),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                    ),
                    if (c.fromApp) ...[
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Ma konto w aplikacji Table',
                        child: Glyph(AppIcons.deviceMobile, size: 14, color: AppColors.accent),
                      ),
                    ],
                    if (c.returning) ...[
                      const SizedBox(width: 6),
                      const Tooltip(
                        message: 'Wraca do lokalu',
                        child: Glyph(AppIcons.starFill, size: 13, color: Color(0xFFE0A21B)),
                      ),
                    ],
                  ],
                ),
                if (c.phone != null)
                  SelectableText(
                    c.phone!,
                    style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                  ),
              ],
            ),
          ),
          cell('${c.visits}', _numberColumn),
          cell('${c.noShows}', _numberColumn, color: c.noShows > 0 ? AppColors.error : AppColors.textMuted),
          cell('${c.orders}', _numberColumn, color: c.orders > 0 ? null : AppColors.textMuted),
          cell(c.spentGrosze > 0 ? Fmt.price(c.spentGrosze) : '—', _numberColumn + 16,
              color: c.spentGrosze > 0 ? null : AppColors.textMuted),
          cell(c.lastVisit == null ? '—' : Fmt.dayShort(c.lastVisit!), _dateColumn,
              color: c.lastVisit == null ? AppColors.textMuted : null),
          cell(c.nextReservation == null ? '—' : Fmt.dayShort(c.nextReservation!), _dateColumn,
              color: c.nextReservation == null ? AppColors.textMuted : AppColors.accent),
        ],
      ),
    );
  }
}

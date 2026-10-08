import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_core/table_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/notes_view.dart';
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

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}

/// Baza klientów: goście z rezerwacji i zamówień na wynos. Po lewej lista z wyszukiwaniem, po prawej
/// wybrany klient (liczby, historia wizyt, notatki zespołu) albo podsumowanie wszystkich klientów.
/// Uprawnienie „Baza klientów”.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  var _sort = _Sort.recent;
  String? _selected;

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
            (c.company?.toLowerCase().contains(query) ?? false) ||
            (c.address?.toLowerCase().contains(query) ?? false) ||
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

  void _select(String? key) => setState(() => _selected = _selected == key ? null : key);

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
              SegmentedTabs<_Sort>(
                options: [for (final s in _Sort.values) (s, s.label)],
                selected: _sort,
                onChanged: (s) => setState(() => _sort = s),
              ),
              const Spacer(),
              if (all.isNotEmpty) ...[
                PanelPill(_plural(all.length, 'klient', 'klientów', 'klientów'), icon: AppIcons.userList),
                const SizedBox(width: 8),
                PanelPill(
                  _plural(returning, 'powracający', 'powracający', 'powracających'),
                  icon: AppIcons.arrowsClockwise,
                ),
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
              final selected = all.where((c) => c.key == _selected).firstOrNull;
              return Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 320,
                      child: _CustomerList(
                        search: _search,
                        customers: list,
                        sort: _sort,
                        selectedKey: selected?.key,
                        onSearch: () => setState(() {}),
                        onSelect: _select,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TabContent(
                        tab: selected?.key ?? '',
                        child: selected == null
                            ? _Summary(customers: all, onSelect: _select)
                            : _CustomerDetail(
                                restaurantId: restaurant.id,
                                customer: selected,
                                onClose: () => _select(null),
                              ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Lista klientów po lewej: wyszukiwanie i wiersze z imieniem, telefonem i liczbą według sortowania.
class _CustomerList extends StatelessWidget {
  const _CustomerList({
    required this.search,
    required this.customers,
    required this.sort,
    required this.selectedKey,
    required this.onSearch,
    required this.onSelect,
  });

  final TextEditingController search;
  final List<Customer> customers;
  final _Sort sort;
  final String? selectedKey;
  final VoidCallback onSearch;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: search,
              onChanged: (_) => onSearch(),
              decoration: InputDecoration(
                hintText: 'Imię albo telefon',
                isDense: true,
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Glyph(AppIcons.search, size: 18, color: AppColors.textMuted),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.ring),
          Expanded(
            child: customers.isEmpty
                ? Center(
                    child: Text(
                      'Nikogo nie znaleziono',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: customers.length,
                    itemBuilder: (context, i) {
                      final c = customers[i];
                      return _CustomerTile(
                        customer: c,
                        trailing: switch (sort) {
                          _Sort.recent => c.lastVisit == null ? '—' : Fmt.dayShort(c.lastVisit!),
                          _Sort.visits => '${c.visits + c.orders}',
                          _Sort.spent => c.spentGrosze > 0 ? Fmt.price(c.spentGrosze) : '—',
                        },
                        selected: c.key == selectedKey,
                        onTap: () => onSelect(c.key),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.trailing, required this.selected, required this.onTap});

  final Customer customer;
  final String trailing;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = customer;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: selected ? AppColors.accentFill.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall?.copyWith(color: selected ? AppColors.accent : null),
                            ),
                          ),
                          if (c.fromApp) ...[
                            const SizedBox(width: 6),
                            Glyph(AppIcons.deviceMobile, size: 13, color: AppColors.accent),
                          ],
                          if (c.returning) ...[
                            const SizedBox(width: 4),
                            const Glyph(AppIcons.starFill, size: 12, color: Color(0xFFE0A21B)),
                          ],
                        ],
                      ),
                      Text(
                        [
                          c.phone == null ? 'Bez telefonu' : Fmt.phone(c.phone),
                          ?c.company,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  trailing,
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Podsumowanie wszystkich klientów, gdy nikt nie jest wybrany.
class _Summary extends StatelessWidget {
  const _Summary({required this.customers, required this.onSelect});

  final List<Customer> customers;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final all = customers;
    final returning = all.where((c) => c.returning).length;
    final fromApp = all.where((c) => c.fromApp).length;
    final visits = all.fold(0, (s, c) => s + c.visits);
    final noShows = all.fold(0, (s, c) => s + c.noShows);
    final orders = all.fold(0, (s, c) => s + c.orders);
    final spent = all.fold(0, (s, c) => s + c.spentGrosze);
    final loyal = [
      for (final c in all)
        if (c.visits + c.orders > 0) c,
    ]..sort((a, b) => (b.visits + b.orders).compareTo(a.visits + a.orders));
    final upcoming = [
      for (final c in all)
        if (c.nextReservation != null) c,
    ]..sort((a, b) => a.nextReservation!.compareTo(b.nextReservation!));

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Klienci',
                  value: '${all.length}',
                  hint: 'w aplikacji Table: $fromApp',
                  icon: AppIcons.userList,
                  color: TileColors.blue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: StatTile(
                  label: 'Powracający',
                  value: '$returning',
                  hint: all.isEmpty ? null : '${(returning * 100 / all.length).round()}% klientów',
                  icon: AppIcons.arrowsClockwise,
                  color: TileColors.green,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: StatTile(
                  label: 'Wizyty',
                  value: '$visits',
                  hint: 'nieobecności: $noShows',
                  icon: AppIcons.calendarCheck,
                  color: TileColors.violet,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: StatTile(
                  label: 'Wydatki',
                  value: Fmt.price(spent),
                  hint: 'na wynos: $orders',
                  icon: AppIcons.money,
                  color: TileColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ShortList(
                  title: 'Najczęściej wracają',
                  icon: AppIcons.starFill,
                  color: TileColors.amber,
                  customers: loyal.take(8).toList(),
                  value: (c) => _plural(c.visits + c.orders, 'raz', 'razy', 'razy'),
                  onSelect: onSelect,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _ShortList(
                  title: 'Najbliższe rezerwacje',
                  icon: AppIcons.calendarDots,
                  color: TileColors.blue,
                  customers: upcoming.take(8).toList(),
                  value: (c) => '${Fmt.dayShort(c.nextReservation!)}, ${Fmt.time(c.nextReservation!)}',
                  onSelect: onSelect,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShortList extends StatelessWidget {
  const _ShortList({
    required this.title,
    required this.icon,
    required this.color,
    required this.customers,
    required this.value,
    required this.onSelect,
  });

  final String title;
  final AppIconData icon;
  final Color color;
  final List<Customer> customers;
  final String Function(Customer) value;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PanelCard(
      title: title,
      icon: icon,
      iconColor: color,
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
      child: customers.isEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text('Brak', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in customers)
                  InkWell(
                    onTap: () => onSelect(c.key),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            value(c),
                            style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Wybrany klient: liczby, historia wizyt i zamówień oraz notatki zespołu.
class _CustomerDetail extends ConsumerWidget {
  const _CustomerDetail({required this.restaurantId, required this.customer, required this.onClose});

  final String restaurantId;
  final Customer customer;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final c = customer;
    final query = (restaurantId: restaurantId, key: c.key);
    final history = ref.watch(customerHistoryProvider(query));
    final notes = ref.watch(customerNotesProvider(query));

    final dates = [
      if (c.firstSeen != null) 'Pierwszy raz ${Fmt.dayShort(c.firstSeen!)}',
      if (c.lastVisit != null) 'Ostatnio ${Fmt.dayShort(c.lastVisit!)}',
    ];

    final header = Row(
      children: [
        Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.accentFill.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: Text(_initials(c.name), style: text.titleMedium?.copyWith(color: AppColors.accent)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleLarge),
                  ),
                  if (c.fromApp) ...[
                    const SizedBox(width: 10),
                    Tooltip(
                      message: 'Ma konto w aplikacji Table',
                      child: Glyph(AppIcons.deviceMobile, size: 16, color: AppColors.accent),
                    ),
                  ],
                  if (c.returning) ...[
                    const SizedBox(width: 6),
                    const Tooltip(
                      message: 'Wraca do lokalu',
                      child: Glyph(AppIcons.starFill, size: 15, color: Color(0xFFE0A21B)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 14,
                children: [
                  if (c.phone != null)
                    SelectableText(
                      Fmt.phone(c.phone),
                      style: text.bodyMedium?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                    ),
                  for (final d in dates) Text(d, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
                ],
              ),
              // Dane z zamówień na wynos: firma z NIP-em i ostatni adres dostawy.
              if (c.company != null || c.address != null) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 14,
                  runSpacing: 2,
                  children: [
                    if (c.company != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Glyph(AppIcons.briefcase, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 6),
                          SelectableText(
                            [c.company!, if (c.nip != null) 'NIP ${c.nip}'].join(' · '),
                            style: text.bodyMedium,
                          ),
                        ],
                      ),
                    if (c.address != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Glyph(AppIcons.mapPin, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 6),
                          SelectableText(c.address!, style: text.bodyMedium),
                        ],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (c.nextReservation != null) ...[
          PanelPill(
            '${Fmt.dayShort(c.nextReservation!)}, ${Fmt.time(c.nextReservation!)}',
            icon: AppIcons.calendarDots,
          ),
          const SizedBox(width: 8),
        ],
        IconButton(
          tooltip: 'Zamknij',
          onPressed: onClose,
          icon: Glyph(AppIcons.close, size: 18, color: AppColors.textMuted),
        ),
      ],
    );

    final tiles = Row(
      children: [
        Expanded(
          child: StatTile(
            label: 'Wizyty',
            value: '${c.visits}',
            hint: _plural(c.reservations, 'rezerwacja', 'rezerwacje', 'rezerwacji'),
            icon: AppIcons.calendarCheck,
            color: TileColors.violet,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatTile(
            label: 'Nieobecności',
            value: '${c.noShows}',
            hint: 'odwołane: ${c.cancelled}',
            icon: AppIcons.calendarX,
            color: TileColors.rose,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatTile(label: 'Na wynos', value: '${c.orders}', icon: AppIcons.shoppingBag, color: TileColors.green),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: StatTile(
            label: 'Wydatki',
            value: Fmt.price(c.spentGrosze),
            hint: c.visits + c.orders == 0 ? null : 'średnio ${Fmt.price(c.spentGrosze ~/ (c.visits + c.orders))}',
            icon: AppIcons.money,
            color: TileColors.amber,
          ),
        ),
      ],
    );

    final notesCard = PanelCard(
      title: 'Notatki',
      icon: AppIcons.notePencil,
      iconColor: TileColors.blue,
      child: NotesView(
        scrollable: false,
        notes: notes,
        hint: 'Na przykład alergia na orzechy, ulubiony stolik',
        onAdd: (body) async {
          await ref
              .read(repositoryProvider)
              .addCustomerNote(restaurantId, c.key, body, memberId: ref.read(panelMemberProvider)?.dbMemberId);
          ref.invalidate(customerNotesProvider(query));
        },
        onDelete: (note) async {
          await ref.read(repositoryProvider).deleteCustomerNote(note.id);
          ref.invalidate(customerNotesProvider(query));
        },
      ),
    );

    final historyCard = PanelCard(
      title: 'Historia',
      icon: AppIcons.clockBack,
      iconColor: TileColors.violet,
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
      child: history.when(
        skipLoadingOnReload: true,
        loading: () => const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(12),
          child: Text(errorText(e), style: text.bodyMedium?.copyWith(color: AppColors.error)),
        ),
        data: (events) => events.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Text('Brak wizyt', style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final e in events) _EventRow(event: e)],
              ),
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 860;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(padding: const EdgeInsets.fromLTRB(20, 16, 12, 16), child: header),
              ),
              const SizedBox(height: 16),
              tiles,
              const SizedBox(height: 16),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: historyCard),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: notesCard),
                  ],
                )
              else ...[
                notesCard,
                const SizedBox(height: 16),
                historyCard,
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Wiersz historii: rezerwacja (z liczbą osób i stanem) albo zamówienie na wynos.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final CustomerEvent event;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = event;
    final (icon, title) = switch (e.kind) {
      'delivery' => (AppIcons.moped, 'Dostawa'),
      'pickup' => (AppIcons.shoppingBag, 'Odbiór osobisty'),
      _ => (AppIcons.calendarDots, e.partySize == null ? 'Rezerwacja' : 'Rezerwacja · ${Fmt.people(e.partySize!)}'),
    };
    final String status;
    final Color statusColor;
    if (e.kind == 'reservation') {
      final s = ReservationStatus.fromDb(e.status);
      status = s.label;
      statusColor = switch (s) {
        ReservationStatus.noShow => AppColors.error,
        ReservationStatus.cancelled => AppColors.textMuted,
        ReservationStatus.confirmed || ReservationStatus.seated => AppColors.accent,
        ReservationStatus.completed => AppColors.textMuted,
      };
    } else {
      status = e.kind == 'pickup' ? 'Odebrane' : 'Dostarczone';
      statusColor = AppColors.textMuted;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Glyph(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.bodyMedium),
                Text(
                  '${Fmt.dayShort(e.at)}, ${Fmt.time(e.at)}',
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted, fontFeatures: _tabular),
                ),
              ],
            ),
          ),
          Text(status, style: text.bodySmall?.copyWith(color: statusColor)),
          SizedBox(
            width: 96,
            child: Text(
              e.spentGrosze > 0 ? Fmt.price(e.spentGrosze) : '—',
              textAlign: TextAlign.end,
              style: text.bodyMedium?.copyWith(
                color: e.spentGrosze > 0 ? null : AppColors.textMuted,
                fontFeatures: _tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
